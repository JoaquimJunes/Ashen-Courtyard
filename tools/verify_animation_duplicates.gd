extends SceneTree
## Read-only comparison of actual imported animation bindings and evaluated poses.
const SAMPLE_HZ = 120.0
const POSITION_TOLERANCE = 0.000001
const BASIS_TOLERANCE = 0.000001
var failure = ""
var identity_paths = {}

func _initialize():
	call_deferred("run")

func all_nodes(node):
	var result = [node]
	for child in node.get_children(): result.append_array(all_nodes(child))
	return result

func hash_value(value):
	var digest = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(value))
	return digest.finish().hex_encode()

func vector(value):
	return [value.x, value.y, value.z]

func canonical_source(relative):
	# Reports retain historical source identities while imports use current paths.
	return String(identity_paths.get(relative, relative))

func imported(relative):
	failure = ""
	var path = "res://" + canonical_source(relative).trim_prefix("res://")
	if not path.begins_with("res://assets/animations/Mixamo/") or not path.ends_with(".fbx") or ".." in path.split("/"):
		failure = "Only original Mixamo FBX sources are supported."
		return {}
	var packed = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not packed is PackedScene:
		failure = "Godot import unavailable."
		return {}
	var scene_state = packed.get_state()
	for index in scene_state.get_node_count():
		for property in scene_state.get_node_property_count(index):
			if scene_state.get_node_property_name(index, property) == "script" and scene_state.get_node_property_value(index, property) != null:
				failure = "Scripted imports cannot be inspected."
				return {}
	var host = packed.instantiate()
	root.add_child(host)
	var result = {"host":host, "clips":[], "nodes":all_nodes(host), "transforms":{}, "layout":[]}
	for node in result.nodes:
		var relative_node = String(host.get_path_to(node))
		var layout = [relative_node, node.get_class()]
		if node is Node3D:
			result.transforms[node] = node.transform
			layout.append(node.transform)
		if node is Skeleton3D:
			for bone in node.get_bone_count():
				layout.append([String(node.get_bone_name(bone)),node.get_bone_parent(bone),node.get_bone_rest(bone)])
		result.layout.append(layout)
		if node is AnimationPlayer:
			var animation_root = node.get_node_or_null(node.root_node)
			for name in node.get_animation_list():
				if String(name) != "RESET":
					result.clips.append({"name":String(name),"animation":node.get_animation(name),"root":animation_root})
	return result

func bindings(scene, clip):
	var result = []
	if not clip.root:
		failure = "Animation root is missing."
		return []
	var animation = clip.animation
	if not is_finite(animation.length) or animation.length <= 0:
		failure = "Animation duration is invalid."
		return []
	for index in animation.get_track_count():
		var type = animation.track_get_type(index)
		if not type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			failure = "Unsupported track type %s at %s." % [type, animation.track_get_path(index)]
			return []
		var path = animation.track_get_path(index)
		var target = clip.root.get_node_or_null(NodePath(path.get_concatenated_names()))
		if not target is Node3D or (target != scene.host and not scene.host.is_ancestor_of(target)):
			failure = "Track target does not resolve inside the source scene: " + str(path)
			return []
		var bone = -1
		if path.get_subname_count():
			if path.get_subname_count() != 1 or not target is Skeleton3D:
				failure = "Unsupported track binding: " + str(path)
				return []
			bone = target.find_bone(path.get_subname(0))
			if bone < 0:
				failure = "Bone binding is missing: " + str(path)
				return []
		result.append({"node":target,"bone":bone,"type":type,"track":index,"path":String(scene.host.get_path_to(target))+":"+(String(target.get_bone_name(bone)) if bone>=0 else "")})
	return result

