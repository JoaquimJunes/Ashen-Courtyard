extends SceneTree
## Actual collision steps verify slope adhesion without extending airborne support.
const Motor = preload("res://features/character/character_motor.gd")
var checks := 0
var failures := 0
var world: Node3D
var actor: CharacterBody3D
var motor: Motor
var delta := 1.0/60.0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func tick(velocity: Vector3, can_step: bool = true) -> void:
	await physics_frame
	motor.request_horizontal(velocity)
	motor.step(delta, 24.0, can_step)

func prepare(z: float = -5.0) -> void:
	var surface_y := 10.0+0.25/cos(deg_to_rad(30))-z*tan(deg_to_rad(30))
	motor.teleport(Transform3D(Basis.IDENTITY, Vector3(0, surface_y+0.08, z)))
	for frame in 15: await tick(Vector3.ZERO)
	check(actor.is_on_floor(), "Fixture settles on the 30-degree slope")

func verify_rate(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	delta = 1.0/rate
	for heading in [0.0, 30.0]:
		await prepare()
		var grounded := true
		var finite := true
		var restored := true
		var peak_gap := 0.0
		var velocity := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(heading))*6.5
		for frame in rate*2:
			await tick(velocity)
			grounded = grounded and actor.is_on_floor()
			finite = finite and actor.global_transform.is_finite() and actor.velocity.is_finite()
			restored = restored and is_equal_approx(actor.floor_snap_length, 0.1)
			var plane_y := 10.0+0.25/cos(deg_to_rad(30))-actor.position.z*tan(deg_to_rad(30))
			peak_gap = maxf(peak_gap, absf(actor.position.y-plane_y-motor.support_clearance(Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(30)))))
		var label := "%s Hz heading %.0f" % [rate, heading]
		check(grounded, label + ": downhill sprint retains every floor contact")
		check(finite and peak_gap < 0.04, label + ": stays within collision/contact tolerance of the support plane (%.4f m)" % peak_gap)
		check(restored, label + ": temporary slope support never changes the configured floor snap")
	await prepare()
	motor.request_horizontal(Vector3.BACK*6.5)
	check(is_equal_approx(motor.locomotion_snap_length(delta, false), actor.floor_snap_length), "%s Hz: committed dodge/action motion cannot extend support" % rate)
	var before := actor.position
	motor.launch(8.0)
	var launched := false
	for frame in maxi(2, rate/5):
		await tick(Vector3.BACK*6.5)
		launched = launched or not actor.is_on_floor()
	check(launched and actor.position.y > before.y+0.4, "%s Hz: an intentional jump detaches from the descending slope" % rate)
	check(is_equal_approx(motor.locomotion_snap_length(delta, true), actor.floor_snap_length), "%s Hz: airborne movement keeps the normal snap distance" % rate)
	await prepare(15.0)
	var left := false
	var recaptured := false
	var departed_y := 0.0
	for frame in rate*2:
		await tick(Vector3.BACK*6.5)
		if not actor.is_on_floor() and not left:
			left = true
			departed_y = actor.position.y
		elif left and actor.is_on_floor(): recaptured = true
	check(left and not recaptured and actor.position.y < departed_y-0.5, "%s Hz: sprinting off the ramp enters an uninterrupted cliff fall" % rate)
	check(actor.position.z > 21.0 and actor.velocity.z > 6.4, "%s Hz: departure retains horizontal momentum over the gap" % rate)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var ramp := Shapes.solid(world, Vector3(20, 0.5, 40), Vector3(0, 10, 0), Color.GRAY)
	ramp.rotation.x = deg_to_rad(30)
	actor = CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 7
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	actor.add_child(collision)
	world.add_child(actor)
	motor = Motor.new()
	motor.configure(actor, CombatTuning.new(), capsule)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30, 60, 120]: await verify_rate(rate)
	Engine.physics_ticks_per_second = original_rate
	world.free()
	print("DOWNHILL SUPPORT RESULT: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)
