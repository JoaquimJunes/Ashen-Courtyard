extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if ok: print("PASS: ",message)
 else:
  failures += 1
  push_error(message)
func tick() -> void:
 await physics_frame
 await process_frame
func run() -> void:
 CameraPreferences.loaded = true
 CameraPreferences.reset()
 change_scene_to_file("res://scenes/arena.tscn")
 for i in 8: await tick()
 var p = current_scene.player
 current_scene.boss.frozen = true
 p.controller.manual = true
 for i in 8: await tick()
 p.set_physics_process(false)
 p.rig.set_physics_process(false)
 for hz in [30,60,120]:
  Engine.physics_ticks_per_second = hz
  var delta: float = 1.0/hz
  for side in [-1,1]:
   CameraPreferences.set_value("side",side)
   for smoothing in [0.0,0.12,0.35]:
    CameraPreferences.set_value("smoothing",smoothing)
    for direction in [-1,1]:
     p.position = Vector3(0,0.02,4)
     p.yaw = 0.0
     p.pitch = 0.65
     p.rig.reset_follow()
     var reversals := 0
     var max_step := 0.0
     var lowest := INF
     for i in hz:
      var before: float = p.rig.rotation.y
      p.apply_mouse_look(Vector2(-direction*deg_to_rad(1800)*delta/0.003,-10))
      p.rig.update_follow(delta)
      var step := angle_difference(before,p.rig.rotation.y)
      if step*direction < -0.00001: reversals += 1
      max_step = maxf(max_step,absf(step))
      await tick()
      lowest = minf(lowest,p.camera.global_position.y)
     var label := "%d Hz / shoulder %d / smoothing %.2f / direction %d" % [hz,side,smoothing,direction]
     check(reversals == 0 and max_step <= deg_to_rad(1800)*delta+0.001,"Fast grounded orbit never reverses or snaps: "+label)
     check(lowest > 0.05,"Ground collision stays solid during fast orbit: "+label)
     for i in int(hz*3): p.rig.update_follow(delta)
     check(absf(angle_difference(p.rig.rotation.y,p.yaw)) < 0.01,"Camera catches up after stopping input: "+label)
 # Fast orbit alongside a solid perimeter wall, with normal ground collision.
 CameraPreferences.reset()
 p.position = Vector3(12.6,0.02,3)
 p.yaw = 0
 p.pitch = 0.65
 p.rig.reset_follow()
 var safe := true
 for i in 120:
  p.apply_mouse_look(Vector2(100,0))
  p.rig.update_follow(1.0/120)
  await tick()
  safe = safe and absf(p.camera.global_position.x) < 13.8 and p.camera.global_position.y > 0.05
 check(safe,"Rapid orbit keeps wall and ground collision")
 Engine.physics_ticks_per_second = 60
 CameraPreferences.reset()
 print("FAST CAMERA RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
