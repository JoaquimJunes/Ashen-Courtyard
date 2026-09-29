extends SceneTree
var stage: Node3D
var models: Array[Node3D] = []
var title: Label
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 root.size = Vector2i(1280,500)
 RenderingServer.global_shader_parameter_set("psx_enabled",false)
 stage = Node3D.new()
 root.add_child(stage)
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("18242e")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color.WHITE
 env.ambient_light_energy = 0.65
 world.environment = env
 stage.add_child(world)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-45,-30,0)
 light.light_energy = 1.4
 light.shadow_enabled = true
 stage.add_child(light)
 Shapes.box(stage,Vector3(25,0.1,8),Vector3(0,-0.055,0),Color("354957"))
 var camera := Camera3D.new()
 stage.add_child(camera)
 camera.position = Vector3(0,3.0,-12)
 camera.look_at(Vector3(0,0.85,0))
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.keep_aspect = Camera3D.KEEP_WIDTH
 camera.size = 12
 camera.current = true
 var ui := CanvasLayer.new()
 stage.add_child(ui)
 title = Label.new()
 title.position = Vector2(30,22)
 title.add_theme_font_size_override("font_size",23)
 ui.add_child(title)
 for i in 6:
  var model = load("res://scenes/models/psx_knight.tscn").instantiate()
  stage.add_child(model)
  model.position.x = (2.5-i)*1.95
  model.set_process(false)
  models.append(model)
  var label := Label.new()
  label.position = Vector2(100+i*205,445)
  label.text = "%d%%" % (i*20)
  label.add_theme_font_size_override("font_size",18)
  ui.add_child(label)
 for clip in ["roll_forward","roll_left","roll_right","roll_back"]:
  title.text = "QUATERNIUS → KNIGHT / "+clip.to_upper()+" / POSE CHECK"
  for i in models.size():
   models[i].dodging = true
   models[i].dodge_clip = clip
   models[i].dodge_progress = i*0.2
   models[i].update_pose(0)
  for frame in 3: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("/tmp/ashen-"+clip+".png")
 quit()
