extends RefCounted
## Source files are read-only; validate in memory before atomically publishing output.
const Config = preload("res://tools/character_asset_import.gd")
const Definition = preload("res://features/presentation/appearance_definition.gd")
const Appearance = preload("res://features/presentation/character_appearance.gd")
var last_error := ""
var last_definition: Definition
var _materials := {}
var _textures := {}

func reject(message: String) -> bool:
	last_error = message
	return false

func canonical_skeleton(manifest: Definition) -> Skeleton3D:
	var result := Skeleton3D.new()
	for name in manifest.bone_names: result.add_bone(name)
	for index in manifest.bone_names.size():
		var parent := result.find_bone(manifest.parent_names[index]) if manifest.parent_names[index] != "" else -1
		result.set_bone_parent(index,parent)
		result.set_bone_rest(index,manifest.rest_transforms[index])
	return result

func metadata_valid(config: Config, manifest: Definition) -> bool:
	if config.kind not in ["body","skinned","rigid"]: return reject("Unknown asset kind.")
	if manifest == null or manifest.bone_names.size() != 65 or manifest.parent_names.size() != 65 or manifest.rest_transforms.size() != 65:
		return reject("Reference must contain the complete canonical 65-bone manifest.")
	if config.rig_id != manifest.rig_id: return reject("Metadata rig identifier does not match the reference.")
	if config.mesh_regions.is_empty(): return reject("Declare at least one region and its source mesh path.")
	if config.kind == "body":
		if config.slot != &"" or config.attachment_bone != &"": return reject("Body metadata cannot declare an equipment slot or socket.")
		if config.mesh_regions.size() != manifest.regions.size(): return reject("Body must declare every reference body region.")
		for region in manifest.regions:
			if not config.mesh_regions.has(region): return reject("Body is missing region: "+str(region))
	else:
		if config.slot == &"" or config.slot not in config.allowed_slots: return reject("Equipment must declare a supported slot.")
	if config.kind == "rigid":
		if config.attachment_bone == &"" or not manifest.bone_names.has(String(config.attachment_bone)):
			return reject("Rigid equipment must declare a known socket bone.")
	elif config.attachment_bone != &"": return reject("Only rigid geometry uses an attachment bone.")
	for region in config.covered_regions:
		if not manifest.regions.has(region): return reject("Unknown covered body region: "+str(region))
	if not config.attachment_transform.is_finite(): return reject("Nonfinite attachment transform.")
	if config.kind != "rigid" and config.attachment_transform != Transform3D.IDENTITY:
		return reject("Skinned assets must not declare a rigid attachment transform.")
	var slots := {}
	for slot in config.allowed_slots:
		if slot == &"" or slots.has(slot): return reject("Allowed slots must be unique nonempty names.")
		slots[slot] = true
	return true

func convert(config: Config, validate_only: bool = false) -> bool:
	last_error = ""
	last_definition = null
	if config == null: return reject("Missing import configuration.")
	if config.source_path.get_extension().to_lower() not in ["glb","gltf"] or not FileAccess.file_exists(config.source_path):
		return reject("Source must be an existing .glb or .gltf file.")
	var manifest := load(config.reference_manifest) as Definition
	if not metadata_valid(config,manifest): return false
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	# append_from_file sets named skin binds from its flags (not this state property).
	state.create_animations = false
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	var error := document.append_from_file(config.source_path,state,EditorSceneFormatImporter.IMPORT_USE_NAMED_SKIN_BINDS)
	if error != OK: return reject("Could not read glTF source: "+error_string(error))
	if config.kind != "rigid" and not raw_skin_data_valid(state): return false
	var scene := document.generate_scene(state)
	if scene == null: return reject("glTF produced no scene.")
	var valid := convert_scene(scene,config,manifest)
	scene.free()
	if not valid: return false
	last_definition.source_path = config.source_path
	last_definition.source_sha256 = FileAccess.get_sha256(config.source_path)
	last_definition.provenance = config.provenance.duplicate(true)
	if validate_only: return true
	return publish(config)

