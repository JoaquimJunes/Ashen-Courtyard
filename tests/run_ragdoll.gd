extends "res://tests/fixtures/dodge_stage.gd"
var impacts := 0

func start_fall(height: float) -> void:
	p.controller.intent.movement = Vector3.ZERO
	await prepare()
	p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,height,0)))
	await settle(6)
	impacts = 0

func wait_recovery(rate: int) -> bool:
	for frame in rate*8:
		if not p.reactions.active: return true
		await settle(1)
	return false

func joint_settings(driver: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for bone: PhysicalBone3D in driver.bones:
		var properties := {"type":bone.joint_type,"offset":bone.joint_offset,"body":bone.body_offset}
		for property in bone.get_property_list():
			if str(property.name).begins_with("joint_constraints/"):
				properties[property.name] = bone.get(property.name)
		result.append(properties)
	return result

func same_joint_settings(before: Array[Dictionary], after: Array[Dictionary]) -> bool:
	if before.size() != after.size(): return false
	for index in before.size():
		if before[index].size() != after[index].size(): return false
		for property in before[index]:
			var left: Variant = before[index][property]
			var right: Variant = after[index].get(property)
			# The engine exposes angular settings in degrees but stores radians.
			if left is float and right is float:
				if not is_equal_approx(left,right): return false
			elif left != right: return false
	return true

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	p.landing.landed.connect(func(_severity,_height,_damage): impacts += 1)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await start_fall(3)
		var location := p.position
		var constraints := joint_settings(p.reactions.driver)
		check(p.take_damage(5,"falling_hit"),"%s Hz descending hit accepted" % rate)
		check(same_joint_settings(constraints,joint_settings(p.reactions.driver)),"Animation handoff preserves joint types, offsets and all authored constraint settings")
		var aligned := true
		for body: PhysicalBone3D in p.reactions.driver.bones:
			var expected: Transform3D = (p.model.skeleton.global_transform*p.model.skeleton.get_bone_global_pose(body.get_bone_id())*body.body_offset).orthonormalized()
			aligned = aligned and body.global_transform.is_equal_approx(expected)
		check(aligned,"Rebinding physical constraints preserves the incoming animated body transforms")
		check(p.reactions.active and p.state == p.State.RAGDOLL and p.motor.ragdoll_motion,"Descending hit transfers physical authority and action ownership")
		check(p.reactions.driver.bones.size() == 10 and p.reactions.driver.simulator.is_simulating_physics(),"Ten physical bodies simulate the knight")
		await settle(1)
		check(p.position.distance_to(location) < 0.2,"Ragdoll handover does not teleport the camera anchor")
		var ticket: RefCounted = p.actions.request("jump",true)
		check(ticket.resolved and not ticket.accepted and p.actions.buffered.is_empty(),"No buffered actions leak through ragdoll/get-up")
		check(await wait_recovery(rate),"Surviving ragdoll settles and automatically gets up")
		await settle(8)
		check(p.is_on_floor() and p.state == p.State.FREE and p.collision_layer == 2 and p.collision_mask == 7 and not p.model.top_level,"Recovery restores collision, presentation and grounded control")
		check(p.actions.active_definition == null and not p.motor.ragdoll_motion and not p.reactions.driver.simulator.is_simulating_physics(),"Recovery releases reaction and physical ownership")
		check(impacts == 1 and p.health == 95,"Safe ragdoll landing counts once, without extra damage (events=%s, health=%s)" % [impacts,p.health])
		check(await ActionTest.start(p,"jump"),"Jump works after physical recovery")
	# Rising and grounded hits keep ordinary hurt behavior.
	await prepare()
	await ActionTest.start(p,"jump")
	check(p.velocity.y > 0 and p.take_damage(1,"rising_hit") and not p.reactions.active,"Rising hit does not ragdoll")
	await prepare()
	check(p.take_damage(1,"ground_hit") and not p.reactions.active,"Grounded hit does not ragdoll")
	# Lethal ordinary landing, and a hit followed by a damaging physical landing.
	Engine.physics_ticks_per_second = 60
	await start_fall(16)
	for frame in 120:
		if p.dead: break
		await settle(1)
	check(p.dead and p.reactions.active and p.reactions.lethal,"Lethal landing activates ragdoll")
	await settle(180)
	check(p.reactions.active and not p.reactions.getting_up and p.actions.active_definition == null,"Dead ragdoll never gets up and releases action ownership")
	await start_fall(8)
	p.take_damage(5,"high_hit")
	await wait_recovery(60)
	check(not p.dead and p.health < 95 and impacts == 1,"Airborne ragdoll still receives one shared fall-damage event")
	# It stays vulnerable: each bone delegates to the same damage receiver/token.
	await start_fall(3)
	p.take_damage(5,"ragdoll_vulnerable")
	var bone: PhysicalBone3D = p.reactions.driver.torso
	var receiver := preload("res://features/combat/damage_receiver.gd").resolve(bone)
	check(receiver == p,"Physical bone explicitly resolves to its character receiver")
	var other: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	other.controller.manual = true
	stage.add_child(other)
	other.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(8,0.05,0)))
	check(other.reactions.definition == p.reactions.definition and other.reactions.driver.torso != bone and not other.reactions.active and not other.reactions.driver.simulator.is_simulating_physics(),"Shared rig definition creates independent per-character physics bodies")
	other.queue_free()
	var damage = preload("res://features/combat/damage_request.gd").new(5,&"bone_hit")
	check(receiver.receive_damage(damage) and not receiver.receive_damage(damage) and p.health == 90,"Ragdoll damage uses normal strike deduplication")
	paused = true
	var at := bone.global_transform
	var clock: float = p.reactions.settle_time
	for frame in 8: await process_frame
	check(bone.global_transform == at and p.reactions.settle_time == clock,"Pause freezes ragdoll physics and recovery clock")
	paused = false
	await wait_recovery(60)
	# Standing clearance is checked before handing control back to the capsule.
	await start_fall(3)
	p.take_damage(5,"low_ceiling")
	await settle(40)
	var ceiling := Shapes.solid(fixtures,Vector3(25,0.3,25),Vector3(0,1.45,0),Color.GRAY)
	await settle(200)
	if p.crawling.available():
		check(not p.reactions.active and p.crawling.active and p.motor.crawling_posture,"Low ceiling recovers safely into crawl instead of a standing get-up")
	else:
		check(p.reactions.active and not p.reactions.getting_up,"Profile without crawl retains physical recovery under low ceiling")
	ceiling.queue_free()
	await settle(2)
	if p.crawling.available():
		var was_crawling: bool = p.crawling.active
		var to_crouch = await ActionTest.result(p,"crouch")
		var to_stand = await ActionTest.result(p,"crouch")
		check(was_crawling and to_crouch.accepted and to_stand.accepted,"Clearing headroom permits deliberate crawl/crouch/stand exit: %s / %s / %s" % [to_crouch.reason,to_stand.reason,p.motor.posture_obstruction])
	else:
		check(await wait_recovery(60),"Clearing headroom allows automatic get-up")
	await start_fall(3)
	p.take_damage(5,"support_loss")
	for frame in 240:
		if p.reactions.getting_up: break
		await settle(1)
	check(p.reactions.getting_up,"Recovery starts after settling")
	fixtures.get_child(0).position.y -= 2
	await settle(3)
	check(p.reactions.active and not p.reactions.getting_up and p.motor.ragdoll_motion,"Losing support during get-up returns to physical falling")
	check(await wait_recovery(60),"A lower safe landing can recover after interrupted get-up")
	await start_fall(3)
	p.take_damage(5,"getup_death")
	for frame in 240:
		if p.reactions.getting_up: break
		await settle(1)
	p.take_damage(999,"fatal_getup_hit")
	await settle(3)
	check(p.dead and p.reactions.active and not p.reactions.getting_up,"Lethal damage during get-up returns to dead ragdoll")
	check(p.camera_anchor(1.45).y >= 0.39,"Prone camera pivot remains above nearby floor")
	# Reset at each phase; subsequent use gets a fresh rig, not stale velocities.
	for iteration in 3:
		await start_fall(3)
		p.take_damage(5,"repeat_hit")
		await settle(10)
		p.reset_for_lab(Transform3D.IDENTITY)
		var stopped := true
		for body: PhysicalBone3D in p.reactions.driver.bones:
			stopped = stopped and body.collision_layer == 0 and not body.is_simulating_physics()
		check(stopped and not p.reactions.active and not p.motor.ragdoll_motion and p.actions.active_definition == null and p.health == 100,"Repeated reset releases all physical and action ownership")
	await start_fall(3)
	p.take_damage(5,"unload_hit")
	var driver: RefCounted = p.reactions.driver
	p.queue_free()
	await settle(2)
	check(not driver.active,"Unloading stops physical simulation")
	Engine.physics_ticks_per_second = original_rate
	print("RAGDOLL: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
