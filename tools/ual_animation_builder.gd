extends RefCounted
## One transactional path for all source-native UAL libraries and the runtime rig.
## Authoring scenes are loaded only by tools/tests; runtime uses the extracted assets.
const MANIFEST = preload("res://tools/ual_animation_build_manifest.tres")
const REFERENCE_BODY = preload("res://assets/models/ual/mannequin_body.res")
const RIG_ID := &"ual1_65_v1"
var last_error := ""

func fail(message: String) -> bool:
	last_error = message
	return false

func same_rig(reference: Skeleton3D, candidate: Skeleton3D) -> bool:
	if reference == null or candidate == null or reference.get_bone_count() != 65 or candidate.get_bone_count() != 65: return false
	for bone in reference.get_bone_count():
		if reference.get_bone_name(bone) != candidate.get_bone_name(bone) or reference.get_bone_parent(bone) != candidate.get_bone_parent(bone) or not reference.get_bone_rest(bone).is_equal_approx(candidate.get_bone_rest(bone)): return false
	return true

func canonical_rig(candidate: Skeleton3D) -> bool:
	if candidate == null or candidate.get_bone_count() != 65 or REFERENCE_BODY.bone_names.size() != 65: return false
	for bone in candidate.get_bone_count():
		var parent := candidate.get_bone_parent(bone)
		var parent_name := candidate.get_bone_name(parent) if parent >= 0 else ""
		if candidate.get_bone_name(bone) != REFERENCE_BODY.bone_names[bone] or parent_name != REFERENCE_BODY.parent_names[bone] or not candidate.get_bone_rest(bone).is_equal_approx(REFERENCE_BODY.rest_transforms[bone]): return false
	return true

func same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if a is Vector3: return a.distance_to(b) < 0.00001
	if a is Quaternion: return absf(a.x-b.x)+absf(a.y-b.y)+absf(a.z-b.z)+absf(a.w-b.w) < 0.00001
	if a is float: return absf(a-b) < 0.00001
	if a is Array or a is PackedFloat32Array or a is PackedVector3Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same_value(a[index],b[index]): return false
		return true
	return a == b

func same_clip(source: Animation, saved: Animation) -> bool:
	if saved == null or not is_equal_approx(source.length,saved.length) or source.loop_mode != saved.loop_mode or source.get_track_count() != saved.get_track_count(): return false
	for track in source.get_track_count():
		if source.track_get_type(track) != saved.track_get_type(track) or source.track_get_path(track) != saved.track_get_path(track) or source.track_is_enabled(track) != saved.track_is_enabled(track) or source.track_get_interpolation_type(track) != saved.track_get_interpolation_type(track) or source.track_get_interpolation_loop_wrap(track) != saved.track_get_interpolation_loop_wrap(track) or source.track_get_key_count(track) != saved.track_get_key_count(track): return false
		for key in source.track_get_key_count(track):
			if not is_equal_approx(source.track_get_key_time(track,key),saved.track_get_key_time(track,key)) or not is_equal_approx(source.track_get_key_transition(track,key),saved.track_get_key_transition(track,key)) or not same_value(source.track_get_key_value(track,key),saved.track_get_key_value(track,key)): return false
	return true

func valid_targets(player: AnimationPlayer, clip: Animation) -> bool:
	var animation_root := player.get_node_or_null(player.root_node)
	if animation_root == null: return false
	for track in clip.get_track_count():
		var path := clip.track_get_path(track)
		var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null: return false
		if clip.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D] and path.get_subname_count() > 0:
			if not target is Skeleton3D or target.find_bone(path.get_subname(0)) < 0: return false
	return true

