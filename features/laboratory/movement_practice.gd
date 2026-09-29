extends Node3D
## Optional hub fixture using the real Warden lifecycle, with explicit dependencies.
enum Mode { OFF, TARGET, TIMED_ATTACKS }
const Intent = preload("res://features/character/character_intent.gd")
@export var target_profile: CombatTuning = preload("res://features/laboratory/data/practice_character.tres")
var mode := Mode.OFF
var player: CharacterBody3D
var services: Node
var target: CharacterBody3D
var intent := Intent.new()
@onready var player_start: Marker3D = $PlayerStart
@onready var target_start: Marker3D = $TargetStart
@onready var sign: Label3D = $Sign

func configure(character: CharacterBody3D, context: Node) -> void:
	player = character
	services = context

func clear_target() -> void:
	if is_instance_valid(target):
		target.frozen = true
		target.collision_layer = 0
		target.collision_mask = 0
		target.hide()
		target.queue_free()
	target = null
	sign.hide()
	player.combat_enabled = false
	player.target = null
	player.locked = false

func reset_for_station(station: int) -> void:
	clear_target()
	if station != 0: mode = Mode.OFF
	if mode == Mode.OFF: return
	target = preload("res://scenes/boss.tscn").instantiate()
	# Authored fixture definitions remain read-only, including nested resources.
	target.tuning = target_profile
	target.services = services
	target.controller.manual = true
	target.transform = target_start.transform
	add_child(target)
	target.target = player
	intent = Intent.new()
	target.submit_intent(intent)
	player.combat_enabled = true
	player.target = target
	sign.show()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(target): return
	intent.movement = Vector3.ZERO
	intent.action = &""
	intent.facing = Vector3.ZERO
	if target.dead or player.dead: return
	var offset: Vector3 = player.global_position-target.global_position
	var action: Resource = target.actions.active_definition
	if action == null or (target.state == target.State.TELEGRAPH and target.timer < action.windup*action.tracking_fraction):
		intent.facing = offset
	if mode == Mode.TIMED_ATTACKS and action == null and offset.length() <= 3.3:
		intent.action = &"boss_overhead"

func _process(_delta: float) -> void:
	if not is_instance_valid(target): return
	sign.text = "DEFEATED" if target.dead else "PRACTICE TARGET"

func status() -> String:
	if not is_instance_valid(target): return "Combat practice off"
	if target.dead: return "TARGET DEFEATED\nReset station to repeat"
	if mode == Mode.TARGET: return "STATIONARY TARGET / %d HP\nLock on, attack, cast or dodge" % target.health
	var phase: String = ["Approach to start","Telegraph — dodge the strike","Strike","Recovery — punish the opening"][target.state]
	return "TIMED OVERHEAD / %d HP / 10 damage\n%s" % [target.health,phase]
