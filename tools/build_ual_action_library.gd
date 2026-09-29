extends SceneTree
## CLI-compatible wrapper around the shared atomic source-native builder.
const Builder = preload("res://tools/ual_animation_builder.gd")
const MANIFEST = preload("res://tools/ual_animation_build_manifest.tres")
const OUTPUT := "res://assets/animations/ual/anim_ual_native_actions_library_v01.tres"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var builder := Builder.new()
	var ok := builder.build_library(root,MANIFEST.action_clips,OUTPUT,Callable(),{"spell_idle":{"source_glb_clip":"Spell_Simple_Idle_Loop"},"climb_up_1m_rm":{"source_root_motion":true}})
	if not ok: push_error(builder.last_error)
	else: print("UAL NATIVE_ACTIONS: preserved and verified ",MANIFEST.action_clips.size()," source clips")
	quit(0 if ok else 1)
