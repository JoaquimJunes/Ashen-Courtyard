extends SceneTree
## Tests the contract through real collision and an unrelated character composition.
const Probe = preload("res://tests/fixtures/motion_probe.gd")
const Definition = preload("res://features/abilities/ability_definition.gd")
const Motion = preload("res://features/character/motion_request.gd")
var checks := 0
var failures := 0
var stage: Node3D
var a: Probe
var b: Probe
var samples: Array[Dictionary] = []
var recording := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
	await process_frame
func record() -> void:
	if recording:
		samples.append({"air":not a.is_on_floor(),"vx":a.velocity.x,
			"budget":a.actions.travel.remaining,"active":a.actions.active_definition != null,
			"request":a.actions.motion.kind,"time":a.actions.timer})
func fresh(at: Vector3 = Vector3(-0.5,12.02,0)) -> void:
	recording = false
	a.actions.brake = false
	a.actions.request_until = INF
	a.actions.distance = 1.0
	a.reset(at)
	await tick(8)
	samples.clear()
	recording = true
func until_air() -> void:
	for i in Engine.physics_ticks_per_second:
		await tick()
		if not a.is_on_floor(): return
	check(false,"Probe leaves the platform")
func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	Shapes.solid(stage,Vector3(100,1,100),Vector3(0,-0.5,0),Color.GRAY)
	Shapes.solid(stage,Vector3(4,12,30),Vector3(-2,6,0),Color.GRAY)
	a = Probe.new()
	b = Probe.new()
	var definition := Definition.new()
	definition.id = &"motion_probe"
	definition.combat_action = false
	definition.stamina_cost = 25
	definition.active_seconds = 3.0
	a.actions.definition = definition
	b.actions.definition = definition
	stage.add_child(a)
	stage.add_child(b)
	b.reset(Vector3(-1,12.02,10))
	a.stepped.connect(record)
	await tick(8)
	check(a.actions.definition == b.actions.definition and a.actions.travel != b.actions.travel and a.simulation.resolver != b.simulation.resolver,"Shared definitions have independent motion owners and budgets")
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for policy in [Motion.AirPolicy.INHERIT,Motion.AirPolicy.RETAIN_DEPARTURE,Motion.AirPolicy.DIRECTED]:
			# Configure test data only before an attempt. Production Resources remain read-only.
			definition.airborne_motion = policy
			definition.active_seconds = 3.0
			await fresh()
			a.intent.action = &"probe"
			await until_air()
			await tick(int(rate*0.7))
			var expected := 7.0 if policy == Motion.AirPolicy.DIRECTED else 4.0
			var consistent := true
			var exhausted := false
			for sample in samples:
				if sample.air and sample.budget == 0:
					exhausted = true
					consistent = consistent and absf(sample.vx-expected) < 0.001
			check(exhausted and consistent and not a.is_on_floor(),"%s Hz policy %s: exhausted ground travel never stops an airborne character" % [rate,policy])
			check(a.resources.stamina == 75 and b.resources.stamina == 100 and b.actions.travel.remaining == 0,"An unrelated NPC uses atomic costs without affecting a second instance")
			var before := a.velocity.x
			a.actions.cancel(&"interrupted")
			await tick()
			check(absf(a.velocity.x-before) < 0.001 and a.actions.motion.kind == Motion.Kind.INHERIT and not a.simulation.resolver.has_retained,"Cancellation releases ownership but preserves physical air momentum")
		# No request during recovery and natural action completion must both inherit.
		definition.airborne_motion = Motion.AirPolicy.RETAIN_DEPARTURE
		definition.active_seconds = 0.55
		await fresh()
		a.actions.distance = 100.0
		a.actions.request_until = 0.35
		a.intent.action = &"probe"
		await tick(int(rate*0.9))
		var saw_recovery := false
		var saw_finished := false
		var momentum_ok := true
		for sample in samples:
			if sample.air and sample.request == Motion.Kind.INHERIT:
				saw_recovery = saw_recovery or sample.active
				saw_finished = saw_finished or not sample.active
				momentum_ok = momentum_ok and absf(sample.vx-4.0) < 0.001
		check(saw_recovery and saw_finished and momentum_ok and a.actions.active_definition == null,"%s Hz: ending the active window or the action cannot zero momentum" % rate)
		# Explicit braking is a distinct request, not an accidental absent override.
		definition.active_seconds = 3.0
		await fresh()
		a.intent.action = &"probe"
		await until_air()
		a.actions.brake = true
		a.actions.travel.reset(100)
		var before := a.velocity.x
		await tick(3)
		check(a.velocity.x < before and a.velocity.x >= 0,"%s Hz: intentional air braking still works" % rate)
		# Blocked requested travel is spent; a removed wall cannot bank ground motion.
		await fresh(Vector3(10,0.02,0))
		var wall := Shapes.solid(stage,Vector3(0.3,5,6),Vector3(10.55,2.5,0),Color.GRAY)
		await tick(2)
		a.intent.action = &"probe"
		await tick(int(rate*0.4))
		check(a.position.x < 10.2 and a.actions.travel.remaining == 0,"%s Hz: solid wall consumes the requested ground budget" % rate)
		wall.queue_free()
		await tick(2)
		var blocked_at := a.position
		await tick(int(rate*0.25))
		check(a.position.distance_to(blocked_at) < 0.002,"Removing a ground wall cannot release banked action travel")
	# Landing can replace ownership during a step. Replacement time starts at zero.
	Engine.physics_ticks_per_second = 60
	await fresh()
	a.intent.action = &"probe"
	a.movement.landed.connect(replace_on_contact,CONNECT_ONE_SHOT)
	await until_air()
	for i in 150:
		await tick()
		if a.is_on_floor(): break
	check(a.is_on_floor() and a.actions.contact_delta == 0 and a.actions.timer == 0,"Contact-started action receives no motion/playback time from its predecessor")
	# Reset and teleport clear retained policy state, even without a new action.
	await fresh()
	a.intent.action = &"probe"
	await until_air()
	check(a.simulation.resolver.has_retained,"Departure policy has live per-instance state")
	a.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(15,3,0)))
	check(not a.simulation.resolver.has_retained and a.velocity == Vector3.ZERO,"Teleport clears the stored departure vector")
	a.reset(Vector3(15,0.02,0))
	check(a.actions.travel.remaining == 0 and a.actions.active_definition == null and a.resources.stamina == 100,"Reset releases requests, travel and costs together")
	# A launch while floor contact is cached must select airborne physics immediately.
	await tick(8)
	a.motor.move_velocity = Vector3.RIGHT*4
	a.motor.launch(5)
	await tick()
	check(a.position.y > 0.02 and absf(a.velocity.x-4) < 0.001 and a.simulation.resolver.last_airborne,"Launch invalidates cached floor contact without player-specific states")
	# Retained references make cleanup observable after the owning body is gone.
	await fresh()
	a.intent.action = &"probe"
	await until_air()
	var owner = a.actions
	var resolver = a.simulation.resolver
	var weak_sim: WeakRef = weakref(a.simulation)
	a.queue_free()
	recording = false
	await tick(2)
	check(owner.active_definition == null and owner.travel.remaining == 0 and not resolver.has_retained,"Unload releases action and retained-motion ownership")
	owner = null
	resolver = null
	check(weak_sim.get_ref() == null,"Simulation and named signal handlers do not create reference cycles")
	var bypasses: Array[String] = []
	find_motion_bypasses("res://features",bypasses)
	find_motion_bypasses("res://scripts",bypasses)
	check(bypasses.is_empty(),"Production movement obeys the shared simulation/motor boundary: %s" % str(bypasses))
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await tick(2)
	print("MOTION CONTRACT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)

func replace_on_contact(_speed: float) -> void:
	a.actions.cancel(&"contact")
	a.actions.request("probe")
	a.actions.tick()

func find_motion_bypasses(path: String, found: Array[String]) -> void:
	for directory in DirAccess.get_directories_at(path):
		find_motion_bypasses(path.path_join(directory),found)
	for file in DirAccess.get_files_at(path):
		if not file.ends_with(".gd"): continue
		var full := path.path_join(file)
		if file in ["character_motor.gd","character_simulation.gd"]: continue
		var source := FileAccess.get_file_as_string(full)
		if "request_horizontal(" in source or "motor.step(" in source or "move_and_slide(" in source:
			found.append(full)
