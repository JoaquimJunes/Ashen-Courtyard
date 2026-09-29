extends "res://tests/run_mantle.gd"
const IK = preload("res://features/presentation/limb_ik.gd")

func until_phase(phase: int) -> bool:
	p.controller.intent.surface_motion = Vector2(0,1)
	for frame in 120:
		await settle(1)
		if p.traversal.status == &"mantle" and p.traversal.mantle.phase == phase: return true
	return false

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	for phase in 4:
		check(await start_grab(),"Prepare phase %s reset" % phase)
		check(await until_phase(phase),"Reach pull-up phase %s" % phase)
		p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(6,0.04,0)))
		p.controller.intent.movement = Vector3.ZERO
		p.controller.intent.surface_motion = Vector2.ZERO
		await settle(4)
		check(not p.traversal.attached() and not p.motor.tucked and not p.presentation.mantle.active and p.actions.active_definition == null and p.stamina == 100,"Reset clears phase, attachment, posture, pose and costs")
	check(await start_grab(),"Prepare pause")
	var position := p.position
	var stamina: float = p.stamina
	paused = true
	for i in 8: await process_frame
	check(p.position == position and p.stamina == stamina and p.traversal.status == &"hang","Pause freezes supported hang")
	paused = false
	await settle(2)
	# Camera orbit and either shoulder cannot change wall-facing or input meaning.
	var input := preload("res://features/character/input_controller.gd").new()
	Input.action_press("forward")
	for yaw: float in [0.0,PI/2,PI]:
		check(input.sample(yaw).surface_motion.y > 0.99,"Forward surface intent remains forward while camera rotates")
	Input.action_release("forward")
	var heading := p.rotation.y
	for yaw: float in [0.0,PI/2,PI,-PI/2]:
		p.yaw = yaw
		await settle(2)
		check(is_equal_approx(p.rotation.y,heading) and p.position.distance_to(position)<0.002,"Camera orbit preserves grip and body facing")
	var lock_target := Combatant.new()
	stage.add_child(lock_target)
	lock_target.position = p.position+Vector3(8,0,0)
	p.target = lock_target
	p.locked = true
	for running in [false,true]:
		p.controller.intent.sprint = running
		p.controller.intent.movement = Vector3.RIGHT
		await settle(20)
		check(p.locked and is_equal_approx(p.rotation.y,heading) and p.position.distance_to(position)<0.002,"Target lock and running intent preserve attached wall-facing")
	p.controller.intent.sprint = false
	p.controller.intent.movement = Vector3.ZERO
	p.target = null
	p.locked = false
	lock_target.queue_free()
	p.pose_driver.evaluate(1.0/60)
	var visual: RefCounted = p.presentation.mantle
	for side in ["l","r"]:
		var hand: Vector3 = p.traversal.candidate.left_hand if side == "l" else p.traversal.candidate.right_hand
		var error := IK.position(visual.skeleton,visual.bones["Hand."+side]).distance_to(hand)
		check(error < 0.025,"Hanging hand %s matches geometry (%.3f m)" % [side,error])
	# The same read-only Resources must never share posture or runtime state.
	var second: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	second.controller.manual = true
	stage.add_child(second)
	second.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(6,0.04,0)))
	await settle(4)
	check(second.traversal.definition == p.traversal.definition and second.traversal.candidate == null and second.movement.attachment == null,"Definitions shared; candidates/attachments per character")
	check(not second.motor.tucked and is_equal_approx(second.motor.capsule.height,1.8) and second.stamina == 100,"Hanging does not shrink or charge second actor")
	second.queue_free()
	var candidate: RefCounted = p.traversal.candidate
	var surface: Node3D = candidate.surfaces[0].get_ref()
	surface.position.x += 1
	await settle(2)
	check(not p.traversal.attached() and p.velocity.y < 0,"Moving held static surface releases into gravity")
	check(await start_grab(),"Prepare deleted surface")
	candidate = p.traversal.candidate
	surface = candidate.surfaces[0].get_ref()
	surface.queue_free()
	await settle(3)
	check(not p.traversal.attached() and not p.movement.ledge_jump and p.velocity.y < 0,"Deleting support releases without automatic recatch")
	check(await start_grab(),"Prepare unexpected path obstacle")
	check(await until_phase(0),"Begin committed lift")
	Shapes.solid(fixtures,Vector3(4,0.12,1.2),Vector3(0,2.1,0.6),Color.GRAY)
	await settle(40)
	check(not p.traversal.attached() and p.position.z > 0 and p.actions.active_definition == null,"Obstacle inserted during lift cannot be crossed or leave ownership stuck")
	check(await start_grab(),"Prepare death/unload")
	var pending: RefCounted = p.request_action(&"dodge")
	p.take_damage(1000,"fatal_grip")
	await settle(1)
	check(p.dead and p.reactions.active and not p.traversal.attached() and pending.resolved,"Lethal attached hit releases and resolves pending let-go")
	check(await start_grab(),"Prepare unloading held character")
	var modes: RefCounted = p.movement
	var feature: RefCounted = p.traversal
	var actions: RefCounted = p.actions
	p.queue_free()
	await settle(2)
	check(modes.attachment == null and feature.candidate == null and actions.active_definition == null,"Unloading releases all attachment/action ownership")
	# A compact shape can land with its raised feet below the logical root.
	# Standing restoration must use the real support, not remain permanently tucked.
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	await prepare()
	p.set_physics_process(false)
	p.motor.set_posture(1.0,0.85,false)
	var roof := Shapes.solid(fixtures,Vector3(3,0.2,3),Vector3(0,1.5,0),Color.GRAY)
	await settle(2)
	p.set_physics_process(true)
	await settle(30)
	check(p.motor.tucked and p.is_on_floor(),"Blocked standing retains compact collision on actual support")
	roof.queue_free()
	await settle(8)
	check(not p.motor.tucked and p.position.y >= -0.01 and p.is_on_floor(),"Standing restoration rebases feet from tucked support after clearance returns")
	stage.queue_free()
	await settle(2)
	# Actual laboratory menu path supplies only geometry and ordinary reset placement.
	var lab: Node3D = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	p = lab.player
	p.controller.manual = true
	for index in 4:
		lab.start_ledge_test(index)
		await settle(8)
		check(lab.active_station == 4 and p.is_on_floor() and not p.combat_enabled,"Ledge course %s starts grounded with normal lab policy" % index)
		p.controller.intent.movement = Vector3.FORWARD
		p.controller.intent.surface_motion = Vector2(0,1)
		await ActionTest.start(p,"jump")
		await settle(130)
		if index < 2: check(p.position.y > 1.4 and p.traversal.reason == &"completed","Real lab fixture permits pull-up")
		elif index == 2: check(p.traversal.status == &"hang" and p.stamina == 85,"Real lab ceiling blocks paid pull-up but permits hanging")
		else: check(not p.traversal.attached(),"Excluded lab geometry cannot be grabbed")
		p.controller.intent.movement = Vector3.ZERO
		p.controller.intent.surface_motion = Vector2.ZERO
		lab.reset_station()
		await settle(4)
		check(not p.traversal.attached() and not p.motor.tucked and p.stamina == 100,"Lab reset clears traversal")
	lab.queue_free()
	await settle(2)
	print("LEDGE LIFECYCLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
