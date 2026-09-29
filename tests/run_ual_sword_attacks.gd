extends "res://tests/run_ual_native_animation.gd"
## Exact source fidelity plus actual combo, damage-clock and lifecycle integration.
const SOURCE = preload("res://assets/third_party/quaternius/ual2/UAL2_Standard.glb")
const State = preload("res://features/character/character_states.gd").Action

class RecordedCombat extends "res://features/combat/combat_services.gd":
	var swings: Array = []
	func melee(caster: Combatant, amount: float, strike: RefCounted, target: Combatant = null) -> void:
		swings.append([caster.timer,amount])
		super.melee(caster,amount,strike,target)

func verify_combat_source() -> void:
	var imported: Node3D = SOURCE.instantiate()
	root.add_child(imported)
	var source: AnimationPlayer = imported.find_child("AnimationPlayer",true,false)
	var skeleton: Skeleton3D = imported.find_child("Skeleton3D",true,false)
	var reference: Node3D = preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	var reference_skeleton: Skeleton3D = reference.find_child("Skeleton3D",true,false)
	var rig_matches := skeleton.get_bone_count() == 65
	for bone in skeleton.get_bone_count():
		rig_matches = rig_matches and skeleton.get_bone_name(bone) == reference_skeleton.get_bone_name(bone) and skeleton.get_bone_parent(bone) == reference_skeleton.get_bone_parent(bone) and skeleton.get_bone_rest(bone).is_equal_approx(reference_skeleton.get_bone_rest(bone))
	check(rig_matches,"UAL2 retains the canonical names, hierarchy and rest transforms")
	check(PROFILE.native_combat.get_animation_list().size() == 4,"A/B strikes and their matching authored recoveries are available")
	var hash := FileAccess.get_sha256(SOURCE.resource_path)
	for role in PROFILE.native_combat.get_animation_list():
		var native: Animation = PROFILE.native_combat.get_animation(role)
		var original: Animation = source.get_animation(native.get_meta("source_clip"))
		check(native.get_meta("native_keyframes",false) and native.get_meta("source_sha256","") == hash,"Combat source provenance: "+role)
		var same := native.get_track_count() == original.get_track_count() and is_equal_approx(native.length,original.length) and native.loop_mode == original.loop_mode
		for track in original.get_track_count():
			same = same and native.track_get_path(track) == original.track_get_path(track) and native.track_get_type(track) == original.track_get_type(track) and native.track_get_interpolation_type(track) == original.track_get_interpolation_type(track) and native.track_is_enabled(track) == original.track_is_enabled(track) and native.track_get_key_count(track) == original.track_get_key_count(track)
			for key in original.track_get_key_count(track):
				same = same and is_equal_approx(native.track_get_key_time(track,key),original.track_get_key_time(track,key)) and is_equal_approx(native.track_get_key_transition(track,key),original.track_get_key_transition(track,key)) and same_value(native.track_get_key_value(track,key),original.track_get_key_value(track,key))
		check(same,"All source tracks, keys, durations and interpolation preserved: "+role)
	var invalid = PROFILE.duplicate(true)
	invalid.light_attacks[0].strike_end = 100.0
	var previous := source.get_animation_list()
	check(not invalid.install(source) and source.get_animation_list() == previous,"Invalid strike landmarks reject atomically")
	reference.free()
	imported.free()

func start_now(actor: CharacterBody3D, action: String) -> bool:
	var ticket: RefCounted = actor.actions.request(action)
	actor.actions.tick()
	return ticket.accepted

func sample_landmarks(actor: CharacterBody3D, combo: int) -> void:
	var setup: Resource = PROFILE.light_attacks[combo]
	var action: Resource = actor.actions.active_definition
	var before: Vector3 = actor.position
	var stamina: float = actor.stamina
	for point in [[action.windup,setup.strike_start],[action.windup+action.active_seconds,setup.strike_end]]:
		actor.actions.timer = point[0]
		actor.model.update_pose(0)
		check(actor.model.animation.assigned_animation == setup.clip and absf(actor.model.animation.current_animation_position-point[1]) < 0.00001,"Gameplay phase boundary samples the declared source strike landmark")
		var pose: Array = actor.presentation.capture_pose()
		# Compare the runtime arm with the original imported source, not a baked adapter.
		var imported: Node3D = SOURCE.instantiate()
		root.add_child(imported)
		var source: AnimationPlayer = imported.find_child("AnimationPlayer",true,false)
		var skeleton: Skeleton3D = imported.find_child("Skeleton3D",true,false)
		source.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		source.play("Sword_Regular_A" if combo == 0 else "Sword_Regular_B")
		source.seek(point[1],true)
		source.advance(0)
		var authored := true
		for name in ["upperarm_r","lowerarm_r","hand_r","index_01_r"]:
			var bone := skeleton.find_bone(name)
			authored = authored and pose[bone][0].is_equal_approx(skeleton.get_bone_pose_rotation(bone)) and pose[bone][1].is_equal_approx(skeleton.get_bone_pose_position(bone))
		check(authored,"Native attack arm/fingers receive no legacy procedural twist")
		imported.free()
	actor.actions.timer = action.windup+action.active_seconds+action.recovery*0.5
	actor.model.update_pose(0)
	check(actor.model.animation.assigned_animation == setup.recovery_clip,"Recovery phase selects the matching authored return clip")
	check(actor.position == before and actor.stamina == stamina,"Repeated pose sampling cannot move or charge the gameplay actor")
	actor.actions.timer = 0

