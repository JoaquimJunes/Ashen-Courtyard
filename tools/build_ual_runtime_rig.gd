extends SceneTree
## Extract the canonical hierarchy/rest pose without importing the source clip bank at runtime.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var builder := preload("res://tools/ual_animation_builder.gd").new()
	var ok := builder.build_runtime_rig() and builder.build_rig_contract()
	if not ok: push_error(builder.last_error)
	else: print("UAL RUNTIME RIG: verified 65 source bones, unchanged track paths, no source animation bank")
	quit(0 if ok else 1)
