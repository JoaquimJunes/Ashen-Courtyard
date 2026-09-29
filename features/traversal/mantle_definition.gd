extends "res://features/abilities/ability_definition.gd"
## Immutable authoring values; no candidate, phase or attachment state lives here.
@export var probe_distance := 0.42
@export var min_lip_height := 0.30
@export var max_lip_height := 1.85
@export var maximum_catch_adjustment := 0.50
@export var maximum_catch_horizontal := 0.60
@export var maximum_descent_speed := 7.5
@export var approach_degrees := 50.0
@export var top_slope_degrees := 15.0
@export var hand_spacing := 0.36
@export var hand_height := 0.07
@export var grasp_height := 1.15
# Authored hanging pose dimensions, measured from the knight rig.
# Detection uses these stable gameplay values, never the rendered bone pose.
@export var shoulder_half_width := 0.177
@export var shoulder_height := 0.986
@export var shoulder_forward := 0.023
@export var upper_arm_length := 0.292
@export var forearm_length := 0.205
@export var tuck_height := 1.0
@export var tuck_offset := 0.85
@export var clearance := 0.10
@export var landing_search_distance := 0.60
@export var lift_seconds := 0.40
@export var over_seconds := 0.32
@export var stand_seconds := 0.30
@export var settle_timeout := 0.30
@export var release_cooldown := 0.30
