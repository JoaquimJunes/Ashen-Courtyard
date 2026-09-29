extends Resource
## Visual-only controls: character speed, stamina, and collision remain in CombatTuning.
@export_range(0,25) var turn_lean_degrees := 14.0
@export_range(1,1.5) var s_turn_lean_multiplier := 1.15
@export_range(0,30) var uphill_lean_degrees := 6.0
@export_range(0,20) var running_lean_degrees := 10.0
@export_range(1,20) var response := 6.0
@export_range(0.05,0.5) var transition_seconds := 0.30
@export_range(0.01,0.3) var cadence_smoothing := 0.16
@export_range(0.0,0.15) var pose_smoothing := 0.045
@export_range(0,0.2) var foot_clearance := 0.085
@export_range(0,0.3) var plant_height := 0.16
@export_range(0,1) var foot_plant_strength := 0.65

## Presentation-only reach compensation on uneven ground.
@export_range(0,0.5) var max_pelvis_lowering := 0.08
@export_range(0.01,0.2) var leg_reach_reserve := 0.04
@export_range(0.01,0.2) var pelvis_response_seconds := 0.045
@export_range(0.01,0.15) var contact_transition_smoothing := 0.045

## Source-time contact easing on inclines; flat-ground contacts remain unchanged.
@export_range(0.0,0.15) var terrain_contact_blend_seconds := 0.08
