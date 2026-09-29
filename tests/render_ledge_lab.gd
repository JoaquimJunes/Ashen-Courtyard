extends SceneTree
## Review the production laboratory UI and shoulder camera, using real gameplay.
func _initialize() -> void: run.call_deferred()

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	var lab: Node3D = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	lab.start_ledge_test()
	lab.player.controller.manual = true
	for i in 10: await physics_frame
	lab.hud.toggle_pause()
	await capture("res://docs/ledge-grab/lab-menu.png")
	lab.hud.toggle_pause()
	lab.player.controller.intent.movement = Vector3.FORWARD
	lab.player.request_action(&"jump")
	for i in 100:
		await physics_frame
		if lab.player.traversal.status == &"hang": break
	for i in 20: await physics_frame
	await capture("res://docs/ledge-grab/lab-hang.png")
	lab.queue_free()
	await process_frame
	quit()
