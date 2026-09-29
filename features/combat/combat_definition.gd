extends Resource
const BossDefinition = preload("res://features/abilities/boss_attack_definition.gd")
@export var boss_combo: BossDefinition = preload("res://features/abilities/data/boss_combo.tres")
@export var boss_overhead: BossDefinition = preload("res://features/abilities/data/boss_overhead.tres")
@export var boss_lunge: BossDefinition = preload("res://features/abilities/data/boss_lunge.tres")
@export var boss_health: float = 1500.0
var boss_damage: float:
	get: return boss_combo.damage
var boss_combo_windup: float:
	get: return boss_combo.windup
var boss_overhead_windup: float:
	get: return boss_overhead.windup
var boss_lunge_windup: float:
	get: return boss_lunge.windup
var boss_recovery: float:
	get: return boss_combo.recovery
@export var input_buffer: float = 0.2
@export var combo_grace: float = 0.45
@export var hurt_duration: float = 0.35
@export var boss_move_speed: float = 2.3
var boss_lunge_speed: float:
	get: return boss_lunge.lunge_speed
var boss_active: float:
	get: return boss_combo.active_seconds
var boss_combo_gap: float:
	get: return boss_combo.combo_gap
var boss_lunge_duration: float:
	get: return boss_lunge.lunge_duration
var boss_attack_tail: float:
	get: return boss_combo.attack_tail
var boss_overhead_multiplier: float:
	get: return boss_overhead.damage / boss_combo.damage
