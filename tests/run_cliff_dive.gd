extends "res://tests/fixtures/dodge_stage.gd"
var landing_events := 0

func cliff(wall: bool = false) -> void:
	await prepare()
	Shapes.solid(fixtures,Vector3(80,1,80),Vector3(0,-0.51,0),Color.GRAY)
	Shapes.solid(fixtures,Vector3(5,8,4),Vector3(0,4,2),Color.GRAY)
	if wall: Shapes.solid(fixtures,Vector3(5,14,0.3),Vector3(0,6,-6),Color.GRAY)
	p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,8.02,0.5)))
	await settle(6)

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	p.combat_enabled = false
	stage.add_child(p)
	p.landing.landed.connect(func(_severity, _height, _damage): landing_events += 1)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await cliff()
		check(await ActionTest.start(p,"dodge"),"%s Hz: cliff dive starts through the shared action lifecycle" % rate)
		p.stamina_wait = 100 # Observe payment without post-get-up regeneration.
		landing_events = 0
		var beyond_budget := false
		var past_old_limit := false
		var momentum := true
		var immune := true
		var nonnegative := true
		var paused_pose := true
		for frame in rate*3:
			await settle(1)
			if not p.forward_dive.active: break
			if p.forward_dive.phase == p.forward_dive.Phase.AIR:
				beyond_budget = beyond_budget or p.dodge_distance_left == 0
				past_old_limit = past_old_limit or p.forward_dive.since_launch > 0.7
				if p.forward_dive.since_launch > 0: momentum = momentum and absf(p.velocity.z+11.0) < 0.001
				paused_pose = paused_pose and p.forward_dive.roll_time == 0
				if p.forward_dive.since_launch >= 0.32: immune = immune and not p.invulnerable
				nonnegative = nonnegative and p.dodge_distance_left >= 0
		check(beyond_budget and past_old_limit and momentum,"%s Hz: forward speed continues beyond 5.5 m and 0.70 s until contact" % rate)
		check(p.position.z < -8.0 and p.state == p.State.RAGDOLL and p.reactions.active,"%s Hz: failed heavy cliff landing hands the dive to ragdoll" % rate)
		check(immune and paused_pose and nonnegative and p.stamina == 75,"%s Hz: no airborne roll, extra cost, renewed immunity, or negative budget" % rate)
		var health_after: float = p.health
		for frame in rate*8:
			if not p.reactions.active: break
			await settle(1)
		check(not p.reactions.active and p.state == p.State.FREE and p.is_on_floor(),"%s Hz: missed cliff check settles and automatically gets up" % rate)
		check(landing_events == 1 and p.health == health_after and p.stamina == 75,"%s Hz: physical contact never repeats fall damage or charges a failed roll" % rate)
		await cliff(true)
		await ActionTest.start(p,"dodge")
		for frame in rate*2:
			await settle(1)
			if p.reactions.active: break
		check(p.reactions.active and p.position.z > -5.6 and p.position.z < -5.0,"%s Hz: wall stops forward travel before the failed landing ragdolls" % rate)
		await cliff()
		await ActionTest.start(p,"dodge")
		await settle(int(rate*0.85))
		var at := p.position
		var clock: float = p.forward_dive.since_launch
		paused = true
		await settle(4)
		check(p.position == at and p.forward_dive.since_launch == clock,"%s Hz: pause freezes an extended cliff dive" % rate)
		paused = false
		p.actions.cancel(&"test_interrupt")
		check(not p.forward_dive.active and p.actions.active_definition == null and not p.invulnerable,"%s Hz: interruption releases extended dive ownership" % rate)
		p.reset_for_lab(Transform3D.IDENTITY)
		check(p.velocity == Vector3.ZERO and p.dodge_distance_left == 0 and p.forward_dive.since_launch == 0,"%s Hz: reset removes all cliff-dive state" % rate)
		# An expired press and a correctly timed but unaffordable press both fail.
		for failure in ["early","stamina"]:
			await cliff()
			await ActionTest.start(p,"dodge")
			while p.forward_dive.active and p.forward_dive.since_launch < (0.35 if failure == "early" else 0.75): await settle(1)
			if failure == "stamina": p.stamina = 24
			var ticket: RefCounted = p.request_action(&"dodge")
			for frame in rate*2:
				if p.reactions.active: break
				await settle(1)
			check(p.reactions.active and not p.landing.roll_succeeded and ticket.resolved and not ticket.accepted,"%s Hz: %s failure enters physical ragdoll" % [rate,failure])
			p.reset_for_lab(Transform3D.IDENTITY)
			check(not p.reactions.active and not p.motor.ragdoll_motion and p.actions.active_definition == null and p.stamina == 100,"Failed-dive ragdoll reset restores ordinary collision and action ownership")
		await cliff()
		Shapes.solid(fixtures,Vector3(5,8,4),Vector3(0,12,2),Color.GRAY)
		p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,16.02,0.5)))
		await settle(6)
		await ActionTest.start(p,"dodge")
		for frame in rate*3:
			if p.dead: break
			await settle(1)
		check(p.dead and p.reactions.active and p.reactions.lethal and p.health == 0 and p.stamina == 75,"%s Hz: lethal cliff dive enters dead ragdoll with full fall damage" % rate)
	Engine.physics_ticks_per_second = original_rate
	print("CLIFF DIVE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
