extends RefCounted
## Alternating planted grips from accepted surface anchors. No physics/body writes.
var definition: Resource = preload("res://features/traversal/data/shimmy_pose.tres")
var hands: Array[Vector3] = []
var normals: Array[Vector3] = []
var start_normal := Vector3.ZERO
var moving_hand := -1
var next_hand := 1
var elapsed := 0.0
var start := Vector3.ZERO
var activity := 0.0
var sway := 0.0

func reset() -> void:
	hands.clear()
	normals.clear()
	moving_hand = -1
	next_hand = 1
	elapsed = 0
	activity = 0
	sway = 0

func update(candidate: RefCounted, runtime: RefCounted, delta: float) -> void:
	var targets: Array[Vector3] = [candidate.left_hand,candidate.right_hand]
	var facing: Array[Vector3] = [candidate.left_normal,candidate.right_normal]
	for i in 2:
		if facing[i].is_zero_approx(): facing[i] = candidate.normal
	if hands.is_empty():
		hands.assign(targets)
		normals.assign(facing)
	var hanging: bool = runtime.status == &"hang"
	var moving: bool = hanging and absf(runtime.shimmy.speed)>0.01
	activity = lerpf(activity,1.0 if moving else 0.0,1-exp(-15*delta))
	sway = sin(runtime.shimmy.distance_travelled*TAU/definition.stride_distance)*definition.body_sway*activity
	if not hanging:
		moving_hand = -1
		for i in 2:
			hands[i] = hands[i].lerp(targets[i],1-exp(-45*delta))
			normals[i] = blend_normal(normals[i],facing[i],1-exp(-45*delta))
		return
	if moving_hand < 0:
		for i in [next_hand,1-next_hand]:
			if hands[i].distance_to(targets[i]) > (definition.hand_step_distance if moving else 0.005):
				moving_hand = i
				next_hand = 1-i
				start = hands[i]
				start_normal = normals[i]
				elapsed = 0
				break
	if moving_hand >= 0:
		elapsed += delta
		var progress: float = clampf(elapsed/definition.hand_transfer_seconds,0,1)
		hands[moving_hand] = start.lerp(targets[moving_hand],smoothstep(0,1,progress))+Vector3.UP*sin(PI*progress)*definition.hand_lift
		normals[moving_hand] = blend_normal(start_normal,facing[moving_hand],smoothstep(0,1,progress))
		if progress >= 1: moving_hand = -1

func blend_normal(from: Vector3, to: Vector3, weight: float) -> Vector3:
	# These are horizontal face normals. Yaw interpolation stays stable for
	# nearly parallel contacts and avoids a vanishing cross-product axis.
	var yaw := lerp_angle(atan2(from.x,from.z),atan2(to.x,to.z),weight)
	return Vector3(sin(yaw),0,cos(yaw))
