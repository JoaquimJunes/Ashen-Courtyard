extends Resource
const Part = preload("res://features/reactions/ragdoll_part.gd")
const GetUp = preload("res://features/presentation/get_up_definition.gd")
## Shared tuning only. Each character builds and owns its own physical rig.
@export var anchor_bone: StringName = &"Body"
@export var parts: Array[Part] = []
@export var settle_seconds := 0.30
@export var settle_speed := 0.75
@export var settle_angular_speed := 2.0
@export var get_up_seconds := 1.20
@export var get_up_pose: GetUp = preload("res://features/presentation/knight_get_up.tres")
# Torso bone axes: the knight's +Z faces through the breastplate, +Y to the head.
@export var recovery_front_axis := Vector3.BACK
@export var recovery_head_axis := Vector3.UP
@export var angular_damping := 2.5
@export var tumble_speed := 1.2
