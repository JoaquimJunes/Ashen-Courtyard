extends SceneTree
var checks := 0
var failures := 0
var lab: Node3D
var p: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if ok: print("PASS: ",message)
 else:
  failures += 1
  push_error("FAIL: "+message)
func settle(frames: int) -> void:
 for i in frames: await physics_frame
 await process_frame
func release_movement() -> void:
 for action in ["forward","back","left","right","sprint"]: Input.action_release(action)
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 for index in 3:
  var degrees := float([10,20,30][index])
  var center_x := -57.0+index*6.0
  for side in [-1.0,1.0]:
   for height in [0.3,0.6,0.61,0.75]:
    for mode in ["walk","sprint"]:
     release_movement()
     var start := Vector3(center_x+side*3.3,0.05,45.0-height/tan(deg_to_rad(degrees)))
     p.reset_for_lab(Transform3D(Basis.IDENTITY,start))
     await settle(8)
     Input.action_press("right" if side < 0 else "left")
     if mode == "sprint": Input.action_press("sprint")
     var landed := false
     var max_speed := 0.0
     for frame in 45:
      await settle(1)
      var on_tread: bool = absf(p.position.x-center_x) < 1.1 and p.position.y > height-0.05
      landed = landed or (on_tread and p.is_on_floor())
      max_speed = maxf(max_speed,Vector2(p.velocity.x,p.velocity.z).length())
     var label := "%s, %s degree ramp, side %s, %.2f m lip" % [mode,degrees,side,height]
     check(landed == (height <= 0.6),label+": height limit / landing (position %s)" % p.position)
     check(max_speed <= (6.5 if mode == "sprint" else 4.0)+0.02,label+": no horizontal boost")
 # Grounded diagonal step-up remains separate from the new airborne dodge.
 for index in 3:
  var degrees := float([10,20,30][index])
  var center_x := -57.0+index*6.0
  for side in [-1.0,1.0]:
   for along in [-1.0,1.0]:
    release_movement()
    var direction := Vector3(-side,0,along).normalized()
    var edge := Vector3(center_x+side*1.5,0.05,45.0-0.45/tan(deg_to_rad(degrees)))
    p.reset_for_lab(Transform3D(Basis.IDENTITY,edge-direction*1.8))
    await settle(8)
    Input.action_press("right" if side < 0 else "left")
    Input.action_press("forward" if along < 0 else "back")
    var landed := false
    for frame in 60:
     await settle(1)
     landed = landed or (absf(p.position.x-center_x) < 1.1 and p.position.y > 0.05 and p.is_on_floor())
    check(landed,"Oblique walk, %s degree ramp, side %s, along %s" % [degrees,side,along])
 release_movement()
 var ceiling := Shapes.solid(lab,Vector3(4,0.2,4),Vector3(-45,2.2,45.0-0.6/tan(deg_to_rad(30.0))),Color.GRAY)
 p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(-48.3,0.05,ceiling.position.z)))
 await settle(8)
 Input.action_press("right")
 await settle(45)
 check(p.position.x < -46.5 and p.position.y < 0.1,"Ramp ceiling blocks walking without partial lift")
 release_movement()
 ceiling.queue_free()
 lab.reset_station()
 check(p.velocity.is_zero_approx() and p.position.y < 0.1 and not p.invulnerable,"Ramp reset restores grounded spawn")
 print("RAMP STEPS RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
