extends Resource
## A single collider/joint in an authored rig. Runtime bodies are separate Nodes.
@export var bone_name: StringName
@export var length := 0.3
@export var radius := 0.10
@export var box_size := Vector3.ZERO
@export var mass := 2.0
@export_enum("None:0","Cone:2","Hinge:3") var joint_type := 2
@export var hinge_axis := Vector3.RIGHT
@export var angular_lower := -5.0
@export var angular_upper := 135.0
@export var swing_span := 35.0
@export var twist_span := 25.0
