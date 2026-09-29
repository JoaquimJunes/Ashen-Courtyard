extends RefCounted
## Reusable local transforms. Buffers belong to an instance, never an Animation.
var rotations: Array[Quaternion] = []
var positions := PackedVector3Array()
var scales := PackedVector3Array()

func capture(skeleton: Skeleton3D) -> void:
	var count := skeleton.get_bone_count()
	rotations.resize(count)
	positions.resize(count)
	scales.resize(count)
	for bone in count:
		rotations[bone] = skeleton.get_bone_pose_rotation(bone)
		positions[bone] = skeleton.get_bone_pose_position(bone)
		scales[bone] = skeleton.get_bone_pose_scale(bone)

func apply(skeleton: Skeleton3D) -> void:
	if rotations.size() != skeleton.get_bone_count(): return
	for bone in rotations.size():
		skeleton.set_bone_pose_rotation(bone,rotations[bone])
		skeleton.set_bone_pose_position(bone,positions[bone])
		skeleton.set_bone_pose_scale(bone,scales[bone])

func interpolate(skeleton: Skeleton3D, next: RefCounted, weight: float) -> void:
	if rotations.size() != skeleton.get_bone_count() or next.rotations.size() != rotations.size(): return
	for bone in rotations.size():
		skeleton.set_bone_pose_rotation(bone,rotations[bone].slerp(next.rotations[bone],weight))
		skeleton.set_bone_pose_position(bone,positions[bone].lerp(next.positions[bone],weight))
		skeleton.set_bone_pose_scale(bone,scales[bone].lerp(next.scales[bone],weight))