## glTF importers can normalize weights. Inspect source accessors before accepting it.
func raw_skin_data_valid(state: GLTFState) -> bool:
	var json := state.json
	for mesh in json.get("meshes",[]):
		for primitive in mesh.get("primitives",[]):
			var attributes: Dictionary = primitive.get("attributes",{})
			if attributes.has("JOINTS_1") or attributes.has("WEIGHTS_1"):
				return reject("Export at most four influences; secondary joint/weight sets are unsupported.")
			if not attributes.has("JOINTS_0") and not attributes.has("WEIGHTS_0"): continue
			if not attributes.has("JOINTS_0") or not attributes.has("WEIGHTS_0"):
				return reject("Skinned primitives need both JOINTS_0 and WEIGHTS_0.")
			var weights := source_accessor(state,int(attributes.WEIGHTS_0),"VEC4")
			if not last_error.is_empty(): return false
			for vertex in weights:
				var total := 0.0
				for weight in vertex:
					if not is_finite(weight) or weight < 0.0: return reject("Source has invalid skin weights.")
					total += weight
				if absf(total-1.0) > Appearance.WEIGHT_TOLERANCE: return reject("Source skin weights must be normalized before export.")
	for skin in json.get("skins",[]):
		if not skin.has("inverseBindMatrices"): return reject("Source skin needs explicit inverse bind matrices.")
		var matrices := source_accessor(state,int(skin.inverseBindMatrices),"MAT4")
		if not last_error.is_empty(): return false
		for matrix in matrices:
			for value in matrix:
				if not is_finite(value): return reject("Source has nonfinite inverse bind matrices.")
	return true

func source_accessor(state: GLTFState, index: int, expected_type: String) -> Array:
	var json := state.json
	var accessors: Array = json.get("accessors",[])
	if index < 0 or index >= accessors.size():
		reject("Invalid source accessor index.")
		return []
	var accessor: Dictionary = accessors[index]
	if accessor.get("type","") != expected_type or accessor.has("sparse") or not accessor.has("bufferView"):
		reject("Export dense "+expected_type+" skin accessors.")
		return []
	var component: int = accessor.get("componentType",0)
	var normalized: bool = accessor.get("normalized",false)
	if component != 5126 and not (expected_type == "VEC4" and component in [5121,5123] and normalized):
		reject("Unsupported skin accessor component type or missing normalization.")
		return []
	var views: Array = json.get("bufferViews",[])
	var view_index: int = accessor.bufferView
	if view_index < 0 or view_index >= views.size():
		reject("Invalid skin buffer view.")
		return []
	var view: Dictionary = views[view_index]
	var buffers := state.get_buffers()
	var buffer_index: int = view.get("buffer",-1)
	if buffer_index < 0 or buffer_index >= buffers.size():
		reject("Missing skin source buffer.")
		return []
	var bytes: PackedByteArray = buffers[buffer_index]
	var size := 4 if component == 5126 else (2 if component == 5123 else 1)
	var width := 16 if expected_type == "MAT4" else 4
	var stride: int = view.get("byteStride",size*width)
	var start: int = int(view.get("byteOffset",0))+int(accessor.get("byteOffset",0))
	var count: int = accessor.get("count",0)
	var end: int = int(view.get("byteOffset",0))+int(view.get("byteLength",0))
	if count <= 0 or stride < size*width or start < 0 or start+(count-1)*stride+size*width > mini(end,bytes.size()):
		reject("Skin source accessor exceeds its buffer view.")
		return []
	var result: Array = []
	for row in count:
		var values: Array[float] = []
		for column in width:
			var offset := start+row*stride+column*size
			values.append(bytes.decode_float(offset) if component == 5126 else (float(bytes.decode_u16(offset))/65535.0 if component == 5123 else float(bytes[offset])/255.0))
		result.append(values)
	return result

func relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != ancestor and cursor != null:
		if cursor is Node3D: result = cursor.transform*result
		cursor = cursor.get_parent()
	return result

