extends RefCounted
## Measures actual skinned armor in world space, including geometry outside the capsule.
static var last_point := Vector3.ZERO

static func points(skeleton: Skeleton3D) -> PackedVector3Array:
	var instance: MeshInstance3D = skeleton.find_children("*","MeshInstance3D",true,false)[0]
	var transforms: Array[Transform3D] = []
	for bind in instance.skin.get_bind_count():
		var bone := instance.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
		transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bone)*instance.skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	for surface in instance.mesh.get_surface_count():
		var arrays := instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for index in vertices.size():
			var point := Vector3.ZERO
			for j in 4: point += (transforms[bones[index*4+j]]*vertices[index])*weights[index*4+j]
			result.append(point)
	return result

static func penetration(skeleton: Skeleton3D, boxes: Array[AABB]) -> float:
	var deepest := 0.0
	for point in points(skeleton):
		for box in boxes:
			if box.has_point(point):
				var near := point-box.position
				var far := box.end-point
				var depth := minf(minf(near.x,far.x),minf(minf(near.y,far.y),minf(near.z,far.z)))
				if depth>deepest:
					deepest = depth
					last_point = point
	return deepest
