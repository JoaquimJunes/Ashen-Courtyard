extends "res://tests/run_mantle.gd"
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
		check(await start_grab(),"Prepare real pose sequence")
		p.controller.intent.surface_motion = Vector2(0,1)
		var worst_hand := 0.0
		var max_penetration := 0.0
		var samples: Array[Dictionary] = []
		for frame in rate*3:
			await settle(1)
			p.pose_driver.evaluate(1.0/rate)
			var visual: RefCounted = p.presentation.mantle
			var skeleton: Skeleton3D = p.model.skeleton
			var record := {"frame":frame,"status":p.traversal.status,"phase":p.traversal.mantle.phase}
			for part in ["Body","UpperArm.l","LowerArm.l","Hand.l","UpperLeg.l","LowerLeg.l","Foot.l"]:
				record[part] = IK.position(skeleton,p.model.rig.bone(skeleton,part))
			if p.traversal.attached() and p.traversal.mantle.phase == 0:
				for side in ["l","r"]:
					var hand: Vector3 = p.traversal.candidate.left_hand if side == "l" else p.traversal.candidate.right_hand
					worst_hand = maxf(worst_hand,IK.position(skeleton,visual.bones["Hand."+side]).distance_to(hand))
			var mesh: MeshInstance3D = p.model.contact_meshes[0]
			var transforms: Array[Transform3D] = []
			for bind in mesh.skin.get_bind_count():
				var bone := mesh.skin.get_bind_bone(bind)
				if bone < 0: bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
				transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				for index in vertices.size():
					var point := Vector3.ZERO
					for j in 4: point += (transforms[bones[index*4+j]]*vertices[index])*weights[index*4+j]
					if absf(point.x)<2 and point.y>0 and point.y<1.5 and point.z<0 and point.z>-2:
						if minf(-point.z,1.5-point.y) > max_penetration:
							max_penetration = minf(-point.z,1.5-point.y)
							record["deepest_point"] = point
							record["deepest_binds"] = [bones[index*4],bones[index*4+1],bones[index*4+2],bones[index*4+3]]
			record["worst_hand"] = worst_hand
			record["penetration"] = max_penetration
			samples.append(record)
			if not p.traversal.attached(): break
		check(worst_hand < 0.035,"Hand contact remains reachable through lift (%.3f m error)" % worst_hand)
		check(max_penetration < 0.035,"Armor avoids deep wall clipping (%.3f m maximum)" % max_penetration)
		var file := FileAccess.open("/tmp/ledge-pose-metrics.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(samples,"  "))
	Engine.physics_ticks_per_second = original
	stage.queue_free()
	await settle(2)
	print("LEDGE POSES: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
