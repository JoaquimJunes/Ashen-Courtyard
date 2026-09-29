extends SceneTree
## Build-only, script-free inspection exports. Never installed in character gameplay.
## --jobs {jobs:[{source,output}]} --report {results:[...]}
const UAL_RIG := "res://assets/models/ual/runtime_rig.tscn"
const UAL_BODY := "res://assets/models/ual/mannequin_body.res"
const Retarget = preload("res://tools/art_preview_retarget.gd")
const KNIGHT := "res://assets/third_party/fullplate_knight/knight_complete.glb"
const IDENTITY_REGISTRY := "res://tools/art_asset_identities.json"
const POSITION_TOLERANCE := 0.001
const BASIS_TOLERANCE := 0.001
var failure := ""

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var jobs_path := ""
	var report_path := ""
	for index in range(arguments.size() - 1):
		if arguments[index] == "--jobs": jobs_path = arguments[index + 1]
		if arguments[index] == "--report": report_path = arguments[index + 1]
	var input = JSON.parse_string(FileAccess.get_file_as_string(jobs_path))
	if not input is Dictionary or not input.get("jobs") is Array or report_path.is_empty():
		push_error("Expected --jobs JSON {jobs:[{source,output}]} --report PATH")
		quit(2)
		return
	var results := []
	for job in input.jobs:
		failure = ""
		var result := export_job(job)
		result.dependencies = dependency_files(result.dependencies)
		results.append(result)
		print("ART PREVIEW: ", result.source, " ", result.status, " ", result.get("reason", ""))
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if not report:
		push_error("Cannot write report: " + report_path)
		quit(2)
		return
	report.store_string(JSON.stringify({"results":results}, "\t"))
	report.close()
	quit()

func problem(message: String) -> bool:
	failure = message
	return false

func project_path(path: String) -> String:
	return path if path.begins_with("res://") else "res://" + path

func local_path(path: String) -> String:
	return path.trim_prefix("res://")

func standalone_clip_name(source: String) -> String:
	# An unnamed resource's historical filename is its existing catalog identity.
	# Moving the file must not manufacture a new clip or orphan its annotations.
	if FileAccess.file_exists(IDENTITY_REGISTRY):
		var registry = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_REGISTRY))
		if not registry is Dictionary or registry.get("version") != 1 or not registry.get("entries") is Array:
			failure = "Invalid asset identity registry; cannot preserve standalone clip identity."
			return ""
		for entry in registry.entries:
			if local_path(source) in [entry.path, entry.original_path] + entry.aliases:
				return String(entry.original_path).get_file().get_basename()
	return source.get_file().get_basename()

func dependency_files(paths: Array) -> Array:
	var seen := {}
	var queue := paths.duplicate()
	while not queue.is_empty():
		var path := project_path(str(queue.pop_back()))
		if seen.has(path): continue
		seen[path] = true
		if FileAccess.file_exists(path + ".import"):
			seen[path + ".import"] = true
			var config := ConfigFile.new()
			if config.load(path + ".import") == OK:
				for key in config.get_section_keys("remap"):
					if key == "path" or key.begins_with("path."):
						var imported: String = str(config.get_value("remap", key, ""))
						if not imported.is_empty():
							queue.append(imported)
							if FileAccess.file_exists(imported.get_basename() + ".md5"): seen[imported.get_basename() + ".md5"] = true
		if ResourceLoader.exists(path):
			for dependency in ResourceLoader.get_dependencies(path):
				var dep := String(dependency).get_slice("::", String(dependency).count("::"))
				if dep.begins_with("res://"): queue.append(dep)
	var result := []
	for path in seen: result.append(local_path(path))
	result.sort()
	return result

func safe_scene(packed: PackedScene) -> Node:
	if not packed or not check_state(packed.get_state()): return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	return node

