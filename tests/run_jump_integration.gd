extends "res://tests/fixtures/dodge_stage.gd"

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	for direction: Vector3 in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3(1,0,1),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(-1,0,-1)]:
		await prepare()
		p.move_velocity = direction.normalized()*4
		await ActionTest.start(p,"jump")
		await settle(12)
		check(Vector3(p.velocity.x,0,p.velocity.z).distance_to(direction.normalized()*4) < 0.001,"Jump preserves momentum in %s direction" % direction)
		p.pose_driver.evaluate(1.0/60)
		check(p.model.dodge_skin_min_height() >= 0.015,"Retargeted armor stays above capsule bottom")
	await prepare()
	var second: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	second.controller.manual = true
	stage.add_child(second)
	second.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(8,0.05,0)))
	await settle(8)
	check(second.tuning.jump == p.tuning.jump and second.landing.definition == p.landing.definition,"Two characters share read-only jump and landing definitions")
	await ActionTest.start(p,"jump")
	check(second.stamina == 100 and second.state == second.State.FREE and not second.movement.jump_consumed,"Second character does not share jump state or costs")
	second.queue_free()
	await settle(2)
	var executor: RefCounted = p.actions
	var ticket: RefCounted = p.actions.request("jump",true)
	p.queue_free()
	await settle(2)
	check(executor.active_definition == null and ticket.resolved and not ticket.accepted,"Unloading clears airborne ownership and pending result")
	stage.queue_free()
	await settle(2)
	# Actual lab policy: the same player, safe fixture selection and repeated resets.
	var lab: Node3D = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	p = lab.player
	p.controller.manual = true
	for height in [2.5,4.5,8.0,16.0]:
		lab.start_fall_test(height)
		await settle(8)
		check(lab.active_station == 2 and absf(p.position.y-height) < 0.02 and p.is_on_floor(),"Lab drop fixture %.1f m has a grounded start" % height)
		check(p.health == p.max_health and p.stamina == 100 and p.actions.active_definition == null,"Selecting a drop resets resources and ownership")
		lab.reset_station()
		await settle(8)
		check(p.position.y < 0.1 and p.is_on_floor() and not p.movement.jump_consumed,"Station reset restores entrance and jump eligibility")
	lab.go_to_station(0)
	await settle(8)
	check(await ActionTest.start(p,"jump"),"Jump works with laboratory combat disabled")
	lab.hud.menu.open_menu("Settings")
	lab.hud.menu.settings.select("Controls")
	check(lab.hud.keybindings.widgets.jump.text == GameInput.key("jump"),"Shared Controls panel includes the active Jump binding")
	lab.hud.menu.close_menu()
	lab.start_fall_test(3.0,true)
	await settle(8)
	p.controller.intent.movement = Vector3.FORWARD
	for frame in 120:
		if p.reactions.active: break
		await settle(1)
	check(p.reactions.active and p.health == 95 and not lab.test_hit_pending,"Drop + hit tool uses accepted descending damage and the shared reaction")
	lab.reset_station()
	await settle(8)
	check(not p.reactions.active and not p.motor.ragdoll_motion and not p.combat_enabled,"Lab reset clears drop-hit reaction and temporary combat test permission")
	print("JUMP INTEGRATION: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
