extends "res://features/abilities/ability_definition.gd"
@export var preparation: float = 0.0
@export var height: float = 0.0
@export var extension: float = 0.08
@export var air_rate: float = 1.0
@export var speed: float = 7.4
@export var distance: float = 4.34
@export var ground_duration: float = 0.55
@export var pose_blend: float = 0.08
@export_range(0.0, 0.9, 0.01) var animation_start: float = 0.0
@export var immunity_start: float = 0.06
@export var immunity_end: float = 0.32
@export var brake_start: float = 0.7
@export var preparation_speed: float = 7.4
@export_group("Adaptive forward clearance")
@export var adaptive_clearance: bool = false
@export_range(0.0, 1.0, 0.01) var clearance_max_rise: float = 0.6
@export_range(0.0, 0.3, 0.01) var clearance_margin: float = 0.12
@export_range(0.5, 4.0, 0.1) var clearance_lookahead: float = 2.6
@export_range(0.025, 0.25, 0.025) var clearance_probe_spacing: float = 0.1