func check_state(state: SceneState) -> bool:
	var base := state.get_base_scene_state()
	if base and not check_state(base): return false
	for index in state.get_node_count():
		var instance := state.get_node_instance(index)
		if instance and not check_state(instance.get_state()): return false
		for prop in state.get_node_property_count(index):
			if state.get_node_property_name(index, prop) == &"script" and state.get_node_property_value(index, prop) != null:
				return problem("Preview scene contains a script at %s; supply a data-only source rig." % state.get_node_path(index))
	return true

func all_nodes(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children(): result.append_array(all_nodes(child))
	return result

func export_job(job: Dictionary) -> Dictionary:
	var source := project_path(str(job.get("source", "")))
	var output: String = str(job.get("output", ""))
	var result := {"source":local_path(source), "status":"unavailable", "dependencies":[local_path(source)], "clips":[]}
	if output.is_empty() or not output.ends_with(".glb"):
		result.reason = "Output must be a temporary .glb path."
		return result
	var absolute_output := ProjectSettings.globalize_path(output).simplify_path()
	var safe_output := false
	for directory in ["res://docs/tracker/previews/", "res://.artifacts/", "/tmp/"]:
		if absolute_output.begins_with(ProjectSettings.globalize_path(directory).simplify_path().trim_suffix("/") + "/"):
			safe_output = true
	if not safe_output or absolute_output == ProjectSettings.globalize_path(source).simplify_path():
		result.reason = "Output must be separate derived data under docs/tracker/previews, .artifacts or /tmp. Original assets are protected."
		return result
	if source.get_base_dir() == "res://assets/animations/Mixamo" and not current_mixamo_import(source):
		result.reason = failure
		return result
	var resource := ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE)
	var host: Node
	var clips := []
	if resource is Animation or resource is AnimationLibrary:
		if source.begins_with("res://assets/animations/ual/"):
			host = safe_scene(load(UAL_RIG))
			result.model = "UAL mannequin"
			result.model_path = local_path(UAL_RIG)
			result.dependencies.append_array([local_path(UAL_RIG), local_path(UAL_BODY)])
			if host and not add_ual_body(host):
				host.free()
				host = null
		elif source.get_base_dir() == "res://assets/animations":
			host = safe_scene(load(KNIGHT))
			result.model = "Legacy Knight"
			result.model_path = local_path(KNIGHT)
			result.dependencies.append(local_path(KNIGHT))
		else:
			failure = "No documented matching rig for this standalone animation resource."
		if host:
			if resource is AnimationLibrary:
				for clip_name in resource.get_animation_list():
					clips.append({"name":String(clip_name), "animation":resource.get_animation(clip_name), "root":host})
			else:
				var clip_name := resource.resource_name
				if clip_name.is_empty():
					result.dependencies.append(local_path(IDENTITY_REGISTRY))
					clip_name = standalone_clip_name(source)
				clips.append({"name":clip_name, "animation":resource, "root":host})
	elif resource is PackedScene:
		host = safe_scene(resource)
		result.model = source.get_file().get_basename()
		result.model_path = local_path(source)
		if host:
			for node in all_nodes(host):
				if node is AnimationPlayer:
					var animation_root := node.get_node_or_null(node.root_node)
					if not animation_root:
						failure = "AnimationPlayer root is missing: " + String(node.root_node)
						break
					for clip_name in node.get_animation_list():
						if String(clip_name) != "RESET":
							clips.append({"name":String(clip_name), "animation":node.get_animation(clip_name), "root":animation_root})
	else:
		failure = "Source is unavailable or is not an Animation, AnimationLibrary or imported scene. Import it in Godot first."
	if not host:
		result.reason = failure
		return result
	if clips.is_empty(): failure = "The source has no previewable animation clips."
	root.add_child(host)
	if failure.is_empty() and source.get_base_dir() == "res://assets/animations/Mixamo" and not has_mesh(host):
		for clip in clips:
			if not validate_clip(clip.animation, clip.root): break
		if failure.is_empty():
			var target := safe_scene(load(UAL_RIG))
			if target and add_ual_body(target):
				root.add_child(target)
				var retarget := Retarget.new()
				var transferred := retarget.transfer(host, clips, target)
				if transferred.is_empty():
					failure = retarget.last_error
					target.free()
				else:
					host.free()
					host = target
					clips = transferred.clips
					result.model = "UAL mannequin"
					result.model_path = local_path(UAL_RIG)
					result.dependencies.append_array([local_path(UAL_RIG), local_path(UAL_BODY)])
					for path in transferred.dependencies: result.dependencies.append(local_path(path))
					result.provenance = transferred.retarget
					result.provenance.kind = "retargeted_preview"
					result.provenance.status = "pending_visual_review"
					result.provenance.label = "Retargeted mannequin preview · visual review pending"
					result.provenance.source_path = local_path(source)
					result.provenance.source_sha256 = FileAccess.get_sha256(source)
					result.provenance.source_clips = []
					for clip in clips: result.provenance.source_clips.append({"name":clip.name, "duration":clip.animation.length})
			elif target:
				target.free()
	if failure.is_empty(): validate_geometry(host)
	var library := AnimationLibrary.new()
	for index in clips.size():
		var clip: Dictionary = clips[index]
		var animation: Animation = clip.animation.duplicate()
		if not failure.is_empty() or not validate_clip(animation, clip.root): break
		# glTF duration is the last key time. Imported static poses often have a
		# positive one-frame hold but only a key at zero; repeat that same value
		# at the declared end, preserving the hold without creating motion.
		var static_pose := true
		for track in animation.get_track_count():
			if animation.track_get_key_count(track) != 1: static_pose = false
		if static_pose:
			for track in animation.get_track_count():
				if animation.track_get_key_time(track, 0) < animation.length:
					animation.track_insert_key(track, animation.length, animation.track_get_key_value(track, 0))
		# Resolve against the original player root, then rebase without retargeting.
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			var target: Node = clip.root.get_node(NodePath(path.get_concatenated_names()))
			var new_path := String(host.get_path_to(target))
			if path.get_subname_count(): new_path += ":" + path.get_concatenated_subnames()
			animation.track_set_path(track, NodePath(new_path))
		var export_name := "PreviewClip%04d" % index
		animation.resource_name = export_name
		library.add_animation(export_name, animation)
		clip.export_name = export_name
		clip.animation = animation
		result.clips.append({"id":clip.name, "index":index, "name":clip.name, "export_name":export_name, "duration":animation.length, "loop":animation.loop_mode != Animation.LOOP_NONE})
	if not failure.is_empty():
		result.reason = failure
		host.free()
		return result
	for node in all_nodes(host):
		if node is AnimationPlayer:
			node.get_parent().remove_child(node)
			node.free()
	var player := AnimationPlayer.new()
	player.name = "PreviewAnimations"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library("", library)
	host.add_child(player)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.bake_fps = 120
	state.use_named_skin_binds = true
	var error := document.append_from_scene(host, state)
	if error == OK: error = document.write_to_filesystem(state, output)
	if error != OK:
		failure = "Godot GLB export failed with error %d." % error
	elif not validate_roundtrip(host, player, clips, output, result, state):
		pass
	if failure.is_empty():
		result.status = "ready"
	else:
		result.reason = failure
		if FileAccess.file_exists(output): DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
	host.free()
	return result

