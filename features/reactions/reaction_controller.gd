extends Node
## Reaction policy and recovery ownership. No arena/lab dependencies.
signal started(lethal: bool)
signal recovered
const Definition = preload("res://features/reactions/ragdoll_definition.gd")
const State = preload("res://features/character/character_states.gd").Action
var definition: Definition = preload("res://features/reactions/knight_ragdoll.tres")
var actor: CharacterBody3D
var driver = preload("res://features/reactions/ragdoll_driver.gd").new()
var active := false
var lethal := false
var getting_up := false
var settle_time := 0.0
var get_up_time := 0.0
var fall_armed := false
var fall_speed := 0.0
var recovery_floor_clearance := 0.0
var recovery_variant: StringName = &""

func configure(character: CharacterBody3D) -> void:
	actor = character
	# Character tick orders reaction publication before sensing.
	set_physics_process(false)
	if actor.model.rig.ragdoll_definition != null:
		definition = actor.model.rig.ragdoll_definition
	driver.configure(actor,definition)
	actor.damage_applied.connect(on_damage)

func on_damage(request: RefCounted) -> void:
	if active:
		if actor.health <= 0: lethal = true
		return
	if request.damage_type == &"drowning" or actor.swimming.active: return
	var fatal_landing: bool = request.damage_type == &"fall" and actor.health <= 0
	# Death must retain physical motion during ascent and at the apex too.
	# Nonlethal rising hits still use the ordinary controlled hurt response.
	var fatal_airborne_hit: bool = request.damage_type != &"fall" and actor.health <= 0 and actor.motor.is_airborne()
	var hit_descending: bool = request.damage_type != &"fall" and not actor.is_on_floor() and actor.velocity.y < -0.05
	var attached_hit: bool = actor.movement.attachment != null
	if fatal_landing or fatal_airborne_hit or hit_descending or attached_hit:
		begin(actor.health <= 0,fatal_airborne_hit or hit_descending or attached_hit)

func on_landing(severity: StringName, roll_succeeded: bool) -> bool:
	if active: return true
	# This skill is tested on heavy/damaging falls. The ordinary low dive still
	# finishes with its original ground roll. Lethal dives also preserve this pose;
	# ordinary lethal falls still enter through the shared damage notification.
	if roll_succeeded or severity not in [&"heavy",&"damaging",&"lethal"]: return false
	var dive: RefCounted = actor.actions.forward_dive
	if not dive.active or dive.phase != dive.Phase.AIR: return false
	# The controlled motor already reported this impact; physical bones must not
	# report/pay it a second time when they make contact just after the handover.
	begin(severity == &"lethal",false)
	return true

func begin(fatal: bool, airborne: bool) -> void:
	actor.pose_driver.restore_external_handoff()
	var incoming := actor.velocity
	var pose: Array = actor.presentation.capture_pose()
	actor.traversal.release(&"ragdoll")
	actor.presentation.mantle.reset()
	actor.actions.begin_ragdoll()
	actor.presentation.restore_pose(pose)
	actor.presentation.jump.reset()
	actor.casting_light.hide()
	actor.model.casting = false
	actor.locked = false
	actor.motor.acquire_ragdoll()
	driver.start(incoming,definition)
	actor.motor.ragdoll_anchor_offset = driver.anchor()-actor.global_position
	active = true
	lethal = fatal
	getting_up = false
	settle_time = 0
	get_up_time = 0
	recovery_variant = &""
	fall_armed = airborne
	fall_speed = maxf(0,-incoming.y)
	recovery_floor_clearance = 0
	started.emit(lethal)

