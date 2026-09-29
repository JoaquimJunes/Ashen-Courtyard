extends SceneTree
## Native capture of the real player and action; no separate preview physics.
var actor: CharacterBody3D
var title: Label
var detail: Label
var stage: Node3D
var camera: Camera3D
var elapsed := 0.0
func _initialize() -> void: run.call_deferred()

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(960,540)
	root.content_scale_size = Vector2i(960,540)
	OS.low_processor_usage_mode = false
	root.scaling_3d_scale = 1.0
	RenderingServer.global_shader_parameter_set("psx_enabled",false)
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("18242e")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.45
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	stage.add_child(light)
	Shapes.solid(stage,Vector3(80,0.2,80),Vector3(0,-0.1,0),Color("28333c"))
	for i in range(-12,13):
		for line: MeshInstance3D in [Shapes.box(stage,Vector3(26,0.005,0.018),Vector3(0,0.015,i),Color("8496a0")),Shapes.box(stage,Vector3(0.018,0.005,26),Vector3(i,0.015,0),Color("8496a0"))]:
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			line.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	actor = load("res://scenes/player.tscn").instantiate()
	actor.controller.manual = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor.model.set_process(false)
	actor.rig.set_physics_process(false)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	camera.far = 100
	camera.current = true
	var ui := CanvasLayer.new()
	stage.add_child(ui)
	for y in [0,465]:
		var panel := ColorRect.new()
		panel.position = Vector2(0,y)
		panel.size = Vector2(960,75)
		panel.color = Color("18242e")
		ui.add_child(panel)
	title = Label.new()
	title.position = Vector2(28,22)
	title.add_theme_font_size_override("font_size",24)
	ui.add_child(title)
	detail = Label.new()
	detail.position = Vector2(28,478)
	detail.add_theme_font_size_override("font_size",19)
	ui.add_child(detail)
	var wall := Shapes.solid(stage,Vector3(4,1.5,2),Vector3(0,0.75,-1),Color("62737d"))
	var blocked := "--blocked" in OS.get_cmdline_user_args()
	var shimmy := "--shimmy" in OS.get_cmdline_user_args()
	var inside := "--inside" in OS.get_cmdline_user_args()
	if inside: Shapes.solid(stage,Vector3(1,1.5,4),Vector3(2.5,0.75,1),Color("62737d"))
	if blocked: Shapes.solid(stage,Vector3(4,0.2,1.9),Vector3(0,2.8,-1),Color("bc9376"))
	var directory := "/tmp/ledge-blocked-frames" if blocked else "/tmp/ledge-frames"
	if shimmy: directory = "/tmp/shimmy-inside-frames" if inside else "/tmp/shimmy-outside-frames"
	DirAccess.make_dir_recursive_absolute(directory)
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.04,0.5)))
	actor.model.set_process(true)
	actor.set_physics_process(true)
	for i in 8: await physics_frame
	elapsed = 0
	actor.simulation_stepped.connect(func(delta: float): elapsed += delta)
	actor.controller.intent.movement = Vector3.FORWARD
	actor.request_action(&"jump")
	var metadata: Array[Dictionary] = []
	var hanging_at := -1.0
	var done_at := -1.0
	camera.position = Vector3(4,2.7,3.5)
	camera.look_at(Vector3(0,1.4,-0.3))
	camera.size = 4.8
	title.text = "LOW CEILING > HANG > LET GO" if blocked else "JUMP > LEDGE HANG > PULL-UP / 1.5 m WALL"
	if shimmy: title.text = "HANG > SIDEWAYS > " + ("INSIDE CORNER" if inside else "OUTSIDE CORNER")
	for frame in 600:
		var status: StringName = actor.traversal.status
		if status == &"hang":
			if hanging_at < 0: hanging_at = elapsed
			if elapsed-hanging_at >= 0.8:
				actor.controller.intent.surface_motion = Vector2(1,0) if shimmy else Vector2(0,1)
			if shimmy and absf(actor.traversal.candidate.normal.x)>0.999 and done_at < 0:
				done_at = elapsed
			if shimmy and done_at >= 0: actor.controller.intent.surface_motion = Vector2.ZERO
			if blocked and elapsed-hanging_at >= 1.5:
				actor.request_action(&"dodge")
				actor.controller.intent.movement = Vector3.ZERO
				actor.controller.intent.surface_motion = Vector2.ZERO
		if blocked and hanging_at >= 0 and not actor.traversal.attached() and actor.is_on_floor() and done_at < 0: done_at = elapsed
		if actor.traversal.reason == &"completed" and done_at < 0:
			done_at = elapsed
			actor.controller.intent.movement = Vector3.ZERO
			actor.controller.intent.surface_motion = Vector2.ZERO
		var phase: int = actor.traversal.mantle.phase
		if shimmy:
			camera.position = actor.position+Vector3(-4 if inside else 4,2.7,3.5)
			camera.look_at(actor.position+Vector3(0,0.95,-0.3))
		detail.text = "%.2f s | %s | Stamina %.1f | %s\nActual character physics; Forward pulls up, Dodge releases" % [elapsed,status,actor.stamina,actor.traversal.reason]
		await capture(directory+"/%03d.png" % frame)
		metadata.append({"frame":frame,"time":elapsed,"status":status,"phase":phase,"stamina":actor.stamina,"position":actor.position,"tucked":actor.motor.tucked,"reason":actor.traversal.reason,"normal":actor.traversal.candidate.normal if actor.traversal.candidate!=null else Vector3.ZERO})
		if done_at >= 0 and elapsed-done_at > 0.5: break
	var file := FileAccess.open(directory+"/metadata.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"  "))
	stage.queue_free()
	await process_frame
	quit()
