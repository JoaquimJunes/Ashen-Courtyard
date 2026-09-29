extends SceneTree
## Exercise real player/Warden damage paths across spatial boundaries.
const Strike = preload("res://features/combat/strike_token.gd")
var checks := 0
var failures := 0
var player: CharacterBody3D
var boss: CharacterBody3D
var services: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)

func settle() -> void:
	await physics_frame
	await process_frame

func player_hit(strike: RefCounted = null) -> float:
	var before: float = boss.health
	services.melee(player,10,Strike.new() if strike == null else strike,boss)
	return before-boss.health

func boss_hit() -> float:
	player.resources.reset()
	player.dead = false
	boss.actions.cancel(&"fixture")
	var ticket: RefCounted = boss.actions.request("boss_overhead")
	boss.actions.tick()
	check(ticket.accepted,"Warden overhead starts through the shared lifecycle")
	boss.actions.timer = boss.actions.active_definition.windup
	boss.actions.advance(0.0)
	var before: float = player.health
	boss.actions.advance(0.0)
	return before-player.health

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	services = root.get_node("GameSession").configure_world(host)
	player = root.get_node("GameSession").create_player(host,services)
	player.controller.manual = true
	player.set_physics_process(false)
	boss = load("res://scenes/boss.tscn").instantiate()
	boss.services = services
	boss.controller.manual = true
	host.add_child(boss)
	boss.set_physics_process(false)
	boss.target = player
	player.target = boss
	player.motor.teleport(Transform3D.IDENTITY)
	for height in [10.0,-10.0]:
		boss.motor.teleport(Transform3D(Basis(Vector3.UP,PI),Vector3(0,height,-2)))
		await settle()
		check(player_hit() == 0,"Assigned target at height %s is outside player melee reach" % height)
		check(boss_hit() == 0,"Warden cannot hit across a %s m height difference" % height)
	# A modest elevation inside the authored reach remains attackable.
	boss.motor.teleport(Transform3D(Basis(Vector3.UP,PI),Vector3(0,0.5,-2)))
	await settle()
	check(player_hit() == 10,"Nearby elevated target remains within reach")
	check(boss_hit() == boss.tuning.combat.boss_overhead.damage,"Nearby elevated Warden can still hit")
	boss.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0,2)))
	await settle()
	check(player_hit() == 0,"Target behind the player remains outside the attack arc")
	boss.motor.teleport(Transform3D(Basis(Vector3.UP,PI),Vector3(0,0,-4)))
	await settle()
	check(player_hit() == 0,"Distant level target remains outside player melee reach")
	check(boss_hit() == 0,"Distant level target remains outside Warden melee reach")
	boss.motor.teleport(Transform3D(Basis(Vector3.UP,PI),Vector3(0,0,-2)))
	var wall := Shapes.solid(host,Vector3(4,4,0.2),Vector3(0,2,-1),Color.GRAY)
	await settle()
	var token := Strike.new()
	check(player_hit(token) == 0,"World geometry blocks player melee")
	check(boss_hit() == 0,"World geometry blocks Warden melee")
	wall.queue_free()
	await settle()
	check(player_hit(token) == 10,"Blocked player strike can hit after the obstruction clears")
	check(player_hit(token) == 0,"Successful player strike still deduplicates damage")
	var before: float = player.health
	boss.actions.advance(0.0)
	check(before-player.health == boss.tuning.combat.boss_overhead.damage,"Blocked Warden strike can hit after the obstruction clears")
	before = player.health
	boss.actions.advance(0.0)
	check(player.health == before,"Successful Warden strike still deduplicates damage")
	host.queue_free()
	await settle()
	print("COMBAT BOUNDARIES: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
