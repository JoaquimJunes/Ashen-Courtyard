extends "res://tests/run_mantle.gd"
const SkinProbe = preload("res://tests/fixtures/skin_probe.gd")
const IK = preload("res://features/presentation/limb_ik.gd")

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var original := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for inside in [false,true]:
			await start_grab()
			var boxes: Array[AABB] = [AABB(Vector3(-2,0,-2),Vector3(4,1.5,2))]
			if inside:
				Shapes.solid(fixtures,Vector3(1,1.5,4),Vector3(2.5,0.75,1),Color.GRAY)
				boxes.append(AABB(Vector3(2,0,-1),Vector3(1,1.5,4)))
			await settle(2)
			var clipping := 0.0
			var hand_error := 0.0
			p.controller.intent.surface_motion = Vector2.RIGHT
			for frame in rate*6:
				await settle(1)
				p.pose_driver.evaluate(1.0/rate)
				if frame%3==0:
					var depth := SkinProbe.penetration(p.model.skeleton,boxes)
					if depth>clipping:
						clipping=depth
					var visual: RefCounted = p.presentation.mantle
					for i in 2:
						var bone := "Hand.l" if i==0 else "Hand.r"
						hand_error = maxf(hand_error,IK.position(visual.skeleton,visual.bones[bone]).distance_to(visual.shimmy.hands[i]))
				if absf(p.traversal.candidate.normal.x)>.999: break
			check(absf(p.traversal.candidate.normal.x)>.999,"Pose sequence completes the corner")
			check(clipping<0.05,"%s Hz / inside %s: armor clearance (%.3f m)" % [rate,inside,clipping])
			check(hand_error<0.055,"%s Hz / inside %s: hand transfers stay reachable (%.3f m)" % [rate,inside,hand_error])
	Engine.physics_ticks_per_second = original
	stage.queue_free()
	await settle(2)
	print("SHIMMY POSES: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
