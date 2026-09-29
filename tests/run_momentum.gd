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
func reset_player() -> void:
 for action in ["forward","back","left","right","sprint"]: Input.action_release(action)
 lab.go_to_station(0)
 await settle(4)
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 await reset_player()
 Input.action_press("forward")
 await settle(60)
 var jog_pitch: float = p.model.locomotion.pitch
 check(p.move_velocity.length() > 3.9,"Jog accelerates to its existing top speed")
 Input.action_press("sprint")
 await settle(45)
 check(p.move_velocity.length() > 6.4 and p.move_velocity.length() < 6.51,"Sprint accelerates to 6.5 m/s without overshoot")
 check(p.model.locomotion.pitch < jog_pitch-0.04,"Forward lean increases with actual running speed")
 Input.action_release("forward")
 var stop_start := p.position
 await settle(3)
 check(p.move_velocity.length() > 0.5 and p.move_velocity.length() < 6.4,"Releasing movement decelerates instead of stopping instantly")
 await settle(24)
 check(p.move_velocity.is_zero_approx() and Vector2(p.velocity.x,p.velocity.z).length() < 0.01,"Braking reaches a complete stop")
 check(p.position.distance_to(stop_start) < 1.3,"Sprint stopping distance remains controlled")
 await settle(45)
 check(absf(p.model.locomotion.pitch) < 0.01,"Speed-based lean settles upright after stopping")
 await reset_player()
 Input.action_press("forward")
 Input.action_press("sprint")
 await settle(45)
 Input.action_release("forward")
 Input.action_press("back")
 await settle(3)
 check(p.turn_braking and p.move_velocity.length() < 6.3,"180-degree reversal brakes first")
 check(p.move_velocity.normalized().dot(Vector3.FORWARD) > 0.999,"Sharp-turn braking retains the approach direction before cutting")
 await settle(40)
 check(p.move_velocity.normalized().dot(Vector3.BACK) > 0.99 and p.move_velocity.length() > 6.0,"After braking, the knight turns and accelerates into the new direction")
 check((-p.global_basis.z).dot(p.move_velocity.normalized()) > 0.95,"Body facing follows the new travel direction")
 # A gentle S-turn should preserve flow and receive the requested 15% lean boost.
 await reset_player()
 Input.action_press("forward")
 Input.action_press("sprint")
 await settle(40)
 p.yaw = 0.55
 await settle(25)
 p.yaw = -0.55
 var boost := 1.0
 for i in 45:
  await settle(1)
  boost = maxf(boost,p.model.locomotion.s_turn_boost)
 check(is_equal_approx(boost,1.15),"Reversing into an S-turn applies a 15% lean multiplier")
 check(absf(p.model.locomotion.bank) <= deg_to_rad(14*1.15),"Enhanced S-turn lean remains bounded")
 lab.reset_station()
 check(p.move_velocity.is_zero_approx() and not p.turn_braking and p.model.locomotion.s_turn_time == 0,"Reset clears momentum, braking, and S-turn history")
 await reset_player()
 Input.action_press("forward")
 Input.action_press("sprint")
 await settle(35)
 check((await ActionTest.start(p,"dodge")),"Dodge can interrupt running immediately")
 await settle(3)
 check(p.state == p.State.DODGE and p.move_velocity.is_zero_approx(),"Dodge travel does not inherit running momentum")
 # Real camera-relative input: diagonal changes must not shorten the velocity.
 await reset_player()
 Input.action_press("forward")
 Input.action_press("sprint")
 await settle(45)
 var slowest := INF
 var fastest := 0.0
 for side in ["right","left","right"]:
  Input.action_press(side)
  for i in 18:
   await settle(1)
   var speed := Vector2(p.get_real_velocity().x,p.get_real_velocity().z).length()
   slowest = minf(slowest,speed)
   fastest = maxf(fastest,speed)
  Input.action_release(side)
 check(slowest > 6.45,"Diagonal transitions and repeated S-turns retain full sprint speed (min %.3f)" % slowest)
 check(fastest < 6.55,"Diagonal input never increases speed above straight running")
 await settle(10)
 check(p.move_velocity.distance_to(Vector3.FORWARD*6.5) < 0.01,"Returning from diagonal to forward keeps full speed")
 # Check that the same brake/accelerate controls remain consistent across frame rates.
 await reset_player()
 p.set_physics_process(false)
 for fps in [30,60,120]:
  p.move_velocity = Vector3.ZERO
  for i in fps: p.update_ground_movement(Vector3.FORWARD,6.5,1.0/fps)
  var previous: float = p.move_velocity.length()
  p.update_ground_movement(Vector3.BACK,6.5,1.0/fps)
  check(p.turn_braking and p.move_velocity.length() < previous,"%d Hz reversal braking reduces speed" % fps)
  for i in fps: p.update_ground_movement(Vector3.BACK,6.5,1.0/fps)
  check(p.move_velocity.distance_to(Vector3.BACK*6.5) < 0.01,"%d Hz acceleration reaches the same new velocity" % fps)
  for i in fps: p.update_ground_movement(Vector3.ZERO,6.5,1.0/fps)
  check(p.move_velocity.is_zero_approx(),"%d Hz braking settles without drift" % fps)
  for top_speed in [4.0,6.5]:
   p.move_velocity = Vector3.FORWARD*top_speed
   var consistent := true
   for direction in [Vector3(1,0,-1),Vector3(-1,0,-1),Vector3.RIGHT,Vector3.FORWARD]:
    for i in fps/4:
     p.update_ground_movement(direction,top_speed,1.0/fps)
     consistent = consistent and absf(p.move_velocity.length()-top_speed) < 0.001 and not p.turn_braking
   check(consistent,"%d Hz turns maintain %.1f m/s independently of heading" % [fps,top_speed])
 for degrees in [90.0,135.0,179.0,179.99,180.0]:
  p.move_velocity = Vector3.FORWARD*6.5
  var direction := Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(degrees))
  p.update_ground_movement(direction,6.5,1.0/60.0)
  check(p.turn_braking == (degrees >= 180.0),"%.2f-degree turn respects the inclusive 180-degree braking threshold" % degrees)
 print("MOMENTUM RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
