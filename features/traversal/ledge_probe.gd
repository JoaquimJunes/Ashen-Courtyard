extends RefCounted
## Read-only detection. Excludes actors/moving props and never changes body position.
const Candidate = preload("res://features/traversal/ledge_candidate.gd")
const Definition = preload("res://features/traversal/mantle_definition.gd")
var actor: CharacterBody3D
var motor: RefCounted
var definition: Definition
var reason: StringName = &"no_wall"

func configure(body: CharacterBody3D, character_motor: RefCounted, settings: Definition) -> void:
	actor = body
	motor = character_motor
	definition = settings

func permitted(node: Object) -> bool:
	if not node is StaticBody3D: return false
	var at := node as Node
	while at != null:
		if at.is_in_group(&"no_ledge_grab") or at.get_meta(&"no_ledge_grab",false): return false
		at = at.get_parent()
	return true

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return motor.floor_probe(from,to)

func top_ok(hit: Dictionary) -> bool:
	return not hit.is_empty() and permitted(hit.collider) and hit.normal.y >= cos(deg_to_rad(definition.top_slope_degrees))

func find(direction: Vector3, delta: float, water_surface: float = INF, water_max_height: float = 0.5) -> Candidate:
	reason = &"no_wall"
	direction = motor.ground_direction(direction)
	if direction.is_zero_approx(): return null
	var origin := actor.global_position
	var reach: float = motor.capsule.radius+definition.probe_distance+Vector2(actor.velocity.x,actor.velocity.z).length()*delta
	if is_finite(water_surface): reach += maxf(0,actor.swimming.definition.collider_height*0.5-motor.capsule.radius)
	var wall: Dictionary = {}
	for height: float in [0.25,0.65,1.05]:
		wall = ray(origin+Vector3.UP*height,origin+Vector3.UP*height+direction*reach)
		if not wall.is_empty() and absf(wall.normal.y) < 0.25: break
	if wall.is_empty() or absf(wall.normal.y) >= 0.25: return null
	if not permitted(wall.collider):
		reason = &"excluded_surface"
		return null
	var normal := Vector3(wall.normal.x,0,wall.normal.z).normalized()
	if direction.dot(-normal) < cos(deg_to_rad(definition.approach_degrees)):
		reason = &"approach_angle"
		return null
	var sample: Vector3 = wall.position-normal*0.055
	sample.y = origin.y
	var water_entry := is_finite(water_surface)
	var top := ray(Vector3(sample.x,water_surface+water_max_height+0.01,sample.z),Vector3(sample.x,water_surface-0.15,sample.z)) if water_entry else ray(sample+Vector3.UP*definition.max_lip_height,sample+Vector3.UP*definition.min_lip_height)
	if not top_ok(top):
		reason = &"unreachable_top"
		return null
	var candidate := Candidate.new()
	candidate.from_water = water_entry
	candidate.query_tick = Engine.get_physics_frames()
	candidate.lip = top.position+normal*0.055
	candidate.normal = normal
	candidate.left_normal = normal
	candidate.right_normal = normal
	candidate.top_normal = top.normal
	candidate.add_surface(wall.collider)
	candidate.add_surface(top.collider)
	var side := Vector3.UP.cross(normal).normalized()
	for sign_value: float in [-1,1]:
		var point := candidate.lip+side*sign_value*definition.hand_spacing*0.5-normal*0.04
		var hand_top := ray(point+Vector3.UP*0.07,point-Vector3.UP*0.07)
		if not top_ok(hand_top) or absf(hand_top.position.y-candidate.lip.y) > 0.055:
			reason = &"no_hand_support"
			return null
		candidate.add_surface(hand_top.collider)
		if sign_value < 0: candidate.left_hand = hand_top.position+Vector3.UP*definition.hand_height
		else: candidate.right_hand = hand_top.position+Vector3.UP*definition.hand_height
	candidate.hang = candidate.lip+normal*(motor.capsule.radius+0.08)-Vector3.UP*definition.grasp_height
	var catch_height: float = 1.0 if water_entry else definition.maximum_catch_adjustment
	if absf(candidate.hang.y-origin.y) > catch_height or Vector2(candidate.hang.x-origin.x,candidate.hang.z-origin.z).length() > definition.maximum_catch_horizontal:
		reason = &"outside_grasp_pose"
		return null
	if not arms_reach(candidate):
		reason = &"outside_arm_reach"
		return null
	if not motor.posture_path_clear(actor.global_transform,candidate.hang-origin,definition.tuck_height,definition.tuck_offset,0.003):
		reason = &"blocked_grip"
		return null
	update_mantle(candidate)
	reason = &"reachable"
	return candidate

