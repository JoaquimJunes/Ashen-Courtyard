extends RefCounted
## Two-bone presentation constraint. Rotates bones without stretching or body motion.
static func position(skeleton: Skeleton3D, bone: int) -> Vector3:
	return (skeleton.global_transform*skeleton.get_bone_global_pose(bone)).origin

static func set_world_basis(skeleton: Skeleton3D, bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.global_basis
	if parent >= 0: parent_basis *= skeleton.get_bone_global_pose(parent).basis
	skeleton.set_bone_pose_rotation(bone,(parent_basis.inverse()*basis).orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

static func aim(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001: return
	var basis := skeleton.global_basis*skeleton.get_bone_global_pose(bone).basis
	set_world_basis(skeleton,bone,Basis(Quaternion(from.normalized(),to.normalized()))*basis)

static func solve(skeleton: Skeleton3D, upper: int, lower: int, end: int, target: Vector3, pole: Vector3) -> void:
	var a := position(skeleton,upper)
	var b := position(skeleton,lower)
	var c := position(skeleton,end)
	var first := a.distance_to(b)
	var second := b.distance_to(c)
	var direction := (target-a).normalized()
	if direction.is_zero_approx(): return
	var distance := clampf(a.distance_to(target),absf(first-second)+0.002,first+second-0.002)
	var bend := pole-direction*pole.dot(direction)
	if bend.length_squared() < 0.00001:
		bend = (b-a)-direction*(b-a).dot(direction)
	if bend.length_squared() < 0.00001: return
	var along := (first*first-second*second+distance*distance)/(2*distance)
	var elbow := a+direction*along+bend.normalized()*sqrt(maxf(0,first*first-along*along))
	aim(skeleton,upper,b-a,elbow-a)
	b = position(skeleton,lower)
	c = position(skeleton,end)
	aim(skeleton,lower,c-b,target-b)