func current_mixamo_import(source: String) -> bool:
	var config := ConfigFile.new()
	if config.load(source + ".import") != OK:
		return problem("Mixamo source has no existing Godot import. Import it before preparing its preview.")
	var imported: String = str(config.get_value("remap", "path", ""))
	var stamp := imported.get_basename() + ".md5"
	if imported.is_empty() or not FileAccess.file_exists(imported) or not FileAccess.file_exists(stamp):
		return problem("Mixamo import or source checksum is missing. Reimport the source in Godot first.")
	var pattern := RegEx.new()
	pattern.compile('source_md5="([0-9a-f]{32})"')
	var matched := pattern.search(FileAccess.get_file_as_string(stamp))
	if not matched or matched.get_string(1) != FileAccess.get_md5(source):
		return problem("Mixamo import is stale: the source changed after import. Reimport it in Godot first.")
	return true

func has_mesh(host: Node) -> bool:
	for node in all_nodes(host):
		if node is MeshInstance3D and node.mesh: return true
	return false

func add_ual_body(host: Node) -> bool:
	var skeleton := host.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	var body := load(UAL_BODY)
	if not skeleton or not body or body.bone_names.size() != skeleton.get_bone_count():
		return problem("UAL appearance/reference bone count mismatch.")
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else ""
		if body.bone_names[index] != skeleton.get_bone_name(index) or body.parent_names[index] != parent_name or not body.rest_transforms[index].is_equal_approx(skeleton.get_bone_rest(index)):
			return problem("UAL appearance/reference hierarchy or rest mismatch at bone %d." % index)
	var mesh := MeshInstance3D.new()
	mesh.name = "MannequinBody"
	mesh.mesh = body.contact_mesh
	mesh.skin = body.skin
	mesh.skeleton = NodePath("..")
	skeleton.add_child(mesh)
	return true

