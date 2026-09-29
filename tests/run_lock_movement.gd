extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var arena: Node3D
var p: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if ok: print("PASS: ",message)
 else:
  failures += 1
  push_error("FAIL: "+message)
func settle(frames: int = 30) -> void:
 for i in frames: await physics_frame
 await process_frame
func reset_player() -> void:
 p.controller.manual = false
 p.controller.intent = Intent.new()
 arena.boss.dead = false
 arena.boss.position = Vector3(0,0,-5)
 p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.05,6)))
 p.target = arena.boss
 p.combat_enabled = true
 p.locked = true
func target_alignment() -> float:
 var offset: Vector3 = arena.boss.global_position-p.global_position
 return (-p.global_basis.z).dot(Vector3(offset.x,0,offset.z).normalized())
func travel_alignment() -> float:
 return (-p.global_basis.z).dot(Vector3(p.velocity.x,0,p.velocity.z).normalized())
func run() -> void:
 CameraPreferences.loaded = true
 CameraPreferences.reset()
 arena = load("res://scenes/arena.tscn").instantiate()
 root.add_child(arena)
 current_scene = arena
 p = arena.player
 arena.boss.set_physics_process(false)
 arena.boss.position = Vector3(0,0,-5)
 for side in [-1,1]:
  CameraPreferences.set_value("side",side)
  for action in ["left","right","back","forward"]:
   reset_player()
   await settle(10)
   Input.action_press(action)
   await settle(36)
   var aim: Vector3 = arena.boss.global_position+Vector3.UP*1.3
   check(target_alignment() > 0.99,"%s / shoulder %s: walking faces the locked target" % [action,side])
   check((-p.camera.global_basis.z).dot((aim-p.camera.global_position).normalized()) > 0.995,"%s / shoulder %s: camera keeps the enemy targeted" % [action,side])
   Input.action_release(action)
   if action == "back":
    await settle(30)
    check(target_alignment() > 0.99,"Braking and idle keep facing the enemy")
    var facing := p.rotation.y
    var lock := InputEventAction.new()
    lock.action = "lock"
    lock.pressed = true
    p._unhandled_input(lock)
    check(not p.locked and absf(angle_difference(facing,p.rotation.y)) < 0.01,"Unlocking does not snap the character's body")
   reset_player()
   await settle(10)
   Input.action_press(action)
   Input.action_press("sprint")
   await settle(40)
   check(p.sprinting and travel_alignment() > 0.94,"%s / shoulder %s: running faces travel" % [action,side])
   aim = arena.boss.global_position+Vector3.UP*1.3
   check((-p.camera.global_basis.z).dot((aim-p.camera.global_position).normalized()) > 0.995,"Running retains camera lock")
   Input.action_release("sprint")
   var running_heading: float = p.rotation.y
   await settle(1)
   check(absf(angle_difference(running_heading,p.rotation.y)) < deg_to_rad(40),"Returning to target-facing does not snap")
   await settle(40)
   check(target_alignment() > 0.99,"Releasing sprint restores target-facing while walking")
   Input.action_release(action)
 reset_player()
 await settle(10)
 arena.boss.position.x = 6
 var before_turn: float = p.rotation.y
 await settle(1)
 check(absf(angle_difference(before_turn,p.rotation.y)) < deg_to_rad(25) and target_alignment() < 0.99,"Moving target initiates a smooth turn")
 await settle(60)
 check(target_alignment() > 0.99,"Idle follows the moving target")
 Input.action_press("sprint")
 p.rotation.y = PI/2
 await settle(60)
 check(not p.sprinting and target_alignment() > 0.99,"Sprint held without movement still faces the enemy")
 Input.action_release("sprint")
 reset_player()
 await settle(10)
 Input.action_press("forward")
 Input.action_press("sprint")
 await settle(3)
 check(p.model.gait_speed > 0 and p.model.gait_speed < p.tuning.sprint_speed-0.5,"Stride cadence eases into sprinting")
 await settle(40)
 check(p.model.gait_speed > 5.5,"Cadence reaches running speed without changing movement speed")
 Input.action_release("forward")
 Input.action_release("sprint")
 reset_player()
 await settle(5)
 p.rotation.y = PI
 check((await ActionTest.start(p,"light")) and (-p.global_basis.z).dot((arena.boss.position-p.position).normalized()) > 0.99,"Locked sword attack still faces the enemy")
 reset_player()
 await settle(5)
 p.rotation.y = PI/2
 check((await ActionTest.start(p,"cast")) and (-p.global_basis.z).dot((arena.boss.position-p.position).normalized()) > 0.99,"Locked casting faces the enemy independently of camera smoothing")
 reset_player()
 await settle(5)
 p.rotation.y = PI/2
 var facing := p.rotation.y
 p.target = null
 await settle(80)
 check(not p.locked and absf(angle_difference(facing,p.rotation.y)) < 0.01,"Losing the target releases the camera without rotating the body")
 check(p.camera.quaternion.angle_to(Quaternion.IDENTITY) < deg_to_rad(0.1),"Camera returns within 0.1 degrees of free look after losing the target")
 # Scripted intent uses the same rule as keyboard input, at each physics rate.
 var original_rate := Engine.physics_ticks_per_second
 for rate in [30,60,120]:
  Engine.physics_ticks_per_second = rate
  reset_player()
  await settle(5)
  var intent := Intent.new()
  intent.movement = Vector3.RIGHT
  intent.facing = Vector3.FORWARD
  intent.sprint = true
  p.submit_intent(intent)
  p.stamina = 0
  p.resources.stamina_wait = 10
  await settle(rate)
  check(not p.sprinting and travel_alignment() > 0.99,"%s Hz: exhausted running request overrides target and explicit intent facing" % rate)
  intent.sprint = false
  await settle(rate)
  check(target_alignment() > 0.99,"%s Hz: releasing exhausted running request restores target-facing" % rate)
 Engine.physics_ticks_per_second = original_rate
 reset_player()
 await settle(5)
 p.rotation.y = PI/2
 arena.boss.global_position = p.global_position+Vector3.UP*5
 var overlap_heading: float = p.rotation.y
 var overlap_intent := Intent.new()
 overlap_intent.movement = Vector3.RIGHT
 p.submit_intent(overlap_intent)
 await settle(1)
 check(absf(angle_difference(overlap_heading,p.rotation.y)) < 0.01,"Horizontal target overlap retains heading despite movement input")
 reset_player()
 await settle(5)
 p.rotation.y = PI/2
 arena.boss.dead = true
 await settle(5)
 check(not p.locked and absf(angle_difference(PI/2,p.rotation.y)) < 0.01,"Target death releases lock without snapping")
 Input.action_press("back")
 await settle(45)
 check(travel_alignment() > 0.94,"Target death restores ordinary movement-facing")
 Input.action_release("back")
 reset_player()
 await settle(5)
 p.locked = false
 Input.action_press("right")
 await settle(45)
 check(travel_alignment() > 0.94,"Assigned enemy without lock does not override movement-facing")
 Input.action_release("right")
 reset_player()
 await settle(5)
 var air_intent := Intent.new()
 p.submit_intent(air_intent)
 p.motor.teleport(Transform3D(Basis(Vector3.UP,PI/2),Vector3(0,12,6)))
 await settle(20)
 check(not p.is_on_floor() and target_alignment() > 0.95,"Free airborne movement tracks the target")
 air_intent.movement = Vector3.RIGHT
 air_intent.sprint = true
 p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,12,6)))
 await settle(20)
 check(not p.is_on_floor() and not p.sprinting and travel_alignment() > 0.95,"Airborne running intent faces travel without enabling sprint speed")
 reset_player()
 await settle(5)
 var dodge_intent := Intent.new()
 dodge_intent.movement = Vector3.RIGHT
 p.submit_intent(dodge_intent)
 check(await ActionTest.start(p,"dodge"),"Locked sideways dodge starts")
 var dodge_heading: float = p.rotation.y
 arena.boss.position.x = -8
 await settle(10)
 check(p.state != p.State.FREE and absf(angle_difference(dodge_heading,p.rotation.y)) < 0.01,"Committed dodge keeps its facing when the target moves")
 print("LOCK MOVEMENT RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
