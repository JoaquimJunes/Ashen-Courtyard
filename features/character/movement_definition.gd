extends Resource
## Shared authoring defaults; character state is stored separately.
@export var move_speed: float = 4.0
@export var sprint_speed: float = 6.5
@export var move_turn_response: float = 8.0
@export var move_steering_degrees: float = 720.0
@export var max_step_height: float = 0.6
@export var move_acceleration: float = 16.0
@export var move_deceleration: float = 20.0
@export var sharp_turn_deceleration: float = 26.0
@export var sharp_turn_angle: float = 180.0
@export var corner_speed_ratio: float = 0.45
@export var sprint_cost_per_second: float = 20.0
@export var gravity: float = 22.0
@export var air_acceleration: float = 1.5
@export var coyote_seconds: float = 0.10
