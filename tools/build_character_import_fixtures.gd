extends SceneTree
## Re-export existing fitting fixtures for pipeline examples; this creates no new geometry.
const Config = preload("res://tools/character_asset_import.gd")
const Converter = preload("res://tools/character_asset_converter.gd")
const Definition = preload("res://features/presentation/appearance_definition.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var source_dir := "res://art_source/import_fixtures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source_dir))
	var converter := Converter.new()
	for kind in ["body","skinned"]:
		var name: String = "body_reference" if kind == "body" else "chest_reference"
		var original := "res://assets/models/ual/"+("mannequin_body.res" if kind == "body" else "chest_fixture.res")
		var definition := load(original) as Definition
		var scene := Node3D.new()
		scene.name = "AuthorFixture"
		var skeleton := converter.canonical_skeleton(definition)
		skeleton.name = "Skeleton3D"
		skeleton.reset_bone_poses()
		scene.add_child(skeleton)
		var config := Config.new()
		config.source_path = source_dir+"/"+name+".glb"
		config.kind = kind
		config.output_path = "res://.artifacts/import_examples/"+name+".res"
		config.skeleton_path = NodePath("Skeleton3D")
		if kind == "skinned":
			config.slot = &"torso"
			config.covered_regions = [&"torso"]
		config.provenance = {"reference_resource":original,"generator":"res://tools/build_character_import_fixtures.gd","purpose":"Existing fitting-fixture roundtrip, not final art; geometry and materials unchanged"}
		for region in definition.regions:
			var mesh := MeshInstance3D.new()
			mesh.name = "region_"+str(region).replace(".","_")
			mesh.mesh = definition.regions[region]
			mesh.skin = definition.skin
			skeleton.add_child(mesh)
			mesh.skeleton = NodePath("..")
			config.mesh_regions[region] = scene.get_path_to(mesh)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_scene(scene,state,EditorSceneFormatImporter.IMPORT_USE_NAMED_SKIN_BINDS)
		if error == OK: error = document.write_to_filesystem(state,config.source_path)
		scene.free()
		if error == OK: error = ResourceSaver.save(config,"res://tools/character_imports/"+name+".tres")
		if error != OK or not converter.convert(config,true):
			printerr("Fixture export failed: ",error_string(error)," ",converter.last_error)
			quit(1)
			return
		print("REFERENCE FIXTURE: ",config.source_path)
	quit()
