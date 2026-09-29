extends SceneTree
## Native review of the new laboratory controls and real combat fixture.
func _initialize() -> void: run.call_deferred()
func tick(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
func capture(name: String) -> void:
	var previous := paused
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/movement-01/"+name+".png")
	paused = previous
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/movement-01")
	var lab = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	lab.player.controller.manual = true
	await tick(10)
	lab.hud.menu.open_menu("Test Grounds")
	await capture("directory")
	assert(lab.hud.panel.get_global_rect().end.y <= root.size.y,"Directory must fit in the viewport")
	lab.hud.menu.navigate("Practice")
	await capture("practice-menu")
	assert(lab.hud.menu.panel.get_global_rect().end.y <= root.size.y,"Practice menu must fit in the viewport")
	lab.hud.practice_options.mode_selector.select(1)
	lab.hud.practice_options.start_hub()
	await tick(35)
	lab.player.targeting.toggle()
	await tick(20)
	await capture("stationary-target")
	lab.set_practice_mode(2)
	await tick(25)
	lab.hud.diagnostics_enabled = true
	await capture("timed-attack-diagnostics")
	lab.set_practice_mode(1)
	lab.player.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(5,0.02,5)))
	await tick(8)
	lab.player.request_action(&"dodge")
	var captured := false
	for i in 60:
		await tick(1)
		if lab.player.forward_dive.active and lab.player.forward_dive.phase == 1 and lab.player.forward_dive.time >= 0.08 and not lab.player.is_on_floor():
			await capture("dive-diagnostics")
			captured = true
			break
	assert(captured,"Actual dive must enter its airborne phase")
	lab.queue_free()
	await process_frame
	print("MOVEMENT REVIEW: five native captures under docs/movement-01")
	quit()