func arms_reach(candidate: Candidate) -> bool:
	var side := Vector3.UP.cross(candidate.normal)
	var minimum := absf(definition.upper_arm_length-definition.forearm_length)+0.002
	var maximum := definition.upper_arm_length+definition.forearm_length-0.002
	for sign_value: float in [-1,1]:
		var shoulder: Vector3 = candidate.hang+side*sign_value*definition.shoulder_half_width+Vector3.UP*definition.shoulder_height-candidate.normal*definition.shoulder_forward
		var hand := candidate.left_hand if sign_value < 0 else candidate.right_hand
		var distance := shoulder.distance_to(hand)
		if distance < minimum or distance > maximum: return false
	return true

func grip_valid(candidate: Candidate) -> bool:
	if candidate == null or not candidate.valid(): return false
	for point: Vector3 in [candidate.left_hand,candidate.right_hand]:
		var support := point-Vector3.UP*definition.hand_height
		var hit := ray(support+Vector3.UP*0.08,support-Vector3.UP*0.06)
		if not top_ok(hit) or absf(hit.position.y-support.y) > 0.03: return false
	return true

func update_mantle(candidate: Candidate) -> bool:
	candidate.can_mantle = false
	candidate.reason = &"surface_lost"
	if not grip_valid(candidate): return false
	# A narrow lip can sit above/below the walkable surface behind it. Search a
	# bounded distance inward; the same step-height limit applies in every level.
	var radius: float = motor.capsule.radius
	var inset: float = radius+0.16
	var count := maxi(1,ceili(definition.landing_search_distance/(radius*0.5)))
	for index in count+1:
		var distance := inset+definition.landing_search_distance*float(index)/count
		if mantle_route(candidate,distance):
			candidate.can_mantle = true
			candidate.reason = &"ready"
			return true
	return false

func landing_hit(candidate: Candidate, point: Vector3) -> Dictionary:
	var limit: float = motor.tuning.max_step_height
	point.y = candidate.lip.y
	var hit := ray(point+Vector3.UP*(limit+0.12),point-Vector3.UP*(limit+0.12))
	if not top_ok(hit) or absf(hit.position.y-candidate.lip.y) > limit+0.001: return {}
	return hit

func mantle_route(candidate: Candidate, inset: float) -> bool:
	var radius: float = motor.capsule.radius
	var center := candidate.lip-candidate.normal*inset
	var floor := landing_hit(candidate,center)
	if floor.is_empty():
		candidate.reason = &"insufficient_top_space"
		return false
	center.y = floor.position.y
	var supports: Array[Node3D] = [floor.collider]
	var highest := maxf(candidate.lip.y,center.y)
	var side := Vector3.UP.cross(candidate.normal)
	for offset: Vector3 in [side*radius,-side*radius,candidate.normal*radius,-candidate.normal*radius]:
		var hit := landing_hit(candidate,center+offset)
		# Require a supported footprint on the sampled landing plane, not on the
		# lip's plane. A riser under the feet makes us try slightly farther inward.
		var plane_y: float = center.y-Vector3(floor.normal).dot(offset)/floor.normal.y
		if hit.is_empty() or absf(hit.position.y-plane_y) > 0.07:
			candidate.reason = &"insufficient_top_space"
			return false
		highest = maxf(highest,hit.position.y)
		supports.append(hit.collider)
	# Do not turn the farther landing search into a vault across a missing floor.
	var steps := maxi(1,ceili(inset/0.08))
	for index in range(1,steps+1):
		var hit := landing_hit(candidate,candidate.lip-candidate.normal*(inset*index/steps))
		if hit.is_empty():
			candidate.reason = &"insufficient_top_space"
			return false
		highest = maxf(highest,hit.position.y)
		supports.append(hit.collider)
	candidate.stand = motor.standing_position(center,floor.normal,0.03)
	if not motor.posture_clear(Transform3D(actor.global_basis,candidate.stand),motor.standing_height,motor.standing_offset):
		candidate.reason = &"standing_blocked"
		return false
	var bottom: float = definition.tuck_offset-definition.tuck_height*0.5
	candidate.lift = candidate.hang
	candidate.lift.y = highest-bottom+definition.clearance
	candidate.over = center
	candidate.over.y = candidate.lift.y
	var previous := candidate.hang
	for point: Vector3 in [candidate.lift,candidate.over,candidate.stand]:
		if not motor.posture_path_clear(Transform3D(actor.global_basis,previous),point-previous,definition.tuck_height,definition.tuck_offset):
			candidate.reason = &"path_blocked"
			return false
		previous = point
	for surface in supports: candidate.add_surface(surface)
	return true
