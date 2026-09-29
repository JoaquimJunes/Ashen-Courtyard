extends SceneTree
## Native data fidelity and real actor behavior are separate contracts.
const PROFILE = preload("res://features/presentation/data/ual_animation_profile.tres")
const UAL = preload("res://scenes/models/ual_mannequin.tscn")
const LEGACY = preload("res://scenes/models/psx_knight.tscn")
const Intent = preload("res://features/character/character_intent.gd")
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var world: Node3D
var actors: Array[CharacterBody3D] = []
var intents: Array[RefCounted] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	# Text resources round floating-point serialization, but not authored poses.
	if a is Vector3: return a.distance_to(b) < 0.00001
	if a is Quaternion: return absf(a.x-b.x)+absf(a.y-b.y)+absf(a.z-b.z)+absf(a.w-b.w) < 0.00001
	if a is float: return absf(a-b) < 0.00001
	return a == b

func verify_source() -> void:
	var imported: Node3D = preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	root.add_child(imported)
	var source: AnimationPlayer = imported.find_child("AnimationPlayer",true,false)
	source.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var hash := FileAccess.get_sha256(preload("res://tools/ual_animation_build_manifest.tres").source_scene.resource_path)
	check(PROFILE.native_locomotion.get_animation_list().size() == 6,"Exactly six native locomotion clips")
	check(PROFILE.native_locomotion.get_meta("source_sha256","") == hash,"Library records the current untouched source import")
	var key_count := 0
	for role: String in PROFILE.native_source_clips:
		var original: Animation = source.get_animation(PROFILE.native_source_clips[role])
		var native: Animation = PROFILE.native_locomotion.get_animation(role)
		check(is_equal_approx(native.length,original.length) and native.loop_mode == original.loop_mode,role+": source duration and looping preserved")
		check(native.get_meta("source_sha256","") == hash and native.get_meta("source_clip","") == PROFILE.native_source_clips[role],role+": source provenance")
		var track_properties := native.get_track_count() == original.get_track_count()
		var key_properties := track_properties
		var key_values := track_properties
		for track in mini(native.get_track_count(),original.get_track_count()):
			track_properties = track_properties and native.track_get_path(track) == original.track_get_path(track) and native.track_get_type(track) == original.track_get_type(track) and native.track_is_enabled(track) == original.track_is_enabled(track) and native.track_get_interpolation_type(track) == original.track_get_interpolation_type(track) and native.track_get_interpolation_loop_wrap(track) == original.track_get_interpolation_loop_wrap(track)
			key_properties = key_properties and native.track_get_key_count(track) == original.track_get_key_count(track)
			for key in mini(native.track_get_key_count(track),original.track_get_key_count(track)):
				key_count += 1
				key_properties = key_properties and is_equal_approx(native.track_get_key_time(track,key),original.track_get_key_time(track,key)) and is_equal_approx(native.track_get_key_transition(track,key),original.track_get_key_transition(track,key))
				key_values = key_values and same_value(native.track_get_key_value(track,key),original.track_get_key_value(track,key))
		check(track_properties,role+": track targets, types, interpolation and enabled state unchanged")
		check(key_properties,role+": all source key counts, times and transitions unchanged")
		check(key_values,role+": every authored transform key unchanged")
		if role in ["walk","jog","sprint","crouch_walk"]:
			check(native.get_meta("plant_l",[]).size() == 121 and native.get_meta("plant_r",[]).size() == 121,role+": source-observed sole contact metadata")
	var before := source.get_animation_list()
	var invalid = PROFILE.duplicate()
	invalid.aliases = {"k_idle":"missing_native_or_fallback"}
	check(not invalid.install(source) and source.get_animation_list() == before,"Invalid profile leaves the imported library available")
	check(PROFILE.install(source),"Complete profile installs atomically")
	for alias: String in PROFILE.aliases:
		var role: StringName = PROFILE.aliases[alias]
		var native: bool = PROFILE.native_locomotion.has_animation(role) or PROFILE.native_combat.has_animation(role) or PROFILE.native_actions.has_animation(role) or PROFILE.native_swimming.has_animation(role)
		check(source.get_animation(alias) == PROFILE.clip_for(alias) and PROFILE.is_native(alias) == native,alias+": correct native/fallback ownership")
	check(PROFILE.temporary_fallbacks.size() >= 5 and PROFILE.free_hand_actions == [&"bolt",&"burst",&"heal"],"Unmigrated actions are labeled and free-hand requests are editable")
	print("UAL source verification: ",key_count," authored keys across six clips")
	imported.free()

