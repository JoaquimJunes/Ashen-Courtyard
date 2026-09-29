extends SceneTree
var lab: Node3D
func _initialize() -> void: call_deferred("run")
func capture(path: String) -> void:
 for i in 6: await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(path)
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 for i in 25: await physics_frame
 await capture("/tmp/ashen-lab-hub.png")
 lab.hud.toggle_pause()
 await capture("/tmp/ashen-lab-menu.png")
 lab.hud.toggle_pause()
 lab.player.set_physics_process(false)
 lab.player.hide()
 lab.hud.hide()
 var view := Camera3D.new()
 lab.add_child(view)
 view.current = true
 view.position = Vector3(110,145,135)
 view.look_at(Vector3(0,2,0))
 view.projection = Camera3D.PROJECTION_ORTHOGONAL
 view.size = 155
 view.far = 500
 RenderingServer.global_shader_parameter_set("psx_enabled",false)
 await capture("/tmp/ashen-lab-overview.png")
 for id in range(1,9):
  var station: Node3D = lab.stations[id]
  view.position = station.position+Vector3(27,27,32)
  view.look_at(station.position+Vector3(0,3,0))
  view.size = 39
  await capture("/tmp/ashen-lab-station-%02d.png" % id)
 quit()
