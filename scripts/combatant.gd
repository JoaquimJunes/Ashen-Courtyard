extends CharacterBody3D
class_name Combatant

signal health_changed(current: float, maximum: float)
signal died
signal damaged
signal damage_applied(request: RefCounted)
var tuning: CombatTuning = preload("res://data/combat.tres")
const Damage = preload("res://features/combat/damage_request.gd")
const BodyDefinition = preload("res://features/character/body_definition.gd")
var resources = preload("res://features/character/character_resources.gd").new()
var motor = preload("res://features/character/character_motor.gd").new()
var services: Node
var health: float:
	get: return resources.health
	set(value): resources.health = value
var max_health: float:
	get: return resources.maximum_health
	set(value): resources.maximum_health = value
var dead := false
var invulnerable := false
var received: Dictionary = {}
var capsule: CapsuleShape3D
var hitboxes: RefCounted
var damage_layer := 0
const COMBATANTS := &"damage_characters"
const Aim = preload("res://features/combat/aim_request.gd")

func get_aim() -> Aim:
	var origin := global_position+Vector3.UP*1.2
	return Aim.new(origin,origin-global_basis.z*80)

func setup(hp: float, body: BodyDefinition) -> void:
	resources.configure(tuning.resources,hp)
	resources.health_changed.connect(on_health_changed)
	collision_layer = body.collision_layer
	damage_layer = body.collision_layer
	add_to_group(COMBATANTS)
	collision_mask = body.collision_mask
	var col := CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = body.radius
	capsule.height = body.height
	col.shape = capsule
	col.position.y = capsule.height / 2.0
	add_child(col)
	motor.configure(self,tuning,capsule)

func on_health_changed(current: float, maximum: float) -> void:
	health_changed.emit(current,maximum)

# Shared damage interface. Strike IDs identify one damage window globally.
func take_damage(amount: float, strike_id: String) -> bool:
	return receive_damage(Damage.new(amount,StringName(strike_id)))

func receive_damage(request: Damage) -> bool:
	if dead or (invulnerable and request.damage_type not in [&"fall",&"drowning"]) or not is_finite(request.amount) or request.amount <= 0: return false
	if request.strike != null:
		if not request.strike.claim(self): return false
	else:
		# Compatibility adapter for callers still providing only a string identity.
		# New attacks own StrikeTokens, released with their action/projectile.
		if received.has(request.strike_id): return false
		if received.size() >= 128: received.erase(received.keys()[0])
		received[request.strike_id] = 8.0
	# Commit the alive/dead transition before Resources publishes health. Signals
	# are synchronous: a health/damage listener may immediately apply another hit.
	var lethal := request.amount >= health
	if lethal: dead = true
	if hitboxes != null and request.region != &"":
		hitboxes.last_contact = {"region":request.region,"position":request.impact}
	resources.apply_damage(request.amount)
	damage_applied.emit(request)
	damaged.emit()
	# Only the hit that committed death owns its notification. A nonlethal outer
	# hit must not announce death again after a nested listener delivers a fatal hit.
	if lethal: died.emit()
	return true

func reset_resources() -> void:
	dead = false
	invulnerable = false
	received.clear()
	resources.reset()

func in_arc(target: Combatant, reach: float, dot_limit: float = 0.15) -> bool:
	if not is_instance_valid(target) or target.dead: return false
	var offset := target.global_position - global_position
	# Reach is three-dimensional; only the facing angle is projected onto the floor.
	if offset.length() > reach: return false
	offset.y = 0
	return offset.length() < 0.15 or (-global_transform.basis.z).dot(offset.normalized()) > dot_limit

func face_direction(direction: Vector3, weight: float = 1.0) -> void:
	motor.face_direction(direction,weight)

func tick_damage_history(delta: float) -> void:
	for identity: StringName in received.keys():
		received[identity] -= delta
		if received[identity] <= 0: received.erase(identity)
