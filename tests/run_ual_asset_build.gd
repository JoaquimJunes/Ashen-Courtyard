extends SceneTree
## Runtime assets stay independent of authoring imports; failed builds are transactional.
const Builder = preload("res://tools/ual_animation_builder.gd")
const MANIFEST = preload("res://tools/ual_animation_build_manifest.tres")
const RUNTIME = preload("res://assets/models/ual/runtime_rig.tscn")
const PROFILE = preload("res://features/presentation/data/ual_animation_profile.tres")
const BODY = preload("res://assets/models/ual/mannequin_body.res")
const OUTPUT := "res://.artifacts/tests/ual-asset-build/library.tres"
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)
func dependencies(path: String, found: Dictionary) -> void:
	if found.has(path): return
	found[path] = true
	for value: String in ResourceLoader.get_dependencies(path):
		var dependency := value.get_slice("::",value.get_slice_count("::")-1)
		if dependency.begins_with("res://"): dependencies(dependency,found)
func corrupt_annotation(_role: String, clip: Animation, _source: Node, _player: AnimationPlayer, _name: String) -> void:
	clip.length += 0.25
func run() -> void:
	var builder := Builder.new()
	var source: Node = MANIFEST.source_scene.instantiate()
	var runtime: Node = RUNTIME.instantiate()
	root.add_child(source)
	root.add_child(runtime)
	var original: Skeleton3D = source.find_child("Skeleton3D",true,false)
	var skeleton: Skeleton3D = runtime.find_child("Skeleton3D",true,false)
	var player: AnimationPlayer = runtime.find_child("AnimationPlayer",true,false)
	var source_player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	check(builder.canonical_rig(skeleton) and builder.same_rig(original,skeleton),"Runtime retains all 65 source bone names, parents and rest transforms")
	check(source.get_path_to(original) == runtime.get_path_to(skeleton),"Runtime preserves Armature/Skeleton3D track addressing")
	check(runtime.find_children("*","MeshInstance3D",true,false).is_empty() and player.get_animation_list().is_empty(),"Runtime rig contains no meshes or imported source animations")
	check(source_player.get_animation_list().size() > 20,"Authoring source still retains its complete animation bank")
	var transforms_match: bool = original.transform.is_equal_approx(skeleton.transform) and original.get_parent().transform.is_equal_approx(skeleton.get_parent().transform)
	check(transforms_match,"Runtime retains source armature/skeleton orientation and scale")
	check(runtime.get_meta("rig_identifier",&"") == &"ual1_65_v1" and runtime.get_meta("source_sha256","") == FileAccess.get_sha256(MANIFEST.source_scene.resource_path),"Runtime rig preserves source provenance without a source resource dependency")
	check(PROFILE.rig_contract.valid(skeleton),"Lightweight runtime contract validates the extracted rig")
	var all_targets := true
	for library: AnimationLibrary in [PROFILE.native_locomotion,PROFILE.native_combat,PROFILE.native_actions,PROFILE.native_swimming,PROFILE.temporary_actions]:
		for name: String in library.get_animation_list(): all_targets = all_targets and builder.valid_targets(player,library.get_animation(name))
	check(all_targets,"Every extracted/native/temporary track resolves on the lightweight rig")
	var bindings_match := true
	for bind in BODY.skin.get_bind_count():
		bindings_match = bindings_match and skeleton.find_bone(BODY.skin.get_bind_name(bind)) >= 0
	check(bindings_match,"Existing body named skin bindings all resolve without rebinding")
	var graph := {}
	dependencies("res://scenes/models/ual_player.tscn",graph)
	var no_imports := true
	for path: String in graph:
		if "/quaternius/UAL" in path or "/quaternius/ual2/UAL" in path or path.contains("ual_animation_build_manifest"): no_imports = false
	check(no_imports and graph.has("res://assets/models/ual/runtime_rig.tscn"),"Production model dependency graph excludes complete source banks and build manifest")
	var rest := skeleton.get_bone_rest(1)
	var changed := rest
	changed.origin.x += 0.1
	skeleton.set_bone_rest(1,changed)
	check(not builder.canonical_rig(skeleton),"Builder rejects a changed reference rest transform")
	skeleton.set_bone_rest(1,rest)
	check(builder.build_library(root,MANIFEST.swimming_clips,OUTPUT),"Shared builder successfully stages, reloads and verifies source clips")
	var hash := FileAccess.get_sha256(OUTPUT)
	check(not builder.build_library(root,{"missing":[MANIFEST.source_scene.resource_path,"not_a_ual_clip"]},OUTPUT) and FileAccess.get_sha256(OUTPUT) == hash,"Missing input leaves the previously working output unchanged")
	check(not builder.build_library(root,MANIFEST.swimming_clips,OUTPUT,corrupt_annotation) and FileAccess.get_sha256(OUTPUT) == hash,"Serialized key/length verification rejects mutation and preserves working output")
	var clean := true
	for filename in DirAccess.get_files_at(OUTPUT.get_base_dir()):
		if filename.contains(".pending-"): clean = false
	check(clean,"Successful and failed builds clean their private staging files")
	var saved: AnimationLibrary = ResourceLoader.load(OUTPUT,"AnimationLibrary",ResourceLoader.CACHE_MODE_IGNORE)
	var provenance: bool = saved.get_meta("rig_identifier",&"") == &"ual1_65_v1" and saved.get_meta("rig_reference_sha256","") == FileAccess.get_sha256(MANIFEST.source_scene.resource_path)
	for role: String in MANIFEST.swimming_clips:
		var clip := saved.get_animation(role)
		provenance = provenance and clip.get_meta("native_keyframes",false) and clip.get_meta("source_sha256","") == FileAccess.get_sha256(MANIFEST.swimming_clips[role][0]) and builder.same_clip(source_player.get_animation(MANIFEST.swimming_clips[role][1]),clip)
	check(provenance,"Saved library carries verified rig/source hashes and unchanged keys")
	runtime.free()
	source.free()
	print("UAL ASSET BUILD: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
