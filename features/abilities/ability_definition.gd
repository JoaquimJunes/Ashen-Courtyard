extends Resource
## Shared authoring data. Execution state always belongs to AbilityController.
@export var id: StringName
@export var combat_action := true
@export var input_buffer_seconds := -1.0
@export var allowed_modes: Array[StringName] = [&"grounded", &"airborne"]
@export var stamina_cost := 0.0
@export var mana_cost := 0.0
@export var flask_cost := 0
@export var windup := 0.0
@export var active_seconds := 0.0
@export var recovery := 0.0
## Negative disables chaining; otherwise the post-strike follow-through before it opens.
@export var chain_after_active := -1.0
@export var damage := 0.0
@export var heal_amount := 0.0
@export var interrupt_on_damage := true
enum ModeExit { CANCEL, CONTINUE }
@export var mode_exit_policy: ModeExit = ModeExit.CANCEL
@export var required_capabilities: Array[StringName] = []
@export var requires_ground := false
@export var requires_standing := false
@export var variant: StringName = &"default"
const Motion = preload("res://features/character/motion_request.gd")
@export var airborne_motion: Motion.AirPolicy = Motion.AirPolicy.INHERIT
@export_group("Spell delivery")
@export var projectile_speed := 18.0
@export var projectile_lifetime := 3.0
@export var radius := 4.0
