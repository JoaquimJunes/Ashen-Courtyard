extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
var checks := 0
var failures := 0
var lab: Node3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func tick(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func run() -> void:
	lab = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await tick(6)
	lab.go_to_station(5)
	var station: Node3D = lab.stations[5]
	var water: Area3D = station.fixtures.get_node("SwimmingPool")
	check(water != null and station.fixtures.get_node_or_null("RecoveryVolume") == null,"Swimming station has water instead of entry reset")
	var p: CharacterBody3D = lab.player
	var intent := Intent.new()
	p.submit_intent(intent)
	p.reset_for_lab(Transform3D(Basis.IDENTITY,station.to_global(Vector3(10,-3,4))))
	var resets: int = lab.reset_count
	await tick(20)
	check(p.swimming.active and lab.reset_count == resets,"Deep pool stays playable below the former reset surface")
	intent.swim_vertical = 1
	await tick(110)
	check(not p.swimming.underwater and p.global_position.y > -1.2,"Pool ascent returns to surface")
	intent.swim_vertical = 0
	intent.movement = Vector3.FORWARD
	intent.swim_direction = Vector3.FORWARD
	intent.surface_motion = Vector2(0,1)
	p.reset_for_lab(Transform3D(Basis.IDENTITY,station.to_global(Vector3(10,-1.1,-6))))
	await tick(160)
	check(not p.swimming.active and p.is_on_floor(),"Existing dock provides a safe automatic ledge exit")
	var ramp := Shapes.solid(lab,Vector3(4,0.3,8),station.to_global(Vector3(4,-0.7,3)),Color.GRAY)
	ramp.rotation.x = -0.20
	intent.movement = Vector3.FORWARD
	intent.swim_direction = Vector3.FORWARD
	p.reset_for_lab(Transform3D(Basis.IDENTITY,station.to_global(Vector3(4,-1.1,6.5))))
	await tick(120)
	check(not p.swimming.active and p.is_on_floor(),"Sloped shallow shore restores walking (position %s)" % p.position)
	ramp.queue_free()
	lab.go_to_station(0)
	await tick(8)
	check(not p.swimming.active and p.resources.breath == 20 and not p.motor.swimming_posture,"Station switch clears swimming and breath state")
	lab.queue_free()
	await process_frame
	print("SWIMMING LAB: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
