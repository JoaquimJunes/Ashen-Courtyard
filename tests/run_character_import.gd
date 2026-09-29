extends SceneTree
const Config = preload("res://tools/character_asset_import.gd")
const Converter = preload("res://tools/character_asset_converter.gd")
const Appearance = preload("res://features/presentation/character_appearance.gd")
const Definition = preload("res://features/presentation/appearance_definition.gd")
const BODY = preload("res://assets/models/ual/mannequin_body.res")
const CHEST = preload("res://assets/models/ual/chest_fixture.res")
var checks := 0
var failures := 0
var converter := Converter.new()
var workspace := "user://character_import_tests"
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)

func source_scene(definition: Definition, reversed: bool = false) -> Node3D:
	var scene := Node3D.new()
	scene.name = "AuthorFixture"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	var names := definition.bone_names.duplicate()
	if reversed: names.reverse()
	for name in names: skeleton.add_bone(name)
	for index in definition.bone_names.size():
		var bone := skeleton.find_bone(definition.bone_names[index])
		skeleton.set_bone_rest(bone,definition.rest_transforms[index])
		skeleton.set_bone_parent(bone,skeleton.find_bone(definition.parent_names[index]))
	skeleton.reset_bone_poses()
	scene.add_child(skeleton)
	for region in definition.regions:
		var mesh := MeshInstance3D.new()
		mesh.name = "region_"+str(region).replace(".","_")
		mesh.mesh = definition.regions[region]
		mesh.skin = definition.skin.duplicate()
		skeleton.add_child(mesh)
		mesh.skeleton = NodePath("..")
	return scene

func configuration(scene: Node, definition: Definition, body: bool = false) -> Config:
	var config := Config.new()
	config.kind = "body" if body else "skinned"
	config.skeleton_path = NodePath("Skeleton3D")
	config.slot = &"" if body else &"torso"
	config.covered_regions.assign([] if body else [&"torso"])
	for region in definition.regions: config.mesh_regions[region] = "Skeleton3D/region_"+str(region).replace(".","_")
	config.output_path = workspace+"/"+("body" if body else "armor")+".res"
	return config

func test_scene_validation() -> void:
	var scene := source_scene(CHEST)
	var config := configuration(scene,CHEST)
	check(converter.convert_scene(scene,config,BODY),"Existing armor fixture converts: "+converter.last_error)
	check(converter.last_definition.skin.get_bind_count() == 65,"Runtime skin uses named canonical binds")
	var reordered := source_scene(CHEST,true)
	check(converter.convert_scene(reordered,config,BODY),"Bone array order is independent of name/rest contract: "+converter.last_error)
	reordered.free()
	var mesh: MeshInstance3D = scene.get_node(config.mesh_regions.keys().map(func(key): return config.mesh_regions[key])[0])
	var original_skin := mesh.skin
	mesh.skin = original_skin.duplicate()
	var bad_bind := mesh.skin.get_bind_pose(1)
	bad_bind.origin.x += 0.1
	mesh.skin.set_bind_pose(1,bad_bind)
	check(not converter.convert_scene(scene,config,BODY),"Wrong inverse bind rejected")
	bad_bind.origin.x = NAN
	mesh.skin.set_bind_pose(1,bad_bind)
	check(not converter.convert_scene(scene,config,BODY),"Nonfinite inverse bind rejected")
	mesh.skin = original_skin
	var skeleton: Skeleton3D = scene.get_node("Skeleton3D")
	var rest := skeleton.get_bone_rest(1)
	var changed := rest
	changed.origin.y += 0.02
	skeleton.set_bone_rest(1,changed)
	check(not converter.convert_scene(scene,config,BODY),"Changed canonical rest rejected")
	skeleton.set_bone_rest(1,rest)
	var parent := skeleton.get_bone_parent(2)
	skeleton.set_bone_parent(2,0)
	check(not converter.convert_scene(scene,config,BODY),"Changed canonical hierarchy rejected")
	skeleton.set_bone_parent(2,parent)
	config.mesh_regions[&"missing"] = "Skeleton3D/Missing"
	check(not converter.convert_scene(scene,config,BODY),"Missing mesh path rejected")
	config.mesh_regions.erase(&"missing")
	config.covered_regions = [&"invented_region"]
	check(not converter.convert_scene(scene,config,BODY),"Unknown coverage region rejected")
	config.covered_regions = [&"torso"]
	config.allowed_slots = [&"torso",&"torso"]
	check(not converter.convert_scene(scene,config,BODY),"Duplicate slot declarations rejected")
	scene.free()
	var body_scene := source_scene(BODY)
	var body_config := configuration(body_scene,BODY,true)
	check(converter.convert_scene(body_scene,body_config,BODY),"Existing explicit body regions convert")
	var surfaces := 0
	for mesh_value: ArrayMesh in BODY.regions.values(): surfaces += mesh_value.get_surface_count()
	check(converter.last_definition.contact_mesh.get_surface_count() == surfaces,"Contact geometry aggregates explicitly declared body regions")
	check(not converter.last_definition.sole_vertices.l.is_empty() and not converter.last_definition.sole_vertices.r.is_empty(),"Body conversion generates explicit support for both feet")
	body_config.mesh_regions.erase(&"torso")
	check(not converter.convert_scene(body_scene,body_config,BODY),"Incomplete declared body region map rejected")
	body_scene.free()

