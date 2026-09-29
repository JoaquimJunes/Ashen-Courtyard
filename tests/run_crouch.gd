extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var world: Node3D
var p: CharacterBody3D
var input := Intent.new()
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if ok: print("PASS: ",message)
 else:
  failures += 1
  push_error("FAIL: "+message)
func settle(frames: int = 20) -> void:
 for i in frames: await physics_frame
 await process_frame
func reset_at(height: float = 0.05) -> void:
 input = Intent.new()
 p.submit_intent(input)
 p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,height,6)))
 await settle()
func box(size: Vector3, at: Vector3) -> StaticBody3D:
 return Shapes.solid(world,size,at,Color.GRAY)
func run() -> void:
 world = load("res://scenes/arena.tscn").instantiate()
 root.add_child(world)
 current_scene = world
 world.boss.set_physics_process(false)
 p = world.player
 world.boss.position = Vector3(0,0,-8)
 var original_rate := Engine.physics_ticks_per_second
 for rate in [30,60,120]:
  Engine.physics_ticks_per_second = rate
  await reset_at()
  check(await ActionTest.start(p,"crouch"),"%s Hz: crouch accepted through action lifecycle" % rate)
  await settle(rate)
  check(p.posture.crouched and p.motor.persistent_posture and is_equal_approx(p.motor.capsule.height,0.96),"%s Hz: lowered collider persists without automatic stand" % rate)
  check(p.state == p.State.FREE and p.actions.active_definition == null,"Crouch releases action slot")
  check(is_equal_approx(p.stamina,p.tuning.stamina_max),"Crouch costs no stamina")
  p.target = world.boss
  p.locked = true
  input.movement = Vector3.RIGHT
  await settle(rate)
  check(absf(Vector2(p.velocity.x,p.velocity.z).length()-2.0) < 0.05,"%s Hz: crouch speed is 2m/s" % rate)
  var toward: Vector3 = (world.boss.position-p.position).normalized()
  check((-p.global_basis.z).dot(toward) > 0.98,"Crouching faces locked target")
  input.movement = Vector3(1,0,1).normalized()
  await settle(rate/2)
  check(absf(Vector2(p.velocity.x,p.velocity.z).length()-2.0) < 0.05,"Diagonal crouch has no speed bonus")
  input.movement = Vector3.ZERO
  await settle(rate/2)
  var ceiling := box(Vector3(4,0.2,4),p.position+Vector3.UP*1.6)
  await settle()
  check(not (await ActionTest.start(p,"crouch")) and p.posture.crouched,"Blocked standing leaves crouch active")
  p.health = p.max_health-10
  for action in ["light","heavy","cast","heal","jump","dodge"]:
   var before := Vector3(p.stamina,p.mana,p.flasks)
   var result = await ActionTest.result(p,action)
   check(not result.accepted and result.reason == &"standing_blocked" and before == Vector3(p.stamina,p.mana,p.flasks),"%s blocked before resource spending" % action)
  input.sprint = true
  input.movement = Vector3.FORWARD
  await settle(3)
  check(p.posture.crouched and not p.sprinting and is_equal_approx(p.stamina,p.tuning.stamina_max),"Blocked sprint stays crouched without stamina drain")
  input.sprint = false
  input.movement = Vector3.ZERO
  ceiling.queue_free()
  await settle(rate/2)
  check(p.posture.crouched,"Removing ceiling does not retry a discarded stand request")
  check(await ActionTest.start(p,"crouch"),"Fresh press stands when clear")
  check(not p.posture.crouched and not p.motor.persistent_posture and is_equal_approx(p.motor.capsule.height,1.8),"Standing restores original capsule")
  for action in ["light","heavy","cast","heal","jump","dodge"]:
   await reset_at()
   p.health = p.max_health-10
   check(await ActionTest.start(p,"crouch"),"Prepare crouch for "+action)
   check((await ActionTest.start(p,action)) and not p.posture.crouched,"%s stands before action starts" % action)
  await reset_at()
  await ActionTest.start(p,"crouch")
  input.sprint = true
  input.movement = Vector3.RIGHT
  await settle(rate/2)
  check(not p.posture.crouched and p.sprinting,"Sprint exits crouch when clear")
  await reset_at()
  await ActionTest.start(p,"crouch")
  p.stamina = 0
  p.resources.stamina_wait = 10
  check(not (await ActionTest.start(p,"jump")) and p.posture.crouched,"Unaffordable action preserves crouch")
  p.stamina = 40
  p.resources.stamina_wait = 0
  await settle(rate/2)
  check(p.stamina > 40,"Grounded crouching permits stamina regeneration")
  var time: float = p.presentation.crouch.clock
  paused = true
  for i in 5: await process_frame
  check(is_equal_approx(time,p.presentation.crouch.clock),"Pause freezes crouch playback")
  paused = false
  await reset_at()
  for height in [2.0,4.0]:
   var platform := box(Vector3(4,0.2,4),Vector3(0,height-0.1,6))
   await reset_at(height+0.03)
   check(await ActionTest.start(p,"crouch"),"Crouch on elevated platform")
   platform.queue_free()
   await settle(4)
   check(p.motor.is_airborne() and p.posture.crouched,"Departure retains crouched posture")
   for i in rate*3:
    await physics_frame
    if p.is_on_floor() and p.landing.last_height > 0.5: break
   await process_frame
   check(p.landing.last_height > height-0.3,"Impact measurement includes crouched fall")
   check(p.posture.crouched if height == 2.0 else not p.posture.crouched,"Soft fall returns crouched; heavy fall restores standing when clear")
   check(p.state == p.State.LAND if height == 4.0 else p.state == p.State.FREE,"Existing landing commitment preserved")
   await reset_at()
  await ActionTest.start(p,"crouch")
  p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.05,6)))
  check(not p.posture.crouched and not p.motor.persistent_posture and p.actions.active_definition == null,"Reset clears posture and action ownership")
 # Two instances share read-only tuning without sharing posture or collider state.
 var other: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
 other.controller.manual = true
 world.add_child(other)
 other.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(6,0.05,6)))
 await reset_at()
 await ActionTest.start(p,"crouch")
 await settle(30)
 check(p.posture.definition == other.posture.definition and not other.posture.crouched and is_equal_approx(other.motor.capsule.height,1.8),"Shared definition preserves instance-local stance and collision")
 other.queue_free()
 # A descending hit must hand over to the existing ragdoll system.
 var perch := box(Vector3(4,0.2,4),Vector3(0,2.9,6))
 await reset_at(3.03)
 await ActionTest.start(p,"crouch")
 await settle(30)
 perch.queue_free()
 await settle(12)
 check(p.take_damage(5,"crouch_fall_hit") and p.reactions.active,"Descending crouched hit enters ragdoll")
 check(not p.posture.crouched and not p.motor.persistent_posture,"Ragdoll releases persistent crouch ownership")
 for i in Engine.physics_ticks_per_second*8:
  await physics_frame
  if not p.reactions.active: break
 await process_frame
 check(not p.reactions.active and p.state == p.State.FREE and is_equal_approx(p.motor.capsule.height,1.8),"Surviving crouched fall recovers standing")
 await reset_at()
 await ActionTest.start(p,"crouch")
 check(p.take_damage(1,"crouch_ground_hit") and p.posture.crouched and p.state == p.State.HURT,"Grounded damage keeps safe crouch collider during hurt")
 check(not (await ActionTest.start(p,"crouch")),"Hurt commitment rejects posture changes")
 await reset_at()
 Engine.physics_ticks_per_second = original_rate
 # New C binding must not replace a custom action already using C.
 var config := ConfigFile.new()
 for action in GameInput.DEFAULTS:
  if action != "crouch": config.set_value("bindings",action,KEY_C if action == "heal" else GameInput.DEFAULTS[action])
 config.save("user://crouch-migration.cfg")
 GameInput.load_settings("user://crouch-migration.cfg")
 check(GameInput.bindings.heal == KEY_C and GameInput.bindings.crouch != KEY_C and GameInput.valid(GameInput.bindings),"New binding preserves existing C assignment")
 world.queue_free()
 await settle()
 world = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(world)
 current_scene = world
 p = world.player
 input = Intent.new()
 p.submit_intent(input)
 await settle()
 check(await ActionTest.start(p,"crouch"),"Test Grounds uses same crouch implementation without combat")
 check(not (await ActionTest.start(p,"light")) and p.posture.crouched,"Disabled lab combat leaves stance unchanged")
 for i in 3:
  world.reset_station()
  await settle()
  check(not p.posture.crouched and not p.motor.persistent_posture,"Repeated lab reset restores standing")
  await ActionTest.start(p,"crouch")
 # Walk into authored tunnels using real input, with both shoulder cameras.
 world.go_to_station(3)
 var station: Node3D = world.stations[3]
 for shoulder in [-1,1]:
  CameraPreferences.set_value("side",shoulder)
  input = Intent.new()
  p.submit_intent(input)
  p.reset_for_lab(Transform3D(Basis.IDENTITY,station.global_position+Vector3(12,0.05,6.5)))
  await settle()
  await ActionTest.start(p,"crouch")
  await settle(20)
  input.movement = Vector3.FORWARD
  await settle(120)
  input.movement = Vector3.ZERO
  await settle(20)
  check(p.position.z-station.position.z < 3.0,"Shoulder %s: real movement enters 1.5m tunnel" % shoulder)
  check(not (await ActionTest.start(p,"crouch")),"Tunnel blocks standing")
  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = SphereShape3D.new()
  query.shape.radius = 0.08
  query.collision_mask = 1
  for camera_height in [1.2,1.65,2.2]:
   CameraPreferences.set_value("height",camera_height)
   await settle(30)
   query.transform.origin = p.camera.global_position
   check(p.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"Shoulder %s / height %.2f: camera remains clear of tunnel geometry" % [shoulder,camera_height])
  input.movement = Vector3.BACK
  await settle(100)
  input.movement = Vector3.ZERO
  await settle(20)
  check(p.posture.crouched and (await ActionTest.start(p,"crouch")),"Walk out still crouched, then stand with fresh press")
 for tunnel in [-12.0,0.0]:
  p.reset_for_lab(Transform3D(Basis.IDENTITY,station.global_position+Vector3(tunnel,0.05,6.5)))
  await settle()
  await ActionTest.start(p,"crouch")
  await settle(20)
  input.movement = Vector3.FORWARD
  await settle(120)
  input.movement = Vector3.ZERO
  check(p.position.z-station.position.z < 3.0,"Crouch clears 1.2m and exact 1m with contact margin (x=%s, z=%s)" % [tunnel,p.position.z-station.position.z])
 print("CROUCH RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