func finite_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite() and absf(value.basis.determinant()) > 0.000000001

func validate_geometry(host: Node) -> bool:
	var mesh_count := 0
	for node in all_nodes(host):
		if node is Node3D and not finite_transform(node.transform):
			return problem("Invalid transform at " + String(host.get_path_to(node)))
		if node is Skeleton3D:
			for bone in node.get_bone_count():
				if not finite_transform(node.get_bone_rest(bone)):
					return problem("Invalid rest transform: " + String(node.get_bone_name(bone)))
		if node is MeshInstance3D and node.mesh:
			mesh_count += 1
			if node.skin:
				var skeleton := node.get_node_or_null(node.skeleton) as Skeleton3D
				if not skeleton: return problem("Skin has no matching Skeleton3D at " + String(node.skeleton))
				for bind in node.skin.get_bind_count():
					var bone: int = node.skin.get_bind_bone(bind)
					var bind_name: StringName = node.skin.get_bind_name(bind)
					if bind_name != &"": bone = skeleton.find_bone(bind_name)
					if bone < 0 or bone >= skeleton.get_bone_count() or not finite_transform(node.skin.get_bind_pose(bind)):
						return problem("Invalid skin bind %d (%s)." % [bind, bind_name])
	if mesh_count == 0: return problem("Matching source has no mesh to display.")
	return true

func validate_clip(animation: Animation, animation_root: Node) -> bool:
	if not is_finite(animation.length) or animation.length <= 0 or animation.get_track_count() == 0:
		return problem("Animation duration must be positive and contain tracks.")
	if animation.loop_mode == Animation.LOOP_PINGPONG:
		return problem("Ping-pong animation playback is not supported by this preview version.")
	var seen_targets := {}
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
		var prefix := "%s track %d (%s): " % [animation.resource_name, track, path]
		if animation.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			return problem(prefix + "unsupported track type; cannot preserve it in a GLB preview.")
		var target_key := "%s:%d" % [path, animation.track_get_type(track)]
		if seen_targets.has(target_key): return problem(prefix + "duplicate target component would be merged by GLB export.")
		seen_targets[target_key] = true
		if not animation.track_is_enabled(track):
			return problem(prefix + "disabled tracks require explicit conversion support.")
		if not target is Node3D: return problem(prefix + "target is missing or is not Node3D.")
		if path.get_subname_count() > 0:
			if path.get_subname_count() != 1 or not target is Skeleton3D or target.find_bone(path.get_subname(0)) < 0:
				return problem(prefix + "bone target is absent from the selected rig.")
		if animation.track_get_key_count(track) == 0: return problem(prefix + "track has no keys.")
		for key in animation.track_get_key_count(track):
			var time := animation.track_get_key_time(track, key)
			var value = animation.track_get_key_value(track, key)
			if not is_finite(animation.track_get_key_transition(track, key)):
				return problem(prefix + "non-finite key transition.")
			if value is Quaternion and value.length_squared() < 0.000001:
				return problem(prefix + "invalid zero quaternion.")
			if not is_finite(time) or time < 0 or time > animation.length + 0.0001:
				return problem(prefix + "key time is outside the declared duration.")
			if not (value is Vector3 or value is Quaternion) or not value.is_finite():
				return problem(prefix + "non-finite or unsupported key value.")
	return true

