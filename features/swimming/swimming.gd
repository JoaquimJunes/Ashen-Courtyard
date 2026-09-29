extends RefCounted
## Per-character water state. Geometry and body movement belong to CharacterMotor.
const Water = preload("res://features/swimming/water_volume.gd")
const Motion = preload("res://features/character/motion_request.gd")
const Definition = preload("res://features/swimming/swim_definition.gd")
const ENTRY_CONTACT_MARGIN := 0.005 # Match floor solver separation at exact depth thresholds.
const Damage = preload("res://features/combat/damage_request.gd")
var definition: Definition = preload("res://features/swimming/swimming.tres")
var actor: CharacterBody3D
var water: Area3D
var active := false
var underwater := false
var fast := false
var wants_fast := false
var fast_exhausted := false
var direction := Vector3.ZERO
var vertical := 0.0
var heading := Vector3.FORWARD
var drowning_clock := 0.0
var damage_serial := 0
var last_entry_safe := false
var resetting := false
var generation := 0
var head_detector = preload("res://features/swimming/head_water_detector.gd").new()

func configure(character: CharacterBody3D) -> void:
	actor = character
	head_detector.configure(character)
	actor.resources.maximum_breath = definition.breath_seconds
	actor.resources.reset_breath()
	actor.motor.teleported.connect(reset)

func depth_at(volume: Area3D, point: Vector3) -> float:
	var top: float = volume.surface_y()
	var hit: Dictionary = actor.motor.floor_probe(Vector3(point.x,top-0.01,point.z),Vector3(point.x,top-volume.size.y,point.z))
	return top-hit.position.y if not hit.is_empty() else volume.size.y

func mode() -> StringName:
	return &"underwater_swimming" if underwater else &"surface_swimming"

func refresh_mode() -> void:
	if active and actor.movement.attachment == null:
		actor.movement.set_water_mode(mode())

func prepare(delta: float) -> void:
	if actor.dead: return
	# Entry measures immersion from the feet; floating retains its own waterline.
	var sample := actor.global_position+Vector3.UP*(definition.surface_offset if active else definition.immersion_height-ENTRY_CONTACT_MARGIN)
	var found := Water.at(actor,sample)
	if actor.reactions.active:
		if found != null and depth_at(found,sample) >= definition.safe_entry_depth and not actor.reactions.lethal:
			if actor.motor.swim_posture_clear(heading,definition.collider_height,definition.collider_offset,actor.reactions.driver.collision_exclusions):
				actor.reactions.reset()
				actor.actions.cancel(&"water_recovery")
				enter(found)
		return
	if actor.movement.attachment != null:
		active = false
		fast = false
		return
	if active:
		if not is_instance_valid(water) or water.is_queued_for_deletion():
			leave(true)
			return
		var foot: Dictionary = actor.motor.floor_probe(actor.global_position+Vector3.UP*definition.collider_offset,actor.global_position-Vector3.UP*0.25)
		var wading: bool = not foot.is_empty() and water.surface_y()-foot.position.y < definition.exit_depth
		if wading or not water.contains(sample,0.2):
			if found != null and not wading: water = found
			else: leave()
		refresh_mode()
	elif found != null:
		# Preserve hard shallow impacts; deep water alone interrupts falling recovery.
		if depth_at(found,sample) >= definition.safe_entry_depth or (actor.is_on_floor() and actor.actions.is_available()) or absf(actor.velocity.y) < 2.0:
			enter(found)

func try_crouch_entry() -> bool:
	if active or actor.dead or actor.reactions.active or actor.movement.attachment != null or not actor.actions.is_available(): return false
	var sample := actor.global_position+Vector3.UP*(definition.crouch_entry_depth-ENTRY_CONTACT_MARGIN)
	var volume := Water.at(actor,sample)
	if volume == null or depth_at(volume,sample) < definition.crouch_entry_depth: return false
	return enter(volume)

func enter(volume: Area3D) -> bool:
	if actor.dead or actor.movement.attachment != null: return false
	var axis := Vector3.UP
	if not actor.motor.swim_posture_clear(axis,definition.collider_height,definition.collider_offset): axis = heading
	if not actor.motor.swim_posture_clear(axis,definition.collider_height,definition.collider_offset): return false
	generation += 1
	var owner := generation
	water = volume
	active = true
	underwater = actor.global_position.y+maxf(definition.surface_offset+0.2,definition.immersion_height+0.3) < water.surface_y()
	last_entry_safe = depth_at(water,actor.global_position) >= definition.safe_entry_depth
	actor.actions.cancel(&"water_entry")
	# Cancellation observers may reset, kill or unload the character synchronously.
	# A newer lifecycle owns its state; never resume the interrupted entry over it.
	if generation != owner: return false
	if actor.dead or actor.actions.unloaded:
		active = false
		water = null
		return false
	if not actor.motor.set_swim_posture(axis,definition.collider_height,definition.collider_offset):
		active = false
		water = null
		return false
	actor.posture.reset()
	actor.crawling.reset()
	actor.presentation.crawl.reset()
	actor.controller.reset_attack()
	actor.presentation.crouch.reset()
	actor.presentation.jump.reset()
	actor.landing.reset()
	actor.locked = false
	actor.sprinting = false
	actor.invulnerable = false
	actor.motor.request_water_velocity(actor.velocity.limit_length(definition.fast_speed))
	actor.simulation.resolver.reset()
	refresh_mode()
	return true

