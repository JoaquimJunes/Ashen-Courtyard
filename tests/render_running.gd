extends SceneTree
var lab: Node3D
var p: CharacterBody3D
var camera: Camera3D
func _initialize() -> void: run.call_deferred()
func settle(frames: int) -> void:
 for i in frames: await physics_frame
 await process_frame
func capture(label: String) -> void:
 camera.global_position = p.global_position+Vector3(4,1.8,2)
 camera.look_at(p.global_position+Vector3.UP*0.9)
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/run-"+label+".png")
 print(label," position ",p.position," pitch ",rad_to_deg(p.model.locomotion.pitch)," bank ",rad_to_deg(p.model.locomotion.bank)," clip ",p.model.animation.current_animation, " feet ",p.model.locomotion.contacts)
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 lab.hud.hide()
 PSXStyle.enabled = false
 RenderingServer.global_shader_parameter_set("psx_enabled",false)
 camera = Camera3D.new()
 lab.add_child(camera)
 camera.fov = 45
 camera.current = true
 for mode in ["jog","sprint"]:
  lab.go_to_station(0)
  await settle(4)
  Input.action_press("forward")
  if mode == "sprint": Input.action_press("sprint")
  await settle(45)
  await capture(mode)
  Input.action_release("forward")
  Input.action_release("sprint")
 for index in 3:
  lab.go_to_station(1)
  p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(-57+index*6,0.05,46)))
  await settle(4)
  Input.action_press("forward")
  Input.action_press("sprint")
  await settle(60)
  await capture("ramp-%d" % [10+index*10])
  Input.action_release("forward")
  Input.action_release("sprint")
 lab.go_to_station(0)
 await settle(4)
 Input.action_press("forward")
 Input.action_press("sprint")
 await settle(30)
 Input.action_release("forward")
 Input.action_press("left")
 await settle(5)
 await capture("left-turn")
 Input.action_release("left")
 Input.action_press("right")
 await settle(9)
 await capture("right-turn")
 Input.action_release("right")
 Input.action_release("sprint")
 quit()