func save_verified(resource: Resource, output: String, verify: Callable) -> bool:
	# Unique staging names allow independent builders without exposing partial files.
	var extension := output.get_extension()
	var pending := output.get_basename()+".pending-%s-%s." % [OS.get_process_id(),Time.get_ticks_usec()]+extension
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	if error != OK: return fail("Cannot create output directory: "+error_string(error))
	error = ResourceSaver.save(resource,pending)
	var saved: Resource = ResourceLoader.load(pending,"",ResourceLoader.CACHE_MODE_IGNORE) if error == OK else null
	var verified: bool = saved != null and verify.call(saved)
	if verified:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(pending),ProjectSettings.globalize_path(output))
		verified = error == OK
	if FileAccess.file_exists(pending): DirAccess.remove_absolute(ProjectSettings.globalize_path(pending))
	if not verified: return fail("Serialized asset validation/save failed; existing output preserved. "+error_string(error))
	last_error = ""
	return true

func build_library(host: Node, clips: Dictionary, output: String, annotate: Callable = Callable(), extra_metadata: Dictionary = {}) -> bool:
	if clips.is_empty(): return fail("Native library needs at least one clip.")
	var sources := {}
	var hashes := {}
	var players := {}
	var library := AnimationLibrary.new()
	var valid := true
	for role: String in clips:
		var spec: Array = clips[role]
		if spec.size() != 2 or role.is_empty():
			valid = fail("Clip manifest requires a nonempty role, source path and clip name.")
			break
		var path: String = spec[0]
		var name: String = spec[1]
		if not sources.has(path):
			var packed := load(path) as PackedScene
			if packed == null:
				valid = fail("Import the unchanged UAL source before extraction: "+path)
				break
			var source := packed.instantiate()
			sources[path] = source
			host.add_child(source)
			var player := source.find_child("AnimationPlayer",true,false) as AnimationPlayer
			var skeleton := source.find_child("Skeleton3D",true,false) as Skeleton3D
			if player == null or not canonical_rig(skeleton):
				valid = fail("Source differs from the versioned 65-bone reference: "+path)
				break
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			players[path] = player
			hashes[path] = FileAccess.get_sha256(path)
		var player: AnimationPlayer = players[path]
		if not player.has_animation(name) or not valid_targets(player,player.get_animation(name)):
			valid = fail("Missing clip or invalid track target: "+path+" / "+name)
			break
		var clip := player.get_animation(name).duplicate(true) as Animation
		if annotate.is_valid(): annotate.call(role,clip,sources[path],player,name)
		clip.set_meta("source_clip",name)
		clip.set_meta("source_scene",path)
		clip.set_meta("source_sha256",hashes[path])
		clip.set_meta("native_keyframes",true)
		if extra_metadata.has(role):
			for key: String in extra_metadata[role]: clip.set_meta(key,extra_metadata[role][key])
		library.add_animation(role,clip)
	if valid:
		library.set_meta("source_sha256",hashes.values()[0] if hashes.size() == 1 else hashes)
		if hashes.size() == 1: library.set_meta("source_scene",hashes.keys()[0])
		library.set_meta("rig_identifier",RIG_ID)
		library.set_meta("rig_reference_sha256",FileAccess.get_sha256(MANIFEST.source_scene.resource_path))
		valid = save_verified(library,output,func(saved: Resource) -> bool:
			if not saved is AnimationLibrary or saved.get_animation_list().size() != clips.size(): return false
			if saved.get_meta("rig_identifier",&"") != RIG_ID or saved.get_meta("rig_reference_sha256","") != library.get_meta("rig_reference_sha256"): return false
			for role: String in clips:
				var path: String = clips[role][0]
				var name: String = clips[role][1]
				if not saved.has_animation(role): return false
				var clip: Animation = saved.get_animation(role)
				if not same_clip(players[path].get_animation(name),clip): return false
				if clip.get_meta("source_scene","") != path or clip.get_meta("source_clip","") != name or clip.get_meta("source_sha256","") != hashes[path] or not clip.get_meta("native_keyframes",false): return false
				for key: String in library.get_animation(role).get_meta_list():
					if not clip.has_meta(key) or not same_value(library.get_animation(role).get_meta(key),clip.get_meta(key)): return false
			return true)
	for source: Node in sources.values(): source.free()
	return valid

