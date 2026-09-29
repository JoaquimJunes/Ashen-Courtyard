extends RefCounted
## Hanging locomotion policy. Queries geometry and requests motion; never moves the body.
const Motion = preload("res://features/character/motion_request.gd")
const Candidate = preload("res://features/traversal/ledge_candidate.gd")
var definition: Resource = preload("res://features/traversal/data/knight_shimmy.tres")
var edge := preload("res://features/traversal/ledge_edge_probe.gd").new()
var traversal_ref: WeakRef
var traversal: RefCounted:
	get: return traversal_ref.get_ref()
var actor: CharacterBody3D
var speed := 0.0
var distance_travelled := 0.0
var corner_path: RefCounted
var corner_progress := 0.0
var pending_progress := 0.0
var pending: Candidate
var request: Motion
var reason: StringName = &"hanging"

func configure(feature: RefCounted) -> void:
	traversal_ref = weakref(feature)
	actor = traversal.actor
	edge.configure(traversal.probe,definition)

func prepare(axis: float, delta: float) -> void:
	var attachment: RefCounted = actor.movement.attachment
	attachment.motion = null
	pending = null
	request = null
	if absf(axis) < 0.2:
		speed = 0
		reason = &"hanging"
		return
	speed = move_toward(speed,axis*definition.speed,definition.acceleration*delta)
	if corner_path == null:
		corner_path = edge.corner(traversal.candidate,signf(speed))
		corner_progress = 0
	if corner_path != null:
		if not corner_path.start.valid() or not corner_path.end.valid():
			corner_path = null
			speed = 0
			reason = &"corner_lost"
			return
		var duration: float = maxf(definition.corner_seconds,corner_path.length/definition.speed)
		pending_progress = clampf(corner_progress+(speed/definition.speed)*corner_path.sign_value*delta/duration,0,1)
		pending = corner_path.sample(edge,pending_progress)
		reason = &"inside_corner" if corner_path.inside else &"outside_corner"
	else:
		pending = edge.straight(traversal.candidate,speed*delta)
		reason = &"shimmy"
	if pending == null or not edge.clear_segment(actor.global_position,pending.hang):
		speed = 0
		pending = null
		reason = edge.reason
		return
	request = Motion.new()
	request.kind = Motion.Kind.CONSTRAINED
	request.attachment_token = attachment.token
	request.target_position = pending.hang
	request.facing = -pending.normal
	attachment.motion = request

func after_move(result: RefCounted, applied: RefCounted) -> void:
	if pending == null or applied != request: return
	if result.blocked:
		speed = 0
		reason = &"side_obstruction"
		# Retain reachable hand support at the actual collision endpoint.
		actor.movement.attachment.hold_position = actor.global_position
	else:
		distance_travelled += result.displacement.length()
		traversal.candidate = pending
		actor.movement.attachment.candidate = pending
		actor.movement.attachment.hold_position = pending.hang
		actor.presentation.mantle.candidate = pending
		if corner_path != null:
			corner_progress = pending_progress
			if corner_progress >= 1 or corner_progress <= 0: corner_path = null
	pending = null
	request = null

func reset() -> void:
	speed = 0
	distance_travelled = 0
	corner_path = null
	corner_progress = 0
	pending = null
	request = null
	reason = &"hanging"
