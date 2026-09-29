extends Resource
const PoseKey = preload("res://features/presentation/get_up_keyframe.gd")
## Shared authored poses only; capture, anchors and playback belong to instances.
@export var face_down: Array[PoseKey] = []
@export var face_up: Array[PoseKey] = []
@export_range(0.01,0.4) var entry_fraction := 0.18
@export_range(0.65,0.99) var idle_blend_start := 0.88
@export var ground_clearance := 0.015
@export var hand_plant_end := 0.30
@export var back_hand_plant_start := 0.23
@export var back_hand_plant_end := 0.32
@export var front_foot_plant_start := 0.38
@export var back_foot_plant_start := 0.44
@export var foot_plant_end := 0.74
