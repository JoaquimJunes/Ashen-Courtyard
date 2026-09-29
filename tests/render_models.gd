extends SceneTree
## Visual QA for the two GLB assets. Writes a front and rear view to /tmp.
var stage: Node3D
var models: Array[Node3D] = []
var camera: Camera3D

func _initialize() -> void:
 call_deferred("render_models")

func render_models() -> void:
 stage = Node3D.new()
 root.add_child(stage)
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("17232e")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("b4c6dc")
 env.ambient_light_energy = 0.55
 world.environment = env
 stage.add_child(world)
 var key := DirectionalLight3D.new()
 key.rotation_degrees = Vector3(-40,-35,0)
 key.light_energy = 1.3
 key.shadow_enabled = true
 stage.add_child(key)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(-15,140,0)
 fill.light_color = Color("80bccc")
 fill.light_energy = 0.65
 stage.add_child(fill)
 Shapes.box(stage,Vector3(20,0.1,20),Vector3(0,-0.07,0),Color("263540"))
 for which in ["psx_knight","psx_warden"]:
  var model := load("res://scenes/models/%s.tscn" % which).instantiate() as Node3D
  stage.add_child(model)
  model.position.x = 1.35 if which == "psx_knight" else -1.10
  model.rotation.y = -0.45
  models.append(model)
 camera = Camera3D.new()
 stage.add_child(camera)
 camera.position = Vector3(0.2,2.6,-7.5)
 camera.look_at(Vector3(0,1.40,0))
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 5.7
 camera.current = true
 var ui := CanvasLayer.new()
 stage.add_child(ui)
 var heading := Label.new()
 heading.text = "ASHEN COURTYARD / CHARACTER MODELS"
 heading.position = Vector2(40,28)
 heading.add_theme_font_size_override("font_size",24)
 heading.modulate = Color("e1c390")
 ui.add_child(heading)
 for i in range(2):
  var title := Label.new()
  title.text = "AZURE KNIGHT  /  TEXTURED PSX" if i == 0 else "CINDER WARDEN  /  TEXTURED PSX"
  title.position = Vector2(125 if i == 0 else 730,665)
  title.add_theme_font_size_override("font_size",18)
  ui.add_child(title)
 for frame in range(6): await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/ashen-knights-front.png")
 for model in models: model.rotation.y += PI
 for frame in range(6): await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/ashen-knights-back.png")
 quit()
