extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
const ActionTest = preload("res://tests/action_test_driver.gd")
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
	check(await ActionTest.start(p,"crouch"),"Enter crouch")
	await tick(0.3)
func fit(label: String) -> void:
	check(-p.model.dodge_skin_min_height(Vector3.DOWN) < 0.962,label+": visible silhouette fits capsule height")
	check(p.model.dodge_skin_min_height() > -0.035,label+": feet remain above ground")
	var snapshot: Array = p.presentation.capture_pose()
	p.hitboxes.capture()
	check(snapshot == p.presentation.capture_pose(),label+": fitted sensing never changes pose")
func run() -> void:
	world = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	p = world.player
	world.go_to_station(3)
	var station: Node3D = world.stations[3]
	var origin: Vector3 = station.global_position+Vector3(-12,0,0)
	# Nominal 1m roof has both a 2cm floor step and a separate 2cm ceiling dip.
	var bump := Shapes.solid(station,Vector3(2.8,0.02,1.2),Vector3(-12,0.01,-1),Color.GRAY)
	var dip := Shapes.solid(station,Vector3(2.8,0.02,1.2),Vector3(-12,0.99,-3.5),Color.GRAY)
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for shoulder in [-1,1]:
			CameraPreferences.set_value("side",shoulder)
			await reset_at(origin+Vector3(0,0.05,6.5))
			fit("%s/%s idle" % [rate,shoulder])
			intent.movement = Vector3.FORWARD
			await tick(3.2)
			intent.movement = Vector3.ZERO
			await tick(0.3)
			check(p.position.z-origin.z < 1,"%s/%s: reach tunnel middle" % [rate,shoulder])
			check(not (await ActionTest.start(p,"crouch")) and p.posture.crouched,"Stand inside tunnel safely rejected")
			intent.sprint = true
			intent.movement = Vector3.FORWARD
			await tick(0.5)
			check(p.posture.crouched and not p.sprinting and p.velocity.length() > 1.9,"Blocked sprint remains movable at crouch speed")
			fit("%s/%s walking" % [rate,shoulder])
			intent.sprint = false
			intent.movement = Vector3.BACK
			await tick(0.55)
			check(p.velocity.z > 1.9,"Turn and reverse while beneath roof")
			intent.movement = Vector3.FORWARD
			await tick(4.5)
			check(p.position.z-origin.z < -7,"%s/%s: entire 1m tunnel and both 0.98m variations crossed" % [rate,shoulder])
			intent.movement = Vector3.BACK
			await tick(8.5)
			intent.movement = Vector3.ZERO
			await tick(0.3)
			check(p.position.z-origin.z > 5.5,"%s/%s: full reverse crossing" % [rate,shoulder])
			check(await ActionTest.start(p,"crouch"),"Exit then stand restores standing collision")
	bump.free()
	dip.free()
	# Crouching alone cannot enter a smaller passage; crawling requires a hold.
	var blocker := Shapes.solid(station,Vector3(3,0.2,5),Vector3(-12,0.95,0),Color.GRAY)
	await reset_at(origin+Vector3(0,0.05,6.5))
	intent.movement = Vector3.FORWARD
	await tick(3.2)
	check(p.position.z-origin.z > 2.5,"0.85m tunnel blocks entry")
	var blocked: Vector3 = p.position
	intent.movement = Vector3.BACK
	await tick(1.0)
	check(p.position.z > blocked.z+1.2,"Undersized passage allows safe retreat")
	blocker.free()
	world.free()
	await process_frame
	print("TUNNEL CLEARANCE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
