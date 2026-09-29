extends SceneTree
const Intent = preload("res://features/character/character_intent.gd")
const Driver = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var actor: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	Shapes.solid(stage,Vector3(100,0.2,100),Vector3(0,-0.1,0),Color.GRAY)
	GameInput.configure()
	actor = load("res://scenes/player.tscn").instantiate()
	actor.controller.manual = true
	stage.add_child(actor)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for direction: Vector3 in [Vector3.FORWARD,Vector3.RIGHT]:
			for heading in [direction,direction*3,direction*3+Vector3.UP*4]:
				actor.submit_intent(Intent.new())
				actor.reset_for_lab(Transform3D.IDENTITY)
				await tick(4)
				actor.controller.intent.movement = heading
				var start: Vector3 = actor.position
				await Driver.start(actor,&"dodge")
				actor.controller.intent.movement = Vector3.ZERO
				for i in rate*3:
					await tick()
					if actor.state == actor.State.FREE: break
				var forward := direction == Vector3.FORWARD
				var expected := 5.5 if forward else 4.34
				var distance := (actor.position-start).dot(direction)
				check(absf(distance-expected) < 0.06,"%s Hz %s dodge input %s keeps %.2f m reach (%.3f)" % [rate,"forward dive" if forward else "ground roll",heading,expected,distance])
		actor.submit_intent(Intent.new())
		actor.reset_for_lab(Transform3D.IDENTITY)
		await tick(4)
		actor.controller.intent.movement = Vector3(3,4,-3)
		actor.controller.intent.sprint = true
		await tick(rate/2)
		check(absf(Vector2(actor.velocity.x,actor.velocity.z).length()-6.5) < 0.01 and is_zero_approx(actor.move_velocity.y),"%s Hz ground intent remains horizontal at sprint speed" % rate)
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await process_frame
	print("MOVEMENT INPUT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
