extends "res://tests/fixtures/dodge_stage.gd"
## Retain the useful floor-clearance and continuity checks from the retired hop suite.
func lowest_skin() -> float:
	return p.position.y+p.model.dodge_skin_min_height()
func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	p.combat_enabled = false
	stage.add_child(p)
	for direction: Vector3 in [Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT,Vector3.BACK]:
		await prepare()
		p.controller.intent.movement = direction
		await ActionTest.start(p,"dodge")
		p.controller.intent.movement = Vector3.ZERO
		var lowest := INF
		var worst_change := 0.0
		var previous: Array[Quaternion] = []
		for frame in 75:
			await settle(1)
			lowest = minf(lowest,lowest_skin())
			for bone in p.model.skeleton.get_bone_count():
				var rotation: Quaternion = p.model.skeleton.get_bone_pose_rotation(bone)
				if previous.size() <= bone: previous.append(rotation)
				else:
					worst_change = maxf(worst_change,previous[bone].angle_to(rotation))
					previous[bone] = rotation
		check(lowest >= -0.04,"%s armor stays above the floor through entry/recovery (%.4f m)" % [direction,lowest])
		check(worst_change < 1.3,"%s poses remain continuous (maximum %.1f degrees/frame)" % [direction,rad_to_deg(worst_change)])
	print("DODGE POSES: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
