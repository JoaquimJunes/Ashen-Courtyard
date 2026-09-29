extends SceneTree
## The production enemy must obey the same airborne continuity contract.
const Intent = preload("res://features/character/character_intent.gd")
const Driver = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var enemy: CharacterBody3D
var samples: Array[Dictionary] = []
var recording := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick(count: int = 1) -> void:
	for i in count: await physics_frame
	await process_frame
func record() -> void:
	if recording:
		samples.append({"air":not enemy.is_on_floor(),"velocity":enemy.velocity,
			"phase":enemy.actions.phase,"active":enemy.actions.active_definition != null})
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	Shapes.solid(stage,Vector3(100,1,40),Vector3(0,-0.5,0),Color.GRAY)
	Shapes.solid(stage,Vector3(4,100,8),Vector3(-2,50,0),Color.GRAY)
	enemy = load("res://scenes/boss.tscn").instantiate()
	enemy.controller.manual = true
	stage.add_child(enemy)
	physics_frame.connect(record)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		recording = false
		enemy.controller.manual = true
		enemy.actions.cancel(&"test_reset")
		enemy.motor.teleport(Transform3D(Basis(Vector3.UP,-PI/2),Vector3(-0.6,100.02,0)))
		enemy.movement.reset()
		var intent := Intent.new()
		intent.facing = Vector3.RIGHT
		enemy.submit_intent(intent)
		await tick(8)
		check(enemy.is_on_floor(),"%s Hz: production Warden starts supported" % rate)
		samples.clear()
		recording = true
		check(await Driver.start(enemy,&"boss_lunge"),"Production lunge starts through the common lifecycle")
		await tick(int(rate*3.4))
		var recovery_seen := false
		var finished_seen := false
		var constant_momentum := true
		var speed: float = enemy.tuning.combat.boss_lunge.lunge_speed
		for sample in samples:
			if not sample.air: continue
			var horizontal: Vector3 = Vector3(sample.velocity.x,0,sample.velocity.z)
			constant_momentum = constant_momentum and horizontal.distance_to(Vector3.RIGHT*speed) < 0.001
			recovery_seen = recovery_seen or sample.phase == enemy.actions.Phase.RECOVERY
			finished_seen = finished_seen or not sample.active
		check(recovery_seen and finished_seen and constant_momentum,"%s Hz: lunge, recovery and action completion preserve the same air velocity" % rate)
		check(not enemy.is_on_floor() and enemy.actions.active_definition == null and enemy.position.x > 20,"Warden keeps moving after the lunge's active window and commitment finish")
		enemy.controller.manual = false
		var downward: float = enemy.velocity.y
		await tick(2)
		check(absf(enemy.velocity.x-speed) < 0.001 and enemy.velocity.y < downward,"Losing an AI target produces idle input while momentum and gravity continue")
		# A collision-resolved stop must transfer as zero, never resurrect the lunge.
		var wall := Shapes.solid(stage,Vector3(0.3,120,8),Vector3(enemy.position.x+1,60,0),Color.GRAY)
		await tick(int(rate*0.15))
		check(absf(enemy.velocity.x) < 0.001 and enemy.motor.move_velocity.length() < 0.001,"A wall changes physical momentum after ownership has been released")
		wall.queue_free()
		await tick(2)
		var at := enemy.position.x
		await tick(int(rate*0.1))
		check(absf(enemy.position.x-at) < 0.001,"Removing the wall cannot revive a finished enemy lunge")
	recording = false
	physics_frame.disconnect(record)
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await tick(2)
	print("BOSS MOTION: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
