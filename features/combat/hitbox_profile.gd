extends Resource
const Region = preload("res://features/combat/hit_region.gd")
@export var rig_id: StringName
@export var regions: Array[Region] = []
@export var breathing_bone: StringName = &"Head"
@export var breathing_offset := Vector3(0,0.13,0.12)
@export var source_model: String
