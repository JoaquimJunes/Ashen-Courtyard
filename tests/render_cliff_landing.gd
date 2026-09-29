extends SceneTree
## Native capture of the real player and action; no separate preview physics.
var actor: CharacterBody3D
var title: Label
var detail: Label
var stage: Node3D
var camera: Camera3D
var stepped := false
func _initialize() -> void: run.call_deferred()

func step_once() -> void:
	stepped = false
	actor.set_physics_process(true)
	while not stepped:
		await physics_frame
		await process_frame
	if not actor.forward_dive.active: actor.model.update_pose(1.0/60.0)

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
	Shapes.solid(stage,Vector3(35,0.2,35),Vector3(0,-0.1,0),Color("28333c"))
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
	actor.simulation_stepped.connect(func(_delta: float):
		stepped = true
		actor.set_physics_process(false)
		actor.model.set_process(false))
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
	Shapes.solid(stage,Vector3(4,8,4),Vector3(0,4,2),Color("62737d"))
	for kind: String in ["timed", "timed_close"]:
		var directory := "/tmp/cliff-landing-frames/"+kind
		DirAccess.make_dir_recursive_absolute(directory)
		actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,8.02,0.5)))
		actor.model.set_process(false)
		for i in 6: await step_once()
		camera.position = Vector3(18,10,3)
		camera.look_at(Vector3(0,3.7,-4.5))
		camera.size = 14.5
		title.text = "CLIFF DIVE / FORWARD MOTION UNTIL CONTACT" if kind == "cliff" else "TIMED LANDING / FORWARD ROLL / HALF FALL DAMAGE"
		var pressed := false
		var metadata: Array[Dictionary] = []
		for frame in 126:
			if frame == 1: actor.request_action(&"dodge")
			if kind != "cliff" and not pressed and not actor.is_on_floor() and actor.velocity.y < 0:
				var g: float = actor.forward_dive.gravity_value()
				var v: float = -actor.velocity.y
				if (sqrt(v*v+2*g*maxf(0,actor.position.y))-v)/g <= 0.10:
					actor.request_action(&"dodge")
					pressed = true
			await step_once()
			# Automatic model processing is enabled again when dive ownership ends;
			# capture sampling still advances presentation exactly once per physics tick.
			actor.model.set_process(false)
			if kind == "timed_close":
				camera.size = 4.8
				var center: Vector3 = actor.position+Vector3.UP*1.0
				camera.position = center+Vector3(7,2,-3)
				camera.look_at(center)
			detail.text = "%.2f s | Forward %.2f m/s | Height %.2f m | %s\nStamina %.0f | Fall damage %.1f | %s" % [frame/60.0,-actor.velocity.z,actor.position.y,actor.State.keys()[actor.state],actor.stamina,actor.landing.last_damage,"TIMING SUCCESS" if actor.landing.roll_succeeded else ("Dodge pressed" if pressed else "No landing input")]
			await capture(directory+"/%03d.png" % frame)
			metadata.append({"frame":frame,"position":actor.position,"state":actor.state,"timed":actor.landing.roll_succeeded,"height":actor.landing.last_height,"damage":actor.landing.last_damage,"stamina":actor.stamina,"armor_clearance":actor.model.dodge_skin_min_height()})
		var file := FileAccess.open(directory+"/metadata.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(metadata,"  "))
	stage.queue_free()
	await process_frame
	quit()
