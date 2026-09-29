extends SceneTree
const Helper = preload("res://tools/art_preview_retarget.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children(): result.append_array(nodes(child))
	return result
func clip_data(animation: Animation) -> Array:
	var data := [animation.length, animation.loop_mode]
	for track in animation.get_track_count():
		data.append([animation.track_get_type(track), String(animation.track_get_path(track)), animation.track_get_interpolation_type(track)])
		for key in animation.track_get_key_count(track):
			var value = animation.track_get_key_value(track,key)
			if value is Vector3: value = [value.x,value.y,value.z]
			elif value is Quaternion: value = [value.x,value.y,value.z,value.w]
			data.append([animation.track_get_key_time(track,key),value])
	return data
func clip_digest(animation: Animation) -> String:
	return JSON.stringify(clip_data(animation),"",true,true).sha256_text()
func run() -> void:
	var target: Node = load("res://assets/models/ual/runtime_rig.tscn").instantiate()
	root.add_child(target)
	var target_skeleton: Skeleton3D = target.get_node("Armature/Skeleton3D")
	var target_hash := Helper.rig_fingerprint(target_skeleton)
	var profile_helper := Helper.new()
	var valid_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Helper.PROFILES[0]))
	for field in ["id","version","source_motion_bone","source_to_target","target_rest_only","source_world_to_target_world"]:
		var malformed := valid_profile.duplicate(true)
		malformed.erase(field)
		check(not profile_helper.validate_profile(malformed,"fixture"),"Malformed profile rejects missing "+field)
	var malformed := valid_profile.duplicate(true)
	malformed.source_world_to_target_world = [[1,0],[0,1,0],[0,0,1]]
	check(not profile_helper.validate_profile(malformed,"fixture"),"Malformed basis dimensions reject")
	malformed = valid_profile.duplicate(true)
	malformed.source_world_to_target_world[0][0] = NAN
	check(not profile_helper.validate_profile(malformed,"fixture"),"Nonfinite basis rejects")
	malformed = valid_profile.duplicate(true)
	malformed.source_to_target.mixamorig_LeftArm = malformed.source_to_target.mixamorig_RightArm
	check(not profile_helper.validate_profile(malformed,"fixture"),"Duplicate target mapping rejects")
	var target_rests := []
	for bone in target_skeleton.get_bone_count(): target_rests.append(target_skeleton.get_bone_rest(bone))
	var target_rest_world := []
	for bone in target_skeleton.get_bone_count(): target_rest_world.append(target_skeleton.global_transform * target_skeleton.get_bone_global_rest(bone))
	var groups := {}
	var paths := DirAccess.get_files_at("res://assets/animations/Mixamo")
	var expected_source_count := Array(paths).filter(func(path): return String(path).ends_with(".fbx")).size()
	var source_count := 0
	var negative_checked := false
	for file in paths:
		if not file.ends_with(".fbx"): continue
		var source_path := "res://assets/animations/Mixamo/" + file
		var before := FileAccess.get_sha256(source_path)
		var source: Node = load(source_path).instantiate()
		root.add_child(source)
		var skeleton := source.find_child("Skeleton3D",true,false) as Skeleton3D
		var player: AnimationPlayer
		for node in nodes(source):
			if node is AnimationPlayer: player = node
		var helper := Helper.new()
		var profile := helper.profile_for(skeleton, target_skeleton)
		check(not profile.is_empty(), file + ": fingerprint must match explicit profile")
		if profile.is_empty(): source.free(); continue
		groups[profile.id] = groups.get(profile.id,0) + 1
		var clip_name := String(Array(player.get_animation_list()).filter(func(name): return name != &"RESET")[0])
		var original := player.get_animation(clip_name)
		var original_digest := clip_digest(original)
		var source_clip := {"name":clip_name,"animation":original,"root":player.get_node(player.root_node)}
		var output := helper.transfer(source,[source_clip],target)
		check(not output.is_empty(), file + ": " + helper.last_error)
		if output.is_empty(): source.free(); continue
		source_count += 1
		var baked: Animation = output.clips[0].animation
		var times := helper.sample_times(original.length)
		check(baked.length == original.length, file + ": exact source duration")
		check(times[0] == 0 and times[-1] == original.length, file + ": both exact endpoints")
		for i in range(1,times.size()-1): check(absf(times[i] - times[i-1] - 1.0/120.0) < 0.0000001,file + ": 120 Hz intervals")
		var library := AnimationLibrary.new()
		library.add_animation("retarget",baked)
		var target_player := AnimationPlayer.new()
		target_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		target_player.add_animation_library("",library)
		target.add_child(target_player)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var hips := skeleton.find_bone("mixamorig_Hips")
		var pelvis := target_skeleton.find_bone("pelvis")
		var root_bone := target_skeleton.find_bone("root")
		var source_rest_hips := (skeleton.global_transform*skeleton.get_bone_global_rest(hips)).origin
		var first_source := Vector3.ZERO
		var first_target := Vector3.ZERO
		# Independent oracle: original AnimationPlayer, not the helper's sampler.
		for phase in 17:
			var time := original.length * float(phase) / 16.0
			skeleton.reset_bone_poses()
			target_skeleton.reset_bone_poses()
			player.play(clip_name)
			player.seek(time,true)
			target_player.play("retarget")
			target_player.seek(time,true)
			skeleton.force_update_all_bone_transforms()
			target_skeleton.force_update_all_bone_transforms()
			var source_hips := (skeleton.global_transform*skeleton.get_bone_global_pose(hips)).origin
			var target_hips := (target_skeleton.global_transform*target_skeleton.get_bone_global_pose(pelvis)).origin
			check(target_hips.distance_to(target_rest_world[pelvis].origin + source_hips - source_rest_hips) < 0.00002,file + ": no centering, scaling, floor snapping or lost travel")
			if phase == 0:
				first_source = source_hips
				first_target = target_hips
			check((target_hips-first_target).distance_to(source_hips-first_source) < 0.00002,file + ": travel direction and distance preserved")
			for bone in target_skeleton.get_bone_count():
				if bone != root_bone: check(target_skeleton.get_bone_pose_position(bone).is_equal_approx(target_rests[bone].origin),file+": UAL limb length retained")
				check(target_skeleton.get_bone_pose_scale(bone).is_equal_approx(target_rests[bone].basis.get_scale()),file+": UAL scale retained")
			for source_name in ["mixamorig_Hips","mixamorig_Head","mixamorig_LeftHand","mixamorig_RightFoot"]:
				var source_bone := skeleton.find_bone(source_name)
				var target_bone := target_skeleton.find_bone(profile.source_to_target[source_name])
				var source_rest := (skeleton.global_transform*skeleton.get_bone_global_rest(source_bone)).basis.orthonormalized().get_rotation_quaternion()
				var source_pose := (skeleton.global_transform*skeleton.get_bone_global_pose(source_bone)).basis.orthonormalized().get_rotation_quaternion()
				var expected: Quaternion = (source_pose*source_rest.inverse()*target_rest_world[target_bone].basis.orthonormalized().get_rotation_quaternion()).normalized()
				var actual := (target_skeleton.global_transform*target_skeleton.get_bone_global_pose(target_bone)).basis.orthonormalized().get_rotation_quaternion()
				check(1.0-absf(actual.dot(expected)) < 0.00002,file+": independent source orientation oracle")
		target_player.free()
		check(clip_digest(original)==original_digest,file+": original clip unchanged")
		check(FileAccess.get_sha256(source_path)==before,file+": original FBX unchanged")
		check(Helper.rig_fingerprint(target_skeleton)==target_hash,file+": reference rig unchanged")
		if profile.id == "mixamo_crawl_v1" and not negative_checked:
			negative_checks(helper,source,source_clip,target,skeleton,target_skeleton)
			negative_checked = true
		source.free()
	check(expected_source_count > 0 and source_count==expected_source_count,"Every available meshless Mixamo source must transfer")
	check(groups.size()==2 and groups.has("mixamo_common_v1") and groups.has("mixamo_crawl_v1"),"Available sources use the two explicitly validated rig profiles")
	check(negative_checked,"Incompatible tracks/rigs must be tested regardless of source filename")
	target.free()
	print("ART PREVIEW RETARGET: %d checks, %d failures; %d actual source clips" % [checks,failures,source_count])
	quit(1 if failures else 0)
