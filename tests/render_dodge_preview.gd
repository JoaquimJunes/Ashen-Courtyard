extends SceneTree
## Record actual character ticks. Never simulate a separate preview controller.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var raised := OS.get_cmdline_user_args().has("--raised-gap")
	var directory := "/tmp/dive-clearance-frames" if raised else "/tmp/dodge-preview-frames"
	var preview = load("res://scenes/dive_clearance_preview.tscn" if raised else "res://scenes/dodge_preview.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	# Freeze in the start callback so a slow render cannot skip preparation ticks.
	preview.body.actions.started.connect(func(_id: StringName): preview.playing = false,CONNECT_ONE_SHOT)
	while preview.waiting_for_floor:
		await physics_frame
		await process_frame
	preview.playing = false
	DirAccess.make_dir_recursive_absolute(directory)
	var metadata: Array[Dictionary] = []
	for frame in 76:
		if frame > 0 and preview.phase != preview.Phase.FINISHED:
			preview.step_frame()
			await physics_frame
			await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/%03d.png" % frame)
		metadata.append({"frame":frame,"time":preview.elapsed,"phase":preview.phase,"travel":preview.start_transform.origin.z-preview.body.position.z,"rise":preview.body.position.y,"grounded":preview.body.is_on_floor()})
	var file := FileAccess.open(directory+"/metadata.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"  "))
	file.close()
	print("Preview frames: %s | landing %.4f s, total %.4f s, distance %.4f m" % [directory,preview.landing_time,preview.elapsed,preview.start_transform.origin.z-preview.body.position.z])
	preview.queue_free()
	await process_frame
	quit()
