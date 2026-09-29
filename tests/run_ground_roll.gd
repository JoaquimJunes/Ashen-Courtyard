extends "res://tests/fixtures/dodge_stage.gd"
## Exercise real action requests and physics, including every simulation tick.
var samples: Array[Dictionary] = []
var recording := false
func record(delta: float) -> void:
	if not recording: return
	samples.append({"delta":delta,"position":p.position,"ground":p.is_on_floor(),"vy":p.velocity.y,"timer":p.timer,"immune":p.invulnerable,"progress":p.model.dodge_progress,"state":p.state})
	if p.state != p.State.DODGE: recording = false

func begin_roll(direction: Vector3) -> bool:
	p.controller.intent.movement = direction
	samples.clear()
	recording = true
	var accepted := await ActionTest.start(p,"dodge")
	p.controller.intent.movement = Vector3.ZERO
	return accepted

func complete_roll() -> void:
	for frame in Engine.physics_ticks_per_second*3:
		if p.state != p.State.DODGE: break
		await settle(1)

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	p.simulation_stepped.connect(record)
	var original_rate := Engine.physics_ticks_per_second
	var directions := [Vector3.LEFT,Vector3.RIGHT,Vector3.BACK,Vector3(-1,0,1),Vector3(1,0,1)]
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for combat in [false,true]:
			p.combat_enabled = combat
			for direction: Vector3 in directions:
				await prepare()
				var start := p.position
				var label := "%s Hz %s %s" % [rate,"combat enabled" if combat else "combat disabled",direction]
				check(await begin_roll(direction),"Ground roll accepted: "+label)
				check(p.actions.active_definition == p.tuning.dodge_ground and p.stamina == 75 and p.actions.ground_roll.active,"Ground definition and single cost: "+label)
				var clip := "roll_left" if direction == Vector3.LEFT else ("roll_right" if direction == Vector3.RIGHT else "roll_back")
				check(p.model.dodge_clip == clip and not p.model.dodge_airborne and p.model.dodge_progress > 0,"Referenced clip starts on first tick: "+label)
				# Changes during commitment cannot redirect travel or change the clip.
				p.controller.intent.movement = -direction
				await complete_roll()
				p.controller.intent.movement = Vector3.ZERO
				var duration := 0.0
				var floor_ok := true
				var immunity_ok := true
				for sample in samples:
					duration += sample.delta
					floor_ok = floor_ok and sample.ground and absf(sample.position.y-start.y) < 0.01 and sample.vy <= 0
					immunity_ok = immunity_ok and (sample.immune == (sample.timer >= 0.06 and sample.timer < 0.32))
				var travel: Vector3 = samples.back().position-start
				check(floor_ok,"No physical hop on level ground: "+label)
				check(absf(duration-0.70) < 0.001,"Exactly 0.70 s grounded action: "+label)
				check(absf(travel.length()-4.34) < 0.015 and travel.normalized().dot(direction.normalized()) > 0.999,"4.34 m reach and fixed heading: "+label)
				check(immunity_ok and p.actions.active_definition == null and not p.actions.ground_roll.active,"Immunity expires and ownership releases: "+label)
	Engine.physics_ticks_per_second = original_rate
	await prepare()
	check(await begin_roll(Vector3.ZERO) and p.forward_dive.active and not p.actions.ground_roll.active,"Stationary dodge uses the shared forward dive")
	await complete_roll()
	await prepare()
	check(await begin_roll(Vector3.FORWARD) and p.forward_dive.active and not p.actions.ground_roll.active,"Adaptive forward dive remains the forward action")
	await complete_roll()
	# Real steps and headroom use the shared motor, with no launch or raised arc.
	for height in [0.4,0.6,0.8]:
		await prepare()
		Shapes.solid(fixtures,Vector3(6,height,5),Vector3(4,height/2,0),Color.GRAY)
		await settle(2)
		await begin_roll(Vector3.RIGHT)
		await complete_roll()
		check((p.position.x > 2 and p.position.y >= height-0.02) == (height <= 0.6),"Ground roll obeys maximum step height %.1f m" % height)
	await prepare()
	Shapes.solid(fixtures,Vector3(6,0.6,5),Vector3(4,0.3,0),Color.GRAY)
	Shapes.solid(fixtures,Vector3(10,0.3,5),Vector3(3,2.15,0),Color.GRAY)
	await settle(2)
	await begin_roll(Vector3.RIGHT)
	await complete_roll()
	check(p.position.x < 1 and p.position.y < 0.02,"Ceiling blocks a step without capsule penetration")
	# Losing the floor means ordinary falling; no renewed lift or immunity.
	await prepare()
	await begin_roll(Vector3.RIGHT)
	await settle(8)
	fixtures.get_child(0).position.y -= 3
	await settle(5)
	var clock: float = p.dodge_ground_time
	check(p.velocity.y < 0 and p.model.dodge_airborne,"Edge departure falls under gravity and blends to tucked pose")
	await settle(10)
	check(p.dodge_ground_time == clock and not p.invulnerable,"Airborne interval pauses rolling but does not extend immunity")
	await settle(60)
	check(p.is_on_floor() and p.state == p.State.FREE and p.position.x > 4.34,"Lower landing completes remaining roll after retaining airborne momentum beyond flat-ground reach")
	# A wall cannot store travel, even if removed before recovery is over.
	await prepare()
	var wall := Shapes.solid(fixtures,Vector3(0.3,4,5),Vector3(0.55,2,0),Color.GRAY)
	await settle(2)
	await begin_roll(Vector3.RIGHT)
	await settle(33)
	var remaining: float = p.dodge_distance_left
	var at := p.position
	wall.queue_free()
	await complete_roll()
	check(p.position.distance_to(at) <= remaining+0.02 and p.position.x < 1,"Blocked roll consumes requested travel instead of banking it")
	await prepare()
	p.stamina = 24
	check(not await begin_roll(Vector3.RIGHT) and p.stamina == 24 and not p.actions.ground_roll.active,"Rejected roll cannot spend resources or take ownership")
	recording = false
	await prepare()
	await begin_roll(Vector3.LEFT)
	await settle(8)
	paused = true
	at = p.position
	clock = p.dodge_ground_time
	for frame in 5: await process_frame
	check(p.position == at and p.dodge_ground_time == clock,"Pause freezes grounded roll position and playback")
	paused = false
	await complete_roll()
	check(p.state == p.State.FREE,"Resume finishes the grounded roll")
	await prepare()
	await begin_roll(Vector3.BACK)
	while p.dodge_ground_time < 0.6: await settle(1)
	var serial: int = p.serial
	var ticket: RefCounted = p.actions.request("dodge",true)
	p.controller.intent.movement = Vector3.LEFT
	await settle(9)
	p.controller.intent.movement = Vector3.ZERO
	check(ticket.resolved and ticket.accepted and p.serial == serial+1 and p.model.dodge_clip == "roll_left","One buffered follow-up begins only after recovery")
	for interruption in ["damage","death","reset"]:
		await prepare()
		await begin_roll(Vector3.RIGHT)
		if interruption == "damage": p._on_damaged()
		elif interruption == "death":
			p.dead = true
			p.died.emit()
		else: p.reset_for_lab(Transform3D.IDENTITY)
		check(not p.actions.ground_roll.active and p.actions.ground_roll.actor == null and p.actions.active_definition == null and not p.model.dodging and not p.invulnerable,"%s clears roll ownership, cached poses and immunity" % interruption)
	await prepare()
	await begin_roll(Vector3.LEFT)
	var executor: RefCounted = p.actions.ground_roll
	p.queue_free()
	await settle(2)
	check(not executor.active and executor.actor == null,"Unloading releases ground-roll ownership")
	Engine.physics_ticks_per_second = original_rate
	print("GROUND ROLL: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