func test_raw_source_weights() -> void:
	var state := GLTFState.new()
	var bytes := PackedByteArray()
	bytes.resize(16)
	bytes.encode_float(0,0.5)
	bytes.encode_float(4,0.5)
	state.buffers = [bytes]
	state.json = {"bufferViews":[{"buffer":0,"byteLength":16}],"accessors":[{"bufferView":0,"componentType":5126,"count":1,"type":"VEC4"}],"meshes":[{"primitives":[{"attributes":{"JOINTS_0":0,"WEIGHTS_0":0}}]}]}
	converter.last_error = ""
	check(converter.raw_skin_data_valid(state),"Raw normalized source weights accepted")
	bytes.encode_float(0,0.501)
	state.buffers = [bytes]
	check(not converter.raw_skin_data_valid(state),"Raw nonnormalized weights rejected before importer repair")
	bytes.encode_float(0,NAN)
	state.buffers = [bytes]
	check(not converter.raw_skin_data_valid(state),"Raw nonfinite weights rejected")
	var json := state.json.duplicate(true)
	json.meshes[0].primitives[0].attributes["WEIGHTS_1"] = 0
	state.json = json
	check(not converter.raw_skin_data_valid(state),"More than four source influences rejected")

func invalid_glb(source_path: String, target_path: String, change_weights: bool) -> void:
	var bytes := FileAccess.get_file_as_bytes(source_path)
	var json_length := bytes.decode_u32(12)
	var json: Dictionary = JSON.parse_string(bytes.slice(20,20+json_length).get_string_from_utf8())
	var accessor_index: int = json.meshes[0].primitives[0].attributes.WEIGHTS_0 if change_weights else json.skins[0].inverseBindMatrices
	var accessor: Dictionary = json.accessors[accessor_index]
	var view: Dictionary = json.bufferViews[accessor.bufferView]
	var start: int = 28+json_length+int(view.get("byteOffset",0))+int(accessor.get("byteOffset",0))
	if change_weights:
		var size := 4 if int(accessor.componentType) == 5126 else (2 if int(accessor.componentType) == 5123 else 1)
		for index in size*4: bytes[start+index] = 0
	else: bytes.encode_float(start+12*4,0.5)
	var file := FileAccess.open(target_path,FileAccess.WRITE)
	file.store_buffer(bytes)

