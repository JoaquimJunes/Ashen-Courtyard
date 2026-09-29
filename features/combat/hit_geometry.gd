extends RefCounted
## Exact segment and closest-point tests for the supported convex primitives.
## Queries never advance animation or create physics bodies.
static func closest(shape: Shape3D, point: Vector3) -> Vector3:
	if shape is BoxShape3D:
		return point.clamp(-shape.size*0.5,shape.size*0.5)
	var anchor := Vector3.ZERO
	if shape is CapsuleShape3D:
		var half: float = maxf(0,shape.height*0.5-shape.radius)
		anchor.y = clampf(point.y,-half,half)
	return anchor+(point-anchor).limit_length(shape.radius)

static func closest_world(shape: Shape3D, at: Transform3D, point: Vector3) -> Vector3:
	if shape is BoxShape3D: return at*closest(shape,at.affine_inverse()*point)
	# Orthogonal per-axis fitting keeps a shin narrow without sacrificing depth.
	# Euclidean nearest points on scaled capsules require an ellipsoid projection.
	var basis := at.basis.orthonormalized()
	var scale := at.basis.get_scale().abs()
	var local := basis.inverse()*(point-at.origin)
	var anchor := Vector3.ZERO
	if shape is CapsuleShape3D:
		var half: float = maxf(0,shape.height*0.5-shape.radius)*scale.y
		anchor.y = clampf(local.y,-half,half)
	var offset := local-anchor
	var radii: Vector3 = scale*shape.radius
	if (offset/radii).length_squared() <= 1: return point
	var square := radii*radii
	var low := 0.0
	var high := radii.length()*offset.length()
	for i in 32:
		var middle := (low+high)*0.5
		var denominator := square+Vector3.ONE*middle
		if (radii*offset/denominator).length_squared() > 1: low = middle
		else: high = middle
	return at.origin+basis*(anchor+square*offset/(square+Vector3.ONE*high))

static func sphere_roots(from: Vector3, travel: Vector3, center: Vector3, radius: float) -> Array[float]:
	var a := travel.length_squared()
	if a < 0.0000000001: return []
	var offset := from-center
	var b := 2*offset.dot(travel)
	var disc := b*b-4*a*(offset.length_squared()-radius*radius)
	if disc < 0: return []
	return [(-b-sqrt(disc))/(2*a),(-b+sqrt(disc))/(2*a)]

static func segment(shape: Shape3D, from: Vector3, to: Vector3) -> float:
	if closest(shape,from).distance_squared_to(from) < 0.0000000001: return 0.0
	var travel := to-from
	if shape is BoxShape3D:
		return box_interval(from,to,-shape.size*0.5,shape.size*0.5).x
	var best := INF
	var half: float = maxf(0,shape.height*0.5-shape.radius) if shape is CapsuleShape3D else 0.0
	for y in [-half,half]:
		for t in sphere_roots(from,travel,Vector3.UP*y,shape.radius):
			if t >= 0 and t <= 1: best = minf(best,t)
	if half > 0:
		var flat_from := Vector3(from.x,0,from.z)
		var flat_travel := Vector3(travel.x,0,travel.z)
		for t in sphere_roots(flat_from,flat_travel,Vector3.ZERO,shape.radius):
			if t >= 0 and t <= 1 and absf(from.y+travel.y*t) <= half: best = minf(best,t)
	return best if best != INF else -1.0

static func box_interval(from: Vector3, to: Vector3, low: Vector3, high: Vector3) -> Vector2:
	var first := 0.0
	var last := 1.0
	var travel := to-from
	for axis in 3:
		if absf(travel[axis]) < 0.0000001:
			if from[axis] < low[axis] or from[axis] > high[axis]: return Vector2(-1,-1)
		else:
			var a: float = (low[axis]-from[axis])/travel[axis]
			var b: float = (high[axis]-from[axis])/travel[axis]
			first = maxf(first,minf(a,b))
			last = minf(last,maxf(a,b))
			if first > last: return Vector2(-1,-1)
	return Vector2(first,last)