func _physics_process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	if not active: return
	if getting_up:
		# On a slope the capsule feet sit above the floor ray. Preserve the same
		# support-loss tolerance below that contact, including steep walkable ramps.
		var support: Dictionary = actor.motor.floor_probe(actor.global_position+Vector3.UP*0.06,actor.global_position-Vector3.UP*(0.12+recovery_floor_clearance))
		if lethal or support.is_empty():
			getting_up = false
			settle_time = 0
			actor.motor.acquire_ragdoll()
			driver.start(Vector3.ZERO,definition)
			actor.motor.ragdoll_anchor_offset = driver.anchor()-actor.global_position
			fall_armed = not lethal
			fall_speed = 0
			if not lethal: actor.actions.begin_ragdoll()
			actor.presentation.get_up.reset()
			recovery_variant = &""
			return
		get_up_time += delta
		var sample_started := Time.get_ticks_usec()
		actor.presentation.get_up.sample(clampf(get_up_time/definition.get_up_seconds,0,1))
		actor.pose_driver.external_microseconds += Time.get_ticks_usec()-sample_started
		if get_up_time >= definition.get_up_seconds:
			driver.reset()
			active = false
			getting_up = false
			actor.actions.finish()
			actor.landing.reset()
			actor.movement.reset()
			actor.presentation.jump.reset()
			actor.presentation.get_up.reset()
			recovery_variant = &""
			recovered.emit()
		return
	actor.motor.follow_ragdoll(driver.anchor(),driver.torso.linear_velocity)
	fall_speed = maxf(fall_speed,-driver.torso.linear_velocity.y)
	if fall_armed and driver.contact():
		fall_armed = false
		# Use the same severity calculation and one impact event for the whole rig.
		# The reaction retains ownership instead of starting a standing land pose.
		actor.landing.on_landed(fall_speed)
		fall_speed = 0
	if not driver.contact() and driver.torso.linear_velocity.y < -2.0 and actor.motor.floor_probe(driver.anchor(),driver.anchor()-Vector3.UP*1.4).is_empty():
		fall_armed = true
	if lethal: return
	settle_time = settle_time+delta if driver.settled(definition) else 0.0
	if settle_time < definition.settle_seconds: return
	var place: Dictionary = actor.motor.ragdoll_recovery_location(driver.anchor(),driver.collision_exclusions)
	if place.is_empty():
		if actor.crawling.available():
			var prone: Dictionary = actor.motor.ragdoll_crawl_location(driver.anchor(),actor.crawling.definition,driver.collision_exclusions)
			if not prone.is_empty():
				driver.stop_simulation()
				actor.motor.restore_crawling_from_ragdoll(prone.transform,actor.crawling.definition)
				driver.restore_visual_parent()
				driver.reset()
				active = false
				actor.actions.finish()
				actor.landing.reset()
				actor.movement.reset()
				actor.presentation.jump.reset()
				actor.presentation.get_up.reset()
				actor.crawling.recovered_prone()
				recovered.emit()
		return
	var pose: Array[Transform3D] = driver.capture_physical_pose()
	# Choose once from the settled torso. Side landings take the nearer branch.
	var orientation := recovery_orientation(driver.torso.global_basis)
	recovery_variant = orientation.variant
	var facing: Vector3 = orientation.facing
	if facing.length_squared() > 0.01:
		place.transform.basis = Basis.looking_at(facing.normalized(),Vector3.UP)
	# Turn off ragdoll collision before restoring the capsule, so the character
	# cannot step onto its own physical bones during floor snapping.
	driver.stop_simulation()
	recovery_floor_clearance = actor.motor.support_clearance(place.normal)
	actor.motor.restore_from_ragdoll(place.transform)
	driver.restore_visual_parent()
	actor.presentation.get_up.begin(pose,recovery_variant,definition.get_up_pose,place.normal)
	getting_up = true
	get_up_time = 0
	actor.actions.begin_get_up()

func recovery_orientation(torso_basis: Basis) -> Dictionary:
	torso_basis = torso_basis.orthonormalized()
	var face_up := (torso_basis*definition.recovery_front_axis).dot(Vector3.UP) > 0
	var facing: Vector3 = torso_basis*definition.recovery_head_axis*(-1 if face_up else 1)
	facing.y = 0
	return {"variant":&"face_up" if face_up else &"face_down","facing":facing.normalized()}

func reset() -> void:
	if active:
		driver.reset()
		actor.motor.release_ragdoll()
		actor.presentation.get_up.reset()
	active = false
	lethal = false
	getting_up = false
	settle_time = 0
	get_up_time = 0
	fall_armed = false
	fall_speed = 0
	recovery_floor_clearance = 0
	recovery_variant = &""

func _exit_tree() -> void:
	if is_instance_valid(actor) and is_instance_valid(actor.model): reset()