func snapshot(host: Node) -> Dictionary:
	var poses := {}
	for node in all_nodes(host):
		if node is Skeleton3D:
			node.force_update_all_bone_transforms()
			for bone in node.get_bone_count():
				var key := String(node.get_bone_name(bone))
				# Multiple skeletons may share names; ambiguous comparisons are rejected.
				if poses.has(key):
					problem("Multiple skeletons share bone names; a distinct preview mapping is required.")
					return {}
				poses[key] = node.global_transform * node.get_bone_global_pose(bone)
	return poses

func reset_pose(host: Node) -> void:
	for node in all_nodes(host):
		if node is Skeleton3D: node.reset_bone_poses()

func validate_roundtrip(host: Node, player: AnimationPlayer, clips: Array, output: String, result: Dictionary, export_state: GLTFState) -> bool:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.use_named_skin_binds = true
	var error := document.append_from_file(output, state)
	if error != OK: return problem("Reopening exported GLB failed: %d." % error)
	# Godot rebakes glTF at import. Align this verification grid with a single
	# source clip's authored keys when it was time-scaled (for example 60 samples
	# over 0.9333 seconds), avoiding false conversion failures from reimport alone.
	var verify_fps := 120.0
	if clips.size() == 1:
		var animation: Animation = clips[0].animation
		var subdivisions := 1
		for track in animation.get_track_count(): subdivisions = maxi(subdivisions, animation.track_get_key_count(track) - 1)
		var candidate := float(subdivisions) / animation.length
		var aligned := candidate > 0 and candidate <= 480
		for track in animation.get_track_count():
			for key in animation.track_get_key_count(track):
				var tick := animation.track_get_key_time(track, key) * candidate
				if absf(tick - roundf(tick)) > 0.0001: aligned = false
		if aligned: verify_fps = candidate
	var imported := document.generate_scene(state, verify_fps, false, false)
	if not imported: return problem("Exported GLB could not recreate a scene.")
	imported.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(imported)
	var imported_player: AnimationPlayer
	for node in all_nodes(imported):
		if node is AnimationPlayer: imported_player = node
	if not imported_player:
		imported.free()
		return problem("Export dropped the animation player.")
	imported_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Godot sanitizes punctuation in glTF node names. Compare through its explicit
	# export mapping, never by guessing a different bone or retargeting a pose.
	var bone_names := {}
	for node in export_state.nodes:
		if not node.original_name.is_empty(): bone_names[node.original_name] = node.resource_name
	var transform_targets := {}
	for clip in clips:
		var animation: Animation = clip.animation
		for track in animation.get_track_count():
			var path := animation.track_get_path(track)
			if path.get_subname_count() == 0:
				var target := host.get_node(path)
				var exported_index := export_state.get_node_index(target)
				if exported_index < 0:
					var candidates := []
					for index in export_state.nodes.size():
						if export_state.nodes[index].original_name == String(target.name): candidates.append(index)
					if candidates.size() == 1: exported_index = candidates[0]
				var imported_target := state.get_scene_node(exported_index)
				# Godot's generated mesh nodes are not registered in scene_nodes.
				if not imported_target and exported_index >= 0:
					var exported_node_name: String = state.nodes[exported_index].resource_name
					var matches := []
					for candidate in all_nodes(imported):
						if String(candidate.name) == exported_node_name: matches.append(candidate)
					if matches.size() == 1: imported_target = matches[0]
				if not imported_target is Node3D:
					imported.free()
					return problem("Export dropped animated node " + String(path))
				transform_targets[target] = imported_target
	var exported_names := {}
	var animations: Array = state.json.get("animations", [])
	for index in animations.size(): exported_names[animations[index].get("name", "")] = index
	var baseline := {}
	for node in all_nodes(host) + all_nodes(imported):
		if node is Node3D: baseline[node] = node.transform
	var max_position := 0.0
	var max_basis := 0.0
	var count := 0
	for clip_index in clips.size():
		var clip: Dictionary = clips[clip_index]
		var name: String = clip.export_name
		if not imported_player.has_animation(name) or not exported_names.has(name):
			failure = "Export lost clip identity: " + clip.name
			break
		result.clips[clip_index].index = exported_names[name]
		var original: Animation = clip.animation
		var roundtrip := imported_player.get_animation(name)
		roundtrip.loop_mode = original.loop_mode
		if absf(original.length - roundtrip.length) > 0.0001:
			failure = "Export changed duration for %s: %.6f to %.6f." % [clip.name, original.length, roundtrip.length]
			break
		# Independent, deterministic samples include ends, key times and between-key times.
		var times := {0.0:true, original.length:true}
		for step in 17: times[original.length * float(step) / 16.0] = true
		for track in original.get_track_count():
			var key_count := original.track_get_key_count(track)
			for key in range(0, key_count, maxi(1, key_count / 12)):
				times[original.track_get_key_time(track, key)] = true
		for time in times:
			for node in baseline: node.transform = baseline[node]
			reset_pose(host)
			reset_pose(imported)
			player.play(name)
			imported_player.play(name)
			player.seek(time, true)
			imported_player.seek(time, true)
			var before := snapshot(host)
			var after := snapshot(imported)
			if not failure.is_empty(): break
			if before.size() != after.size():
				failure = "Export changed the number of skeleton bones for " + clip.name
				break
			for bone in before:
				var exported_bone: String = bone_names.get(bone, bone)
				if not after.has(exported_bone):
					failure = "Export renamed or dropped bone " + bone
					break
				var a: Transform3D = before[bone]
				var b: Transform3D = after[exported_bone]
				var distance := a.origin.distance_to(b.origin)
				var basis_error := maxf((a.basis.x - b.basis.x).length(), maxf((a.basis.y - b.basis.y).length(), (a.basis.z - b.basis.z).length()))
				max_position = maxf(max_position, distance)
				max_basis = maxf(max_basis, basis_error)
				if distance > POSITION_TOLERANCE or basis_error > BASIS_TOLERANCE:
					failure = "Export pose differs for %s / %s at %.4fs (position %.6fm, basis %.6f)." % [clip.name, bone, time, distance, basis_error]
					break
			for target in transform_targets:
				var a: Transform3D = target.global_transform
				var b: Transform3D = transform_targets[target].global_transform
				var distance := a.origin.distance_to(b.origin)
				var basis_error := maxf((a.basis.x - b.basis.x).length(), maxf((a.basis.y - b.basis.y).length(), (a.basis.z - b.basis.z).length()))
				max_position = maxf(max_position, distance)
				max_basis = maxf(max_basis, basis_error)
				if distance > POSITION_TOLERANCE or basis_error > BASIS_TOLERANCE:
					failure = "Export changed animated node %s at %.4fs." % [target.name, time]
					break
			count += 1
			if not failure.is_empty(): break
		if not failure.is_empty(): break
	result.validation = {"samples":count, "max_position_error_m":max_position, "max_basis_error":max_basis, "position_tolerance_m":POSITION_TOLERANCE, "basis_tolerance":BASIS_TOLERANCE, "reimport_sample_fps":verify_fps}
	imported.free()
	return failure.is_empty()