func leave(force: bool = false) -> bool:
	# A low roof must not force an overlapping standing capsule.
	if not actor.motor.restore_posture() and not force: return false
	active = false
	underwater = false
	fast = false
	wants_fast = false
	water = null
	actor.presentation.swim.reset()
	actor.movement.clear_water_mode()
	actor.simulation.resolver.reset()
	return true

func sample_intent(intent: RefCounted) -> void:
	if not intent.sprint: fast_exhausted = false
	vertical = clampf(intent.swim_vertical,-1,1)
	direction = Vector3.ZERO
	wants_fast = false
	if not active or actor.movement.attachment != null: return
	if vertical < 0: underwater = true
	if underwater:
		direction = intent.swim_direction if intent.swim_direction != Vector3.ZERO else intent.movement
		direction += Vector3.UP*vertical
	else:
		direction = Vector3(intent.movement.x,0,intent.movement.z)
	direction = direction.limit_length(1.0)
	wants_fast = intent.sprint and not fast_exhausted and direction != Vector3.ZERO and actor.actions.is_available()
	refresh_mode()

func motion(delta: float, paid: bool) -> Motion:
	var request := Motion.new()
	request.kind = Motion.Kind.WATER
	if wants_fast and not paid: fast_exhausted = true
	fast = wants_fast and paid and actor.actions.is_available()
	var controlled: Vector3 = direction if actor.actions.is_available() else Vector3.ZERO
	var target := controlled*(definition.fast_speed if fast else definition.speed)
	var velocity: Vector3 = actor.velocity.move_toward(target,(definition.acceleration if controlled != Vector3.ZERO else definition.drag)*delta)
	if is_instance_valid(water):
		var target_y: float = water.surface_y()-definition.surface_offset
		if underwater and vertical >= 0 and actor.global_position.y >= target_y-definition.resurface_margin and velocity.y >= 0:
			underwater = false
		if not underwater:
			velocity.y = clampf((target_y-actor.global_position.y)*definition.surface_response,-definition.speed,definition.speed)
			# No upward overshoot or jump when holding ascend at the surface.
			if delta > 0 and velocity.y > 0: velocity.y = minf(velocity.y,maxf(0,(target_y-actor.global_position.y)/delta))
	if controlled.length_squared() > 0.001: heading = controlled.normalized()
	request.water_velocity = velocity
	request.water_height = definition.collider_height
	refresh_mode()
	return request

func after_motion(from: Vector3, result: RefCounted) -> void:
	if actor.dead or actor.movement.attachment != null: return
	if not active:
		var crossing := Water.crossed(actor,from+Vector3.UP*definition.immersion_height,actor.global_position+Vector3.UP*definition.immersion_height)
		if not crossing.is_empty() and depth_at(crossing.water,crossing.point) >= definition.safe_entry_depth:
			enter(crossing.water)
	if active:
		result.grounded = false
		result.impact_speed = 0
		result.velocity = actor.velocity
		actor.motor.impact_down_speed = 0
		refresh_mode()

func tick_breath(delta: float) -> void:
	if actor.dead: return
	var owner := generation
	var point: Vector3 = actor.hitboxes.breathing_position()
	var intervals: Array = head_detector.sample(point,delta)
	for interval in intervals:
		if owner != generation or actor.dead or actor.is_queued_for_deletion(): return
		var empty_seconds: float = actor.resources.tick_breath(interval.seconds,interval.submerged,definition.breath_refill_seconds)
		if owner != generation: return
		if not interval.submerged:
			drowning_clock = 0
			continue
		drowning_clock += empty_seconds
		while drowning_clock >= 1.0-0.000001 and not actor.dead:
			drowning_clock = maxf(0,drowning_clock-1.0)
			damage_serial += 1
			var hit := Damage.new(actor.max_health*definition.drowning_fraction_per_second,StringName("drowning_%s_%s" % [actor.get_instance_id(),damage_serial]))
			hit.damage_type = &"drowning"
			actor.receive_damage(hit)
			if owner != generation: return

func can_exit() -> bool:
	return active and not underwater and vertical >= 0 and is_instance_valid(water) and actor.resources.can_spend(actor.traversal.definition.stamina_cost)

func begin_exit() -> void:
	actor.presentation.swim.reset()
	active = false
	fast = false
	wants_fast = false

func reset() -> void:
	if resetting: return
	generation += 1
	resetting = true
	active = false
	underwater = false
	fast = false
	wants_fast = false
	fast_exhausted = false
	direction = Vector3.ZERO
	vertical = 0
	heading = Vector3.FORWARD
	water = null
	drowning_clock = 0
	last_entry_safe = false
	head_detector.reset()
	actor.resources.reset_breath()
	actor.presentation.swim.reset()
	actor.movement.clear_water_mode()
	resetting = false
