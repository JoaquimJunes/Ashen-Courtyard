extends "res://tests/run_mantle.gd"
## Real jumps against translated geometry; low lips must never acquire a hang.

func attempt(height: float, elevation: float = 0.0) -> Dictionary:
	p.controller.intent.movement = Vector3.ZERO
	p.controller.intent.surface_motion = Vector2.ZERO
	await prepare(Vector3(0,0.04,0.5))
	wall(height)
	fixtures.position.y = elevation
	p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,elevation+0.04,0.5)))
	await settle(10)
	var start_y: float = p.position.y
	p.controller.intent.movement = Vector3.FORWARD
	var started: bool = await ActionTest.start(p,"jump")
	var origin_recorded: bool = absf(p.movement.jump_origin_y-start_y) < 0.001
	var rejected_low := false
	var attached := false
	for frame in Engine.physics_ticks_per_second*2:
		await settle(1)
		rejected_low = rejected_low or p.traversal.reason == &"within_jump_height"
		attached = attached or p.traversal.attached()
		if p.traversal.status == &"hang" or (p.is_on_floor() and not attached): break
	return {"started":started,"origin_recorded":origin_recorded,"attached":attached,"rejected_low":rejected_low}

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for elevation: float in [0,7]:
			for height: float in [0.8,1.2,1.25,1.5]:
				var result := await attempt(height,elevation)
				var label := "%s Hz / %.2f m wall / %.1f m base" % [rate,height,elevation]
				check(result.started and result.origin_recorded,"%s: takeoff records feet height before movement" % label)
				check(result.attached == (height>1.2),"%s: only above-jump ledges acquire attachment" % label)
				if height <= 1.2:
					check(result.rejected_low,"%s: reachable low grip is rejected by height policy" % label)
	# Request validation must also reject a directly submitted low candidate.
	Engine.physics_ticks_per_second = 60
	await attempt(1.2)
	p.set_physics_process(false)
	p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.4,0.5)))
	var candidate: RefCounted = p.traversal.probe.find(Vector3.FORWARD,1.0/60)
	p.traversal.candidate = candidate
	check(candidate != null and p.traversal.requirement("ledge_grab") == &"within_jump_height","Direct requests cannot bypass the low-ledge entry rule")
	# The threshold follows the shared authored jump definition, not a copied constant.
	var original_tuning: Resource = p.tuning
	p.tuning = original_tuning.duplicate()
	p.tuning.jump = original_tuning.jump.duplicate()
	p.tuning.jump.height = 1.6
	p.actions.tuning = p.tuning
	var retuned := await attempt(1.5)
	check(retuned.started and not retuned.attached and retuned.rejected_low,"A taller authored jump also skips a 1.5 m lip")
	p.tuning = original_tuning
	p.actions.tuning = original_tuning
	p.reset_for_lab(Transform3D.IDENTITY)
	check(p.movement.jump_origin_y == 0 and not p.movement.ledge_jump,"Lab reset clears the per-jump reference")
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await settle(2)
	print("LEDGE HEIGHT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
