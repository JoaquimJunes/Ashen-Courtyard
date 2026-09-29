extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
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
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 for i in 4:
  var gap: float = [0.5,1.0,2.0,3.0][i]
  var height := 0.5+i*0.25
  var z := -10.5+i*7.0
  # Walk up the new access stairs using ordinary movement, then reset for a
  # repeatable takeoff near the cliff edge (no independent jump ability).
  p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(-63.3,0.05,z)))
  await settle(8)
  Input.action_press("right")
  await settle(70)
  Input.action_release("right")
  check(p.position.y >= height-0.02 and p.position.x > -60.5,"Walking access to %.1f m gap takeoff platform" % gap)
  p.reset_for_lab(Transform3D(Basis(Vector3.UP,-PI/2),Vector3(-57.95,height+0.05,z)))
  await settle(8)
  var resets: int = lab.reset_count
  Input.action_press("forward")
  check((await ActionTest.start(p,"dodge")),"Adaptive forward dive toward %.1f m laboratory gap" % gap)
  Input.action_release("forward")
  var landed := false
  for frame in 45:
   await settle(1)
   landed = landed or (p.is_on_floor() and p.position.x > -57.5+gap and p.position.y >= height-0.02)
  if gap < 3.0:
   check(landed,"Land across %.1f m actual gap" % gap)
   check(lab.reset_count == resets,"Clear the gap without triggering its catch/reset area")
  else:
   # The current low dive cannot span this lane from a 0.45 m setback.
   # Removing the higher legacy arc must not introduce an invisible landing.
   check(not landed,"3 m gap from 0.45 m setback exceeds the shallow dive's airborne reach")
   check(lab.reset_count > resets,"An unreachable gap falls to the catch area and resets safely")
 for index in 3:
  var degrees := float([10,20,30][index])
  var center_x := -57.0+index*6.0
  for side in [-1.0,1.0]:
   p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(center_x+side*3.2,0.05,45.0-0.4/tan(deg_to_rad(degrees)))))
   await settle(8)
   Input.action_press("right" if side < 0 else "left")
   (await ActionTest.start(p,"dodge"))
   Input.action_release("right")
   Input.action_release("left")
   await settle(42)
   check(p.is_on_floor() and absf(p.position.x-center_x) < 1.5 and p.position.y > 0.35,"Physical roll lands on %s degree ramp from side %s" % [degrees,side])
 lab.reset_station()
 check(p.velocity.is_zero_approx() and p.stamina == p.tuning.stamina_max and not p.model.dodging,"Station reset clears the directional roll")
 print("DODGE LAB RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
