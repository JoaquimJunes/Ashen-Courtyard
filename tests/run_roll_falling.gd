extends "res://tests/fixtures/dodge_stage.gd"
var samples: Array[Dictionary] = []
var tracking := false

func record(_delta: float) -> void:
	if tracking:
		samples.append({"grounded":p.is_on_floor(),"position":p.position,
			"velocity":p.velocity,"time":p.timer,"immune":p.invulnerable,
			"roll_clock":p.dodge_ground_time,"travel_clock":p.actions.ground_roll.travel_time,
			"air_speed":p.actions.ground_roll.air_speed,"budget":p.dodge_distance_left,
			"active":p.actions.ground_roll.active,"definition":p.actions.active_definition})

func cliff(direction: Vector3, height: float = 8.0) -> void:
	tracking = false
	p.controller.intent.movement = Vector3.ZERO
	await prepare()
	Shapes.solid(fixtures,Vector3(80,1,80),Vector3(0,-0.51,0),Color.GRAY)
	Shapes.solid(fixtures,Vector3(4,height,4),-direction.normalized()*2+Vector3.UP*height/2,Color.GRAY)
	p.reset_for_lab(Transform3D(Basis.IDENTITY,-direction.normalized()*0.5+Vector3.UP*(height+0.02)))
	await settle(6)
	samples.clear()
	tracking = true

func roll(direction: Vector3) -> void:
	p.controller.intent.movement = direction
	check(await ActionTest.start(p,"dodge"),"Side/back roll enters through the shared action lifecycle")
	p.controller.intent.movement = Vector3.ZERO
	p.stamina_wait = 100

func await_contact() -> void:
	var fell := not p.is_on_floor()
	for frame in Engine.physics_ticks_per_second*3:
		await settle(1)
		fell = fell or not p.is_on_floor()
		if fell and p.is_on_floor(): return
	check(false,"Falling roll reaches a real landing")

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	p.combat_enabled = true
	stage.add_child(p)
	p.simulation_stepped.connect(record)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for direction: Vector3 in [Vector3.LEFT,Vector3.RIGHT,Vector3.BACK,Vector3(-1,0,1),Vector3(1,0,1)]:
			await cliff(direction)
			var start := p.position
			await roll(direction)
			p.controller.intent.movement = -direction # Cannot steer a committed roll.
			await await_contact()
			p.controller.intent.movement = Vector3.ZERO
			var falling: Array[Dictionary] = []
			for sample in samples:
				if not sample.grounded and sample.active: falling.append(sample)
			check(falling.size() > rate/2,"%s Hz %s: exercises a fall longer than the roll's old motion limit" % [rate,direction])
			var first: Dictionary = falling.front()
			var speed_ok := true
			var clocks_ok := true
			var immunity_ok := true
			var spent_budget := false
			for sample in falling:
				var horizontal: Vector3 = Vector3(sample.velocity.x,0,sample.velocity.z)
				speed_ok = speed_ok and horizontal.distance_to(direction.normalized()*first.air_speed) < 0.001
				clocks_ok = clocks_ok and sample.roll_clock == first.roll_clock and sample.travel_clock == first.travel_clock
				immunity_ok = immunity_ok and (sample.time < 0.32 or not sample.immune)
				spent_budget = spent_budget or (sample.budget == 0 and sample.time > 0.7)
			check(speed_ok and first.air_speed > 7 and spent_budget,"Side/back speed survives both distance exhaustion and 0.70 s; fixed heading")
			check(clocks_ok and immunity_ok and p.stamina == 75,"Only ground playback/braking pause; cost stays once and immunity expires")
			check((p.position-start).dot(direction.normalized()) > 6 and p.state == p.State.LAND and not p.actions.ground_roll.active,"Heavy contact still uses the existing landing response and releases the roll")
		# Leaving during the braking tail must retain the lower departure speed.
		tracking = false
		await prepare()
		tracking = true
		samples.clear()
		await roll(Vector3.RIGHT)
		while p.dodge_ground_time < 0.54: await settle(1)
		fixtures.get_child(0).position.y -= 8
		while p.is_on_floor(): await settle(1)
		var departure: float = p.actions.ground_roll.air_speed
		await settle(int(rate*0.25))
		check(departure > 0 and departure < 7 and absf(p.velocity.x-departure) < 0.001,"%s Hz: late edge preserves braking speed instead of accelerating" % rate)
		# Wall collision still wins; removing it cannot accumulate a speed burst.
		await cliff(Vector3.RIGHT)
		var wall := Shapes.solid(fixtures,Vector3(0.3,12,8),Vector3(3,5,0),Color.GRAY)
		await settle(2)
		await roll(Vector3.RIGHT)
		while p.timer < 0.7: await settle(1)
		check(p.position.x < 2.55 and absf(p.velocity.x) < 0.001 and p.dodge_distance_left == 0,"%s Hz: wall blocks the falling roll and consumes requested distance" % rate)
		wall.queue_free()
		await settle(2)
		check(p.velocity.x > 0 and p.velocity.x <= 7.4,"Removing an airborne obstruction resumes only the retained speed")
		await await_contact()
		# The existing landing skill remains available from a side roll.
		await cliff(Vector3.LEFT)
		await roll(Vector3.LEFT)
		while p.is_on_floor() or p.position.y > 1.2: await settle(1)
		var ticket: RefCounted = p.request_action(&"dodge")
		await await_contact()
		check(ticket.accepted and p.landing.roll_succeeded and p.stamina == 50 and p.actions.active_definition == p.tuning.landing_roll,"%s Hz: timed landing from a side roll still replaces ownership and pays once" % rate)
	Engine.physics_ticks_per_second = 60
	await cliff(Vector3.BACK)
	await roll(Vector3.BACK)
	while p.is_on_floor(): await settle(1)
	var at := p.position
	var speed: float = p.actions.ground_roll.air_speed
	paused = true
	await settle(6)
	check(p.position == at and p.actions.ground_roll.air_speed == speed,"Pause freezes falling roll and retained momentum")
	paused = false
	p.receive_damage(preload("res://features/combat/damage_request.gd").new(5,&"falling_roll_hit"))
	# Wait out immunity if the edge was reached while it was still active.
	if not p.reactions.active:
		while p.timer < 0.34: await settle(1)
		p.receive_damage(preload("res://features/combat/damage_request.gd").new(5,&"falling_roll_hit_late"))
	check(p.reactions.active and not p.actions.ground_roll.active and p.actions.ground_roll.air_speed == 0,"Accepted falling hit hands off to ragdoll and releases stored roll momentum")
	p.reset_for_lab(Transform3D.IDENTITY)
	check(p.velocity == Vector3.ZERO and p.actions.ground_roll.air_speed == 0 and p.actions.active_definition == null,"Reset clears falling-roll state and motor velocity")
	await cliff(Vector3.LEFT)
	await roll(Vector3.LEFT)
	while p.is_on_floor(): await settle(1)
	var executor: RefCounted = p.actions.ground_roll
	p.queue_free()
	tracking = false
	await settle(2)
	check(not executor.active and executor.air_speed == 0 and executor.actor == null,"Unloading releases falling-roll ownership")
	Engine.physics_ticks_per_second = original_rate
	print("ROLL FALLING: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
