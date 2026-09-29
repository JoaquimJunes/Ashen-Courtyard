extends SceneTree
const Stage = preload("res://tests/fixtures/swim_stage.gd")
const Intent = preload("res://features/character/character_intent.gd")
var checks := 0
var failures := 0
var stage: Stage

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	current_scene = stage
	var p: CharacterBody3D = stage.player
	var old_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await stage.reset_at()
		check(p.swimming.active and p.movement.mode == &"surface_swimming","%s: surface entry" % rate)
		await stage.tick(0.5)
		check(absf(p.position.y+1.1) < 0.035 and p.resources.breath == 20,"%s: stable surface and air" % rate)
		stage.intent.movement = Vector3.RIGHT
		stage.intent.swim_direction = Vector3.RIGHT
		await stage.tick(0.8)
		check(absf(p.velocity.x-2.5) < 0.02,"%s: normal swim speed" % rate)
		stage.intent.sprint = true
		var stamina: float = p.stamina
		await stage.tick(0.5)
		check(p.swimming.fast and absf(p.velocity.x-4.0) < 0.02 and absf(p.stamina-(stamina-10)) < 0.02,"%s: fast speed and exact exertion" % rate)
		p.stamina = 0
		p.stamina_wait = 1
		await stage.tick(0.25)
		check(not p.swimming.fast and p.velocity.length() <= 2.51,"%s: exhaustion returns to normal" % rate)
		await stage.tick(1.1)
		check(not p.swimming.fast and p.stamina > 0,"%s: holding exhausted fast-swim does not repeatedly drain recovered stamina" % rate)
		await stage.reset_at()
		stage.intent.swim_vertical = -1
		await stage.tick(0.5)
		check(p.movement.mode == &"underwater_swimming" and p.position.y < -1.5,"%s: crouch input dives" % rate)
		stage.intent.swim_vertical = 0
		await stage.tick(0.5)
		var depth: float = p.position.y
		await stage.tick(0.8)
		check(absf(p.position.y-depth) < 0.015 and p.velocity.length() < 0.02,"%s: neutral underwater depth" % rate)
		p.stamina = 30
		p.stamina_wait = 0
		await stage.tick(0.5)
		check(absf(p.stamina-45) < 0.03,"%s: normal underwater stamina recovery" % rate)
		stage.intent.swim_vertical = 1
		await stage.tick(1.6)
		check(not p.swimming.underwater and absf(p.position.y+1.1) < 0.05,"%s: resurface without jumping" % rate)
		await stage.reset_at()
		stage.intent.swim_direction = Vector3(1,-1,0).normalized()
		stage.intent.movement = Vector3.RIGHT
		stage.intent.swim_vertical = -1
		await stage.tick(0.3)
		stage.intent.swim_vertical = 0
		await stage.tick(0.6)
		check(p.velocity.x > 1 and p.velocity.y < -1 and p.velocity.length() <= 2.51,"%s: camera-directed 3D steering is normalized" % rate)
		await stage.reset_at(Vector3(-9,-0.4,0))
		check(not p.swimming.active and p.is_on_floor(),"%s: shallow water remains grounded" % rate)
		stage.intent.movement = Vector3.RIGHT
		await stage.tick(1.4)
		check(p.swimming.active,"%s: walking from shallow water into deep water" % rate)
		for entry_action in ["jump","dodge"]:
			await stage.reset_at(Vector3(3,0.41,-8.7))
			stage.intent.movement = Vector3.BACK
			stage.intent.swim_direction = Vector3.BACK
			p.motor.face_direction(Vector3.BACK)
			var entry_ticket: RefCounted = p.request_action(entry_action)
			await stage.tick(1.7)
			check(entry_ticket.accepted and p.swimming.active and not p.forward_dive.active and p.health == p.max_health,"%s: actual %s action transitions into swimming" % [rate,entry_action])
		await stage.reset_at(Vector3(3,12,0))
		await stage.tick(1.6)
		check(p.swimming.active and not p.dead and p.health == p.max_health and not p.reactions.active,"%s: deep entry cancels falling consequences" % rate)
		await stage.reset_at(Vector3(3,4,0))
		p.motor.launch(-180)
		await stage.tick(0.15)
		check(p.swimming.active and p.health == p.max_health,"%s: fast segment crossing catches water before floor landing publication" % rate)
		await stage.reset_at(Vector3(-9,12,0))
		await stage.tick(1.5)
		check(p.health < p.max_health,"%s: shallow floor retains fall damage" % rate)
		await stage.reset_at(Vector3(3,-2.3,0))
		var wall := Shapes.solid(stage,Vector3(0.2,5,4),Vector3(4,-2,0),Color.GRAY)
		stage.intent.movement = Vector3.RIGHT
		stage.intent.swim_direction = Vector3.RIGHT
		await stage.tick(0.8)
		check(p.position.x < 3.7,"%s: swim body cannot pass through wall" % rate)
		wall.free()
		stage.intent.swim_vertical = -1
		await stage.tick(1.5)
		check(p.position.y > -5.2 and p.health == p.max_health,"%s: underwater floor collision is not a landing" % rate)
		var roof := Shapes.solid(stage,Vector3(12,0.2,12),Vector3(3,-1.4,0),Color.GRAY)
		stage.intent.movement = Vector3.ZERO
		stage.intent.swim_direction = Vector3.ZERO
		stage.intent.swim_vertical = 1
		await stage.tick(1.5)
		check(p.position.y < -2.1,"%s: underwater roof blocks ascent" % rate)
		roof.free()
	Engine.physics_ticks_per_second = old_rate
	stage.queue_free()
	await process_frame
	print("SWIMMING: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