func clip_signature(scene, clip, targets):
	var animation = clip.animation
	var tracks = []
	for binding in targets:
		var track = binding.track
		var keys = []
		for key in animation.track_get_key_count(track):
			keys.append([animation.track_get_key_time(track,key),animation.track_get_key_transition(track,key),animation.track_get_key_value(track,key)])
		tracks.append([binding.path,binding.type,animation.track_is_enabled(track),animation.track_is_imported(track),animation.track_get_interpolation_type(track),animation.track_get_interpolation_loop_wrap(track),keys])
	return [clip.name,String(scene.host.get_path_to(clip.root)),animation.length,animation.loop_mode,animation.step,tracks]

func evaluate(scene, clip, targets, time):
	for node in scene.transforms: node.transform = scene.transforms[node]
	for node in scene.nodes:
		if node is Skeleton3D: node.reset_bone_poses()
	for target in targets:
		var animation = clip.animation
		if not animation.track_is_enabled(target.track) or animation.track_get_key_count(target.track) == 0: continue
		var value
		match target.type:
			Animation.TYPE_POSITION_3D: value = animation.position_track_interpolate(target.track,time)
			Animation.TYPE_ROTATION_3D: value = animation.rotation_track_interpolate(target.track,time)
			Animation.TYPE_SCALE_3D: value = animation.scale_track_interpolate(target.track,time)
		if target.bone >= 0:
			match target.type:
				Animation.TYPE_POSITION_3D: target.node.set_bone_pose_position(target.bone,value)
				Animation.TYPE_ROTATION_3D: target.node.set_bone_pose_rotation(target.bone,value)
				Animation.TYPE_SCALE_3D: target.node.set_bone_pose_scale(target.bone,value)
		else:
			match target.type:
				Animation.TYPE_POSITION_3D: target.node.position = value
				Animation.TYPE_ROTATION_3D: target.node.quaternion = value
				Animation.TYPE_SCALE_3D: target.node.scale = value
	var pose = {}
	for node in scene.nodes:
		if not node is Node3D: continue
		var path = String(scene.host.get_path_to(node))
		pose[path] = node.global_transform
		if node is Skeleton3D:
			node.force_update_all_bone_transforms()
			for bone in node.get_bone_count(): pose[path+":"+String(node.get_bone_name(bone))] = node.global_transform * node.get_bone_global_pose(bone)
	return pose

func inspect_source(relative):
	var scene = imported(relative)
	if scene.is_empty(): return {"source":relative,"error":failure}
	var result = {"source":relative,"path":canonical_source(relative),"sha256":FileAccess.get_sha256("res://"+canonical_source(relative)),"layout_sha256":hash_value(scene.layout),"clips":[],"bones":[]}
	for node in scene.nodes:
		if node is Skeleton3D:
			for index in node.get_bone_count(): result.bones.append({"name":String(node.get_bone_name(index)),"parent":node.get_bone_parent(index)})
	for clip in scene.clips:
		var targets = bindings(scene,clip)
		var descriptor = {"name":clip.name,"duration":clip.animation.length,"loop":clip.animation.loop_mode,"tracks":clip.animation.get_track_count(),"poses":[]}
		if not failure.is_empty(): descriptor.error=failure
		else:
			descriptor.metadata_sha256=hash_value(clip_signature(scene,clip,targets))
			for index in 9:
				var time = clip.animation.length*index/8.0
				var pose = evaluate(scene,clip,targets,time)
				var positions = {}
				for path in pose: positions[path]=vector(pose[path].origin)
				descriptor.poses.append({"time":time,"positions":positions})
		result.clips.append(descriptor)
	scene.host.free()
	return result

