extends RefCounted
## Geometry-only continuation query. Straight edges and corner routes use the same grip checks.
const Candidate = preload("res://features/traversal/ledge_candidate.gd")
var probe: RefCounted
var settings: Resource
var reason: StringName = &"edge_end"

func configure(ledge_probe: RefCounted, definition: Resource) -> void:
	probe = ledge_probe
	settings = definition

func hand(point: Vector3) -> Dictionary:
	var hit: Dictionary = probe.ray(point+Vector3.UP*0.07,point-Vector3.UP*0.07)
	if not probe.top_ok(hit): return {}
	if absf(hit.position.y-point.y) > settings.height_tolerance: return {}
	return hit

func grip(lip: Vector3, normal: Vector3, center: Vector3, anchors: Array[Vector3] = []) -> Candidate:
	var value := Candidate.new()
	value.query_tick = Engine.get_physics_frames()
	value.lip = lip
	value.normal = normal
	value.left_normal = normal
	value.right_normal = normal
	value.hang = center
	var side := Vector3.UP.cross(normal)
	if anchors.is_empty():
		for sign_value: float in [-1,1]:
			anchors.append(lip+side*sign_value*probe.definition.hand_spacing/2-normal*0.04)
	for index in 2:
		var hit := hand(anchors[index])
		if hit.is_empty():
			reason = &"edge_end"
			return null
		value.add_surface(hit.collider)
		if index == 0: value.left_hand = hit.position+Vector3.UP*probe.definition.hand_height
		else: value.right_hand = hit.position+Vector3.UP*probe.definition.hand_height
	if not probe.arms_reach(value):
		reason = &"corner_out_of_reach"
		return null
	if not probe.motor.posture_clear(Transform3D(Basis.IDENTITY,center),probe.definition.tuck_height,probe.definition.tuck_offset):
		reason = &"side_obstruction"
		return null
	return value

func wall_at(lip: Vector3, normal: Vector3) -> Dictionary:
	var point := lip-Vector3.UP*0.12
	var hit: Dictionary = probe.ray(point+normal*0.10,point-normal*0.12)
	if hit.is_empty() or not probe.permitted(hit.collider): return {}
	if absf(hit.normal.y)>0.25 or hit.normal.dot(normal)<0.97: return {}
	return hit

func straight(current: Candidate, distance: float) -> Candidate:
	var tangent := Vector3.UP.cross(current.normal)
	var lip := current.lip+tangent*distance
	var face := wall_at(lip,current.normal)
	if face.is_empty():
		reason = &"edge_end"
		return null
	lip.x = face.position.x
	lip.z = face.position.z
	var top := hand(lip-current.normal*0.04)
	if top.is_empty():
		reason = &"edge_end"
		return null
	lip.y = top.position.y
	var value := grip(lip,current.normal,lip+current.normal*(probe.motor.capsule.radius+0.08)-Vector3.UP*probe.definition.grasp_height)
	if value != null:
		value.add_surface(face.collider)
		value.add_surface(top.collider)
	return value

func clear_segment(from: Vector3, to: Vector3) -> bool:
	return probe.motor.posture_path_clear(Transform3D(Basis.IDENTITY,from),to-from,probe.definition.tuck_height,probe.definition.tuck_offset,0.003)

func corner(current: Candidate, sign_value: float) -> RefCounted:
	var direction := Vector3.UP.cross(current.normal)*sign_value
	var level := current.lip-Vector3.UP*0.12
	# Concave: a neighboring face blocks travel. Convex: look back from beyond the edge.
	var hit: Dictionary = probe.ray(level+current.normal*0.06,level+current.normal*0.06+direction*settings.corner_search)
	var inside := not hit.is_empty()
	if not inside:
		hit = probe.ray(level+direction*settings.corner_search-current.normal*0.06,level-direction*0.08-current.normal*0.06)
	if hit.is_empty() or not probe.permitted(hit.collider) or absf(hit.normal.y)>0.25: return null
	var next_normal := Vector3(hit.normal.x,0,hit.normal.z).normalized()
	var angle := current.normal.signed_angle_to(next_normal,Vector3.UP)
	if absf(rad_to_deg(angle)) < settings.minimum_corner_degrees or absf(rad_to_deg(angle)) > settings.maximum_corner_degrees: return null
	if inside != (next_normal.dot(direction) < 0): return null
	var denominator := direction.dot(next_normal)
	if absf(denominator)<0.2: return null
	var distance := (Vector3(hit.position)-current.lip).dot(next_normal)/denominator
	var radius: float = probe.motor.capsule.radius+0.08
	if distance < 0.01 or distance > (radius+0.10 if inside else 0.21): return null
	var path := preload("res://features/traversal/ledge_corner_path.gd").new()
	path.pivot = current.lip+direction*distance
	path.normal = current.normal
	path.next_normal = next_normal
	path.direction = direction
	path.next_direction = Vector3.UP.cross(next_normal)*sign_value
	path.sign_value = sign_value
	path.extent = distance
	path.radius = radius
	path.inside = inside
	path.angle = angle
	path.start = current
	path.end = straight_at(path.pivot+path.next_direction*distance,next_normal)
	path.face = weakref(hit.collider)
	if path.end == null: return null
	# The two lips must meet; don't reach across a gap or change height here.
	for face_normal: Vector3 in [current.normal,next_normal]:
		var near: Vector3 = path.pivot-face_normal*0.035+(-direction if face_normal == current.normal else path.next_direction)*0.025
		if hand(near).is_empty(): return null
	var previous := current.hang
	for index in range(1,settings.corner_samples+1):
		var value: Candidate = path.sample(self,float(index)/settings.corner_samples)
		if value == null or not clear_segment(previous,value.hang): return null
		path.length += previous.distance_to(value.hang)
		previous = value.hang
	return path

func straight_at(lip: Vector3, normal: Vector3) -> Candidate:
	var seed := Candidate.new()
	seed.lip = lip
	seed.normal = normal
	return straight(seed,0)
