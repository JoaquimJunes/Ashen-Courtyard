extends SceneTree
## Pose review using the production sampler. Synthetic lying starts; no preview physics.
var actor: CharacterBody3D
var title: Label
var detail: Label
var stage: Node3D
var camera: Camera3D
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
	var metadata: Array[Dictionary] = []
	for kind: String in ["face_down","face_up"]:
		var directory := "/tmp/get-up-frames/"+kind
		DirAccess.make_dir_recursive_absolute(directory)
		actor.reset_for_lab(Transform3D.IDENTITY)
		actor.model.set_process(false)
		actor.model.animation.play("k_idle")
		actor.model.animation.seek(0,true)
		actor.model.animation.advance(0)
		var skeleton: Skeleton3D = actor.model.skeleton
		skeleton.force_update_all_bone_transforms()
		var body := skeleton.find_bone("Body")
		var pivot: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(body)).origin
		var tilt := Basis(Vector3.RIGHT,PI/2 if kind == "face_up" else -PI/2)
		var lying := Transform3D(tilt,Vector3(0,0.32,0)-tilt*pivot)
		var world_poses: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			world_poses.append(lying*skeleton.global_transform*skeleton.get_bone_global_pose(bone))
		actor.presentation.get_up.begin(world_poses,StringName(kind))
		camera.position = Vector3(-3.8,2.2,-5)
		camera.look_at(Vector3(0,0.8,0))
		camera.size = 3.3
		title.text = "%s / SUPPORTED GET-UP / 1.20 s" % kind.to_upper().replace("_"," ")
		for frame in 73:
			var progress := float(frame)/72
			actor.presentation.get_up.sample(progress)
			var hand: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Hand.l"))).origin
			var foot: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Foot.l"))).origin
			var pelvis: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(body)).origin
			detail.text = "%.2f s | Settle > hand plant > kneel > rise
Authored pose preview; gameplay body stays fixed" % (progress*1.2)
			await capture(directory+"/%03d.png" % frame)
			metadata.append({"variant":kind,"frame":frame,"time":progress*1.2,"progress":progress,"pelvis":pelvis,"hand":hand,"foot":foot,"mesh_min":actor.model.dodge_skin_min_height()})
		actor.presentation.get_up.reset()
	var file := FileAccess.open("/tmp/get-up-frames/metadata.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"  "))
	stage.queue_free()
	await process_frame
	quit()
