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
	actor.model.update_pose(1.0/60.0)

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
	for kind: String in ["hit_recovery","lethal_landing"]:
		var directory := "/tmp/ragdoll-frames/"+kind
		DirAccess.make_dir_recursive_absolute(directory)
		actor.set_physics_process(false)
		actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,3 if kind == "hit_recovery" else 16,0)))
		actor.model.set_process(true)
		camera.position = Vector3(4,3,-9)
		camera.look_at(Vector3(0,1.0,0))
		camera.size = 6.0
		camera.current = true
		title.text = "DESCENDING HIT / RAGDOLL / AUTOMATIC GET-UP" if kind == "hit_recovery" else "LETHAL LANDING / PHYSICAL RAGDOLL"
		actor.set_physics_process(true)
		var hit := false
		for frame in 270:
			if kind == "hit_recovery" and not hit and actor.velocity.y < -1.0:
				actor.take_damage(5,"review_hit")
				hit = true
			var status := "falling"
			if actor.reactions.active: status = "dead ragdoll" if actor.dead else ("getting up" if actor.reactions.getting_up else "physical ragdoll")
			elif actor.is_on_floor(): status = "control restored"
			detail.text = "Health %.0f | %s | physical bodies %d" % [actor.health,status,10 if actor.reactions.active and not actor.reactions.getting_up else 0]
			await capture(directory+"/%03d.png" % frame)
	stage.queue_free()
	await process_frame
	quit()
