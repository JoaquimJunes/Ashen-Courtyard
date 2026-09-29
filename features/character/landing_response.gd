extends RefCounted
## Consumes one physical landing event; never integrates motion or changes Resources.
signal landed(severity: StringName, equivalent_height: float, damage: float)
const Definition = preload("res://features/character/landing_definition.gd")
const Damage = preload("res://features/combat/damage_request.gd")
var actor: CharacterBody3D
var definition: Definition
var last_height := 0.0
var last_damage := 0.0
var roll_succeeded := false
var severity: StringName = &"none"
var animation_time := 0.0
var animation_duration := 0.0
var serial := 0

func configure(character: CharacterBody3D, settings: Definition) -> void:
	actor = character
	definition = settings
	actor.movement.landed.connect(on_landed)

func reset() -> void:
	last_height = 0
	last_damage = 0
	roll_succeeded = false
	severity = &"none"
	animation_time = 0
	animation_duration = 0
	serial = 0

func tick(delta: float) -> void:
	animation_time += delta

func classify(speed: float, gravity: float) -> Dictionary:
	var height := maxf(0,speed)*maxf(0,speed)/(2.0*maxf(gravity,0.001))
	var kind: StringName = &"soft"
	var fraction := 0.0
	var duration := 0.0
	if height > definition.heavy_height:
		kind = &"heavy"
		duration = definition.heavy_recovery
	if height > definition.damage_height:
		kind = &"damaging"
		duration = definition.damaging_recovery
		fraction = clampf((height-definition.damage_height)/maxf(0.001,definition.lethal_height-definition.damage_height),0,1)
	if height >= definition.lethal_height:
		kind = &"lethal"
		fraction = 1.0
	return {"height":height,"severity":kind,"fraction":fraction,"recovery":duration}

func on_landed(impact_speed: float) -> void:
	if actor.dead: return
	var result := classify(impact_speed,actor.tuning.gravity)
	last_height = result.height
	severity = result.severity
	last_damage = result.fraction*actor.max_health
	# Classify the unmodified impact first: lethal heights can never become safe
	# through timing, stamina or dodge immunity. Ragdolls cannot perform inputs.
	roll_succeeded = actor.actions.try_landing_roll(result.severity in [&"heavy",&"damaging"])
	if roll_succeeded: last_damage *= actor.tuning.landing_roll.fall_damage_multiplier
	animation_time = 0
	animation_duration = result.recovery if result.recovery > 0 else definition.soft_animation_seconds
	if roll_succeeded: animation_duration = 0 # The accepted roll owns presentation.
	# Hard impact replaces any action and its buffered follow-up. Taking fall damage
	# cannot shorten this recovery through the ordinary combat hurt reaction.
	var physical_recovery: bool = actor.reactions.on_landing(severity,roll_succeeded)
	if result.recovery > 0 and not physical_recovery and not roll_succeeded: actor.actions.begin_landing(result.recovery)
	if last_damage > 0:
		serial += 1
		var strike = preload("res://features/combat/strike_token.gd").new()
		strike.id = StringName("fall_%s_%s" % [actor.get_instance_id(),serial])
		var request := Damage.new(last_damage,strike.id,strike)
		request.damage_type = &"fall"
		request.impact = actor.global_position
		actor.receive_damage(request)
	landed.emit(severity,last_height,last_damage)
