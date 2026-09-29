extends "res://tests/fixtures/dodge_stage.gd"
## Regression coverage for supported recovery and death while rising.

func prepare_ramp(degrees: float) -> void:
	p.set_physics_process(false)
	if is_instance_valid(fixtures):
		fixtures.queue_free()
		await settle(2)
	fixtures = Node3D.new()
	stage.add_child(fixtures)
	# Long enough that a tumbling ragdoll must recover on the incline itself.
	var ramp := Shapes.solid(fixtures,Vector3(30,0.5,100),Vector3(0,8,0),Color.GRAY)
	ramp.rotation.x = deg_to_rad(degrees)
	var surface_y := 8.0+0.25/cos(deg_to_rad(degrees))
	p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,surface_y+1.0,0)))
	p.set_physics_process(true)
	await physics_steps(6)

func physics_steps(frames: int) -> void:
	# Each completed owner tick is one sample, even when several physics ticks
	# share a render frame. Waiting for process_frame changes the hit pose/time.
	for frame in frames: await p.simulation_stepped

func wait_recovery(rate: int) -> bool:
	var began_get_up := false
	for frame in rate*15:
		await physics_steps(1)
		began_get_up = began_get_up or p.reactions.getting_up
		if not p.reactions.active: break
	if p.reactions.active:
		print("RECOVERY WAIT: position=",p.position," velocity=",p.reactions.driver.torso.linear_velocity," angular=",p.reactions.driver.torso.angular_velocity," contact=",p.reactions.driver.contact()," settle_time=",p.reactions.settle_time," dead=",p.dead," getting_up=",p.reactions.getting_up," location=",p.motor.ragdoll_recovery_location(p.reactions.driver.anchor(),p.reactions.driver.collision_exclusions))
	return began_get_up and not p.reactions.active

func check_slope_clearance(degrees: float) -> void:
	await prepare_ramp(degrees)
	p.set_physics_process(false)
	p.motor.acquire_ragdoll()
	var anchor := Vector3(0,8.0+0.25/cos(deg_to_rad(degrees))+0.7,0)
	var exclusions: Array[RID] = [p.get_rid()]
	var place: Dictionary = p.motor.ragdoll_recovery_location(anchor,exclusions)
	check(not place.is_empty(),"%.0f degree supported slope has a clear standing location" % degrees)
	var ceiling := Shapes.solid(fixtures,Vector3(30,0.2,100),Vector3(0,9.8,0),Color.GRAY)
	ceiling.rotation.x = deg_to_rad(degrees)
	await settle(3)
	check(p.motor.ragdoll_recovery_location(anchor,exclusions).is_empty(),"%.0f degree slope still rejects insufficient standing headroom" % degrees)
	ceiling.collision_layer = 4
	await settle(2)
	check(p.motor.ragdoll_recovery_location(anchor,exclusions).is_empty(),"%.0f degree recovery keeps the controlled enemy collision mask" % degrees)
	ceiling.collision_layer = 8
	await settle(2)
	check(not p.motor.ragdoll_recovery_location(anchor,exclusions).is_empty(),"%.0f degree recovery ignores layers outside the controlled mask" % degrees)
	ceiling.queue_free()
	await settle(2)
	check(not p.motor.ragdoll_recovery_location(anchor,exclusions).is_empty(),"%.0f degree slope becomes recoverable when its ceiling is removed" % degrees)
	p.motor.release_ragdoll()

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for degrees: float in [30,40]:
			await prepare_ramp(degrees)
			check(p.velocity.y < 0 and p.take_damage(1,"slope_hit") and p.reactions.active,"%s Hz / %.0f degrees: falling hit starts physical reaction" % [rate,degrees])
			check(await wait_recovery(rate),"%s Hz / %.0f degrees: living ragdoll completes physical get-up" % [rate,degrees])
			await settle(6)
			check(not p.dead and p.is_on_floor() and p.state == p.State.FREE and not p.motor.ragdoll_motion,"%s Hz / %.0f degrees: grounded control returns" % [rate,degrees])
			check(p.get_floor_normal().y < 0.90,"%s Hz / %.0f degrees: recovery remains on the incline" % [rate,degrees])
		await prepare()
		check(await ActionTest.start(p,"jump"),"%s Hz: nonlethal ascending-hit setup" % rate)
		await settle(5)
		check(p.velocity.y > 0 and p.take_damage(1,"nonlethal_ascent") and not p.reactions.active and not p.dead,"%s Hz: nonlethal ascent retains ordinary hurt behavior" % rate)
		await settle(rate*2)
		check(p.is_on_floor() and p.state == p.State.FREE,"%s Hz: ordinary rising hurt still lands and restores control" % rate)
		await prepare()
		check(await ActionTest.start(p,"jump"),"%s Hz: lethal ascending-hit setup" % rate)
		await settle(5)
		check(p.velocity.y > 0 and p.take_damage(999,"lethal_ascent") and p.dead and p.reactions.active and p.reactions.lethal,"%s Hz: fatal ascending hit transfers to lethal ragdoll" % rate)
		var anchor: Vector3 = p.reactions.driver.anchor()
		await settle(rate*3)
		check(p.reactions.driver.anchor().distance_to(anchor) > 0.2 and p.reactions.driver.contact(),"%s Hz: airborne corpse moves and contacts the floor" % rate)
		check(p.reactions.active and not p.reactions.getting_up and p.actions.active_definition == null,"%s Hz: corpse remains physical without recovering or owning an action" % rate)
	Engine.physics_ticks_per_second = 60
	for degrees: float in [0,30,40,44]:
		await check_slope_clearance(degrees)
	# Exercise blocked recovery through the real reaction state machine as well.
	await prepare(Vector3(0,3,0))
	check(p.take_damage(1,"ceiling_hit") and p.reactions.active,"Ceiling fixture starts physical reaction")
	await settle(40)
	var ceiling := Shapes.solid(fixtures,Vector3(30,0.2,30),Vector3(0,1.5,0),Color.GRAY)
	await settle(240)
	if p.crawling.available():
		check(not p.reactions.active and p.crawling.active and not p.motor.ragdoll_motion,"Low ceiling hands control to the validated crawling posture")
	else:
		check(p.reactions.active and not p.reactions.getting_up,"Unsupported crawl profile retains physical ownership beneath roof")
	ceiling.queue_free()
	await settle(2)
	if p.crawling.available():
		check(p.crawling.active and await ActionTest.start(p,"crouch") and await ActionTest.start(p,"crouch"),"Removing the ceiling keeps crawl until deliberate safe exit")
	else:
		check(await wait_recovery(60),"Removing the ceiling allows physical recovery")
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await settle(2)
	print("RECOVERY REGRESSIONS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