func step(frames: int, rate: int) -> void:
	for frame in frames:
		await physics_frame
		for actor in actors: actor.pose_driver.evaluate(1.0/rate)
	await process_frame

func reset_pair(rate: int) -> void:
	intents.clear()
	for index in actors.size():
		var intent := Intent.new()
		intents.append(intent)
		actors[index].submit_intent(intent)
		actors[index].reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(index*8,0.05,6)))
	await step(rate/2,rate)

func verify_runtime() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(100,1,100),Vector3(0,-0.5,0),Color.GRAY)
	for index in 2:
		var actor: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
		actor.model_scene = UAL if index == 0 else LEGACY
		actor.controller.manual = true
		world.add_child(actor)
		actor.model.set_process(false)
		actors.append(actor)
	var native: CharacterBody3D = actors[0]
	var legacy: CharacterBody3D = actors[1]
	check(native.model.rig is Resource and native.model.rig.identifier == &"ual1_65_v1" and legacy.model.rig.identifier == &"knight_14","Editable rigs keep canonical and legacy defaults separate")
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await reset_pair(rate)
		var lower_arm: int = native.model.rig.bone(native.model.skeleton,"LowerArm.r")
		native.model.skeleton.reset_bone_poses()
		native.model.animation.play("k_idle")
		native.model.animation.seek(0.3,true)
		native.model.animation.advance(0)
		var authored_arm: Quaternion = native.model.skeleton.get_bone_pose_rotation(lower_arm)
		native.model.apply_combat_pose(native)
		check(authored_arm.is_equal_approx(native.model.skeleton.get_bone_pose_rotation(lower_arm)),"%s Hz: native idle has no permanent fallback arm twist" % rate)
		for mode in ["jog","sprint","crouch"]:
			await reset_pair(rate)
			if mode == "crouch":
				for actor in actors: check(await ActionTest.start(actor,&"crouch"),"%s Hz: %s accepts crouch" % [rate,actor.model.rig.identifier])
				await step(rate/2,rate)
				var clock: float = native.presentation.crouch.clock
				await step(rate/4,rate)
				check(native.presentation.crouch.clock > clock+0.1,"%s Hz: native crouch idle advances its authored animation" % rate)
			for intent in intents:
				intent.movement = Vector3.FORWARD
				intent.sprint = mode == "sprint"
			await step(rate,rate)
			var expected: String = "crouch/crouch_walk" if mode == "crouch" else "running/"+mode
			check(native.model.animation.current_animation == expected,"%s Hz: %s selects native locomotion" % [rate,mode])
			check(native.velocity.distance_to(legacy.velocity) < 0.001 and absf(native.position.z-legacy.position.z) < 0.001,"%s Hz: %s keeps existing motor speed and displacement" % [rate,mode])
			check(absf(native.stamina-legacy.stamina) < 0.001,"%s Hz: %s keeps existing stamina timing" % [rate,mode])
			var finite := true
			for bone in native.model.skeleton.get_bone_count(): finite = finite and native.model.skeleton.get_bone_global_pose(bone).is_finite()
			check(finite and native.model.dodge_skin_min_height() > -0.04,"%s Hz: %s finalized pose stays finite and clear of floor" % [rate,mode])
			if mode == "crouch":
				check(-native.model.dodge_skin_min_height(Vector3.DOWN) <= native.posture.definition.crouch_height,"%s Hz: native crouch remains inside the existing collider height" % rate)
				for intent in intents: intent.movement = Vector3.ZERO
				await step(rate/2,rate)
				var roof := Shapes.solid(world,Vector3(16,0.2,4),native.position+Vector3(4,1.6,0),Color.GRAY)
				await step(3,rate)
				check(not (await ActionTest.start(native,&"crouch")) and native.posture.crouched and is_equal_approx(native.motor.capsule.height,native.posture.definition.crouch_height),"%s Hz: native presentation preserves blocked stand and authored physical posture" % rate)
				roof.free()
			check(not native.dead and not legacy.dead,"%s Hz: %s causes no unexpected death" % [rate,mode])
	Engine.physics_ticks_per_second = original_rate
	world.free()
	actors.clear()

func run() -> void:
	verify_source()
	await verify_runtime()
	print("UAL NATIVE RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
