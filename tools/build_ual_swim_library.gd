extends SceneTree
## CLI-compatible wrapper around the shared atomic source-native builder.
const Builder = preload("res://tools/ual_animation_builder.gd")
const MANIFEST = preload("res://tools/ual_animation_build_manifest.tres")
const OUTPUT := "res://assets/animations/ual/anim_ual_native_swimming_library_v01.tres"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var builder := Builder.new()
	var ok := builder.build_library(root,MANIFEST.swimming_clips,OUTPUT,Callable(),{"swim_idle":{"source_glb_clip":"Swim_Idle_Loop"},"swim_forward":{"source_glb_clip":"Swim_Fwd_Loop"}})
	if not ok: push_error(builder.last_error)
	else: print("UAL NATIVE_SWIMMING: preserved and verified ",MANIFEST.swimming_clips.size()," source clips")
	quit(0 if ok else 1)
