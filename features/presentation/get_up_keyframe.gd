extends Resource
## Original supported pose, in character space (metres; forward is -Z).
@export_range(0,1) var time := 0.0
@export var pelvis := Vector3(0,0.3,0)
@export var torso_degrees := Vector3.ZERO
@export var left_foot := Vector3(-0.14,0.10,0)
@export var right_foot := Vector3(0.14,0.10,0)
@export var left_hand := Vector3(-0.3,0.1,-0.4)
@export var right_hand := Vector3(0.4,0.5,-0.3)
@export var knee_pole := Vector3.FORWARD
@export_range(0,1.5) var knees_out := 0.0
@export var left_foot_pitch := 0.0
@export var right_foot_pitch := 0.0
