extends SceneTree
func _initialize() -> void: run.call_deferred()
func capture(path: String) -> void:
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(path)
func run() -> void:
 var lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 lab.player.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.03,4)))
 for i in 15: await physics_frame
 lab.hud.toggle_pause()
 await capture("/tmp/lab-forward-menu.png")
 lab.hud.toggle_pause()
 lab.player.begin("dodge")
 for i in 9: await physics_frame
 paused = true
 await capture("/tmp/lab-forward-lean.png")
 paused = false
 for i in 15: await physics_frame
 paused = true
 await capture("/tmp/lab-forward-dive.png")
 paused = false
 quit()
