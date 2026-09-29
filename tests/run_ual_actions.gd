extends "res://tests/run_ual_native_animation.gd"
## Source fidelity, equipment-sensitive idle, heavy timing and tap-cast phases.
const State = preload("res://features/character/character_states.gd").Action

class RecordedCombat extends "res://features/combat/combat_services.gd":
	var swings: Array = []
	var casts: Array = []
	func melee(caster: Combatant, amount: float, _strike: RefCounted, _target: Combatant = null) -> void:
		swings.append([caster.timer,amount])
	func cast(caster: Combatant, definition: Resource, _aim: Aim, _strike: RefCounted) -> void:
		casts.append([caster.timer,definition.id,definition.damage])

func start_now(actor: CharacterBody3D, action: String) -> bool:
	var ticket: RefCounted = actor.actions.request(action)
	actor.actions.tick()
	return ticket.accepted

func verify_action_sources() -> void:
	check(PROFILE.native_actions.get_animation_list().size() == 7,"Seven native sword, spell and root-motion mantle clips are installed")
	for role in PROFILE.native_actions.get_animation_list():
		var native: Animation = PROFILE.native_actions.get_animation(role)
		var path: String = native.get_meta("source_scene","")
		var source: Node3D = load(path).instantiate()
		var player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
		var original: Animation = player.get_animation(native.get_meta("source_clip"))
		var verified := preload("res://tools/build_ual_combat_library.gd").new()
		check(verified.same_clip(original,native),role+": all original keys, interpolation and loop metadata are unchanged")
		check(native.get_meta("native_keyframes",false) and native.get_meta("source_sha256","") == FileAccess.get_sha256(path),role+": provenance identifies the untouched source")
		verified.free()
		source.free()
	var invalid := PROFILE.duplicate(true)
	invalid.spell_cast.enter_fraction = 1.0
	var source: Node3D = preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	var player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	var before := player.get_animation_list()
	check(not invalid.install(player) and player.get_animation_list() == before,"Invalid cast phase configuration cannot partially install a profile")
	source.free()

