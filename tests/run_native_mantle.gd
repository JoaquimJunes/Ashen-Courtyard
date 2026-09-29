extends "res://tests/run_mantle.gd"
## Synthetic root-motion contract fixture; never substitutes for a shipped clip.
const CLIP := &"mantle_contract/pull_up"
var native_clip: Animation
var source_profile: Resource
var other: CharacterBody3D

func install_fixture() -> void:
	source_profile = p.model.animation_profile
	p.model.animation_profile = source_profile.duplicate()
	p.model.animation_profile.mantle_clip = CLIP
	p.model.animation_profile.mantle_source_end_seconds = 0.0
	native_clip = Animation.new()
	native_clip.length = 1.7
	var root_track := native_clip.add_track(Animation.TYPE_POSITION_3D)
	native_clip.track_set_path(root_track,NodePath("Armature/Skeleton3D:root"))
	native_clip.position_track_insert_key(root_track,0,Vector3.ZERO)
	native_clip.position_track_insert_key(root_track,native_clip.length,Vector3(0,1,-0.6))
	for name in ["spine_02","thigh_l","index_01_r"]:
		var bone: int = p.model.skeleton.find_bone(name)
		var rest: Quaternion = p.model.skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var track := native_clip.add_track(Animation.TYPE_ROTATION_3D)
		native_clip.track_set_path(track,NodePath("Armature/Skeleton3D:"+name))
		native_clip.rotation_track_insert_key(track,0,rest)
		native_clip.rotation_track_insert_key(track,native_clip.length,rest*Quaternion(Vector3.RIGHT,0.35))
	var library := AnimationLibrary.new()
	library.add_animation(&"pull_up",native_clip)
	p.model.animation.add_animation_library(&"mantle_contract",library)

