extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")

var failures := 0
var checks := 0
var arena: Node3D

func _initialize() -> void:
 call_deferred("run")

func check(condition: bool, description: String) -> void:
 checks += 1
 if not condition:
  failures += 1
  push_error("FAIL: " + description)
 else: print("PASS: " + description)

func spawn_arena() -> void:
 arena = load("res://scenes/arena.tscn").instantiate()
 root.add_child(arena)
 current_scene = arena
 arena.player.set_physics_process(false)
 arena.boss.set_physics_process(false)
 await physics_frame

func run() -> void:
 await spawn_arena()
 var p = arena.player
 var b = arena.boss
 var skin_mesh: MeshInstance3D = p.model.contact_meshes[0]
 var skin_bounds: AABB = skin_mesh.get_aabb()
 check(skin_bounds.position.x < -0.4 and skin_bounds.end.x > 0.4, "Imported body contains both mirrored halves")
 check(p.model.animation.has_animation("k_walk") and p.model.rig.bone(p.model.skeleton,"Hand.r") >= 0, "Imported walk animation and hand rig are available")
 if p.model.equipment != null:
  var equipment = p.model.equipment
  check(equipment.items.has(&"sword") and equipment.current_sockets.get(&"sword") == &"right_hand" and equipment.items[&"sword"].visual.get_parent() == equipment.socket_frame(&"right_hand"), "Sword is attached to the configured right-hand socket")
 else:
  check(p.model.hand_attachment.get_child_count() > 0, "Legacy sword is attached to the imported hand bone")
 var toggle := InputEventKey.new()
 toggle.physical_keycode = KEY_F4
 toggle.pressed = true
 arena.get_node("RetroEffects")._unhandled_input(toggle)
 check(not PSXStyle.enabled and not paused, "F4 disables retro effects without pausing combat")
 arena.get_node("RetroEffects")._unhandled_input(toggle)
 check(PSXStyle.enabled, "F4 restores retro effects")
 check(p.health == 100 and p.flasks == 3, "Fresh player health and flasks")
 check(p.stamina == 100 and p.mana == 100, "Fresh stamina and mana")
 check(b.take_damage(10,"same"), "First strike accepted")
 check(not b.take_damage(10,"same") and b.health == b.max_health-10, "Repeated strike cannot double-hit")
 check(b.take_damage(10,"next"), "Next strike can damage")
 p.invulnerable = true
 check(not p.take_damage(10,"dodge_hit"), "Invulnerability rejects damage")
 p.invulnerable = false
 check(p.take_damage(10,"dodge_hit"), "Expired invulnerability allows damage")
 p.state = p.State.FREE
 p.stamina = 5
 check(not (await ActionTest.start(p,"heavy")) and p.stamina == 5, "Unaffordable action does not spend stamina")
 p.stamina = 100
 check((await ActionTest.start(p,"heavy")) and p.stamina == 64, "Heavy attack spends its cost once")
 check(not (await ActionTest.start(p,"dodge")) and p.stamina == 64, "Committed attack cannot be cancelled by dodge")
 p.position = Vector3(0,0,0)
 p.rotation = Vector3.ZERO
 b.position = Vector3(0,0,-2)
 var before: float = b.health
 p.timer = 0
 p._physics_process(0.1)
 check(b.health == before, "Windup does not deal damage")
 p.timer = p.tuning.heavy_windup
 p._physics_process(0.01)
 p._physics_process(0.01)
 check(b.health == before-p.tuning.heavy_damage, "Active window deals exactly one hit")
 p.timer = p.tuning.heavy_windup+p.tuning.heavy_active+0.01
 p._physics_process(0.01)
 check(b.health == before-p.tuning.heavy_damage, "Recovery does not deal damage")
 p.state = p.State.FREE
 p.stamina = 100
 p.controller.manual = true
 p.controller.intent.movement = p.global_basis.z
 (await ActionTest.start(p,"dodge"))
 p.controller.intent.movement = Vector3.ZERO
 p._physics_process(0.1)
 check(p.invulnerable, "Dodge enters invulnerability window")
 p.timer = p.tuning.dodge_ground.immunity_end
 p._physics_process(0.01)
 check(not p.invulnerable, "Dodge leaves invulnerability window")
 p.timer = 1.1
 p.position.y = 0
 p.velocity = Vector3(0,-1,0)
 p.move_and_slide()
 p.dodge_phase = p.DodgePhase.GROUND_ROLL
 p.dodge_ground_time = p.actions.active_definition.ground_duration
 p._physics_process(0.01)
 check(p.state == p.State.FREE, "Dodge ends in free movement")
 p.mana = 0
 check(not (await ActionTest.start(p,"cast")) and p.mana == 0, "Spell cannot start without mana")
 p.mana = 100
 p.selected_spell = 0
 check((await ActionTest.start(p,"cast")) and p.mana == 76, "Spell spends mana at start")
 p.take_damage(1,"interrupt")
 p._physics_process(0.5)
 check(projectile_count() == 0 and p.mana == 76, "Interrupted cast produces no projectile or refund")
 p.state = p.State.FREE
 (await ActionTest.start(p,"cast"))
 p.timer = p.tuning.bolt_windup
 p._physics_process(0.01)
 p._physics_process(0.01)
 check(projectile_count() == 1, "Completed cast emits only one projectile")
 # Independent ray-sweep integration checks, using real physics geometry.
 await physics_frame
 for child in arena.get_children():
  if child.get_script() == load("res://scripts/projectile.gd"): child.queue_free()
 await process_frame
 p.position = Vector3(0,0,0)
 b.position = Vector3(0,0,-3)
 await physics_frame
 var projectile = load("res://scenes/projectile.tscn").instantiate()
 projectile.direction = Vector3.FORWARD
 projectile.strike_id = "integration_bolt"
 projectile.source = p
 arena.add_child(projectile)
 projectile.position = Vector3(0,1.2,0)
 projectile.set_physics_process(false)
 before = b.health
 projectile._physics_process(0.25)
 check(b.health == before-32, "Swept projectile hits boss without tunneling")
 await process_frame
 var wall_bolt = load("res://scenes/projectile.tscn").instantiate()
 wall_bolt.direction = Vector3.RIGHT
 arena.add_child(wall_bolt)
 wall_bolt.position = Vector3(12,1,0)
 wall_bolt.set_physics_process(false)
 wall_bolt._physics_process(0.2)
 check(wall_bolt.is_queued_for_deletion(), "Projectile is stopped by courtyard wall")
 p.state = p.State.FREE
 p.health = 50
 (await ActionTest.start(p,"heal"))
 p.timer = 0.8
 p._physics_process(0.01)
 check(p.health == 100 and p.flasks == 2, "Healing spends one flask and caps health")
 p.state = p.State.FREE
 p.mana = 99
 p.stamina = 99
 p.mana_wait = 0
 p.stamina_wait = 0
 p._physics_process(1.0)
 check(p.mana == 100 and p.stamina == 100, "Regeneration caps at resource maximums")
 # Verify burst range and occlusion against real static geometry.
 p.position = Vector3.ZERO
 b.position = Vector3(0,0,-3)
 await physics_frame
 before = b.health
 p.serial += 1
 arena.cast(p,1)
 check(b.health == before-p.tuning.burst_damage, "Burst damages a nearby target")
 var barrier := Shapes.solid(arena,Vector3(4,3,0.3),Vector3(0,1.5,-1.5),Color.GRAY)
 await physics_frame
 before = b.health
 p.serial += 1
 arena.cast(p,1)
 check(b.health == before, "Burst cannot damage through geometry")
 barrier.queue_free()
 await physics_frame
 b.position = Vector3(0,0,-6)
 before = b.health
 p.serial += 1
 arena.cast(p,1)
 check(b.health == before, "Burst cannot damage outside its radius")
 # Run each boss pattern through telegraph and active windows.
 b.frozen = false
 b.controller.manual = true
 for pattern in range(3):
  p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0,-2.4)))
  p.health = p.max_health
  p.state = p.State.FREE
  p.invulnerable = false
  b.motor.teleport(Transform3D.IDENTITY)
  # Sync both colliders before motion; stale overlaps can push the Warden upward.
  await physics_frame
  await process_frame
  b.actions.cancel(&"test_pattern")
  b.request_action([&"boss_combo",&"boss_overhead",&"boss_lunge"][pattern])
  b._physics_process(0.1)
  check(p.health == p.max_health, "Boss pattern %s telegraph is harmless" % pattern)
  b.actions.timer = b.actions.active_definition.windup
  b._physics_process(0.001)
  b._physics_process(0.01)
  check(p.health < p.max_health, "Boss pattern %s active window hits" % pattern)
  var hp: float = p.health
  b._physics_process(0.01)
  check(p.health == hp, "Boss pattern %s deduplicates its strike" % pattern)
  if pattern == 0:
   b.actions.timer = b.tuning.boss_active+b.tuning.boss_combo_gap
   b._physics_process(0.01)
   check(p.health < hp, "Boss combo second swing is an independent strike")
  # An instantaneous fixture relocation must reseed historical hit geometry.
  p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(3,0,0)))
  hp = p.health
  b.actions.strikes.clear()
  b.actions.timer = 0
  b._physics_process(0.01)
  check(p.health == hp, "Boss pattern %s can be avoided sideways" % pattern)
  b.actions.timer = 2.0
  b._physics_process(0.01)
  check(b.state == b.State.RECOVERY, "Boss pattern %s exposes recovery" % pattern)
 b.frozen = true
 p.health = p.max_health
 p.state = p.State.FREE
 # Spring arm must shorten rather than put the camera through any boundary.
 for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
  p.position = direction*12.0
  p.yaw = atan2(direction.x,direction.z)
  p._physics_process(0.016)
  for frame in range(4): await physics_frame
  check(p.arm.get_hit_length() < p.arm.spring_length, "Camera retracts near boundary %s" % direction)
 p.target = null
 p.locked = true
 p._physics_process(0.016)
 check(not p.locked, "Lock clears when target disappears")
 p.target = b
 arena.hud.toggle_pause()
 check(paused and arena.hud.overlay.visible, "Pause opens menu and stops encounter")
 arena.hud.toggle_pause()
 check(not paused, "Resume restores encounter")
 b.take_damage(10000,"finish")
 check(arena.finished and arena.hud.overlay.visible and not p.locked, "Victory opens retry and clears lock")
 arena.get_node("RetroEffects")._unhandled_input(toggle)
 # Call the same reload path as the Retry button.
 arena.hud.restart()
 await process_frame
 await physics_frame
 arena = current_scene
 p = arena.player
 b = arena.boss
 p.set_physics_process(false)
 b.set_physics_process(false)
 check(not PSXStyle.enabled, "Retry preserves the chosen effects setting")
 arena.get_node("RetroEffects")._unhandled_input(toggle)
 check(not arena.finished and p.health == 100 and b.health == b.max_health, "Retry restores encounter and boss health")
 check(p.flasks == 3 and p.mana == 100 and p.stamina == 100, "Retry restores all resources")
 check(p.received.is_empty() and b.received.is_empty() and projectile_count() == 0, "Retry clears strike history and projectiles")
 p.take_damage(1000,"death")
 check(arena.finished and p.dead and arena.hud.overlay.visible, "Death opens retry menu")
 arena.hud.restart()
 await process_frame
 await physics_frame
 arena = current_scene
 check(not arena.player.dead and not arena.finished, "Repeated retry works after death")
 print("RESULT: %s checks, %s failures" % [checks,failures])
 current_scene.queue_free()
 await process_frame
 await process_frame
 quit(1 if failures else 0)

func projectile_count() -> int:
 var count := 0
 for child in arena.get_children():
  if child.get_script() == load("res://scripts/projectile.gd") and not child.is_queued_for_deletion(): count += 1
 return count
