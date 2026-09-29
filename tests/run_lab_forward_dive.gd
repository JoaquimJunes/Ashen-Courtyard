extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
var lab: Node3D
var p: CharacterBody3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("PASS " if ok else "FAIL ",message)
func settle(frames: int) -> void:
 for i in frames: await physics_frame
 await process_frame
func prepare(heading: float = 0) -> void:
 for action in ["forward","back","left","right","sprint"]: Input.action_release(action)
 p.reset_for_lab(Transform3D(Basis(Vector3.UP,heading),Vector3(0,0.02,4)))
 await settle(6)
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 check(p.actions.definition_for("dodge") == p.tuning.dodge_forward and not p.combat_enabled,"Laboratory uses the shared forward dive without combat")
 var original_rate := Engine.physics_ticks_per_second
 for rate in [30,60,120]:
  Engine.physics_ticks_per_second = rate
  await prepare()
  var start: Vector3 = p.position
  check((await ActionTest.start(p,"dodge")) and p.forward_dive.active,"Stationary dodge starts the forward trial at %s Hz" % rate)
  check(p.stamina == p.tuning.stamina_max-p.tuning.dodge_forward.stamina_cost,"Stamina charged once at %s Hz" % rate)
  var peak := 0.0
  var immune_ok := true
  var contact_ok := true
  var frames := 0
  var flight_time := -1.0
  while p.state == p.State.DODGE and frames < rate*3:
   await settle(1)
   frames += 1
   peak = maxf(peak,p.position.y-start.y)
   if p.forward_dive.active:
    if p.forward_dive.phase == 0 or p.forward_dive.since_launch >= 0.32: immune_ok = immune_ok and not p.invulnerable
    if p.forward_dive.phase == 2:
     contact_ok = contact_ok and p.is_on_floor()
     if flight_time < 0: flight_time = p.forward_dive.since_launch
  check(absf(peak-0.25) < 0.015,"New physical arc stays near 0.25 m at %s Hz (%.3f)" % [rate,peak])
  check(flight_time >= 0.24 and flight_time <= 0.28,"Airborne dive is shorter at %s Hz (%.3f s)" % [rate,flight_time])
  check(absf(start.z-p.position.z-5.5) < 0.06,"Forward travel stays near 5.5 m at %s Hz (%.3f)" % [rate,start.z-p.position.z])
  check(immune_ok and contact_ok,"Preparation has no immunity; roll requires floor at %s Hz" % rate)
  check(p.state == p.State.FREE and p.model.is_processing() and not p.forward_dive.active,"Normal animation resumes at %s Hz" % rate)
 Engine.physics_ticks_per_second = original_rate
 for heading in [PI/2,PI,-PI/2]:
  await prepare(heading)
  var start: Vector3 = p.position
  var direction := -p.global_basis.z
  (await ActionTest.start(p,"dodge"))
  await settle(75)
  check((p.position-start).dot(direction) > 4.2 and p.state == p.State.FREE,"Forward dive respects body heading %.0f degrees" % rad_to_deg(heading))
 for target_phase in [0,1,2]:
  await prepare()
  (await ActionTest.start(p,"dodge"))
  for i in 75:
   if p.forward_dive.phase == target_phase: break
   await settle(1)
  var at: Vector3 = p.position
  var timer: float = p.forward_dive.time
  paused = true
  await settle(6)
  check(p.position == at and p.forward_dive.time == timer,"Pause freezes phase %s" % target_phase)
  paused = false
  lab.reset_station()
  check(not p.forward_dive.active and p.forward_dive.pose == null and p.model.is_processing() and p.state == p.State.FREE and p.stamina == p.tuning.stamina_max,"Reset clears trial state in phase %s" % target_phase)
 # Wall and low-ceiling collision still use the real player capsule.
 await prepare()
 var wall := Shapes.solid(lab,Vector3(5,4,0.3),Vector3(0,2,2.8),Color.GRAY)
 await settle(2)
 (await ActionTest.start(p,"dodge"))
 await settle(75)
 check(p.position.z > 3.0 and p.state == p.State.FREE,"Solid wall blocks travel without storing propulsion")
 wall.queue_free()
 await settle(2)
 await prepare()
 var ceiling := Shapes.solid(lab,Vector3(8,0.3,10),Vector3(0,2.10,1),Color.GRAY)
 await settle(2)
 (await ActionTest.start(p,"dodge"))
 var early := false
 for i in 30:
  await settle(1)
  if p.forward_dive.active and p.forward_dive.phase == 2: early = early or p.forward_dive.since_launch < 0.30
 check(early,"Ceiling produces an earlier real landing")
 ceiling.queue_free()
 await prepare()
 (await ActionTest.start(p,"dodge"))
 p.position.y += 2.0
 await settle(2)
 check(not p.forward_dive.active and p.velocity.y <= 0,"Losing support during preparation cancels launch")
 await prepare()
 (await ActionTest.start(p,"dodge"))
 for i in 50:
  if p.forward_dive.phase == 2: break
  await settle(1)
 await settle(4)
 p.position.y += 2.0
 await settle(2)
 var roll_clock: float = p.forward_dive.roll_time
 await settle(5)
 check(p.forward_dive.active and p.forward_dive.phase == 1 and p.forward_dive.roll_time == roll_clock,"Leaving an edge pauses the grounded roll without launching again")
 await settle(90)
 check(p.state == p.State.FREE and p.model.is_processing(),"Landing again resumes the roll and returns animation control")
 await prepare()
 (await ActionTest.start(p,"dodge"))
 await settle(20)
 p._on_damaged()
 check(not p.forward_dive.active and p.forward_dive.pose == null and p.model.is_processing() and p.state == p.State.HURT,"Interruption clears trial ownership and cached poses")
 await prepare()
 (await ActionTest.start(p,"dodge"))
 for i in 75:
  if p.forward_dive.roll_time > 0.44: break
  await settle(1)
 p.buffered = "dodge"
 p.buffer_time = p.tuning.input_buffer
 var serial: int = p.serial
 await settle(10)
 check(p.serial == serial+1 and p.forward_dive.active and absf(p.stamina-(p.tuning.stamina_max-2*p.tuning.dodge_forward.stamina_cost+p.tuning.stamina_regen/Engine.physics_ticks_per_second)) < 0.001,"One buffered dodge begins after recovery and charges once (serial %s/%s, active %s, stamina %.2f)" % [p.serial,serial+1,p.forward_dive.active,p.stamina])
 await prepare()
 Input.action_press("left")
 (await ActionTest.start(p,"dodge"))
 Input.action_release("left")
 check(not p.forward_dive.active and p.actions.ground_roll.active and p.model.dodge_clip == "roll_left" and p.is_on_floor(),"Side dodge uses the referenced clip directly on the floor")
 await prepare()
 Input.action_press("forward")
 await settle(20)
 check((await ActionTest.start(p,"dodge")) and p.forward_dive.active,"Running forward enters the new trial")
 Input.action_release("forward")
 await settle(75)
 check(p.state == p.State.FREE and p.model.is_processing(),"Running entry recovers to normal movement")
 lab.reset_all()
 check(not p.forward_dive.active and p.rig.subject == p,"Entire-lab reset retains camera follow and clears the trial")
 var courtyard = load("res://scenes/player.tscn").instantiate()
 check(courtyard.tuning.dodge_forward == p.tuning.dodge_forward and courtyard.tuning.dodge_ground == p.tuning.dodge_ground,"Both worlds share the same directional dodge definitions")
 courtyard.free()
 print("LAB FORWARD DIVE: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
