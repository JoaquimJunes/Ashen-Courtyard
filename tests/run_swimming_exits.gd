extends SceneTree
const Stage = preload("res://tests/fixtures/swim_stage.gd")
var checks := 0
var failures := 0
var stage: Stage

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func approach() -> void:
	stage.intent.movement = Vector3.FORWARD
	stage.intent.swim_direction = Vector3.FORWARD
	stage.intent.surface_motion = Vector2(0,1)

func run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	current_scene = stage
	var p: CharacterBody3D = stage.player
	var old_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await stage.reset_at(Vector3(3,-1.1,-6))
		approach()
		await stage.tick(2.5)
		check(not p.swimming.active and p.movement.attachment == null and p.position.y > 0.39 and p.position.z < -8,"%s: automatic swim-to-ledge pull-up (at %s, %s / %s)" % [rate,p.position,p.traversal.status,p.traversal.reason])
		check(not p.motor.swimming_posture and p.motor.capsule.height == p.motor.standing_height,"%s: standing collision restored after exit" % rate)
		await stage.reset_at(Vector3(3,-1.1,-6.7))
		p.stamina = 0
		p.stamina_wait = 2
		approach()
		await stage.tick(0.8)
		check(p.swimming.active and p.movement.attachment == null,"%s: insufficient stamina stays swimming" % rate)
		p.stamina_wait = 0
		await stage.tick(2.2)
		check(not p.swimming.active and p.position.y > 0.39,"%s: recovered stamina allows exit" % rate)
		var roof := Shapes.solid(stage,Vector3(4,0.2,4),Vector3(3,1.6,-9),Color.GRAY)
		await stage.reset_at(Vector3(3,-1.1,-6))
		approach()
		await stage.tick(1)
		check(p.swimming.active and p.movement.attachment == null,"%s: blocked standing destination rejects grab" % rate)
		roof.free()
		await stage.reset_at(Vector3(3,-1.1,-6.7))
		approach()
		stage.intent.swim_vertical = -1
		await stage.tick(0.5)
		check(p.swimming.underwater and p.movement.attachment == null,"%s: diving input suppresses ledge grab" % rate)
		await stage.reset_at(Vector3(3,-1.1,-6.7))
		approach()
		for index in rate:
			await stage.tick(1.0/rate)
			if p.movement.attachment != null: break
		check(p.movement.attachment != null,"%s: attachment acquired" % rate)
		stage.intent.movement = Vector3.ZERO
		stage.intent.swim_direction = Vector3.ZERO
		stage.intent.surface_motion = Vector2.ZERO
		p.traversal.release(&"test_release")
		await stage.tick(0.5)
		check(p.swimming.active and p.movement.attachment == null and not p.reactions.active,"%s: releasing a grip returns to water" % rate)
		await stage.reset_at(Vector3(3,-1.1,-6.7))
		approach()
		for index in rate:
			await stage.tick(1.0/rate)
			if p.movement.attachment != null: break
		stage.ledge.position.x += 30
		await stage.tick(0.4)
		check(p.movement.attachment == null and p.swimming.active,"%s: lost ledge safely releases into water" % rate)
		stage.ledge.position.x -= 30
	Engine.physics_ticks_per_second = old_rate
	stage.queue_free()
	await process_frame
	print("SWIMMING EXITS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
