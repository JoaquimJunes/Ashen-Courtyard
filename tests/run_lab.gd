extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
var lab: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, description: String) -> void:
 checks += 1
 if condition: print("PASS: "+description)
 else:
  failures += 1
  push_error("FAIL: "+description)
func settle(frames: int = 3) -> void:
 for frame in frames: await physics_frame
 await process_frame
func route_clear(points: Array) -> bool:
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.34
 capsule.height = 1.8
 for index in range(points.size()-1):
  var from: Vector3 = points[index]+Vector3.UP*0.95
  var motion: Vector3 = points[index+1]-points[index]
  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = capsule
  query.transform.origin = from
  query.motion = motion
  query.collision_mask = 1
  if lab.get_world_3d().direct_space_state.cast_motion(query)[0] < 0.999: return false
  for step in range(int(ceil(motion.length()))+1):
   var point: Vector3 = points[index].lerp(points[index+1],float(step)/maxf(1,ceil(motion.length())))
   var ground := PhysicsRayQueryParameters3D.create(point+Vector3.UP*0.2,point-Vector3.UP*0.4,1)
   if lab.get_world_3d().direct_space_state.intersect_ray(ground).is_empty(): return false
 return true
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 await settle(8)
 var p = lab.player
 check(lab.stations.size() == 9,"Nine reusable modules load, including the hub")
 check(not p.combat_enabled and p.target == null,"Lab character runs independently without a boss")
 check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/arena.tscn","Default Run Project scene remains the boss courtyard")
 for action in ["light","heavy","cast","heal"]:
  var before := Vector3(p.stamina,p.mana,p.flasks)
  check(not (await ActionTest.start(p,action)) and before == Vector3(p.stamina,p.mana,p.flasks),"Lab rejects %s without spending resources" % action)
  var event := InputEventAction.new()
  event.action = action
  event.pressed = true
  p._unhandled_input(event)
  check(p.buffered == "","Lab does not buffer combat input %s" % action)
 check(not p.take_damage(10,"lab_hit") and p.health == p.max_health,"Lab damage cannot trigger encounter-specific effects")
 check((await ActionTest.start(p,"dodge")),"Existing dodge remains available")
 lab.reset_station()
 check(p.state == p.State.FREE and not p.model.dodging,"Reset interrupts and clears a dodge")
 var paths := {
  0:[Vector3(0,0,10),Vector3.ZERO],
  1:[Vector3.ZERO,Vector3(0,0,19),Vector3(-44,0,19),Vector3(-44,0,24)],
  2:[Vector3.ZERO,Vector3(-22,0,0),Vector3(-26,0,0)],
  3:[Vector3.ZERO,Vector3(0,0,19),Vector3(0,0,24)],
  4:[Vector3.ZERO,Vector3(0,0,-19),Vector3(-44,0,-19),Vector3(-44,0,-24)],
  5:[Vector3.ZERO,Vector3(0,0,-19),Vector3(44,0,-19),Vector3(44,0,-24)],
  6:[Vector3.ZERO,Vector3(0,0,19),Vector3(44,0,19),Vector3(44,0,24)],
  7:[Vector3.ZERO,Vector3(22,0,0),Vector3(26,0,0)],
  8:[Vector3.ZERO,Vector3(0,0,-19),Vector3(0,0,-24)]}
 for id in 9:
  check(route_clear(paths[id]),"Walking route to station %02d has floor and full standing clearance" % id)
  lab.go_to_station(id)
  await settle(6)
  check(lab.active_station == id and p.is_on_floor(),"Station %02d spawn settles safely on the floor" % id)
  check(p.rig.follow_point.distance_to(p.global_position+Vector3.UP*float(CameraPreferences.values.height)) < 0.15,"Station %02d teleport resets camera follow" % id)
 # Check actual ramp faces and walk uphill with the unchanged controller.
 for index in 3:
  lab.go_to_station(1)
  var x := -57.0+index*6
  var query := PhysicsRayQueryParameters3D.create(Vector3(x,8,41),Vector3(x,-1,41),1)
  var hit: Dictionary = lab.get_world_3d().direct_space_state.intersect_ray(query)
  check(not hit.is_empty() and hit.normal.y > 0.85 and hit.position.y > 0.5,"Ramp %s has an upward-facing walkable collision surface" % index)
  p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(x,0.05,46)))
  Input.action_press("forward")
  await settle(105)
  Input.action_release("forward")
  check(p.position.y > 0.3 and p.position.z < 43 and p.is_on_floor(),"Existing character walks up ramp %s without new mechanics" % index)
 # Actual player walking across an aisle, rather than only teleporting.
 lab.go_to_station(0)
 p.position = Vector3(0,0,14)
 p.yaw = PI
 p.rig.reset_follow()
 Input.action_press("forward")
 await settle(180)
 Input.action_release("forward")
 check(lab.active_station == 3 and p.position.z > 22,"Walking enters and activates the crouching station")
 lab.go_to_station(6)
 var object: Node3D = lab.stations[6].reset_objects[0]
 var initial: Transform3D = object.transform
 object.position += Vector3(2,0,1)
 p.health = 15
 p.stamina = 3
 p.mana = 7
 p.flasks = 0
 p.buffered = "cast"
 p.received["old"] = true
 lab.reset_station()
 check(object.transform.is_equal_approx(initial),"Station reset restores displaced test objects")
 check(p.health == p.max_health and p.stamina == p.tuning.stamina_max and p.mana == p.tuning.mana_max and p.flasks == 3,"Station reset restores all player resources")
 check(p.buffered == "" and p.received.is_empty() and p.velocity.is_zero_approx(),"Station reset clears pending actions, damage history, and velocity")
 for station in [lab.stations[6],lab.stations[7]]:
  for item in station.reset_objects: item.position.y += 3
 lab.reset_all()
 var restored := true
 for station in [lab.stations[6],lab.stations[7]]:
  for i in station.reset_objects.size(): restored = restored and station.reset_objects[i].transform.is_equal_approx(station.initial_transforms[i])
 check(restored and lab.active_station == 0,"Entire-lab reset restores every object and returns to the hub")
 lab.go_to_station(5)
 p.position = Vector3(50,0.1,-34) # Deep section, beyond the 1.2 m wading shelf.
 await settle(45)
 check(p.swimming.active and p.position.distance_to(lab.stations[5].spawn.global_position) > 3,"Entering active water starts swimming without resetting the station")
 lab.go_to_station(2)
 p.position = Vector3(-57.25,0.01,-10.5)
 await settle(12)
 check(p.position.distance_to(lab.stations[2].spawn.global_position) < 0.3,"Falling into a jumping gap resets to its entrance")
 p.position.y = -10
 await settle()
 check(p.position.distance_to(lab.stations[2].spawn.global_position) < 0.3,"Out-of-bounds fall recovers the active station")
 for i in 5:
  lab.reset_station()
  await settle()
 check(lab.find_children("*","CharacterBody3D",true,false).size() == 1,"Repeated resets retain exactly one character")
 # The measured raised-gap rigs are the same scene used by the isolated tests.
 for index in 2:
  lab.go_to_station(2)
  var rig: Node3D = lab.stations[2].fixtures.get_node("AdaptiveDiveGap%d" % index)
  p.reset_for_lab(Transform3D(Basis.IDENTITY,rig.to_global(Vector3(0,0.02,3.9))))
  await settle(6)
  Input.action_press("forward")
  await settle(30)
  Input.action_release("forward")
  check(p.is_on_floor() and p.position.y > 0.59,"Raised-gap lane %s start deck is accessible by ordinary walking" % index)
  p.reset_for_lab(rig.get_node("DiveStart").global_transform)
  await settle(6)
  (await ActionTest.start(p,"dodge"))
  await settle(80)
  var local_end := rig.to_local(p.global_position)
  check(local_end.y > 0.99 and local_end.z < -1 and p.state == p.State.FREE,"Raised-gap lane %s completes a playable dive onto the 1 m platform" % index)
  p.reset_for_lab(Transform3D(Basis.IDENTITY,rig.to_global(Vector3(0,0.03,-rig.gap/2))))
  await settle(12)
  check(p.position.distance_to(lab.stations[2].spawn.global_position) < 0.3,"Raised-gap lane %s catch floor resets to station entrance" % index)
 lab.hud.toggle_pause()
 var position: Vector3 = p.position
 await settle()
 check(paused and lab.hud.panel.visible and p.position.is_equal_approx(position),"Lab menu pauses the character")
 lab.hud.menu.navigate("Settings")
 lab.hud.menu.settings.select("Camera")
 lab.hud.options.widgets.fov.value = 76
 lab.hud.options.save_path = "user://lab-camera-test.cfg"
 lab.hud.options.save()
 await settle()
 check(paused and is_equal_approx(p.camera.fov,76),"Shared camera options preview while the lab is paused")
 lab.hud.menu.back()
 lab.hud.toggle_pause()
 check(not paused,"Lab menu resumes the character")
 var diagnostics := InputEventKey.new()
 diagnostics.physical_keycode = KEY_F3
 diagnostics.pressed = true
 Input.parse_input_event(diagnostics)
 var diagnostics_release := diagnostics.duplicate() as InputEventKey
 diagnostics_release.pressed = false
 Input.parse_input_event(diagnostics_release)
 await settle(1)
 check(lab.hud.menu.live_panel.visible,"F3 toggles live diagnostics")
 var retro := InputEventKey.new()
 retro.physical_keycode = KEY_F4
 retro.pressed = true
 var previous: bool = PSXStyle.enabled
 lab.get_node("RetroEffects")._unhandled_input(retro)
 check(PSXStyle.enabled != previous,"F4 toggles the lab's PS1 screen effects")
 lab.get_node("RetroEffects")._unhandled_input(retro)
 # Real camera collision, on both shoulders, against a wall and low ceiling.
 for side in [-1,1]:
  CameraPreferences.set_value("side",side)
  lab.go_to_station(4)
  p.position = Vector3(-57,0,-42)
  p.yaw = PI
  p.rig.reset_follow()
  await settle(20)
  check(p.arm.get_hit_length() < p.arm.spring_length,"Climbing wall retracts camera on shoulder %s" % side)
  lab.go_to_station(3)
  p.position = Vector3(0,0,29.5)
  p.yaw = 0
  p.pitch = 0.2
  p.rig.reset_follow()
  await settle(20)
  check(p.arm.get_hit_length() < p.arm.spring_length,"Crouch tunnel retracts camera on shoulder %s" % side)
 lab.hud.toggle_pause()
 lab.return_to_courtyard()
 await settle()
 check(not paused and current_scene.scene_file_path == "res://scenes/arena.tscn" and current_scene.player.combat_enabled and is_instance_valid(current_scene.boss),"Return to courtyard restores the normal combat encounter")
 print("LAB RESULT: %s checks, %s failures" % [checks,failures])
 current_scene.queue_free()
 await process_frame
 await process_frame
 quit(1 if failures else 0)
