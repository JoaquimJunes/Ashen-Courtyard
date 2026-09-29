extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
const ActionTest = preload("res://tests/action_test_driver.gd")
const Controller = preload("res://features/character/input_controller.gd")
var checks := 0
var failures := 0
var world: Node3D
var p: CharacterBody3D
var intent: RefCounted
var origin := Vector3.ZERO
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func tick(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed+0.00001 < seconds: elapsed += float(await p.simulation_stepped)
	await process_frame
func reset_at(point: Vector3) -> void:
	intent = Intent.new()
	p.submit_intent(intent)
	p.reset_for_lab(Transform3D(Basis.IDENTITY,point))
	await tick(0.25)
func enter() -> void:
	intent.crouch_held = true
	await tick(0.2)
	check(p.posture.crouched and not p.crawling.active,"Press immediately crouches, without early crawling")
	await tick(0.4)
	intent.crouch_held = false
	await tick(0.3)
	check(p.crawling.active and p.motor.crawling_posture,"Half-second hold enters persistent crawl: "+String(p.crawling.last_reason)+" / "+p.motor.posture_obstruction)
func tap() -> void:
	intent.crouch_held = true
	await tick(0.05)
	intent.crouch_held = false
	await tick(0.3)
func run() -> void:
	world = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	p = world.player
	world.go_to_station(3)
	origin = world.stations[3].global_position+Vector3(-6,0,0)
	var clip: Animation = p.model.animation.get_animation("crawling/crawl")
	check(clip != null and is_equal_approx(clip.length,1.8) and clip.get_track_count() == 195,"Approved 1.8s retarget is installed with all 65 bone tracks")
	check(clip.get_meta("original_sha256") == FileAccess.get_sha256("res://assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx"),"Provenance matches untouched downloaded FBX")
	check(not p.model.animation_profile.is_native("crawling/crawl"),"Retargeted Mixamo clip is not mislabelled native UAL")
	check(clip.get_meta("retarget_correction","") == "attached_shoulders_v1","Runtime uses the fitted shoulder retarget")
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		var dt: float = 1.0/rate
		var input := Controller.new()
		for frame in int(rate*0.5)-1:
			check(input.tick_stance(true,dt,frame > 0,0.5) != "crawl","%s Hz: hold cannot enter before 0.5s" % rate)
		check(input.tick_stance(true,dt,true,0.5) == "crawl","%s Hz: crawl begins at exactly 0.5s" % rate)
		check(input.tick_stance(false,dt,true,0.5) == "","Release after hold keeps crawl")
		await reset_at(origin+Vector3(0,0.05,8))
		# Reproduce the sub-millimetre resting penetration seen with rendered physics.
		p.position.y = origin.y-0.0005
		check(await ActionTest.start(p,"crawl"),"Solver floor contact cannot prevent entering crawl")
		await tick(0.3)
		p.position.y = origin.y-0.0005
		p.motor.face_direction(Vector3.RIGHT)
		check((-p.global_basis.z).dot(Vector3.RIGHT) > 0.99,"Solver floor contact cannot prevent a clear crawl turn")
		for shoulder in [-1,1]:
			CameraPreferences.set_value("side",shoulder)
			await reset_at(origin+Vector3(0,0.05,6.5))
			await enter()
			check(p.model.equipment.current_sockets.get(&"sword") == &"left_hip" and not p.locked,"Crawl stows equipment and unlocks")
			p.stamina = 40
			p.resources.stamina_wait = 0
			intent.movement = Vector3.FORWARD
			await tick(3)
			check(absf(p.velocity.length()-1.0) < 0.05,"%s Hz crawl speed 1m/s (%s)" % [rate,p.velocity])
			check(p.stamina > 40,"Crawling regenerates stamina")
			intent.movement = Vector3.ZERO
			await tick(0.3)
			check(p.position.z-origin.z < 4.0,"Enters 0.90m tunnel")
			await tap()
			check(p.crawling.active and not p.posture.crouched,"Rising beneath roof is rejected")
			intent.sprint = true
			for action in ["jump","dodge","light","heavy","cast","heal","use_gadget","ledge_grab"]:
				var before := Vector3(p.stamina,p.mana,p.flasks)
				var result = p.actions.request(action,true)
				check(result.resolved and not result.accepted and result.reason == &"crawling" and before == Vector3(p.stamina,p.mana,p.flasks),"Crawl rejects "+action+" without cost or buffer")
			intent.movement = Vector3.FORWARD
			await tick(11)
			check(p.position.z-origin.z < -7,"%s/%s full tunnel with floor/ceiling variations: %s" % [rate,shoulder,p.position-origin])
			check(not p.sprinting,"Sprint never exits crawl")
			intent.movement = Vector3.BACK
			await tick(16)
			intent.movement = Vector3.ZERO
			intent.sprint = false
			await tick(0.3)
			check(p.position.z-origin.z > 5.5,"Full reverse crossing")
			await tap()
			check(not p.crawling.active and p.posture.crouched,"Tap exits to crouch")
			await tap()
			check(not p.posture.crouched and not p.motor.crawling_posture and is_equal_approx(p.motor.capsule.radius,p.motor.standing_radius),"Second tap restores standing capsule")
			check(p.model.equipment.current_sockets.get(&"sword") == &"right_hand","Equipment restored after exit")
		await reset_at(origin+Vector3(0,0.05,8))
		await enter()
		# Inspect every animation phase, and ensure render interpolation does not advance it.
		for phase in 55:
			p.presentation.crawl.clock = float(phase)/30
			await tick(dt)
			var high: float = -p.model.dodge_skin_min_height(Vector3.DOWN)
			check(high < 0.865 and p.model.dodge_skin_min_height() > -0.015,"%s Hz phase %s silhouette below crawl clearance (%.3f)" % [rate,phase,high])
			for side in ["l","r"]:
				var skeleton: Skeleton3D = p.model.skeleton
				var clavicle := skeleton.find_bone("clavicle_"+side)
				var upper := skeleton.find_bone("upperarm_"+side)
				var chest := skeleton.get_bone_global_pose(skeleton.get_bone_parent(clavicle))
				var socket := chest*skeleton.get_bone_rest(clavicle)*skeleton.get_bone_pose_position(upper)
				var shoulder := skeleton.get_bone_global_pose(upper).origin
				check(socket.distance_to(shoulder) < 0.003,"%s Hz phase %s %s shoulder stays connected to torso" % [rate,phase,side])
			if phase % 27 == 0:
				var cache: RefCounted = p.model.skin_contacts
				cache.update_palette(p.motor.shape_node.global_transform.affine_inverse()*p.model.skeleton.global_transform)
				var outside := 0.0
				for vertex in cache.geometry.vertices.size():
					var point: Vector3 = cache.point(vertex)
					point.y -= clampf(point.y,-p.motor.capsule.height*0.5+p.motor.capsule.radius,p.motor.capsule.height*0.5-p.motor.capsule.radius)
					outside = maxf(outside,point.length()-p.motor.capsule.radius)
				check(outside < 0.035,"Body silhouette fits prone capsule (maximum protrusion %.3f)" % outside)
			var time: float = p.presentation.crawl.clock
			var pose: Array = p.presentation.capture_pose()
			p.pose_driver.display(0.3)
			p.hitboxes.capture()
			check(pose == p.presentation.capture_pose() and time == p.presentation.crawl.clock,"Rendering and fitted sensing do not resample crawl")
		var paused_time: float = p.presentation.crawl.clock
		paused = true
		for i in 5: await process_frame
		check(p.presentation.crawl.clock == paused_time,"Pause freezes crawling")
		paused = false
		p.reset_for_lab(Transform3D(Basis.IDENTITY,origin+Vector3(0,0.05,8)))
		check(not p.crawling.active and not p.motor.crawling_posture and p.presentation.crawl.clock == 0,"Reset clears crawl state, collision and presentation")
		await reset_at(origin+Vector3(12,0.05,6.5))
		await enter()
		intent.movement = Vector3.FORWARD
		await tick(4)
		check(p.position.z-origin.z > 4,"0.80m passage safely blocks entry")
		var blocked := p.position
		intent.movement = Vector3.BACK
		await tick(1)
		check(p.position.z > blocked.z+0.7,"Blocked passage allows retreat")
	world.free()
	await process_frame
	print("CRAWLING: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
