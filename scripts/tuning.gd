extends Resource
class_name CombatTuning
## Compatibility view for existing scenes/tests. Edit the focused Resources below.
const MovementDefinition = preload("res://features/character/movement_definition.gd")
@export var movement: MovementDefinition = preload("res://features/character/data/movement.tres")
const ResourcesDefinition = preload("res://features/character/resources_definition.gd")
@export var resources: ResourcesDefinition = preload("res://features/character/data/resources.tres")
const CombatDefinition = preload("res://features/combat/combat_definition.gd")
@export var combat: CombatDefinition = preload("res://features/combat/data/combat.tres")
const LightDefinition = preload("res://features/abilities/ability_definition.gd")
@export var light: LightDefinition = preload("res://features/abilities/data/light.tres")
const HeavyDefinition = preload("res://features/abilities/ability_definition.gd")
@export var heavy: HeavyDefinition = preload("res://features/abilities/data/heavy.tres")
const BoltDefinition = preload("res://features/abilities/ability_definition.gd")
@export var bolt: BoltDefinition = preload("res://features/abilities/data/bolt.tres")
const BurstDefinition = preload("res://features/abilities/ability_definition.gd")
@export var burst: BurstDefinition = preload("res://features/abilities/data/burst.tres")
const HealDefinition = preload("res://features/abilities/ability_definition.gd")
@export var heal: HealDefinition = preload("res://features/abilities/data/heal.tres")
const DodgeDefinition = preload("res://features/abilities/dodge_definition.gd")
@export var dodge_forward: DodgeDefinition = preload("res://features/abilities/data/dodge_forward.tres")
@export var dodge_ground: DodgeDefinition = preload("res://features/abilities/data/dodge_ground.tres")
const LandingRollDefinition = preload("res://features/abilities/landing_roll_definition.gd")
@export var landing_roll: LandingRollDefinition = preload("res://features/abilities/data/landing_roll.tres")
const JumpDefinition = preload("res://features/abilities/jump_definition.gd")
@export var jump: JumpDefinition = preload("res://features/abilities/data/jump.tres")
@export var landing_action: LightDefinition = preload("res://features/abilities/data/landing.tres")
const LandingDefinition = preload("res://features/character/landing_definition.gd")
@export var landing: LandingDefinition = preload("res://features/character/data/landing.tres")
@export var presentation: Resource = preload("res://data/locomotion.tres")

var player_health: float:
	get: return resources.player_health
var stamina_max: float:
	get: return resources.stamina_max
var stamina_regen: float:
	get: return resources.stamina_regen
var stamina_delay: float:
	get: return resources.stamina_delay
var mana_max: float:
	get: return resources.mana_max
var mana_regen: float:
	get: return resources.mana_regen
var mana_delay: float:
	get: return resources.mana_delay
var light_damage: float:
	get: return light.damage
var heavy_damage: float:
	get: return heavy.damage
var light_cost: float:
	get: return light.stamina_cost
var heavy_cost: float:
	get: return heavy.stamina_cost
var light_windup: float:
	get: return light.windup
var light_active: float:
	get: return light.active_seconds
var light_recovery: float:
	get: return light.recovery
var heavy_windup: float:
	get: return heavy.windup
var heavy_active: float:
	get: return heavy.active_seconds
var heavy_recovery: float:
	get: return heavy.recovery
var bolt_cost: float:
	get: return bolt.mana_cost
var bolt_damage: float:
	get: return bolt.damage
var bolt_windup: float:
	get: return bolt.windup
var burst_cost: float:
	get: return burst.mana_cost
var burst_damage: float:
	get: return burst.damage
var burst_windup: float:
	get: return burst.windup
var cast_recovery: float:
	get: return bolt.recovery
var boss_health: float:
	get: return combat.boss_health
var boss_damage: float:
	get: return combat.boss_damage
var boss_combo_windup: float:
	get: return combat.boss_combo_windup
var boss_overhead_windup: float:
	get: return combat.boss_overhead_windup
var boss_lunge_windup: float:
	get: return combat.boss_lunge_windup
var boss_recovery: float:
	get: return combat.boss_recovery
var move_speed: float:
	get: return movement.move_speed
var sprint_speed: float:
	get: return movement.sprint_speed
var move_turn_response: float:
	get: return movement.move_turn_response
var move_steering_degrees: float:
	get: return movement.move_steering_degrees
var max_step_height: float:
	get: return movement.max_step_height
var move_acceleration: float:
	get: return movement.move_acceleration
var move_deceleration: float:
	get: return movement.move_deceleration
var sharp_turn_deceleration: float:
	get: return movement.sharp_turn_deceleration
var sharp_turn_angle: float:
	get: return movement.sharp_turn_angle
var corner_speed_ratio: float:
	get: return movement.corner_speed_ratio
var sprint_cost_per_second: float:
	get: return movement.sprint_cost_per_second
var gravity: float:
	get: return movement.gravity
var input_buffer: float:
	get: return combat.input_buffer
var combo_grace: float:
	get: return combat.combo_grace
var hurt_duration: float:
	get: return combat.hurt_duration
var heal_amount: float:
	get: return heal.heal_amount
var heal_windup: float:
	get: return heal.windup
var heal_recovery: float:
	get: return heal.recovery
var projectile_speed: float:
	get: return bolt.projectile_speed
var projectile_lifetime: float:
	get: return bolt.projectile_lifetime
var burst_radius: float:
	get: return burst.radius
var boss_move_speed: float:
	get: return combat.boss_move_speed
var boss_lunge_speed: float:
	get: return combat.boss_lunge_speed
var boss_active: float:
	get: return combat.boss_active
var boss_combo_gap: float:
	get: return combat.boss_combo_gap
var boss_lunge_duration: float:
	get: return combat.boss_lunge_duration
var boss_attack_tail: float:
	get: return combat.boss_attack_tail
var boss_overhead_multiplier: float:
	get: return combat.boss_overhead_multiplier
