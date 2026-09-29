extends RefCounted
## Preview-only rest-relative Mixamo transfer. Never used by character gameplay.
const PROFILES := ["res://tools/art_preview_retarget_profiles/mixamo_common_v1.json", "res://tools/art_preview_retarget_profiles/mixamo_crawl_v1.json"]
const SAMPLE_HZ := 120.0
const TOLERANCE := 0.00001
var last_error := ""

func reject(message: String) -> Dictionary:
	last_error = message
	return {}

static func rig_fingerprint(skeleton: Skeleton3D) -> String:
	var bones := []
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		bones.append([String(skeleton.get_bone_name(index)), String(skeleton.get_bone_name(parent)) if parent >= 0 else "", skeleton.get_bone_rest(index)])
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes([skeleton.global_transform, bones]))
	return digest.finish().hex_encode()

func skeletons(node: Node) -> Array[Skeleton3D]:
	var result: Array[Skeleton3D] = []
	if node is Skeleton3D: result.append(node)
	for child in node.get_children(): result.append_array(skeletons(child))
	return result

func profile_for(source: Skeleton3D, target: Skeleton3D) -> Dictionary:
	var source_hash := rig_fingerprint(source)
	var target_hash := rig_fingerprint(target)
	for path in PROFILES:
		var profile = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not profile is Dictionary: return reject("Invalid retarget profile: " + path)
		if not validate_profile(profile, path): return {}
		if profile.get("source_fingerprint") != source_hash: continue
		if profile.get("target_fingerprint") != target_hash:
			return reject("UAL reference rig differs from retarget profile " + str(profile.get("id")))
		profile.path = path
		return profile
	return reject("No validated preview retarget profile matches this source hierarchy, rest pose and scene transform (" + source_hash + ").")

func profile_error(path: String, field: String) -> bool:
	last_error = "Invalid retarget profile %s: %s" % [path,field]
	return false

func validate_profile(profile: Dictionary, path: String) -> bool:
	for field in ["id", "source_fingerprint", "target_fingerprint", "source_motion_bone", "target_motion_bone", "motion_policy", "rotation_policy", "auxiliary_policy"]:
		if not profile.get(field) is String or profile[field].is_empty(): return profile_error(path,field+" must be a nonempty string")
	if profile.get("version") != 1: return profile_error(path,"version must be 1")
	if profile.get("fingerprint_algorithm") != "godot4-variant-rest-hierarchy-world-v1": return profile_error(path,"unsupported fingerprint_algorithm")
	var hash_pattern := RegEx.new()
	hash_pattern.compile("^[0-9a-f]{64}$")
	for field in ["source_fingerprint","target_fingerprint"]:
		if not hash_pattern.search(profile[field]): return profile_error(path,field+" must be a SHA-256 digest")
	if not profile.get("source_to_target") is Dictionary or profile.source_to_target.is_empty(): return profile_error(path,"source_to_target must contain named bone mappings")
	var destinations := []
	for name in profile.source_to_target:
		var destination = profile.source_to_target[name]
		if not name is String or name.is_empty() or not destination is String or destination.is_empty() or destination in destinations:
			return profile_error(path,"source_to_target contains an invalid or repeated target")
		destinations.append(destination)
	for field in ["unmapped_source_rest_only","target_rest_only"]:
		if not profile.get(field) is Array: return profile_error(path,field+" must be an array")
		var names := []
		for name in profile[field]:
			if not name is String or name.is_empty() or name in names: return profile_error(path,field+" contains an invalid or duplicate name")
			names.append(name)
	for name in profile.unmapped_source_rest_only:
		if profile.source_to_target.has(name): return profile_error(path,"source bone appears in both mapping and unmapped policy")
	for name in profile.target_rest_only:
		if name in destinations: return profile_error(path,"target bone appears in both mapping and rest-only policy")
	if not profile.source_to_target.has(profile.source_motion_bone): return profile_error(path,"source_motion_bone must have an explicit target mapping")
	if not profile.target_motion_bone in profile.target_rest_only: return profile_error(path,"target_motion_bone must be a rest-only root")
	var columns = profile.get("source_world_to_target_world")
	if not columns is Array or columns.size()!=3: return profile_error(path,"source_world_to_target_world must have three basis columns")
	for column in columns:
		if not column is Array or column.size()!=3: return profile_error(path,"each basis column must have three finite numbers")
		for value in column:
			if not (value is float or value is int) or not is_finite(value): return profile_error(path,"basis values must be finite numbers")
	return true

