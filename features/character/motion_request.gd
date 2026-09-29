extends RefCounted
## A transient request, not body state. INHERIT never means "zero velocity".
enum Kind { INHERIT, LOCOMOTION, VELOCITY, BRAKE, CONSTRAINED, WATER }
enum AirPolicy { INHERIT, RETAIN_DEPARTURE, DIRECTED }
const Budget = preload("res://features/character/motion_budget.gd")
var kind: Kind = Kind.INHERIT
var air_policy: AirPolicy = AirPolicy.INHERIT
var ground_velocity := Vector3.ZERO
var air_velocity := Vector3.ZERO
var air_gravity_scale := 1.0
var allow_step := false
var braking_rate := 0.0
var budget: Budget
var target_position := Vector3.ZERO
var attachment_token := 0
var water_velocity := Vector3.ZERO
var water_transform := Transform3D.IDENTITY
var water_height := 1.65

# Locomotion/facing input is supplied by the composition root, independently of AI
# or keyboard origin. Direct ground control preserves the current Warden handling.
var direction := Vector3.ZERO
var top_speed := 0.0
var accelerated := true
var air_steering := true
var centered_gravity := true
var facing := Vector3.ZERO
var face_motion := false
var face_when_committed := false
var turn_weight := 1.0
