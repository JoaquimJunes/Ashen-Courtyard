extends SceneTree
## Native UI inspection only; uses the production world and shared menu.
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(path: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	change_scene_to_file("res://scenes/movement_lab.tscn" if "--lab" in OS.get_cmdline_user_args() else "res://scenes/arena.tscn")
	await frames(20)
	var menu: CanvasLayer = current_scene.hud.menu
	menu.open_menu("Settings")
	if "--warning" in OS.get_cmdline_user_args():
		menu.settings.editors.Camera.widgets.fov.value = 78
		menu.request_close()
		await shot("/tmp/ashen-ui-warning.png")
		quit()
		return
	menu.settings.select("Controls")
	await shot("/tmp/ashen-ui-controls.png")
	menu.settings.select("Camera")
	await shot("/tmp/ashen-ui-camera.png")
	menu.navigate("Test Grounds")
	await shot("/tmp/ashen-ui-tests.png")
	if "--lab" in OS.get_cmdline_user_args():
		menu.navigate("Practice")
		await shot("/tmp/ashen-ui-practice.png")
		menu.back()
	menu.navigate("Debug")
	await shot("/tmp/ashen-ui-debug.png")
	menu.set_debug(true)
	menu.close_menu()
	await shot("/tmp/ashen-ui-live.png")
	quit()
