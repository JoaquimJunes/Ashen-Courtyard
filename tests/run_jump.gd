extends "res://tests/fixtures/dodge_stage.gd"
var samples: Array[Dictionary] = []
var recording := false
var landing_count := 0

func record(_delta: float) -> void:
	if recording: samples.append({"p":p.position,"v":p.velocity,"state":p.state,"floor":p.is_on_floor(),"stamina":p.stamina})

func await_landing() -> void:
	for frame in Engine.physics_ticks_per_second*4:
		if landing_count > 0: return
		await settle(1)
	check(false,"Landing occurred within four seconds")

func ready_at(height: float = 0.05) -> void:
	p.controller.intent.movement = Vector3.ZERO
	p.controller.intent.sprint = false
	await prepare()
	if height > 0.1:
		p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,height,0)))
		await settle(1)
	landing_count = 0
	samples.clear()
	recording = true

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	p.simulation_stepped.connect(record)
	p.landing.landed.connect(func(_kind, _height, _damage): landing_count += 1)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for combat in [false,true]:
			p.combat_enabled = combat
			await ready_at()
			var start := p.position
			p.move_velocity = Vector3(4,0,0)
			check(await ActionTest.start(p,"jump"),"%s Hz combat=%s: jump accepted" % [rate,combat])
			check(p.velocity.y > 0 and p.position.y > start.y and p.stamina == 85,"Immediate takeoff pays 15 once")
			check(not await ActionTest.start(p,"jump"),"No double jump during takeoff")
			await await_landing()
			var apex := start.y
			var momentum_ok := true
			var free_in_air := false
			for sample in samples:
				apex = maxf(apex,sample.p.y)
				if not sample.floor:
					momentum_ok = momentum_ok and absf(sample.v.x-4.0) < 0.001
					free_in_air = free_in_air or sample.state == p.State.FREE
			check(absf(apex-start.y-1.2) < 0.012,"1.2 m apex within 12 mm at %s Hz" % rate)
			check(momentum_ok and free_in_air,"Takeoff momentum survives action release")
			check(p.health == p.max_health and p.landing.severity == &"soft" and landing_count == 1,"Ordinary jump lands once without damage or commitment")
			check(p.actions.active_definition == null and p.state == p.State.FREE,"Takeoff action releases before landing")
		# Actual collisions drive severity. Threshold-unit tests below cover exact boundaries.
		for height in [2.5,4.5,8.0,16.0]:
			await ready_at(height)
			await await_landing()
			var expected := "soft" if height < 3 else ("heavy" if height < 6 else ("damaging" if height < 15 else "lethal"))
			check(p.landing.severity == StringName(expected),"%s Hz %.1f m drop: %s" % [rate,height,expected])
			check(absf(p.landing.last_height-height) < 0.6,"Impact speed corresponds to actual drop height")
			check((p.health < p.max_health) == (height > 6) and p.dead == (height > 15),"Fall damage/death thresholds work with combat disabled")
			if height > 3 and height < 15:
				check(p.state == p.State.LAND and p.actions.active_definition == p.tuning.landing_action,"Heavy landing owns the common action slot")
				var hp: float = p.health
				await settle(int(rate*0.15))
				check(p.health == hp and landing_count == 1,"Impact cannot damage repeatedly while grounded")
	Engine.physics_ticks_per_second = 60
	p.combat_enabled = true
	await ready_at()
	p.stamina = 14
	check(not await ActionTest.start(p,"jump") and p.stamina == 14 and p.is_on_floor(),"Insufficient stamina rejects launch atomically")
	await ready_at()
	p.move_velocity = Vector3(6.5,0,0)
	await ActionTest.start(p,"jump")
	p.controller.intent.movement = Vector3.LEFT
	await settle(12)
	check(p.velocity.x > 6 and p.velocity.x < 6.5,"Opposing input permits only small airborne braking")
	p.controller.intent.movement = Vector3.ZERO
	var speed: float = p.velocity.x
	check(await ActionTest.start(p,"light"),"Compatible melee starts during flight")
	await settle(4)
	check(absf(p.velocity.x-speed) < 0.001,"Airborne melee does not replace momentum with ground lunge")
	await ready_at()
	await ActionTest.start(p,"jump")
	await settle(10)
	check(await ActionTest.start(p,"cast"),"Compatible spell starts in flight")
	await settle(ceili((p.tuning.bolt.windup+p.tuning.bolt.recovery)*60)+1)
	check(p.actions.active_definition == null,"Airborne cast completes through landing")
	# Physical ceiling: capsule top is 1.8 m; feet can rise only about 0.2 m.
	await ready_at()
	Shapes.solid(fixtures,Vector3(6,0.2,6),Vector3(0,2.1,0),Color.GRAY)
	await settle(2)
	await ActionTest.start(p,"jump")
	await await_landing()
	var apex := 0.0
	for sample in samples: apex = maxf(apex,sample.p.y)
	check(apex <= 0.205 and p.is_on_floor(),"Ceiling interrupts ascent without penetration or hanging")
	# A buffered press stays pending until real contact, without early spending.
	await ready_at(1.0)
	while p.position.y > 0.25: await settle(1)
	var ticket: RefCounted = p.actions.request("jump",true)
	var hp: float = p.stamina
	check(not ticket.resolved and p.stamina == hp,"Pre-landing press is queued without a cost")
	await settle(8)
	check(ticket.resolved and ticket.accepted and p.velocity.y > 0 and p.stamina == hp-15,"0.12 s pre-landing buffer launches after contact exactly once")
	await ready_at(4.5)
	while p.position.y > 0.35: await settle(1)
	ticket = p.actions.request("jump",true)
	await await_landing()
	check(ticket.resolved and not ticket.accepted and p.state == p.State.LAND and p.stamina == 100,"Heavy landing clears buffered jump and spends nothing")
	check(not await ActionTest.start(p,"jump"),"Heavy recovery blocks takeoff")
	await settle(60)
	check(await ActionTest.start(p,"jump"),"Takeoff becomes available after landing recovery")
	# Walk off an edge; the grace allowance belongs only to ground departure.
	for delay in [2,9]:
		await ready_at()
		p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.01,-14.8)))
		p.controller.intent.movement = Vector3.FORWARD
		p.move_velocity = Vector3.FORWARD*6.5
		while p.is_on_floor(): await settle(1)
		await settle(delay)
		var accepted: bool = await ActionTest.start(p,"jump")
		check(accepted == (delay == 2),"Edge grace expires after 0.10 s (delay %s frames)" % delay)
	await ready_at()
	await ActionTest.start(p,"jump")
	await settle(6)
	paused = true
	var before := p.position
	var clock: float = p.movement.airborne_time
	for frame in 8: await process_frame
	check(p.position == before and p.movement.airborne_time == clock,"Pause freezes trajectory and movement clocks")
	paused = false
	await await_landing()
	check(p.is_on_floor(),"Resume completes the same jump")
	# Fall damage is independent of dodge immunity and lab combat permissions.
	await ready_at()
	p.combat_enabled = false
	p.invulnerable = true
	var request = preload("res://features/combat/damage_request.gd").new(10,&"fall_bypass")
	request.damage_type = &"fall"
	check(p.receive_damage(request) and p.health == 90,"Fall damage bypasses dodge immunity and lab combat switch")
	check(not p.receive_damage(request) and p.health == 90,"Repeated fall strike remains deduplicated")
	for height in [0.0,3.0,3.01,6.0,6.01,15.0,30.0]:
		var result: Dictionary = p.landing.classify(sqrt(2*p.tuning.gravity*height),p.tuning.gravity)
		check(is_equal_approx(result.height,height) and result.fraction >= 0 and result.fraction <= 1,"Exact threshold calculation stays bounded at %.2f m" % height)
	for iteration in 3:
		await ready_at()
		await ActionTest.start(p,"jump")
		p.actions.request("jump",true)
		p.reset_for_lab(Transform3D.IDENTITY)
		check(p.actions.active_definition == null and p.actions.buffered.is_empty() and not p.movement.in_flight and not p.movement.jump_consumed and p.velocity == Vector3.ZERO and p.stamina == 100,"Reset clears jump, buffered input, momentum and fall bookkeeping")
	Engine.physics_ticks_per_second = original_rate
	print("JUMP: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