func sample_times(duration: float) -> PackedFloat64Array:
	var times := PackedFloat64Array()
	for index in int(floor(duration * SAMPLE_HZ)) + 1:
		var time := float(index) / SAMPLE_HZ
		if time < duration - 0.0000001: times.append(time)
	times.append(duration)
	return times

func transfer(source_scene: Node, clips: Array, target_scene: Node) -> Dictionary:
	last_error = ""
	var source_skeletons := skeletons(source_scene)
	var target_skeletons := skeletons(target_scene)
	if source_skeletons.size() != 1 or target_skeletons.size() != 1:
		return reject("Preview retargeting requires exactly one source and one target skeleton.")
	var source: Skeleton3D = source_skeletons[0]
	var target: Skeleton3D = target_skeletons[0]
	var profile := profile_for(source, target)
	if profile.is_empty(): return {}
	var mapping: Dictionary = profile.get("source_to_target", {})
	var ignored: Array = profile.get("unmapped_source_rest_only", [])
	var source_ids := {}
	var target_ids := {}
	var assigned := {}
	for name in mapping:
		var source_index := source.find_bone(name)
		var target_index := target.find_bone(mapping[name])
		if source_index < 0 or target_index < 0 or assigned.has(target_index):
			return reject("Invalid or duplicate retarget bone mapping: " + str(name))
		source_ids[name] = source_index
		target_ids[target_index] = source_index
		assigned[target_index] = true
	for index in source.get_bone_count():
		var name := String(source.get_bone_name(index))
		if not mapping.has(name) and not name in ignored: return reject("Undeclared source bone: " + name)
	for index in target.get_bone_count():
		if not assigned.has(index) and not String(target.get_bone_name(index)) in profile.target_rest_only:
			return reject("Undeclared target bone: " + String(target.get_bone_name(index)))
	var hips := source.find_bone(profile.source_motion_bone)
	var root_motion := target.find_bone(profile.target_motion_bone)
	if hips < 0 or root_motion < 0 or target.get_bone_parent(root_motion) >= 0:
		return reject("Retarget motion must map source hips to the target's root bone.")
	var columns: Array = profile.source_world_to_target_world
	var coordinates := Basis(Vector3(columns[0][0], columns[0][1], columns[0][2]), Vector3(columns[1][0], columns[1][1], columns[1][2]), Vector3(columns[2][0], columns[2][1], columns[2][2]))
	if not coordinates.is_equal_approx(coordinates.orthonormalized()) or coordinates.determinant() < 0.99999:
		return reject("Retarget coordinate conversion must be a proper unit rotation; no scale or mirroring.")
	var coordinate_rotation := coordinates.get_rotation_quaternion()
	var source_rest_rotations := []
	var target_rest_rotations := []
	for index in source.get_bone_count():
		source_rest_rotations.append((source.global_transform * source.get_bone_global_rest(index)).basis.orthonormalized().get_rotation_quaternion())
	for index in target.get_bone_count():
		target_rest_rotations.append((target.global_transform * target.get_bone_global_rest(index)).basis.orthonormalized().get_rotation_quaternion())
	var source_rest_hips := (source.global_transform * source.get_bone_global_rest(hips)).origin
	var target_rest_hips := (target.global_transform * target.get_bone_global_rest(target.find_bone(mapping[profile.source_motion_bone]))).origin
	var results := []
	var validation := []
	for clip in clips:
		var original: Animation = clip.animation
		if not validate_source(original, clip.root, source, mapping, ignored, hips): return {}
		var animation := Animation.new()
		animation.resource_name = original.resource_name
		animation.length = original.length
		animation.step = 1.0 / SAMPLE_HZ
		animation.loop_mode = original.loop_mode
		var rotation_tracks := {}
		for target_index in target_ids:
			var track := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, NodePath(String(target_scene.get_path_to(target)) + ":" + String(target.get_bone_name(target_index))))
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
			rotation_tracks[target_index] = track
		var motion_track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(motion_track, NodePath(String(target_scene.get_path_to(target)) + ":" + String(target.get_bone_name(root_motion))))
		animation.track_set_interpolation_type(motion_track, Animation.INTERPOLATION_LINEAR)
		var times := sample_times(original.length)
		var last_quaternions := {}
		var max_motion_error := 0.0
		var max_rotation_error := 0.0
		for time in times:
			apply_source(original, source, time)
			target.reset_bone_poses()
			var source_hips := (source.global_transform * source.get_bone_global_pose(hips)).origin
			var displacement := coordinates * (source_hips - source_rest_hips)
			var root_position := target.get_bone_rest(root_motion).origin + target.global_transform.basis.inverse() * displacement
			target.set_bone_pose_position(root_motion, root_position)
			animation.position_track_insert_key(motion_track, time, root_position)
			var desired_rotations := {}
			for index in target.get_bone_count():
				if not target_ids.has(index): continue
				var source_index: int = target_ids[index]
				var source_rotation := (source.global_transform * source.get_bone_global_pose(source_index)).basis.orthonormalized().get_rotation_quaternion()
				var delta: Quaternion = source_rotation * source_rest_rotations[source_index].inverse()
				var desired: Quaternion = (coordinate_rotation * delta * coordinate_rotation.inverse() * target_rest_rotations[index]).normalized()
				desired_rotations[index] = desired
				var parent := target.get_bone_parent(index)
				var parent_rotation := target.global_transform.basis.orthonormalized().get_rotation_quaternion()
				if parent >= 0:
					parent_rotation = desired_rotations.get(parent, (target.global_transform * target.get_bone_global_pose(parent)).basis.orthonormalized().get_rotation_quaternion())
				var local := (parent_rotation.inverse() * desired).normalized()
				if last_quaternions.has(index) and local.dot(last_quaternions[index]) < 0: local = -local
				last_quaternions[index] = local
				target.set_bone_pose_rotation(index, local)
				animation.rotation_track_insert_key(rotation_tracks[index], time, local)
			target.force_update_all_bone_transforms()
			var expected_hips := target_rest_hips + displacement
			var actual_hips := (target.global_transform * target.get_bone_global_pose(target.find_bone(mapping[profile.source_motion_bone]))).origin
			max_motion_error = maxf(max_motion_error, actual_hips.distance_to(expected_hips))
			for index in target.get_bone_count():
				if index != root_motion and not target.get_bone_pose_position(index).is_equal_approx(target.get_bone_rest(index).origin):
					return reject("Retarget changed a UAL limb translation.")
				if not target.get_bone_pose_scale(index).is_equal_approx(target.get_bone_rest(index).basis.get_scale()):
					return reject("Retarget changed a UAL bone scale.")
				if desired_rotations.has(index):
					var actual_rotation := (target.global_transform * target.get_bone_global_pose(index)).basis.orthonormalized().get_rotation_quaternion()
					max_rotation_error = maxf(max_rotation_error, 1.0 - absf(actual_rotation.dot(desired_rotations[index])))
		if max_motion_error > TOLERANCE or max_rotation_error > TOLERANCE:
			return reject("Retarget invariant failed for %s (motion %.8fm / rotation %.8f)." % [clip.name, max_motion_error, max_rotation_error])
		results.append({"name":clip.name, "animation":animation, "root":target_scene})
		validation.append({"source_clip":clip.name, "samples":times.size(), "sample_hz":SAMPLE_HZ, "duration":original.length, "first_time":times[0], "last_time":times[-1], "max_hip_displacement_error_m":max_motion_error, "max_rotation_dot_error":max_rotation_error})
	source.reset_bone_poses()
	target.reset_bone_poses()
	return {"clips":results, "dependencies":[profile.path, "res://tools/art_preview_retarget.gd"], "retarget":{"kind":"preview_only", "label":"Retargeted preview — pending visual review", "profile_id":profile.id, "profile_version":profile.version, "profile_path":profile.path.trim_prefix("res://"), "source_rig_fingerprint":profile.source_fingerprint, "target_rig_fingerprint":profile.target_fingerprint, "target_rig":"ual1_65_v1", "sample_hz":SAMPLE_HZ, "motion_policy":profile.motion_policy, "validation":validation}}

