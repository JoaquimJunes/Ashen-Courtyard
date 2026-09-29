extends SceneTree
## Captures the refactored playable worlds and shared-character preview.
func _initialize() -> void: run.call_deferred()
func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/foundation")
	var arena = load("res://scenes/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.boss.frozen = true
	for i in 25: await physics_frame
	await capture("res://docs/foundation/courtyard.png")
	arena.queue_free()
	await process_frame
	var lab = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	for i in 25: await physics_frame
	await capture("res://docs/foundation/test-grounds.png")
	lab.hud.toggle_pause()
	await capture("res://docs/foundation/lab-menu.png")
	lab.hud.toggle_pause()
	lab.queue_free()
	await process_frame
	var preview = load("res://scenes/dodge_preview.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	var captured := false
	for i in 60:
		await physics_frame
		if preview.phase == preview.Phase.DIVE and preview.phase_time >= 0.10:
			preview.toggle_pause()
			await capture("res://docs/foundation/shared-preview.png")
			captured = true
			break
	assert(captured,"Preview must reach the airborne pose")
	preview.queue_free()
	await process_frame
	print("FOUNDATION RENDERS: docs/foundation")
	quit()
