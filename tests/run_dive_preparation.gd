extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
## Anatomical preparation constraints, measured in world space on the real actor.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)
func tick() -> void:
	await physics_frame
	await process_frame
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	Shapes.solid(stage,Vector3(30,0.2,30),Vector3(0,-0.1,0),Color.GRAY)
	var player = load("res://scenes/player.tscn").instantiate()
	player.combat_enabled = false
	player.controller.manual = true
	stage.add_child(player)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for heading in [0.0,PI/2,PI,-PI/2]:
			player.reset_for_lab(Transform3D(Basis(Vector3.UP,heading),Vector3(0,0.02,0)))
			for i in 6: await tick()
			var measurement := {"smallest":INF,"drift":0.0,"samples":0}
			var sample := func():
				var skeleton: Skeleton3D = player.model.skeleton
				for side in ["l","r"]:
					var hip: Vector3 = player.model.locomotion.world_position(skeleton,player.model.rig.bone(skeleton,"UpperLeg."+side))
					var knee: Vector3 = player.model.locomotion.world_position(skeleton,player.model.rig.bone(skeleton,"LowerLeg."+side))
					var ankle: Vector3 = player.model.locomotion.world_position(skeleton,player.model.rig.bone(skeleton,"Foot."+side))
					var axis := (ankle-hip).normalized()
					var bend := knee-hip-axis*(knee-hip).dot(axis)
					measurement.smallest = minf(measurement.smallest,bend.dot(-player.global_basis.z))
					measurement.drift = maxf(measurement.drift,ankle.distance_to(player.forward_dive.pose.feet[side]))
				measurement.samples += 1
			# Capture the committed entry pose before that tick's first preparation step.
			player.actions.started.connect(func(_id: StringName): sample.call(),CONNECT_ONE_SHOT)
			await ActionTest.start(player,"dodge")
			while player.forward_dive.active and player.forward_dive.phase == 0 and measurement.samples < rate:
				sample.call()
				await tick()
			check(measurement.samples >= 3 and measurement.smallest > 0,"%s Hz / %.0f degrees: both knees stay forward throughout preparation (%.4f m)" % [rate,rad_to_deg(heading),measurement.smallest])
			check(measurement.drift < 0.04,"%s Hz / %.0f degrees: supported feet remain planted (%.4f m)" % [rate,rad_to_deg(heading),measurement.drift])
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await tick()
	print("DIVE PREPARATION: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