func convert_scene(scene: Node, config: Config, manifest: Definition) -> bool:
	last_error = ""
	last_definition = null
	_materials.clear()
	_textures.clear()
	if not metadata_valid(config,manifest): return false
	var reference := canonical_skeleton(manifest)
	var validator := Appearance.new()
	validator.configure(reference,manifest.rig_id,config.allowed_slots)
	var result := Definition.new()
	result.rig_id = config.rig_id
	result.slot = config.slot
	result.covered_regions.assign(config.covered_regions)
	result.attachment_bone = config.attachment_bone
	result.attachment_transform = config.attachment_transform
	var source_skeleton: Skeleton3D
	if config.kind != "rigid":
		if not config.skeleton_path.is_empty(): source_skeleton = scene.get_node_or_null(config.skeleton_path) as Skeleton3D
		else:
			var skeletons := scene.find_children("*","Skeleton3D",true,false)
			if scene is Skeleton3D: skeletons.push_front(scene)
			if skeletons.size() == 1: source_skeleton = skeletons[0]
		if source_skeleton == null:
			reference.free()
			return reject("Declare one source armature; it must contain the unchanged UAL65 skeleton.")
		for index in source_skeleton.get_bone_count():
			result.bone_names.append(source_skeleton.get_bone_name(index))
			var parent := source_skeleton.get_bone_parent(index)
			result.parent_names.append(source_skeleton.get_bone_name(parent) if parent >= 0 else "")
			result.rest_transforms.append(source_skeleton.get_bone_rest(index))
		if not validator.near_transform(relative_transform(source_skeleton,scene),Transform3D.IDENTITY):
			reference.free()
			return reject("Armature object transforms differ from the reference; restore the reference transforms before export.")
		result.skin = Skin.new()
		for index in reference.get_bone_count():
			result.skin.add_named_bind(reference.get_bone_name(index),reference.get_bone_global_rest(index).affine_inverse())
	var rigid_root := scene.get_node_or_null(config.rigid_root)
	var used := {}
	for region in config.mesh_regions:
		if str(region).is_empty() or not (region is String or region is StringName):
			last_error = "Region names must be nonempty strings."
			break
		var path := NodePath(str(config.mesh_regions[region]))
		var source := scene.get_node_or_null(path) as MeshInstance3D
		if source == null or not source.mesh is ArrayMesh or used.has(source):
			last_error = "Missing, duplicated or unsupported source mesh: "+str(path)
			break
		used[source] = true
		if source.mesh.get_blend_shape_count() > 0:
			last_error = "Blend shapes are not supported by this converter; export a fixed body shape."
			break
		if config.kind == "rigid":
			if rigid_root == null or (source != rigid_root and not rigid_root.is_ancestor_of(source)):
				last_error = "Rigid mesh must be inside the declared attachment root."
				break
			if not validator.valid_geometry(source.mesh):
				last_error = validator.last_error
				break
			result.regions[StringName(region)] = copy_mesh(source,[],null)
			result.region_transforms[StringName(region)] = relative_transform(source,rigid_root)
		else:
			if source.skin == null or source.get_node_or_null(source.skeleton) != source_skeleton:
				last_error = "Selected mesh must bind to the declared source armature."
				break
			if not validator.near_transform(relative_transform(source,source_skeleton),Transform3D.IDENTITY):
				last_error = "Skinned mesh object transforms differ from the reference; restore the reference transforms before export."
				break
			if not validator.valid_mesh(source.mesh,source.skin):
				last_error = validator.last_error
				break
			var remap: Array[int] = []
			var binds := {}
			for bind in source.skin.get_bind_count():
				var index := reference.find_bone(source.skin.get_bind_name(bind))
				if index < 0 or binds.has(index) or not validator.near_transform(source.skin.get_bind_pose(bind),reference.get_bone_global_rest(index).affine_inverse()):
					last_error = "Skin bind name or inverse rest differs from the canonical rig."
					break
				binds[index] = true
				remap.append(index)
			if not last_error.is_empty(): break
			result.regions[StringName(region)] = copy_mesh(source,remap,result.skin)
	if last_error.is_empty() and config.kind == "body":
		result.contact_mesh = ArrayMesh.new()
		for mesh: ArrayMesh in result.regions.values():
			for surface in mesh.get_surface_count():
				result.contact_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface),mesh.surface_get_arrays(surface))
		result.sole_vertices = preload("res://features/presentation/skin_contact_cache.gd").generate_soles(result.contact_mesh,result.skin,{"l":["foot_l","ball_l","ball_leaf_l"],"r":["foot_r","ball_r","ball_leaf_r"]})
	if last_error.is_empty() and not validator.compatible(result): last_error = validator.last_error
	reference.free()
	if not last_error.is_empty(): return false
	last_definition = result
	return true

func copy_mesh(source: MeshInstance3D, remap: Array, _skin: Skin) -> ArrayMesh:
	var result := ArrayMesh.new()
	result.resource_name = source.mesh.resource_name
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		if not remap.is_empty():
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for index in bones.size(): bones[index] = remap[bones[index]]
			arrays[Mesh.ARRAY_BONES] = bones
		result.add_surface_from_arrays(source.mesh.surface_get_primitive_type(surface),arrays)
		result.surface_set_material(surface,copy_material(source.get_active_material(surface)))
	return result

