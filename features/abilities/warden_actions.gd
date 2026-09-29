extends "res://features/abilities/action_lifecycle.gd"
const BossDefinition = preload("res://features/abilities/boss_attack_definition.gd")
## Warden execution plugs into the same lifecycle used by the player.
enum Phase { APPROACH, TELEGRAPH, ATTACK, RECOVERY }
var phase := Phase.APPROACH
var strikes: Dictionary = {}
var released := false

func definition_for(action: String) -> Definition:
	match action:
		"boss_combo": return tuning.combat.boss_combo
		"boss_overhead": return tuning.combat.boss_overhead
		"boss_lunge": return tuning.combat.boss_lunge
		"bolt": return tuning.bolt
		"burst": return tuning.burst
	return null

func start_action(_action: String) -> void:
	phase = Phase.TELEGRAPH
	released = false
	strikes.clear()
	strikes[0] = strike

func release_action() -> void:
	strikes.clear()
	released = false
	phase = Phase.APPROACH
	timer = 0

func advance(_delta: float) -> void:
	if active_definition == null: return
	if active_definition.variant in [&"projectile",&"burst"]:
		var casting := active_definition
		var owner := serial
		if timer >= casting.windup and not released:
			released = true
			actor.services.cast(actor,casting,actor.get_aim(),strike)
			# Encounter completion can synchronously freeze/cancel the caster.
			if active_definition != casting or serial != owner: return
		if timer >= casting.windup+casting.recovery: finish()
		return
	var definition := active_definition as BossDefinition
	match phase:
		Phase.TELEGRAPH:
			if timer >= definition.windup: phase = Phase.ATTACK; timer = 0
		Phase.ATTACK:
			var second := definition.active_seconds+definition.combo_gap
			var active := timer < definition.active_seconds or (definition.pattern == 0 and timer >= second and timer < second+definition.active_seconds)
			var strike_index := 1 if timer >= second else 0
			if definition.pattern == 2 and timer < definition.lunge_duration:
				request_motion(-actor.global_basis.z*definition.lunge_speed)
				active = true
			var contact: Dictionary = actor.services.melee_contact(actor,actor.target,definition.reach,definition.arc_dot) if active and is_instance_valid(actor.target) else {}
			if not contact.is_empty():
				if not strikes.has(strike_index):
					strikes[strike_index] = preload("res://features/combat/strike_token.gd").new(StringName("%s_%s_%s" % [actor.get_instance_id(),serial,strike_index]))
				actor.services.deal(actor,actor.target,definition.damage,strikes[strike_index],&"physical",contact)
			var duration := second+definition.active_seconds if definition.pattern == 0 else (definition.lunge_duration if definition.pattern == 2 else definition.active_seconds)
			if timer > duration+definition.attack_tail: phase = Phase.RECOVERY; timer = 0
		Phase.RECOVERY:
			if timer >= definition.recovery: finish()