func validate_source(animation: Animation, animation_root: Node, source: Skeleton3D, mapping: Dictionary, ignored: Array, hips: int) -> bool:
	if not is_finite(animation.length) or animation.length <= 0:
		last_error = "Invalid source duration for preview retargeting."
		return false
	var seen := {}
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var identifier := "%s:%d" % [path, animation.track_get_type(track)]
		if seen.has(identifier) or not animation.track_is_enabled(track) or animation.track_get_key_count(track) == 0:
			last_error = "Duplicate, disabled or empty retarget track: " + String(path)
			return false
		seen[identifier] = true
		if animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) != source or path.get_subname_count() != 1:
			last_error = "Retarget cannot preserve non-bone target " + String(path)
			return false
		var name := String(path.get_subname(0))
		var bone := source.find_bone(name)
		if bone < 0 or (not mapping.has(name) and not name in ignored):
			last_error = "Unmapped animated source bone " + name
			return false
		var kind := animation.track_get_type(track)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			last_error = "Unsupported retarget track at " + String(path)
			return false
		for key in animation.track_get_key_count(track):
			var value = animation.track_get_key_value(track, key)
			var key_time := animation.track_get_key_time(track, key)
			if not (value is Vector3 or value is Quaternion) or not value.is_finite() or not is_finite(key_time) or key_time < 0 or key_time > animation.length + 0.0001:
				last_error = "Invalid retarget key value or time: " + name
				return false
			if value is Quaternion and value.length_squared() < 0.000001:
				last_error = "Invalid retarget quaternion: " + name
				return false
			var rest := source.get_bone_rest(bone)
			if kind == Animation.TYPE_SCALE_3D and not value.is_equal_approx(rest.basis.get_scale()):
				last_error = "Animated source scale is unsupported: " + name
				return false
			if kind == Animation.TYPE_POSITION_3D and bone != hips and not value.is_equal_approx(rest.origin):
				last_error = "Animated non-hip source translation is unsupported: " + name
				return false
			if name in ignored and kind == Animation.TYPE_ROTATION_3D and absf(value.normalized().dot(rest.basis.orthonormalized().get_rotation_quaternion())) < 1.0 - TOLERANCE:
				last_error = "Unmapped auxiliary bone has authored motion: " + name
				return false
	return true

func apply_source(animation: Animation, skeleton: Skeleton3D, time: float) -> void:
	skeleton.reset_bone_poses()
	for track in animation.get_track_count():
		var index := skeleton.find_bone(animation.track_get_path(track).get_subname(0))
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D: skeleton.set_bone_pose_position(index, animation.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D: skeleton.set_bone_pose_rotation(index, animation.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D: skeleton.set_bone_pose_scale(index, animation.scale_track_interpolate(track, time))
	skeleton.force_update_all_bone_transforms()
