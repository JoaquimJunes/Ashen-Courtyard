extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
const ActionTest = preload("res://tests/action_test_driver.gd")
const Water = preload("res://features/swimming/water_volume.gd")
var checks := 0
var failures := 0
var world: Node3D
var p: CharacterBody3D
var intent: RefCounted
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
	await tick(0.3)
func run() -> void:
	world = load("res://scenes/arena.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.boss.set_physics_process(false)
	world.boss.position = Vector3(15,0,-10)
	p = world.player
	# Exercise character death/reset without the encounter host disabling physics.
	for connection in p.died.get_connections():
		if connection.callable.get_object() == world: p.died.disconnect(connection.callable)
	var other: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	other.controller.manual = true
	world.add_child(other)
	other.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(6,0.05,6)))
	await reset_at(Vector3(0,0.05,6))
	var saved_binding: int = GameInput.bindings.crouch
	GameInput.bindings.crouch = KEY_V
	GameInput.apply()
	p.controller.manual = false
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	Input.parse_input_event(key)
	await tick(0.2)
	check(p.posture.crouched and not p.crawling.active,"Remapped physical press crouches before the hold threshold")
	await tick(0.4)
	check(p.crawling.active,"Remapped physical hold enters crawling")
	key = InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = false
	Input.parse_input_event(key)
	await tick(0.1)
	check(p.crawling.active,"Remapped physical release preserves crawl")
	GameInput.bindings.crouch = saved_binding
	GameInput.apply()
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await reset_at(Vector3(0,0.05,6))
		check(await ActionTest.start(p,"crawl"),"Enter crawl through shared action lifecycle")
		await tick(0.4)
		check(not other.crawling.active and is_equal_approx(other.motor.capsule.height,1.8),"Independent character keeps own stance and collider")
		intent.movement = Vector3(1,0,-1)
		await tick(0.5)
		check(absf(Vector2(p.velocity.x,p.velocity.z).length()-1) < 0.03,"Diagonal input is normalized")
		intent.movement = Vector3.ZERO
		await tick(0.3)
		var stopped := p.position
		await tick(0.3)
		check(p.position.distance_to(stopped) < 0.005,"Releasing movement stops at current location")
		# A narrow enclosure permits the original posture but not a ninety-degree turn.
		var wall: StaticBody3D = Shapes.solid(world,Vector3(0.1,2,4),p.position+Vector3(0.6,1,0),Color.GRAY)
		await tick(0.1)
		var yaw: float = p.rotation.y
		p.motor.face_direction(Vector3.RIGHT)
		check(is_equal_approx(yaw,p.rotation.y),"Blocked yaw retains safe collider and model orientation")
		wall.free()
		check(p.take_damage(1,"crawl_hurt_%s" % rate) and p.state == p.State.HURT and p.crawling.active and not p.reactions.active,"Grounded hit keeps crawl collider during ordinary hurt")
		await tick(0.5)
		check(p.crawling.active and p.actions.is_available(),"Hurt recovers into crawl")
		# Mouth-based breath remains active outside swimming locomotion.
		var shallow := Water.new()
		shallow.size = Vector3(8,1,8)
		shallow.show_surface = false
		world.add_child(shallow)
		shallow.position = Vector3(p.position.x,0.84,p.position.z)
		await tick(1)
		check(p.crawling.active and not p.swimming.active and p.swimming.head_detector.head_submerged and p.resources.breath < 19.2,"Crawling mouth in shallow water consumes breath without swimming")
		p.resources.breath = 0
		var health: float = p.health
		await tick(1.1)
		check(p.health < health and p.crawling.active and not p.reactions.active,"Drowning keeps prone posture without stagger/ragdoll")
		shallow.free()
		await tick(3.1)
		check(is_equal_approx(p.resources.breath,20) and not p.swimming.head_detector.head_submerged,"Water removal clears immersion and refills breath")
		p.controller.stance_down = true
		p.controller.stance_started_lowered = true
		p.controller.stance_time = 0.2
		root.get_node("GameSession").set_paused(true)
		check(p.controller.stance_rearm,"Pause cancels an incomplete hold/tap")
		root.get_node("GameSession").set_paused(false)
		await tick(0.1)
		check(p.crawling.active,"Release swallowed by pause does not raise the player")
		# Teleports clear persistent geometry and source playback without resource reset.
		p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.05,6)))
		await tick(0.2)
		check(not p.crawling.active and not p.motor.crawling_posture and p.presentation.crawl.clock == 0,"Teleport clears crawl and restores ordinary collision")
		# A falling crawl uses gravity and landing damage, never forced standing.
		var platform := Shapes.solid(world,Vector3(3,0.2,3),Vector3(0,6.9,6),Color.GRAY)
		await reset_at(Vector3(0,7.05,6))
		await ActionTest.start(p,"crawl")
		platform.free()
		await tick(1.2)
		check(p.landing.last_height > 5 and p.health < p.max_health,"%s Hz falling crawl retains normal damaging impact (height=%s health=%s y=%s)" % [rate,p.landing.last_height,p.health,p.position.y])
		await reset_at(Vector3(0,0.05,6))
		await ActionTest.start(p,"crawl")
		await tick(0.3)
		# Validate the low recovery candidate independently of nondeterministic physics settling.
		var roof := Shapes.solid(world,Vector3(6,0.2,6),Vector3(0,1.0,6),Color.GRAY)
		p.reactions.begin(false,false)
		await tick(0.2)
		var place: Dictionary = p.motor.ragdoll_crawl_location(Vector3(0,0.5,6),p.crawling.definition,p.reactions.driver.collision_exclusions)
		check(not place.is_empty(),"Low roof has a safe crawl recovery destination")
		for index in rate*8:
			await physics_frame
			if not p.reactions.active: break
		await process_frame
		check(not p.reactions.active and p.crawling.active and p.motor.crawling_posture,"Living ragdoll recovers into crawl when standing is blocked")
		roof.free()
		await reset_at(Vector3(0,0.05,6))
		await ActionTest.start(p,"crawl")
		check(p.take_damage(p.max_health,"crawl_death_%s" % rate) and p.dead,"Death follows shared damage path")
		await reset_at(Vector3(0,0.05,6))
		check(not p.dead and not p.crawling.active and not p.motor.crawling_posture,"Reset after death restores standing control")
	other.free()
	world.free()
	await process_frame
	# Deep-water entry supersedes crawl and leaves only swimming geometry active.
	world = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	p = world.player
	world.go_to_station(5)
	await reset_at(world.stations[5].global_position+Vector3(0,0.05,13))
	await ActionTest.start(p,"crawl")
	var water := Water.new()
	water.size = Vector3(6,5,6)
	water.show_surface = false
	world.add_child(water)
	water.global_position = p.global_position+Vector3.UP*2.5
	await tick(0.5)
	check(p.swimming.active and not p.crawling.active and not p.motor.crawling_posture,"Water entry releases crawl posture, playback and equipment ownership: "+p.motor.posture_obstruction)
	world.free()
	await process_frame
	print("CRAWL LIFECYCLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