func test_roundtrip() -> void:
	for is_body in [false,true]:
		var definition: Definition = BODY if is_body else CHEST
		var scene := source_scene(definition)
		var config := configuration(scene,definition,is_body)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var path := workspace+("/body.glb" if is_body else "/armor.glb")
		check(document.append_from_scene(scene,state) == OK,"Existing fixture can export glTF")
		check(document.write_to_filesystem(state,path) == OK,"Fixture writes a complete glTF roundtrip source")
		scene.free()
		config.source_path = path
		var imported := GLTFState.new()
		imported.use_named_skin_binds = true
		check(document.append_from_file(path,imported,EditorSceneFormatImporter.IMPORT_USE_NAMED_SKIN_BINDS) == OK,"Fixture glTF reloads")
		var source := document.generate_scene(imported)
		var armature: Skeleton3D = source.find_children("*","Skeleton3D",true,false)[0]
		config.skeleton_path = source.get_path_to(armature)
		for region in config.mesh_regions:
			config.mesh_regions[region] = source.get_path_to(source.find_child("region_"+str(region).replace(".","_"),true,false))
		check(armature.get_bone_count() == 65,"glTF roundtrip retains all unweighted reference bones")
		source.free()
		var checksum := FileAccess.get_sha256(path)
		for repeat in 3:
			check(converter.convert(config),"Repeated glTF conversion "+str(repeat)+": "+converter.last_error)
			var loaded := ResourceLoader.load(config.output_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Definition
			check(loaded != null and loaded.regions.size() == definition.regions.size(),"Saved appearance reload preserves declared geometry")
			check(loaded != null and loaded.bone_names.size() == 65,"Saved appearance preserves full rig manifest")
		check(FileAccess.get_sha256(path) == checksum,"Conversion leaves source unchanged")
		var old_output := FileAccess.get_sha256(config.output_path)
		for weights in [true,false]:
			var bad_path := workspace+("/bad_weights.glb" if weights else "/bad_bind.glb")
			invalid_glb(path,bad_path,weights)
			config.source_path = bad_path
			check(not converter.convert(config),"Actual malformed GLB source rejected: "+("weights" if weights else "bind"))
			check(FileAccess.get_sha256(config.output_path) == old_output,"Malformed GLB preserves previously published output")
		config.source_path = path
		var first_region: Variant = config.mesh_regions.keys()[0]
		config.mesh_regions[first_region] = "MissingMesh"
		check(not converter.convert(config),"Invalid replacement fails before publication")
		check(FileAccess.get_sha256(config.output_path) == old_output,"Failed import leaves previous output byte-identical")

func test_runtime_atomicity() -> void:
	var skeleton := converter.canonical_skeleton(BODY)
	root.add_child(skeleton)
	var appearance := Appearance.new()
	appearance.configure(skeleton,BODY.rig_id)
	check(appearance.set_body(BODY),"Runtime body installs")
	check(appearance.equip(CHEST),"Runtime armor installs")
	var old_mesh: Node = appearance.equipment[&"torso"].nodes[0]
	var old_contact: Node = appearance.contact
	var bad_weights: ArrayMesh = CHEST.regions.values()[0].duplicate()
	var arrays := bad_weights.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for index in 4: weights[index] = 0.0
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	bad_weights.clear_surfaces()
	bad_weights.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	check(not appearance.valid_mesh(bad_weights,CHEST.skin),"Runtime unnormalized weights rejected")
	var bad := CHEST.duplicate(true)
	bad.skin.set_bind_pose(0,Transform3D(Basis.IDENTITY,Vector3.ONE))
	check(not appearance.equip(bad),"Runtime rejects malformed bind replacement")
	check(appearance.equipment[&"torso"].nodes[0] == old_mesh and not appearance.body[&"torso"].visible,"Failed equip preserves live geometry/coverage")
	bad = BODY.duplicate()
	bad.regions = BODY.regions.duplicate()
	bad.regions.erase(&"torso")
	check(not appearance.set_body(bad),"Body replacement cannot remove a covered region")
	check(appearance.contact == old_contact,"Failed body replacement preserves contact mesh")
	check(not appearance.set_slots([&"hat"]),"Cannot remove occupied slot")
	check(appearance.set_slots([&"torso",&"charm"]),"Slots can be configured beyond default five")
	var rigid := Definition.new()
	rigid.slot = &"charm"
	rigid.attachment_bone = &"Head"
	rigid.regions = {&"charm":CHEST.regions.values()[0]}
	check(appearance.equip(rigid),"Rigid geometry needs only valid socket, no armature manifest or skin")
	check(appearance.last_error.is_empty(),"Successful operation clears stale validation error")
	check(skeleton.find_children("*","Skeleton3D",true,false).is_empty(),"Rigid and skinned equipment add no skeleton")
	var old_rigid: Node = appearance.equipment[&"charm"].nodes[0]
	rigid = rigid.duplicate()
	rigid.attachment_bone = &"unknown"
	check(not appearance.equip(rigid),"Rigid unknown socket rejected")
	check(appearance.equipment[&"charm"].nodes[0] == old_rigid,"Rejected rigid swap preserves previous instance")
	rigid.attachment_bone = &"Head"
	rigid.regions = {&"bad":Resource.new()}
	check(not appearance.equip(rigid) and not appearance.last_error.is_empty(),"Invalid rigid region has useful error")
	skeleton.free()

func test_review_assets() -> void:
	for name in ["azure_sword","wooden_shield"]:
		var path: String = "res://assets/equipment/review/"+name+".scn"
		check(ResourceLoader.get_dependencies(path).is_empty(),"Staged "+name+" has no source-pack dependencies")
		var packed := load(path) as PackedScene
		var config := load("res://tools/character_imports/"+name+".tres") as Config
		check(converter.valid_saved_asset(packed,config),"Saved "+name+" retains meshes, materials and all texture pixels")
	var config := load("res://tools/character_imports/azure_sword.tres").duplicate()
	config.output_path = workspace+"/rigid.scn"
	check(converter.convert(config),"Real rigid glTF with no skeleton converts: "+converter.last_error)
	check(converter.last_definition.bone_names.is_empty() and converter.last_definition.skin == null,"Rigid output does not fake a skinned manifest")
	var prior_hash := FileAccess.get_sha256(config.output_path)
	check(converter.convert(config,true),"Validate-only accepts valid source")
	check(FileAccess.get_sha256(config.output_path) == prior_hash,"Validate-only leaves prior output unchanged")
	config.attachment_bone = &"missing_socket"
	check(not converter.convert(config),"CLI pipeline rejects unknown rigid socket")
	check(FileAccess.get_sha256(config.output_path) == prior_hash,"Invalid rigid replacement preserves old file")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(workspace))
	test_scene_validation()
	test_raw_source_weights()
	test_roundtrip()
	test_runtime_atomicity()
	test_review_assets()
	print("CHARACTER IMPORT: ",checks," checks, ",failures," failures")
	quit(1 if failures > 0 else 0)
