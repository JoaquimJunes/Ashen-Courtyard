extends Resource
## Read-only tuning. Distances are metres and breath is measured in seconds.
@export var speed := 2.5
@export var fast_speed := 4.0
@export var fast_cost := 20.0
@export var acceleration := 7.0
@export var drag := 9.0
@export var breath_seconds := 20.0
@export var breath_refill_seconds := 3.0
@export var drowning_fraction_per_second := 0.10
@export var safe_entry_depth := 2.0
@export var surface_offset := 1.1
@export var head_offset := 1.22
@export var immersion_height := 1.3
@export var crouch_entry_depth := 1.0
@export var exit_depth := 0.9
@export var surface_response := 7.0
@export var resurface_margin := 0.12
@export var collider_height := 1.65
@export var collider_offset := 0.9
@export var ledge_height := 0.5
@export var blend_seconds := 0.20

## Neutral model origins for the native waterline-based upright/prone clips.
@export var upright_origin := Vector3(0,0.9,0)
@export var prone_origin := Vector3(0,1.1,0)
