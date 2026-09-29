extends SceneTree
## Damage signals can synchronously end an encounter or replace the casting action.
var checks := 0
var failures := 0
var arena: Node3D
var player: CharacterBody3D
var boss: CharacterBody3D
var replacement_ticket: RefCounted

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)

func settle() -> void:
	await physics_frame
	await process_frame

func spawn_arena() -> void:
	arena = load("res://scenes/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	player = arena.player
	boss = arena.boss
	player.set_physics_process(false)
	boss.set_physics_process(false)
	player.controller.manual = true
	boss.controller.manual = true
	player.motor.teleport(Transform3D.IDENTITY)
	boss.motor.teleport(Transform3D(Basis(Vector3.UP,PI),Vector3(0,0,-2)))
	player.selected_spell = 1
	await settle()

func clear_arena() -> void:
	arena.queue_free()
	await settle()

func start_cast(caster: CharacterBody3D, action: String) -> void:
	var ticket: RefCounted = caster.actions.request(action)
	caster.actions.tick()
	check(ticket.accepted,"Spell starts through the shared action lifecycle")
	caster.actions.timer = caster.actions.active_definition.windup

func replace_cast(_request: RefCounted) -> void:
	player.actions.cancel(&"test_replacement")
	replacement_ticket = player.actions.request("cast")
	player.actions.tick()

func run() -> void:
	await spawn_arena()
	start_cast(player,"cast")
	var before: float = boss.health
	var definition: Resource = player.actions.active_definition
	player.actions.advance(0.0)
	player.actions.advance(0.0)
	check(boss.health == before-definition.damage,"Nonlethal burst releases exactly once")
	check(player.mana == player.tuning.mana_max-definition.mana_cost,"Burst spends its mana only once")
	check(player.actions.active_definition == definition and player.state == player.State.CAST,"Nonlethal burst keeps recovery ownership")
	player.actions.timer = definition.windup+definition.recovery
	player.actions.advance(0.0)
	player.actions.finish_if_idle()
	check(player.actions.active_definition == null and player.state == player.State.FREE,"Normal cast recovery finishes")
	await clear_arena()

	await spawn_arena()
	boss.health = 1
	start_cast(player,"cast")
	player.actions.advance(0.0)
	check(boss.dead and arena.finished and arena.hud.menu.ended,"Lethal player burst completes the real victory flow")
	check(player.actions.active_definition == null and player.actions.strike == null,"Victory cancellation releases cast ownership")
	await clear_arena()

	await spawn_arena()
	player.health = 1
	start_cast(boss,"burst")
	boss.actions.advance(0.0)
	check(player.dead and arena.finished and arena.hud.menu.ended,"Lethal Warden burst completes the real defeat flow")
	check(boss.actions.active_definition == null and boss.actions.strike == null,"Encounter freeze releases Warden spell ownership")
	await clear_arena()

	await spawn_arena()
	start_cast(player,"cast")
	var original_serial: int = player.actions.serial
	boss.damage_applied.connect(replace_cast,CONNECT_ONE_SHOT)
	player.actions.advance(0.0)
	check(replacement_ticket != null and replacement_ticket.accepted,"Damage callback can start a replacement cast")
	check(player.actions.serial == original_serial+1 and player.actions.timer == 0 and not player.actions.released,"Same-definition replacement retains its own clock and release state")
	before = boss.health
	player.actions.advance(0.0)
	check(boss.health == before,"Replacement cannot release before its own windup")
	await clear_arena()
	print("CAST LIFECYCLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
