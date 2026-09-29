extends SceneTree
## CLI-compatible wrapper around the shared atomic source-native builder.
const Builder = preload("res://tools/ual_animation_builder.gd")
const MANIFEST = preload("res://tools/ual_animation_build_manifest.tres")
const OUTPUT := "res://assets/animations/ual/anim_ual_native_combat_library_v01.tres"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var builder := Builder.new()
	var ok := builder.build_library(root,MANIFEST.combat_clips,OUTPUT,Callable(),{})
	if not ok: push_error(builder.last_error)
	else: print("UAL NATIVE_COMBAT: preserved and verified ",MANIFEST.combat_clips.size()," source clips")
	quit(0 if ok else 1)

# Preserve the previous CLI helper surface for source-fidelity tests/tools.
func same_rig(reference: Skeleton3D, candidate: Skeleton3D) -> bool:
	return Builder.new().same_rig(reference,candidate)
func same_value(a: Variant, b: Variant) -> bool:
	return Builder.new().same_value(a,b)
func same_clip(source: Animation, saved: Animation) -> bool:
	return Builder.new().same_clip(source,saved)
