extends RefCounted
## Pull-up path executor. Requests motion; never writes a body transform.
const Motion = preload("res://features/character/motion_request.gd")
enum Phase { LIFT, OVER, STAND, SETTLE, COMPLETE }
var phase: Phase = Phase.LIFT
var elapsed := 0.0
var candidate: RefCounted
var definition: Resource

func begin(value: RefCounted, settings: Resource) -> void:
	candidate = value
	definition = settings
	phase = Phase.LIFT
	elapsed = 0

func duration() -> float:
	match phase:
		Phase.LIFT: return definition.lift_seconds
		Phase.OVER: return definition.over_seconds
		Phase.STAND: return definition.stand_seconds
	return definition.settle_timeout

func progress() -> float: return clampf(elapsed/duration(),0,1)

func request(delta: float, token: int) -> Motion:
	elapsed += delta
	var from: Vector3 = candidate.hang
	var to: Vector3 = candidate.lift
	match phase:
		Phase.OVER: from = candidate.lift; to = candidate.over
		Phase.STAND: from = candidate.over; to = candidate.stand
		Phase.SETTLE: from = candidate.stand; to = candidate.stand-Vector3.UP*0.06
	var motion := Motion.new()
	motion.kind = Motion.Kind.CONSTRAINED
	motion.attachment_token = token
	motion.target_position = from.lerp(to,smoothstep(0,1,progress()))
	return motion

func after_move(result: RefCounted) -> StringName:
	if phase == Phase.SETTLE and result.grounded:
		phase = Phase.COMPLETE
		return &"complete"
	if result.blocked: return &"blocked"
	if elapsed >= duration():
		if phase == Phase.SETTLE: return &"missing_floor"
		phase = (phase+1) as Phase
		elapsed = 0
	return &""

func reset() -> void:
	candidate = null
	definition = null
	elapsed = 0
	phase = Phase.LIFT