func compare(members):
	var result = {"members":members,"member_sha256":{},"verified":false,"evidence":[],"samples":0,"max_position_error_m":0.0,"max_basis_error":0.0,"sample_hz":SAMPLE_HZ}
	for path in members: result.member_sha256[path]=FileAccess.get_sha256("res://"+canonical_source(path))
	var left=imported(members[0])
	if left.is_empty(): result.reason=failure;return result
	var right=imported(members[1])
	if right.is_empty(): result.reason=failure;left.host.free();return result
	if hash_value(left.layout)!=hash_value(right.layout): result.reason="Imported node hierarchy, transforms or bone rest data differ."
	elif left.clips.size()!=right.clips.size() or left.clips.is_empty(): result.reason="Actual imported clip counts differ or are empty."
	else:
		result.clips=[]
		for index in left.clips.size():
			var a=left.clips[index]
			var b=right.clips[index]
			var at=bindings(left,a)
			var bt=bindings(right,b)
			if not failure.is_empty(): result.reason=failure;break
			if hash_value(clip_signature(left,a,at))!=hash_value(clip_signature(right,b,bt)):
				result.reason="Clip identity, duration, loop, resolved bindings, interpolation or exact imported keys differ."
				break
			var times={0.0:true,a.animation.length:true}
			for sample in int(ceil(a.animation.length*SAMPLE_HZ)): times[min(sample/SAMPLE_HZ,a.animation.length)]=true
			for track in a.animation.get_track_count():
				for key in a.animation.track_get_key_count(track): times[a.animation.track_get_key_time(track,key)]=true
			var ordered=times.keys()
			ordered.sort()
			for time in ordered:
				var ap=evaluate(left,a,at,time)
				var bp=evaluate(right,b,bt,time)
				for path in ap:
					result.max_position_error_m=max(result.max_position_error_m,ap[path].origin.distance_to(bp[path].origin))
					for axis in 3: result.max_basis_error=max(result.max_basis_error,ap[path].basis[axis].distance_to(bp[path].basis[axis]))
				result.samples+=1
			result.clips.append({"name":a.name,"duration":a.animation.length,"loop":a.animation.loop_mode,"binding_count":at.size(),"metadata_sha256":hash_value(clip_signature(left,a,at))})
		if not result.has("reason") and result.max_position_error_m<=POSITION_TOLERANCE and result.max_basis_error<=BASIS_TOLERANCE:
			result.verified=true
			result.evidence=["Godot imported node hierarchy/rest transforms and resolved bone bindings match exactly.","Actual clip identities, durations, loops, interpolation metadata and all imported key values match exactly.","All node and bone world transforms match at 120 Hz, every imported key time, and both endpoints; root motion is retained."]
		elif not result.has("reason"): result.reason="Sampled full world poses or root motion differ."
	left.host.free()
	right.host.free()
	return result

func run():
	var args=OS.get_cmdline_user_args()
	var input=""
	var output=""
	for index in args.size()-1:
		if args[index]=="--jobs": input=args[index+1]
		if args[index]=="--report": output=args[index+1]
	if input.is_empty() or output.is_empty(): push_error("Use --jobs input.json --report output.json");quit(1);return
	var registry_path="res://tools/art_asset_identities.json"
	if FileAccess.file_exists(registry_path):
		var registry=JSON.parse_string(FileAccess.get_file_as_string(registry_path))
		if not registry is Dictionary or registry.get("version")!=1 or not registry.get("entries") is Array:
			push_error("Invalid asset identity registry.");quit(1);return
		for entry in registry.entries:
			for alias in [entry.original_path,entry.path]+entry.aliases:
				if identity_paths.has(alias) and identity_paths[alias]!=entry.path:
					push_error("Conflicting asset identity alias.");quit(1);return
				identity_paths[alias]=entry.path
	var jobs=JSON.parse_string(FileAccess.get_file_as_string(input))
	var report={"version":1,"engine":Engine.get_version_info().string,"groups":[],"sources":[]}
	for pair in jobs.get("pairs",[]): report.groups.append(compare(pair.members))
	for source in jobs.get("sources",[]): report.sources.append(inspect_source(source))
	var file=FileAccess.open(output,FileAccess.WRITE)
	if not file: push_error("Cannot write report.");quit(1);return
	file.store_string(JSON.stringify(report,"\t"))
	print("Animation audit: ",report.groups.filter(func(group): return group.verified).size(),"/",report.groups.size()," pairs verified; ",report.sources.size()," sources inspected.")
	quit()