func build_runtime_rig(output: String = "res://assets/models/ual/runtime_rig.tscn") -> bool:
	var source: Node3D = MANIFEST.source_scene.instantiate()
	var original := source.find_child("Skeleton3D",true,false) as Skeleton3D
	var source_player := source.find_child("AnimationPlayer",true,false) as AnimationPlayer
	if not canonical_rig(original) or source_player == null:
		source.free()
		return fail("Runtime rig source does not match the versioned 65-bone reference.")
	var runtime := Node3D.new()
	runtime.name = source.name
	runtime.transform = source.transform
	runtime.set_meta("rig_identifier",RIG_ID)
	runtime.set_meta("source_sha256",FileAccess.get_sha256(MANIFEST.source_scene.resource_path))
	var ancestors: Array[Node3D] = []
	var ancestor := original.get_parent() as Node3D
	while ancestor != source:
		ancestors.push_front(ancestor)
		ancestor = ancestor.get_parent() as Node3D
	var parent: Node3D = runtime
	for node in ancestors:
		var copy := Node3D.new()
		copy.name = node.name
		copy.transform = node.transform
		parent.add_child(copy)
		copy.owner = runtime
		parent = copy
	var skeleton := Skeleton3D.new()
	skeleton.name = original.name
	skeleton.transform = original.transform
	parent.add_child(skeleton)
	skeleton.owner = runtime
	for bone in original.get_bone_count():
		skeleton.add_bone(original.get_bone_name(bone))
		skeleton.set_bone_parent(bone,original.get_bone_parent(bone))
		skeleton.set_bone_rest(bone,original.get_bone_rest(bone))
		skeleton.set_bone_pose(bone,original.get_bone_pose(bone))
		skeleton.set_bone_enabled(bone,original.is_bone_enabled(bone))
	var player := AnimationPlayer.new()
	player.name = source_player.name
	player.root_node = source_player.root_node
	runtime.add_child(player)
	player.owner = runtime
	var paths_match := source.get_path_to(original) == runtime.get_path_to(skeleton) and source_player.get_path_to(source_player.get_node(source_player.root_node)) == player.get_path_to(player.get_node(player.root_node))
	var packed := PackedScene.new()
	var valid := paths_match and packed.pack(runtime) == OK
	if valid:
		valid = save_verified(packed,output,func(saved: Resource) -> bool:
			if not saved is PackedScene: return false
			var instance: Node = saved.instantiate()
			var saved_skeleton := instance.find_child("Skeleton3D",true,false) as Skeleton3D
			var saved_player := instance.find_child("AnimationPlayer",true,false) as AnimationPlayer
			var matches := same_rig(original,saved_skeleton) and saved_player != null and saved_player.get_animation_list().is_empty() and instance.find_children("*","MeshInstance3D",true,false).is_empty()
			if matches:
				for clip: String in source_player.get_animation_list():
					if not valid_targets(saved_player,source_player.get_animation(clip)): matches = false
			instance.free()
			return matches)
	else: fail("Cannot preserve source hierarchy when packing the runtime rig.")
	runtime.free()
	source.free()
	return valid

func build_rig_contract(output: String = "res://assets/models/ual/rig_contract.tres") -> bool:
	var contract_script := load("res://features/presentation/animation_rig_contract.gd") as Script
	if contract_script == null: return fail("Rig contract schema must exist before building its data.")
	var contract: Resource = contract_script.new()
	contract.set("bone_names",REFERENCE_BODY.bone_names.duplicate())
	contract.set("parent_names",REFERENCE_BODY.parent_names.duplicate())
	contract.set("rest_transforms",REFERENCE_BODY.rest_transforms.duplicate())
	contract.set_meta("rig_identifier",RIG_ID)
	contract.set_meta("source_sha256",FileAccess.get_sha256(MANIFEST.source_scene.resource_path))
	return save_verified(contract,output,func(saved: Resource) -> bool:
		if saved.get("bone_names") != REFERENCE_BODY.bone_names or saved.get("parent_names") != REFERENCE_BODY.parent_names: return false
		var transforms: Array = saved.get("rest_transforms")
		if transforms.size() != REFERENCE_BODY.rest_transforms.size(): return false
		for index in transforms.size():
			if not transforms[index].is_equal_approx(REFERENCE_BODY.rest_transforms[index]): return false
		return true)