func verify_sequence(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	check(await start_grab(),"%s Hz: real ledge grab prepares native playback" % rate)
	p.model.update_pose(0)
	check(not p.presentation.mantle.native.active,"Hang retains the contact/shimmy presentation")
	p.controller.intent.surface_motion = Vector2(0,1)
	var sampled := false
	var authored := true
	var authored_legs := true
	var authored_leg_samples := 0
	var exit_legs := true
	var exit_samples := 0
	var source_clock := true
	var contacts_disabled := true
	var roots_consumed := true
	var finite := true
	var repeated_safe := true
	var equipment_stowed := true
	var last_time := 0.0
	var monotonic := true
	for frame in rate*3:
		await settle(1)
		p.pose_driver.evaluate(1.0/rate)
		var driver: RefCounted = p.presentation.mantle.native
		if driver.active:
			sampled = true
			monotonic = monotonic and driver.source_time >= last_time
			last_time = driver.source_time
			var skeleton: Skeleton3D = p.model.skeleton
			var action: RefCounted = p.traversal.mantle
			var total: float = action.definition.lift_seconds+action.definition.over_seconds+action.definition.stand_seconds
			var clock: float = action.elapsed
			if action.phase >= action.Phase.OVER: clock += action.definition.lift_seconds
			if action.phase >= action.Phase.STAND: clock += action.definition.over_seconds
			if action.phase >= action.Phase.SETTLE: clock = total
			var source_end: float = p.model.animation_profile.mantle_source_end_seconds
			if source_end <= 0: source_end = native_clip.length
			source_clock = source_clock and is_equal_approx(driver.source_time,minf(source_end,native_clip.length*clock/total))
			if p.model.animation_profile.mantle_source_end_seconds > 0 and driver.exit_weight > 0:
				exit_samples += 1
				for side in ["l","r"]:
					for part in ["thigh_","calf_","foot_","ball_","ball_leaf_"]:
						var bone := skeleton.find_bone(part+side)
						var track := native_clip.find_track(NodePath("Armature/Skeleton3D:"+part+side),Animation.TYPE_ROTATION_3D)
						var rotation := native_clip.rotation_track_interpolate(track,source_end) if track >= 0 else skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
						var expected := rotation.slerp(p.presentation.mantle.idle[bone][0],driver.exit_weight)
						exit_legs = exit_legs and is_equal_approx(absf(skeleton.get_bone_pose_rotation(bone).dot(expected)),1.0)
			contacts_disabled = contacts_disabled and p.model.locomotion.contacts.is_empty() and p.model.locomotion.anchors.is_empty()
			var root_bone := skeleton.find_bone("root")
			roots_consumed = roots_consumed and skeleton.get_bone_pose_position(root_bone).is_equal_approx(skeleton.get_bone_rest(root_bone).origin)
			if driver.entry_weight >= 1 and driver.exit_weight <= 0:
				authored_leg_samples += 1
				for side in ["l","r"]:
					for part in ["thigh_","calf_","foot_","ball_","ball_leaf_"]:
						var name: String = part+side
						var bone := skeleton.find_bone(name)
						var path := NodePath("Armature/Skeleton3D:"+name)
						var rotation_track := native_clip.find_track(path,Animation.TYPE_ROTATION_3D)
						var position_track := native_clip.find_track(path,Animation.TYPE_POSITION_3D)
						var rotation := native_clip.rotation_track_interpolate(rotation_track,driver.source_time) if rotation_track >= 0 else skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
						var position := native_clip.position_track_interpolate(position_track,driver.source_time) if position_track >= 0 else skeleton.get_bone_rest(bone).origin
						# q and -q describe the same rotation; entry blending may
						# select either representation without changing the pose.
						var sampled_rotation := skeleton.get_bone_pose_rotation(bone)
						authored_legs = authored_legs and is_equal_approx(absf(sampled_rotation.dot(rotation)),1.0) and skeleton.get_bone_pose_position(bone).is_equal_approx(position)
				for name in ["spine_02","index_01_r"]:
					var bone := skeleton.find_bone(name)
					var track := native_clip.find_track(NodePath("Armature/Skeleton3D:"+name),Animation.TYPE_ROTATION_3D)
					var rotation := native_clip.rotation_track_interpolate(track,driver.source_time) if track >= 0 else skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
					authored = authored and skeleton.get_bone_pose_rotation(bone).is_equal_approx(rotation)
			for bone in skeleton.get_bone_count(): finite = finite and skeleton.get_bone_global_pose(bone).is_finite()
			var transform: Transform3D = p.global_transform
			var stamina: float = p.stamina
			var time: float = driver.source_time
			p.model.update_pose(0)
			p.model.update_pose(0)
			repeated_safe = repeated_safe and p.global_transform == transform and p.stamina == stamina and driver.source_time == time
			equipment_stowed = equipment_stowed and p.model.equipment.current_sockets[&"sword"] == &"left_hip"
		if not p.traversal.attached(): break
	check(sampled and monotonic,"%s Hz: source playback follows the accepted mantle clock" % rate)
	check(source_clock,"%s Hz: pull-up keeps its playback rate and never samples beyond the configured source ending" % rate)
	if p.model.animation_profile.mantle_source_end_seconds > 0:
		check(exit_legs and exit_samples > 0,"%s Hz: the top pose blends directly to idle without the source walking tail" % rate)
	check(authored,"%s Hz: native torso and fingers survive the contact adapter" % rate)
	check(authored_legs and authored_leg_samples > 0,"%s Hz: both legs and feet retain the authored source pose throughout the native mantle" % rate)
	check(contacts_disabled,"%s Hz: mantle clears walking foot anchors and terrain contacts" % rate)
	check(roots_consumed and repeated_safe,"%s Hz: root motion and repeated pose sampling never move or charge the actor" % rate)
	check(finite and equipment_stowed,"%s Hz: finite contact pose retains temporarily stowed equipment" % rate)
	check(p.traversal.reason == &"completed" and absf(p.position.y-1.5) < 0.035 and not p.motor.tucked,"%s Hz: unchanged collision phases finish on real ledge support" % rate)
	check(not p.presentation.mantle.native.active and p.model.equipment.current_sockets[&"sword"] == &"right_hand","%s Hz: completion releases native driver and restores equipment" % rate)

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	p.model.set_process(false)
	other = load("res://scenes/player.tscn").instantiate()
	stage.add_child(other)
	other.set_physics_process(false)
	other.model.set_process(false)
	other.position = Vector3(20,0,0)
	var other_pose: Array = other.presentation.capture_pose()
	install_fixture()
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]: await verify_sequence(rate)
	check(other.presentation.capture_pose() == other_pose and not other.presentation.mantle.native.active,"A second character keeps independent mantle playback state")
	# Exercise the actual requested root-motion source as well as the exaggerated
	# synthetic fixture above. No replacement keys are authored into either asset.
	p.model.animation_profile = source_profile
	var actual_clip: StringName = source_profile.mantle_clip
	check(actual_clip != &"" and p.model.animation.has_animation(actual_clip),"Requested native mantle source is installed")
	if actual_clip != &"" and p.model.animation.has_animation(actual_clip):
		native_clip = p.model.animation.get_animation(actual_clip)
		var root_track := native_clip.find_track(NodePath("Armature/Skeleton3D:root"),Animation.TYPE_POSITION_3D)
		check(root_track >= 0 and native_clip.position_track_interpolate(root_track,native_clip.length).length() > 1,"Actual mantle source contains root displacement to consume")
		for rate in [30,60,120]: await verify_sequence(rate)
	p.model.animation_profile = source_profile.duplicate()
	p.model.animation_profile.mantle_clip = CLIP
	p.model.animation_profile.mantle_source_end_seconds = 0.0
	Engine.physics_ticks_per_second = 60
	for interruption in ["damage","death","ragdoll","reset","release"]:
		check(await start_grab(),"Prepare native mantle "+interruption)
		p.model.update_pose(0)
		p.controller.intent.surface_motion = Vector2(0,1)
		await settle(6)
		p.model.update_pose(0.1)
		check(p.presentation.mantle.native.active,"Native driver starts before "+interruption)
		if interruption == "damage": p.take_damage(1,"native_mantle_damage")
		elif interruption == "death": p.take_damage(p.health+1,"native_mantle_death")
		elif interruption == "ragdoll": p.reactions.begin(false,true)
		elif interruption == "reset": p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.05,0.5)))
		else: p.traversal.release(&"test_release")
		check(not p.presentation.mantle.native.active and not p.traversal.attached(),"Native driver clears on "+interruption)
	p.model.animation_profile.mantle_clip = &"missing/clip"
	check(await start_grab(),"Missing source fixture still grabs")
	p.controller.intent.surface_motion = Vector2(0,1)
	await settle(6)
	p.model.update_pose(0.1)
	check(not p.presentation.mantle.native.active and p.presentation.mantle.active,"Missing native source safely retains the procedural contact fallback")
	p.traversal.release(&"test_release")
	p.model.animation_profile = source_profile
	check(await start_grab(),"Prepare native mantle scene exit")
	p.controller.intent.surface_motion = Vector2(0,1)
	await settle(6)
	p.model.update_pose(0.1)
	var driver: RefCounted = p.presentation.mantle.native
	check(driver.active,"Native driver starts before scene exit")
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await settle(2)
	check(not driver.active and driver.entry.is_empty(),"Scene exit clears the native mantle playback state")
	print("NATIVE MANTLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
