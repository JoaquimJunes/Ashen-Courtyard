extends SceneTree
var failures := 0
var checks := 0
var arena: Node3D
const TEST_PATH := "user://camera_settings_test.cfg"

func _initialize() -> void:
 call_deferred("run")

func check(condition: bool, description: String) -> void:
 checks += 1
 if condition: print("PASS: " + description)
 else:
  failures += 1
  push_error("FAIL: " + description)

func settle(frames: int = 60) -> void:
 for frame in frames: await physics_frame
 # Physics-frame signals precede node updates; inspect after those finish.
 await process_frame

func run() -> void:
 CameraPreferences.loaded = true
 CameraPreferences.reset()
 arena = load("res://scenes/arena.tscn").instantiate()
 root.add_child(arena)
 current_scene = arena
 var p = arena.player
 p.set_physics_process(false)
 arena.boss.set_physics_process(false)
 await settle()
 check(p.camera.global_position.x > p.position.x+0.5, "Right shoulder places the camera beside the character")
 CameraPreferences.set_value("side",-1)
 await settle()
 check(p.camera.global_position.x < p.position.x-0.5, "Left shoulder changes composition without turning the character")
 CameraPreferences.set_value("fov",500)
 CameraPreferences.set_value("distance",-5)
 check(CameraPreferences.values.fov == 95 and CameraPreferences.values.distance == 2, "Invalid camera ranges are clamped")
 CameraPreferences.set_value("fov",NAN)
 check(CameraPreferences.values.fov == 95, "Non-finite camera values are rejected")
 CameraPreferences.reset()
 p.position = Vector3.ZERO
 p.rig.reset_follow()
 var start: Vector3 = p.rig.follow_point
 p.position.x += 1.0
 p.rig.update_follow(1.0/60)
 check(p.rig.follow_point.x > start.x and p.rig.follow_point.x < p.position.x, "Follow eases toward movement rather than snapping")
 CameraPreferences.set_value("smoothing",0)
 p.rig.update_follow(1.0/60)
 check(is_equal_approx(p.rig.follow_point.x,p.position.x), "Zero smoothing provides immediate follow")
 # Real sphere collision sweeps at every wall and corner, on both shoulders.
 CameraPreferences.set_value("offset",1.2)
 CameraPreferences.set_value("distance",6)
 for side in [-1,1]:
  CameraPreferences.set_value("side",side)
  for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,
    Vector3(1,0,1),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(-1,0,-1)]:
   p.position = direction*12.4
   p.yaw = atan2(direction.x,direction.z)
   p.rig.reset_follow()
   await settle(5)
   var position: Vector3 = p.camera.global_position
   check(absf(position.x) < 13.8 and absf(position.z) < 13.8,
    "Camera stays inside boundary %s on shoulder %s" % [direction,side])
  # Face parallel to the wall so the shoulder pivot itself collides.
  p.position = Vector3(12.9*side,0,3)
  p.yaw = 0
  p.rig.reset_follow()
  await settle(5)
  check(absf(p.rig.global_position.x) < 13.8, "Sideways shoulder sweep prevents wall clipping (%s)" % side)
 CameraPreferences.reset()
 p.position = Vector3(0,0,4)
 p.yaw = 0
 p.locked = true
 p.rig.reset_follow()
 await settle()
 var aim: Vector3 = arena.boss.global_position+Vector3.UP*1.3
 check((-p.camera.global_basis.z).dot((aim-p.camera.global_position).normalized()) > 0.999, "Lock-on centers the target with an offset camera")
 p.target = null
 p._physics_process(0.016)
 await settle()
 check(not p.locked and p.camera.basis.is_equal_approx(Basis.IDENTITY), "Losing a target returns smoothly to free look")
 p.target = arena.boss
 arena.hud.toggle_pause()
 arena.hud.open_camera_options()
 var options = arena.hud.camera_options
 options.save_path = TEST_PATH
 options.widgets.fov.value = 80
 options.widgets.side.select(1)
 options.widgets.side.item_selected.emit(1)
 options.widgets.invert_y.button_pressed = true
 await settle()
 check(paused and options.is_visible_in_tree() and arena.hud.overlay.visible, "Camera options remain inside the paused encounter")
 check(not is_equal_approx(p.camera.fov,80), "Unapplied camera draft does not alter gameplay")
 options.save()
 await settle(30)
 check(is_equal_approx(p.camera.fov,80) and p.camera.global_position.x < p.position.x, "Apply updates the paused camera without closing the editor")
 options.close()
 check(paused and arena.hud.overlay.visible and not options.visible, "Back returns to pause, without resuming")
 CameraPreferences.reset()
 CameraPreferences.load_settings(TEST_PATH)
 check(CameraPreferences.values.fov == 80 and CameraPreferences.values.side == -1 and CameraPreferences.values.invert_y,
  "Saved options survive a fresh configuration load")
 arena.hud.toggle_pause()
 var mouse := InputEventMouseMotion.new()
 mouse.relative = Vector2(10,10)
 p.pitch = 0
 p.yaw = 0
 CameraPreferences.set_value("sensitivity",2)
 p.apply_mouse_look(mouse.relative)
 check(p.pitch > 0 and is_equal_approx(p.yaw,-0.06), "Sensitivity and inverted mouse look affect free camera input")
 arena.hud.restart()
 await settle(5)
 arena = current_scene
 check(CameraPreferences.values.fov == 80 and is_equal_approx(arena.player.camera.fov,80), "Encounter retry retains camera preferences")
 arena.player.set_physics_process(false)
 arena.boss.set_physics_process(false)
 arena.player.take_damage(1000,"camera_death")
 arena.hud.open_camera_options()
 arena.hud.camera_options.save_path = TEST_PATH
 var escape := InputEventKey.new()
 escape.physical_keycode = KEY_ESCAPE
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 Input.parse_input_event(escape)
 var release := escape.duplicate() as InputEventKey
 release.pressed = false
 Input.parse_input_event(release)
 await settle(1)
 check(arena.finished and arena.hud.overlay.visible and not arena.hud.resume.visible and not arena.hud.camera_options.is_visible_in_tree(), "Options close correctly from the death screen")
 CameraPreferences.reset()
 DirAccess.remove_absolute(TEST_PATH)
 print("CAMERA RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