func negative_checks(helper: RefCounted, source: Node, clip: Dictionary, target: Node, skeleton: Skeleton3D, target_skeleton: Skeleton3D) -> void:
	var rest := skeleton.get_bone_rest(0)
	var altered := rest
	altered.origin.x += 0.01
	skeleton.set_bone_rest(0,altered)
	check(helper.transfer(source,[clip],target).is_empty(),"Unknown source rest fingerprint rejects")
	skeleton.set_bone_rest(0,rest)
	var target_rest := target_skeleton.get_bone_rest(0)
	altered = target_rest
	altered.origin.x += 0.01
	target_skeleton.set_bone_rest(0,altered)
	check(helper.transfer(source,[clip],target).is_empty(),"Changed target rig rejects")
	target_skeleton.set_bone_rest(0,target_rest)
	for kind in ["translation","scale","auxiliary","method","nan"]:
		var changed: Animation = clip.animation.duplicate()
		var track := -1
		var path := String(clip.root.get_path_to(skeleton))
		if kind == "translation":
			track=changed.add_track(Animation.TYPE_POSITION_3D)
			changed.track_set_path(track,NodePath(path+":mixamorig_LeftArm"))
			changed.position_track_insert_key(track,0,skeleton.get_bone_rest(skeleton.find_bone("mixamorig_LeftArm")).origin+Vector3(0.02,0,0))
		elif kind == "scale":
			track=changed.add_track(Animation.TYPE_SCALE_3D)
			changed.track_set_path(track,NodePath(path+":mixamorig_Hips"))
			changed.scale_track_insert_key(track,0,Vector3(1.1,1,1))
		elif kind == "auxiliary":
			track=changed.add_track(Animation.TYPE_ROTATION_3D)
			changed.track_set_path(track,NodePath(path+":mixamorig_HeadTop_End"))
			changed.rotation_track_insert_key(track,0,Quaternion(Vector3.RIGHT,0.3))
		elif kind == "method":
			track=changed.add_track(Animation.TYPE_METHOD)
			changed.track_set_path(track,NodePath(path+":mixamorig_Hips"))
			changed.track_insert_key(track,0,{"method":"queue_free","args":[]})
		else:
			changed.track_set_key_value(0,0,Vector3(NAN,0,0))
		var invalid := {"name":clip.name,"animation":changed,"root":clip.root}
		check(helper.transfer(source,[invalid],target).is_empty(),"Unsupported " + kind + " rejects without a preview")
