extends Node
## Explicit world context. No courtyard or single-boss knowledge.
const Damage = preload("res://features/combat/damage_request.gd")
const Strike = preload("res://features/combat/strike_token.gd")
const Aim = preload("res://features/combat/aim_request.gd")
const Receiver = preload("res://features/combat/damage_receiver.gd")
const Queries = preload("res://features/combat/damage_queries.gd")
var host: Node
var effects: Node3D
var projectile_scene: PackedScene
const SPELL_TONES = {&"projectile":600.0,&"burst":340.0}
const SPELL_TONE_SECONDS := 0.18

func _init() -> void:
	# Standalone actors can prepare cues while their world's insertion is deferred.
	effects = preload("res://features/presentation/world_effects.gd").new()
	add_child(effects)

func _ready() -> void:
	# Runtime preparation avoids a preload cycle through the projectile's Combatant.
	projectile_scene = load("res://scenes/projectile.tscn")
	for frequency in SPELL_TONES.values(): effects.prepare_tone(frequency,SPELL_TONE_SECONDS)
var transients: Array[Node] = []

func enemy_mask(caster: CollisionObject3D) -> int:
	return 2 if (caster.damage_layer if caster is Combatant else caster.collision_layer) & 4 else 4

func opponents(caster: Combatant, radius: float) -> Array[Combatant]:
	# One candidate per character, independent of how many regions it owns.
	return Queries.characters(caster,enemy_mask(caster),caster)

func deal(source: Combatant, victim: Combatant, amount: float, strike: RefCounted, kind: StringName = &"physical", contact: Dictionary = {}) -> bool:
	var request := Damage.new(amount,strike.id if strike != null else &"",strike)
	request.source = source
	request.damage_type = kind
	request.impact = contact.get("position",victim.global_position)
	request.region = contact.get("region",&"")
	return victim.receive_damage(request)

func melee_reaches(caster: Combatant, victim: Combatant, reach: float, dot_limit: float = 0.15) -> bool:
	return not melee_contact(caster,victim,reach,dot_limit).is_empty()

func melee_contact(caster: Combatant, victim: Combatant, reach: float, dot_limit: float = 0.15) -> Dictionary:
	return Queries.contact(caster,victim,caster.global_position,reach,-caster.global_basis.z,dot_limit)

func melee(caster: Combatant, amount: float, strike: RefCounted, target: Combatant = null) -> void:
	var victims := opponents(caster,2.8)
	# Include an explicitly assigned target even before a teleported collider syncs.
	if is_instance_valid(target) and not victims.has(target): victims.append(target)
	for victim in victims:
		var hit := melee_contact(caster,victim,2.8)
		if not hit.is_empty(): deal(caster,victim,amount,strike,&"physical",hit)

func cast(caster: Combatant, definition: Resource, aim: Aim, strike: RefCounted) -> void:
	var origin := aim.origin
	tone(SPELL_TONES[&"projectile"] if definition.variant == &"projectile" else SPELL_TONES[&"burst"],SPELL_TONE_SECONDS)
	if definition.variant == &"projectile":
		var projectile: Node3D = projectile_scene.instantiate()
		projectile.direction = aim.direction()
		projectile.damage = definition.damage
		projectile.speed = definition.projectile_speed
		projectile.life = definition.projectile_lifetime
		projectile.source = caster
		projectile.strike_id = String(strike.id)
		projectile.strike = strike
		projectile.services = self
		projectile.hit_mask = 1|enemy_mask(caster)
		projectile.top_level = true
		host.add_child(projectile)
		projectile.global_position = origin
		transients.append(projectile)
	else:
		effect(origin,Color("bc99ef"),definition.radius)
		for victim in opponents(caster,definition.radius):
			var hit := Queries.contact(caster,victim,origin,definition.radius)
			if not hit.is_empty(): deal(caster,victim,definition.damage,strike,&"magic",hit)

func clear() -> void:
	if is_instance_valid(effects): effects.clear()
	for transient in transients:
		if is_instance_valid(transient): transient.queue_free()
	transients.clear()

func _exit_tree() -> void:
	clear()

func _process(_delta: float) -> void:
	for index in range(transients.size()-1,-1,-1):
		if not is_instance_valid(transients[index]) or transients[index].is_queued_for_deletion(): transients.remove_at(index)

func effect(position: Vector3, color: Color, radius: float) -> void:
	effects.effect(position,color,radius)

func tone(frequency: float, duration: float) -> void:
	effects.tone(frequency,duration)

func prepare_tone(frequency: float, duration: float) -> AudioStreamWAV:
	return effects.prepare_tone(frequency,duration)
