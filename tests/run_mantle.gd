extends "res://tests/fixtures/dodge_stage.gd"

func wall(height: float = 1.5, depth: float = 2.0) -> StaticBody3D:
	return Shapes.solid(fixtures,Vector3(4,height,depth),Vector3(0,height/2,-depth/2),Color.GRAY)

func start_grab(height: float = 1.5) -> bool:
	p.controller.intent.movement = Vector3.ZERO
	p.controller.intent.surface_motion = Vector2.ZERO
	await prepare(Vector3(0,0.04,0.5))
	wall(height)
	await settle(2)
	p.controller.intent.movement = Vector3.FORWARD
	if not await ActionTest.start(p,"jump"): return false
	for i in 150:
		await settle(1)
		if p.traversal.status == &"hang": return true
		if p.is_on_floor() and not p.traversal.attached(): break
	print("GRAB DEBUG ",p.position," ",p.traversal.reason," ",p.traversal.status)
	return false

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var original := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for height: float in [1.5,2.5]:
			var grabbed := await start_grab(height)
			check(grabbed,"%s Hz: jump catches %.1f m ledge" % [rate,height])
			if not grabbed: continue
			check(p.movement.mode == &"climbing" and p.actions.active_definition == null and p.motor.tucked,"Hang retains attachment after Grab releases action")
			var stamina: float = p.stamina
			var at := p.global_position
			await settle(rate)
			check(p.global_position.distance_to(at) < 0.002 and p.stamina == stamina and is_equal_approx(stamina,85),"Hanging holds position; jump costs once; no drain or regen")
			check(not p.request_action(&"jump").accepted and not p.request_action(&"light").accepted,"Attached mode rejects incompatible jump/combat")
			p.controller.intent.surface_motion = Vector2.UP*-1
			for frame in rate*3:
				await settle(1)
				if not p.traversal.attached(): break
			check(p.traversal.reason == &"completed" and p.movement.mode == &"grounded","Pull-up completes on actual top support (%s, %s)" % [p.traversal.reason,p.position])
			check(absf(p.position.y-height) < 0.035 and p.position.z < -0.3 and not p.motor.tucked,"Finish above ledge with standing collision restored")
			check(p.stamina <= 76 and p.stamina >= 75,"Pull-up pays exactly 10; cannot regenerate during motion")
	Engine.physics_ticks_per_second = 60
	check(await start_grab(),"Prepare deliberate release")
	var stamina: float = p.stamina
	var ticket: RefCounted = p.request_action(&"dodge")
	await settle(2)
	check(ticket.accepted and not p.traversal.attached() and p.velocity.y < 0 and not p.invulnerable and p.stamina == stamina,"Dodge binding releases into unpaid ordinary falling")
	check(await start_grab(),"Prepare insufficient-stamina hang")
	p.stamina = 9
	p.controller.intent.surface_motion = Vector2(0,1)
	await settle(90)
	check(p.traversal.status == &"hang" and p.stamina == 9,"Insufficient stamina stays hanging without drain, regen or partial payment")
	p.request_action(&"dodge")
	await settle(2)
	check(not p.traversal.attached(),"Insufficient stamina never blocks let-go")
	check(await start_grab(),"Prepare attached damage")
	p.take_damage(5,"ledge_hit")
	await settle(2)
	check(p.reactions.active and not p.traversal.attached() and not p.presentation.mantle.active,"Hit at zero hanging velocity enters ragdoll and releases attachment")
	await prepare()
	check(not p.motor.tucked and p.actions.active_definition == null and p.movement.attachment == null,"Reset restores motor/action/attachment after ragdoll")
	Engine.physics_ticks_per_second = original
	stage.queue_free()
	await settle(2)
	print("MANTLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
