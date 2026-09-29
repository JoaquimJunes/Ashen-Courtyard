extends RefCounted
## Per-character geometric route. Evaluated from face planes, never from a level name.
const Candidate = preload("res://features/traversal/ledge_candidate.gd")
var pivot := Vector3.ZERO
var normal := Vector3.ZERO
var next_normal := Vector3.ZERO
var direction := Vector3.ZERO
var next_direction := Vector3.ZERO
var sign_value := 1.0
var extent := 0.2
var radius := 0.4
var inside := false
var angle := 0.0
var start: Candidate
var end: Candidate
var face: WeakRef
var length := 0.0

func sample(edge: RefCounted, t: float) -> Candidate:
	var body_normal := normal.rotated(Vector3.UP,angle*t)
	var along := lerpf(-extent,extent,t)
	var lip := pivot+direction*minf(along,0)+next_direction*maxf(along,0)
	var center: Vector3
	var down: Vector3 = Vector3.UP*edge.probe.definition.grasp_height
	if inside:
		var intersection := pivot+(normal+next_normal)*radius/(1+normal.dot(next_normal))-down
		center = start.hang.lerp(intersection,t*2) if t<0.5 else intersection.lerp(end.hang,(t-0.5)*2)
	else:
		center = lip+body_normal*(radius-edge.settings.outside_body_tuck*sin(PI*t))-down
	var anchors: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for hand_sign: float in [-1,1]:
		var shoulder: Vector3 = center+Vector3.UP.cross(body_normal)*hand_sign*edge.probe.definition.shoulder_half_width-body_normal*edge.probe.definition.shoulder_forward
		var separation: float = 0.04 if inside else edge.settings.outside_hand_offset
		var old_hand := pivot+direction*minf(-separation,(shoulder-pivot).dot(direction))-normal*0.04
		var new_hand := pivot+next_direction*maxf(separation,(shoulder-pivot).dot(next_direction))-next_normal*0.04
		# Choose the reachable face from the posed shoulder, including between samples.
		var old_face := shoulder.distance_squared_to(old_hand)<=shoulder.distance_squared_to(new_hand)
		anchors.append(old_hand if old_face else new_hand)
		normals.append(normal if old_face else next_normal)
	var value: Candidate = edge.grip(lip,body_normal,center,anchors)
	if value != null:
		value.left_normal = normals[0]
		value.right_normal = normals[1]
		if face.get_ref() != null: value.add_surface(face.get_ref())
	return value
