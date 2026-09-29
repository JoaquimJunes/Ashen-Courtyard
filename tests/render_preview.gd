extends SceneTree
var scene: Node3D
var frames := 0
func _initialize() -> void:
 call_deferred("start")
func start() -> void:
 scene = load("res://scenes/arena.tscn").instantiate()
 root.add_child(scene)
 current_scene = scene
 scene.boss.frozen = true
func _process(_delta: float) -> bool:
 frames += 1
 if frames == 30:
  capture.call_deferred()
 return false
func capture() -> void:
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/ashen-courtyard-preview.png")
 scene.hud.toggle_pause()
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/ashen-courtyard-pause.png")
 scene.hud.open_camera_options()
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/ashen-camera-options.png")
 scene.hud.menu.navigate("Credits")
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/ashen-courtyard-credits.png")
 quit()
