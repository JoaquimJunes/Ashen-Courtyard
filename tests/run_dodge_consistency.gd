extends SceneTree
## Compare actual motion and action timelines across all three character hosts.
const Driver = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var player: CharacterBody3D
var recording := false
var samples: Array[Dictionary] = []
var origin := Vector3.ZERO
var baseline: Dictionary = {}
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame
func sample(delta: float) -> void:
	if not recording: return
	samples.append({"delta":delta,"at":player.position-origin,"phase":player.dodge_phase,
		"action":player.state,"immune":player.invulnerable,"roll":player.dodge_ground_time})
	if player.state != player.State.DODGE: recording = false
func run() -> void:
	var old_rate := Engine.physics_ticks_per_second
	var directions := [Vector3.ZERO,Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT,Vector3.BACK,
		Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(-1,0,1),Vector3(1,0,1)]
	for path in ["arena","movement_lab","dodge_preview"]:
		var world = load("res://scenes/"+path+".tscn").instantiate()
		root.add_child(world)
		current_scene = world
		# Identical collision conditions isolate host configuration from scene geometry.
		# Actual courtyard/lab surfaces remain covered by their integration suites.
		Shapes.solid(world,Vector3(30,0.2,30),Vector3(0,19.9,-2),Color.GRAY)
		player = world.body if path == "dodge_preview" else world.player
		if path == "arena":
			world.boss.frozen = true
			world.boss.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(10,0,-10)))
		elif path == "dodge_preview":
			# Drive requests ourselves; normal preview replay controls have their own suite.
			world.playing = false
			player.simulation_stepped.disconnect(world.after_character_step)
		player.controller.manual = true
		player.simulation_stepped.connect(sample)
		for rate in [30,60,120]:
			Engine.physics_ticks_per_second = rate
			for direction: Vector3 in directions:
				player.controller.intent.movement = Vector3.ZERO
				player.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,20.02,-2)))
				player.set_physics_process(true)
				await tick(8)
				origin = player.position
				samples.clear()
				recording = true
				player.controller.intent.movement = direction
				var accepted := await Driver.start(player,&"dodge")
				player.controller.intent.movement = Vector3.ZERO
				var forward := direction == Vector3.ZERO or (direction.z < 0 and absf(direction.z) >= absf(direction.x))
				var expected: Resource = player.tuning.dodge_forward if forward else player.tuning.dodge_ground
				var label := "%s / %s Hz / %s" % [path,rate,direction]
				check(accepted and player.actions.active_definition == expected and is_equal_approx(player.stamina,100-expected.stamina_cost),"Shared selection and single cost: "+label)
				for i in rate*3:
					if not recording: break
					await tick()
				check(not recording and player.state == player.State.FREE and player.actions.active_definition == null,"Recovery releases ownership: "+label)
				var distance: float = samples.back().at.length()
				check(absf(distance-expected.distance) < 0.025,"Shared unobstructed reach: "+label)
				var key := "%s/%s" % [rate,direction]
				if path == "arena": baseline[key] = samples.duplicate(true)
				else:
					var previous: Array = baseline[key]
					var equal := samples.size() == previous.size()
					var differences: Array[String] = []
					for i in mini(samples.size(),previous.size()):
						var a: Dictionary = samples[i]
						var b: Dictionary = previous[i]
						var matching: bool = a.at.distance_to(b.at) < 0.025 and a.phase == b.phase and a.action == b.action and a.immune == b.immune and absf(a.roll-b.roll) < 0.00001
						if not matching and differences.size() < 3: differences.append("tick %s: %s vs %s" % [i,a,b])
						equal = equal and matching
					if not equal: print("Trace lengths %s/%s; %s" % [samples.size(),previous.size(),differences])
					check(equal,"Motion, phases and immunity match courtyard tick for tick: "+label)
		world.queue_free()
		await tick(2)
	Engine.physics_ticks_per_second = old_rate
	print("DODGE CONSISTENCY: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