func same_source_arm(actor: CharacterBody3D, source_name: String, time: float, side: String) -> bool:
	var source: Node3D = preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	root.add_child(source)
	var player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	var skeleton: Skeleton3D = source.find_child("Skeleton3D",true,false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(source_name)
	player.seek(time,true)
	player.advance(0)
	var matches := true
	for part in ["upperarm_","lowerarm_","hand_","index_01_"]:
		var bone := skeleton.find_bone(part+side)
		matches = matches and actor.model.skeleton.get_bone_pose_rotation(bone).is_equal_approx(skeleton.get_bone_pose_rotation(bone))
	source.free()
	return matches

func idle_arm_error(actor: CharacterBody3D, source_name: String) -> float:
	# Local arm rotations are unaffected by terrain IK. Compare the visible pose,
	# not only the selected clip and clock: those can advance while a blend stalls.
	var source: Node3D = preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	root.add_child(source)
	var player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	var skeleton: Skeleton3D = source.find_child("Skeleton3D",true,false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(source_name)
	player.seek(actor.model.animation.current_animation_position,true)
	player.advance(0)
	var error := 0.0
	for side in ["l","r"]:
		for part in ["upperarm_","lowerarm_","hand_","index_01_"]:
			var bone := skeleton.find_bone(part+side)
			error = maxf(error,actor.model.skeleton.get_bone_pose_rotation(bone).angle_to(skeleton.get_bone_pose_rotation(bone)))
	source.free()
	return error

func verify_stop_to_idle(rate: int) -> void:
	for gait in ["jog","sprint"]:
		await reset_pair(rate)
		actors[0].model.equipment.set_layout(&"sword")
		actors[2].model.equipment.set_layout(&"all_stowed")
		for index in [0,2]:
			intents[index].movement = Vector3.FORWARD
			intents[index].sprint = gait == "sprint"
		await step(rate,rate)
		for index in [0,2]:
			check(actors[index].model.animation.current_animation == "running/"+gait,"%s Hz: idle regression starts in %s" % [rate,gait])
			intents[index].movement = Vector3.ZERO
			intents[index].sprint = false
		await step(rate,rate)
		for index in [0,2]:
			var actor: CharacterBody3D = actors[index]
			var source_name := "Sword_Idle" if index == 0 else "Idle"
			var error := idle_arm_error(actor,source_name)
			check(actor.model.animation.current_animation == actor.model.idle_clip(),"%s Hz: stopping %s selects %s" % [rate,gait,source_name])
			# Isolated source playback through the existing 45 ms filter trails its
			# breathing motion by up to 1.56 degrees at these rates.
			check(error < deg_to_rad(2.0),"%s Hz: stopping %s settles into visible %s pose (arm error %.2f degrees)" % [rate,gait,source_name,rad_to_deg(error)])
		var other_clock: float = actors[2].model.animation.current_animation_position
		var other_arm: Quaternion = actors[2].model.skeleton.get_bone_pose_rotation(actors[2].model.skeleton.find_bone("lowerarm_r"))
		actors[0].model.update_pose(0.1)
		check(actors[2].model.animation.current_animation_position == other_clock and actors[2].model.skeleton.get_bone_pose_rotation(actors[2].model.skeleton.find_bone("lowerarm_r")) == other_arm,"Advancing held-sword idle cannot change another character's idle pose or clock")

func verify_idle(rate: int) -> void:
	await reset_pair(rate)
	var actor: CharacterBody3D = actors[0]
	check(actor.model.animation.assigned_animation == PROFILE.sword_idle,"%s Hz: held sword selects Sword_Idle" % rate)
	var source: Animation = PROFILE.clip_for(PROFILE.sword_idle)
	var loop_mode := source.loop_mode
	var start_time: float = actor.model.animation.current_animation_position
	var wraps := 0
	var wrap_step := 0.0
	var wrap_source_error := 0.0
	var arm: int = actor.model.skeleton.find_bone("lowerarm_r")
	for frame in rate*4:
		var previous_time: float = actor.model.animation.current_animation_position
		var previous_rotation: Quaternion = actor.model.skeleton.get_bone_pose_rotation(arm)
		actor.model.update_pose(1.0/rate)
		if actor.model.animation.current_animation_position < previous_time:
			wraps += 1
			wrap_step = maxf(wrap_step,previous_rotation.angle_to(actor.model.skeleton.get_bone_pose_rotation(arm)))
			wrap_source_error = maxf(wrap_source_error,idle_arm_error(actor,"Sword_Idle"))
	check(wraps >= 2 and actor.model.animation.current_animation == PROFILE.sword_idle and actor.model.animation.is_playing(),"Sword idle wraps through several cycles without stopping")
	check(absf(actor.model.animation.current_animation_position-fposmod(start_time+4.0,source.length)) < 0.0001,"Sword idle retains elapsed time across cycle boundaries")
	check(wrap_step < deg_to_rad(3.0) and wrap_source_error < deg_to_rad(2.0),"%s Hz: idle cycle boundaries retain the source pose without a visible jump (step %.2f degrees, source error %.2f degrees)" % [rate,rad_to_deg(wrap_step),rad_to_deg(wrap_source_error)])
	check(source.loop_mode == loop_mode,"Idle wrapping cannot mutate the shared source loop metadata")
	actor.model.equipment.set_layout(&"all_stowed")
	actor.model.update_pose(0.2)
	check(actor.model.animation.assigned_animation == &"k_idle","Stowing sword restores unarmed idle")
	actor.model.equipment.set_layout(&"sword")
	actor.model.equipment.request_hand_release(&"idle_test")
	actor.model.update_pose(0.2)
	check(actor.model.animation.assigned_animation == &"k_idle","Temporary hand release also leaves sword idle")
	actor.model.equipment.release_hand_release(&"idle_test")
	actor.model.update_pose(0.2)
	check(actor.model.animation.assigned_animation == PROFILE.sword_idle,"Sword idle returns after temporary stowing ends")

func verify_heavy(rate: int) -> void:
	await reset_pair(rate)
	var native: CharacterBody3D = actors[0]
	var legacy: CharacterBody3D = actors[1]
	for actor in [native,legacy]:
		actor.services.swings.clear()
		check(start_now(actor,"heavy"),"Heavy request commits normally")
	var setup: Resource = PROFILE.heavy_attack
	for point in [[native.tuning.heavy.windup,setup.strike_start],[native.tuning.heavy.windup+native.tuning.heavy.active_seconds,setup.strike_end]]:
		native.actions.timer = point[0]
		native.model.update_pose(0)
		check(native.model.animation.assigned_animation == setup.clip and absf(native.model.animation.current_animation_position-point[1]) < 0.00001,"Heavy source strike landmarks align with gameplay damage boundaries")
		check(same_source_arm(native,"Sword_Attack",point[1],"r"),"Heavy arm and fingers retain the original UAL1 pose")
	native.actions.timer = 0
	var synchronized := true
	for frame in rate*2:
		await step(1,rate)
		synchronized = synchronized and native.state == legacy.state and absf(native.stamina-legacy.stamina) < 0.0001 and absf(native.position.z-legacy.position.z) < 0.0001
		if native.actions.is_available(): break
	check(synchronized and native.actions.is_available(),"%s Hz: heavy duration, cost and motor motion match existing gameplay" % rate)
	check(not native.services.swings.is_empty() and native.services.swings == legacy.services.swings,"Heavy damage ticks and amount are unaffected by animation replacement")
	check(native.presentation.sword_attack.current == null,"Finished heavy releases its pose ownership")

func verify_spell(rate: int, spell: int) -> void:
	await reset_pair(rate)
	var native: CharacterBody3D = actors[0]
	var legacy: CharacterBody3D = actors[1]
	for actor in [native,legacy]:
		actor.selected_spell = spell
		actor.services.casts.clear()
		check(start_now(actor,"cast"),"Tap cast commits normally")
	var setup: Resource = PROFILE.spell_cast
	var action: Resource = native.actions.active_definition
	var original_position: Vector3 = native.position
	var original_mana: float = native.mana
	for point in [[action.windup*0.2,setup.enter_clip],[action.windup*0.85,setup.idle_clip],[action.windup,setup.shoot_clip],[action.windup+action.recovery*0.8,setup.exit_clip]]:
		native.actions.timer = point[0]
		native.model.update_pose(0)
		check(native.model.animation.assigned_animation == point[1],"Tap cast samples enter, idle, shoot and exit in order")
		if point[1] == setup.shoot_clip:
			check(absf(native.model.animation.current_animation_position) < 0.00001 and same_source_arm(native,"Spell_Simple_Shoot",0,"l"),"Spell release uses the source's first extended-hand pose without procedural twisting")
	check(native.position == original_position and native.mana == original_mana and native.services.casts.is_empty(),"Sampling spell poses cannot move, pay again or emit a spell")
	native.actions.timer = 0
	var synchronized := true
	for frame in rate*2:
		await step(1,rate)
		synchronized = synchronized and native.state == legacy.state and absf(native.mana-legacy.mana) < 0.0001
		if native.actions.is_available(): break
	check(synchronized and native.actions.is_available(),"%s Hz: spell %s retains cast duration and mana timing" % [rate,spell])
	check(native.services.casts.size() == 1 and native.services.casts == legacy.services.casts,"Both native and legacy casts release once at the same authoritative time")
	check(native.presentation.spell.current == null and native.model.equipment.current_sockets[&"sword"] == &"right_hand","Cast completion clears its pose and restores held equipment")

func verify_cancellation(rate: int) -> void:
	for kind in ["damage","death","ragdoll","reset"]:
		await reset_pair(rate)
		var actor: CharacterBody3D = actors[0]
		actor.selected_spell = 0
		actor.services.casts.clear()
		check(start_now(actor,"cast"),"Interruption fixture starts casting")
		match kind:
			"damage": actor.take_damage(1,"cast_damage")
			"death": actor.take_damage(actor.health+1,"cast_death")
			"ragdoll": actor.reactions.begin(false,true)
			"reset": actor.reset_for_lab(Transform3D.IDENTITY)
		check(actor.presentation.spell.current == null,"%s clears native casting immediately" % kind)
		await step(rate/2,rate)
		check(actor.services.casts.is_empty(),"Interrupted preparation cannot release a delayed spell")
	await reset_pair(rate)
	var actor: CharacterBody3D = actors[0]
	check(await ActionTest.start(actor,&"jump"),"Airborne spell fixture takes off")
	await step(rate/4,rate)
	check(start_now(actor,"cast") and actor.movement.in_flight,"Cast starts while airborne")
	actor.actions.timer = actor.actions.active_definition.windup
	actor.presentation.jump.sample(0)
	var legs: Array = actor.presentation.capture_pose()
	actor.model.update_pose(0)
	var retained := true
	for bone in actor.model.skeleton.get_bone_count():
		if not actor.presentation.spell.upper_body.has(bone): retained = retained and legs[bone][0].is_equal_approx(actor.model.skeleton.get_bone_pose_rotation(bone))
	check(retained,"Airborne casting preserves the flight pelvis and legs")

func run() -> void:
	verify_action_sources()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(100,1,100),Vector3(0,-0.5,0),Color.GRAY)
	for index in 3:
		var actor: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
		if index == 1: actor.model_scene = LEGACY
		var combat := RecordedCombat.new()
		combat.host = world
		world.add_child(combat)
		actor.services = combat
		actor.controller.manual = true
		world.add_child(actor)
		actor.model.set_process(false)
		if index != 1: check(actor.model.idle_clip() == "k_idle","An airborne spawn cannot acquire the grounded sword idle")
		actors.append(actor)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await verify_idle(rate)
		await verify_stop_to_idle(rate)
		await verify_heavy(rate)
		for spell in [0,1]: await verify_spell(rate,spell)
		await verify_cancellation(rate)
	Engine.physics_ticks_per_second = original_rate
	await reset_pair(60)
	check(start_now(actors[0],"cast") and actors[2].presentation.spell.current == null,"Shared clips do not share per-character casting state")
	var presentation: RefCounted = actors[0].presentation.spell
	var actions: RefCounted = actors[0].actions
	world.free()
	actors.clear()
	check(presentation.actor == null and presentation.current == null and not actions.started.is_connected(presentation.on_started),"Scene exit releases and disconnects the spell driver")
	print("UAL ACTIONS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