func verify_attacks(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	await reset_pair(rate)
	var native: CharacterBody3D = actors[0]
	var legacy: CharacterBody3D = actors[1]
	var other: CharacterBody3D = actors[2]
	var original_other: Array = other.presentation.capture_pose()
	for combo in [0,1,0]:
		for actor in [native,legacy]:
			actor.services.swings.clear()
			check(start_now(actor,"light"),"%s Hz: light combo request accepted" % rate)
		check(native.combo == combo and legacy.combo == combo,"%s Hz: combo preserves A/B/A order" % rate)
		sample_landmarks(native,combo)
		check(other.presentation.sword_attack.current == null and other.presentation.capture_pose() == original_other,"A second UAL actor shares clips but not playback state")
		var synchronized := true
		var finite := true
		for frame in rate*2:
			await step(1,rate)
			synchronized = synchronized and native.state == legacy.state and absf(native.stamina-legacy.stamina) < 0.0001 and absf(native.timer-legacy.timer) < 0.00001 and absf(native.position.z-legacy.position.z) < 0.0001
			for bone in native.model.skeleton.get_bone_count(): finite = finite and native.model.skeleton.get_bone_global_pose(bone).is_finite()
			if native.actions.is_available(): break
		check(synchronized and native.actions.is_available(),"%s Hz: source playback preserves action duration, stamina and lunge displacement" % rate)
		check(finite,"%s Hz: all attack/recovery bone transforms stay finite" % rate)
		check(not native.services.swings.is_empty() and native.services.swings == legacy.services.swings,"%s Hz: damage amount and active damage ticks match the legacy player" % rate)
		for hit in native.services.swings:
			check(hit[0] >= native.tuning.light.windup and hit[0] < native.tuning.light.windup+native.tuning.light.active_seconds and hit[1] == native.tuning.light.damage,"Damage remains inside the authoritative active window")
		check(native.presentation.sword_attack.current == null,"Finished combo releases the pose driver")
		original_other = other.presentation.capture_pose()
	await reset_pair(rate)
	check(start_now(native,"heavy"),"Heavy attack remains available")
	native.model.update_pose(0)
	check(native.presentation.sword_attack.current == PROFILE.heavy_attack and native.model.animation.assigned_animation == &"combat/sword_heavy","Heavy attack selects the UAL1 source profile")
	await reset_pair(rate)
	check(await ActionTest.start(native,&"jump"),"Airborne attack fixture takes off")
	await step(rate/4,rate)
	check(start_now(native,"light") and native.movement.in_flight,"Light attack starts in flight")
	native.actions.timer = native.tuning.light.windup
	native.presentation.jump.sample(0)
	var legs: Array = native.presentation.capture_pose()
	native.model.update_pose(0)
	var keeps_flight := true
	for bone in native.model.skeleton.get_bone_count():
		if not native.presentation.sword_attack.upper_body.has(bone):
			keeps_flight = keeps_flight and legs[bone][0].is_equal_approx(native.model.skeleton.get_bone_pose_rotation(bone)) and legs[bone][1].is_equal_approx(native.model.skeleton.get_bone_pose_position(bone))
	check(keeps_flight,"%s Hz: airborne sword swing preserves the jumping pelvis and legs" % rate)
	await reset_pair(rate)
	check(start_now(native,"light"),"Interruption fixture starts attack")
	native.take_damage(1.0,"sword_interrupt_%s" % rate)
	native.model.update_pose(0)
	check(native.presentation.sword_attack.current == null and native.state == State.HURT,"Damage immediately cancels native attack playback")
	await reset_pair(rate)
	check(start_now(native,"light"),"Ragdoll fixture starts attack")
	native.reactions.begin(false,true)
	check(native.presentation.sword_attack.current == null and native.model.equipment.current_sockets[&"sword"] == &"right_hand","Ragdoll cancels playback and retains the attached sword")
	await reset_pair(rate)
	check(start_now(native,"light"),"Death fixture starts attack")
	native.take_damage(native.health+1,"sword_death_%s" % rate)
	check(native.dead and native.presentation.sword_attack.current == null and native.model.equipment.death_frozen,"Death cannot resume a queued attack or restore equipment")
	await reset_pair(rate)
	check(start_now(native,"light") and native.combo == 0 and native.presentation.sword_attack.serial == native.actions.serial,"Reset starts a fresh A without stale playback state")
	var sword: Node3D = native.model.equipment.items[&"sword"].visual
	check(sword.get_parent() == native.model.equipment.socket_frame(&"right_hand"),"Sword stays on the animated right-hand socket")
	await reset_pair(rate)

func run() -> void:
	verify_combat_source()
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
		actors.append(actor)
	check(actors[0].model.rig.identifier == &"ual1_65_v1" and actors[0].model.equipment.items.size() == 1,"Normal player defaults to UAL with the actual sword and no review markers")
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]: await verify_attacks(rate)
	Engine.physics_ticks_per_second = original_rate
	check(start_now(actors[0],"light"),"Scene teardown fixture starts attack")
	var presentation: RefCounted = actors[0].presentation.sword_attack
	var actions: RefCounted = actors[0].actions
	world.free()
	actors.clear()
	check(presentation.actor == null and presentation.current == null and not actions.started.is_connected(presentation.on_started),"Scene exit disconnects the native attack driver")
	print("UAL SWORD RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