func copy_material(original: Material) -> Material:
	if original == null: return null
	if _materials.has(original): return _materials[original]
	var result: Material = original.duplicate()
	_materials[original] = result
	for property in original.get_property_list():
		if not property.usage & PROPERTY_USAGE_STORAGE: continue
		var value: Variant = original.get(property.name)
		if value is Texture2D:
			if not _textures.has(value):
				var pixels: Image = value.get_image()
				if pixels == null or pixels.is_empty():
					reject("Source material has an unreadable texture.")
					return null
				var texture := PortableCompressedTexture2D.new()
				texture.set_keep_compressed_buffer(true)
				texture.create_from_image(pixels,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
				_textures[value] = texture
			result.set(property.name,_textures[value])
	if original.next_pass != null: result.next_pass = copy_material(original.next_pass)
	return result

func packed_rigid() -> PackedScene:
	var root := Node3D.new()
	root.name = "EquipmentVisual"
	root.set_meta("source_path",last_definition.source_path)
	root.set_meta("source_sha256",last_definition.source_sha256)
	root.set_meta("provenance",last_definition.provenance)
	for region in last_definition.regions:
		var mesh := MeshInstance3D.new()
		mesh.name = region
		mesh.mesh = last_definition.regions[region]
		mesh.transform = last_definition.region_transforms.get(region,Transform3D.IDENTITY)
		root.add_child(mesh)
		mesh.owner = root
	var result := PackedScene.new()
	result.pack(root)
	root.free()
	return result

func valid_material(material: Material, seen: Dictionary) -> bool:
	if material == null or seen.has(material): return true
	seen[material] = true
	for property in material.get_property_list():
		if not property.usage & PROPERTY_USAGE_STORAGE: continue
		var value: Variant = material.get(property.name)
		if value is Texture2D:
			var pixels: Image = value.get_image()
			if pixels == null or pixels.is_empty(): return reject("Staged material lost its texture pixels.")
	return valid_material(material.next_pass,seen)

func valid_saved_asset(artifact: Resource, config: Config) -> bool:
	var meshes: Array = []
	if artifact is Definition:
		var reference := canonical_skeleton(load(config.reference_manifest))
		var validator := Appearance.new()
		validator.configure(reference,config.rig_id,config.allowed_slots)
		var valid := validator.compatible(artifact)
		if not valid: last_error = validator.last_error
		reference.free()
		if not valid: return false
		meshes = artifact.regions.values()
	elif artifact is PackedScene and config.kind == "rigid":
		var instance: Node = artifact.instantiate()
		for node in instance.find_children("*","MeshInstance3D",true,false): meshes.append(node.mesh)
		var valid: bool = meshes.size() == config.mesh_regions.size() and instance.find_children("*","Skeleton3D",true,false).is_empty() and instance.find_children("*","AnimationPlayer",true,false).is_empty()
		instance.free()
		if not valid: return reject("Staged rigid asset must contain only the declared geometry.")
	else: return reject("Staged asset has an unexpected resource type.")
	var seen := {}
	for mesh: ArrayMesh in meshes:
		for surface in mesh.get_surface_count():
			if not valid_material(mesh.surface_get_material(surface),seen): return false
	return true

func publish(config: Config) -> bool:
	var extension := config.output_path.get_extension().to_lower()
	if extension != "res" and not (extension == "scn" and config.kind == "rigid"):
		return reject("Output must be .res, or .scn for a rigid geometry scene.")
	var destination := ProjectSettings.globalize_path(config.output_path).simplify_path()
	if destination == ProjectSettings.globalize_path(config.source_path).simplify_path() or destination == ProjectSettings.globalize_path(config.reference_manifest).simplify_path():
		return reject("Output must not replace a source or reference asset.")
	var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if error != OK: return reject("Cannot create output directory: "+error_string(error))
	var temporary := destination.get_basename()+".staging_"+str(OS.get_process_id())+"_"+str(Time.get_ticks_usec())+"."+extension
	var artifact: Resource = packed_rigid() if extension == "scn" else last_definition
	error = ResourceSaver.save(artifact,temporary,ResourceSaver.FLAG_COMPRESS)
	if error != OK: return reject("Cannot stage asset: "+error_string(error))
	var loaded := ResourceLoader.load(temporary,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if loaded == null or not valid_saved_asset(loaded,config):
		DirAccess.remove_absolute(temporary)
		return reject("Staged asset failed reload validation; previous output preserved. "+last_error)
	error = DirAccess.rename_absolute(temporary,destination)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return reject("Cannot publish asset; previous output preserved: "+error_string(error))
	return true
