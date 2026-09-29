extends "res://features/abilities/action_lifecycle.gd"
## Owns one committed action and its bounded input buffer per character.
const DodgeDefinition = preload("res://features/abilities/dodge_definition.gd")
const State = preload("res://features/character/character_states.gd").Action
const DodgePhase = preload("res://features/character/character_states.gd").DodgePhase
var state := State.FREE
var combo := 0
var combo_until := 0.0
var combo_moveset: StringName
var released := false
var cast_spell := 0
var dodge_phase := DodgePhase.NONE
var dodge_ground_time := 0.0
var dodge_distance_left: float:
	get: return travel.remaining
	set(value): travel.reset(value)
var dodge_dir := Vector3.ZERO
var forward_dive = preload("res://features/abilities/forward_dive.gd").new()
var ground_roll = preload("res://features/abilities/ground_roll.gd").new()
var landing_duration := 0.0
var resetting := false
var active_item: RefCounted
var _prepared_item: RefCounted
var held_heavy_ticket: RefCounted
var held_heavy_serial := -1
const ITEM_ACTIONS := ["light","heavy","cast","heal","use_gadget"]

func definition_for(action: String) -> Definition:
	if action in ITEM_ACTIONS and actor.items.catalog != null:
		actor.items.resolver.legacy_tuning = actor.tuning
		return actor.items.resolver.ability_for(action)
	match action:
		"crawl": return preload("res://features/abilities/data/crawl.tres")
		"crouch": return preload("res://features/abilities/data/crouch.tres")
		"ledge_grab": return actor.traversal.grab_definition
		"mantle": return actor.traversal.definition
		"landing_roll": return tuning.landing_roll
		"jump": return tuning.jump
		"light": return tuning.light
		"heavy": return tuning.heavy
		"cast": return tuning.bolt if actor.selected_spell == 0 else tuning.burst
		"heal": return tuning.heal
		"dodge":
			var local: Vector3 = actor.global_basis.inverse()*requested_dodge_direction()
			# Match the animation's dominant-axis selection, captured at action start.
			if local.z > 0 or absf(local.x) > absf(local.z):
				return tuning.dodge_ground
			return tuning.dodge_forward
	return null

func can_pay(action: String, definition: Definition) -> bool:
	if action in ITEM_ACTIONS:
		return actor.resources.can_spend(definition.stamina_cost,definition.mana_cost) and actor.items.resolver.can_pay(action)
	return super.can_pay(action,definition)

func capture_definition(action: String, definition: Definition) -> Definition:
	_prepared_item = actor.items.resolver.capture(action) if action in ITEM_ACTIONS else null
	return _prepared_item.ability if _prepared_item != null else definition

func pay_cost(action: String, definition: Definition) -> bool:
	if action in ITEM_ACTIONS: return actor.items.resolver.commit(_prepared_item,actor.resources)
	return super.pay_cost(action,definition)

func notify_cost_changed(action: String) -> void:
	if action in ITEM_ACTIONS: actor.items.inventory.changed.emit()

func requested_dodge_direction() -> Vector3:
	var direction: Vector3 = actor.movement_direction()
	if direction == Vector3.ZERO:
		direction = -actor.global_basis.z
	return direction

func is_available() -> bool: return state == State.FREE

func heavy_charging() -> bool:
	return state == State.HEAVY and active_definition != null and timer < active_definition.windup

func request_heavy_charge() -> RefCounted:
	# A held charge owns the normal heavy action, including costs and windup.
	# Never buffer it: releasing must not leave a heavy attack waiting to start.
	held_heavy_ticket = request("heavy")
	return held_heavy_ticket

func release_heavy_charge() -> void:
	if held_heavy_serial == serial and heavy_charging(): cancel(&"heavy_charge_released")

func can_buffer() -> bool: return state not in [State.RAGDOLL,State.GET_UP,State.LEDGE_GRAB,State.MANTLE]

func retains_pending() -> bool:
	# Retain the current attack's one follow-up (or the dodge replacing it).
	# Heavy/cast/jump requests keep their normal short input windows.
	return not unloaded and is_instance_valid(actor) and not actor.dead and state == State.LIGHT and active_definition != null and pending_may_wait and pending_owner_serial == serial and buffered in ["light","dodge"]

func tick(ongoing_stamina: float = 0, ongoing_mana: float = 0) -> bool:
	var paid := super.tick(ongoing_stamina,ongoing_mana)
	if request_block_reason() == &"": try_light_chain()
	return paid

func try_light_chain() -> void:
	if not retains_pending() or buffered != "light" or active_definition.chain_after_active < 0: return
	var opens := active_definition.windup+active_definition.active_seconds+minf(active_definition.chain_after_active,active_definition.recovery)
	if timer < opens: return
	# Only commitment is exempted. Costs, posture and movement requirements still
	# apply. Failure keeps the outgoing attack alive to play its normal recovery.
	var reason := validate("light",false,true)
	if reason != &"":
		resolve_pending(reason)
		return
	var owner := serial
	var ticket := pending_result
	combo_until = tuning.combo_grace
	finish()
	# Finished observers may kill, reset, unload or replace the request. Respect
	# that newer state; otherwise start/pay through the usual commit path now,
	# before presentation runs, without a rendered idle frame between swings.
	if serial == owner and pending_result == ticket and active_definition == null and is_available() and not actor.dead and request_block_reason() == &"":
		super.tick()

func request(action: String, allow_buffer: bool = false) -> Result:
	var blocked := request_block_reason()
	if blocked != &"": return reject_request(action,blocked)
	if actor.crawling.active and action not in ["crouch","crawl"]:
		return reject_request(action,&"crawling")
	if not actor.dead and actor.swimming.active and action not in ["ledge_grab","mantle"]:
		return reject_request(action,&"movement_mode")
	if allow_buffer and action == "light" and buffered == "light" and retains_pending():
		return pending_result
	if allow_buffer and action == "dodge" and state == State.LIGHT:
		# A dodge replaces a queued swing even during flight. At attack completion
		# its ordinary grounded requirement is rechecked; it cannot become an air dodge.
		return super.request(action,true)
	if action == "crouch":
		return super.request(action,false)
	if actor.movement.attachment != null:
		if action == "dodge": return actor.traversal.request_release()
		var requested := definition_for(action)
		if requested != null and not requested.allowed_modes.has(&"climbing"): return reject_request(action,&"movement_mode")
	if (action == "dodge" and not actor.is_on_floor() and actor.velocity.y < 0) or action == "landing_roll":
		# A fresh input edge becomes a contact request, not a midair dodge. Keep
		# only the lifecycle's existing one-slot buffer; holding the key cannot arm it.
		if actor.is_on_floor() or actor.velocity.y >= 0: return reject_request(action,&"requires_descent")
		if not landing_roll_controlled(): return reject_request(action,&"committed")
		return super.request("landing_roll",true)
	return super.request(action,allow_buffer)

func landing_roll_controlled() -> bool:
	return not actor.dead and not actor.reactions.active and state in [State.FREE,State.DODGE]

func try_landing_roll(eligible: bool) -> bool:
	if buffered != "landing_roll": return false
	var reason: StringName = &"" if eligible else &"landing_not_eligible"
	if reason == &"" and not landing_roll_controlled(): reason = &"committed"
	if reason == &"" and not actor.is_on_floor(): reason = &"requires_ground"
	if reason == &"": reason = validate("landing_roll",true)
	# Shared payment resolves before replacement; failure never partly spends.
	var pose: Array = actor.presentation.capture_pose()
	var result := resolve_pending(reason,&"landing_roll")
	if result.accepted: actor.presentation.blend_ground_roll_from(pose)
	return result.accepted

func additional_requirement(action: String) -> StringName:
	if actor.crawling.active:
		if action not in ["crouch","crawl"]: return &"crawling"
		if action == "crouch" and not actor.crawling.can_rise(): return &"crouch_blocked"
	if action == "crawl": return actor.crawling.requirement()
	if not actor.dead and actor.swimming.active and action not in ["ledge_grab","mantle"]: return &"movement_mode"
	if action in ITEM_ACTIONS and not actor.items.resolver.presentation_available(action,actor.model.animation): return &"missing_animation"
	if action == "crouch" and actor.posture.crouched and not actor.posture.can_stand(): return &"standing_blocked"
	if definition_for(action).requires_standing and not actor.posture.can_stand(): return &"standing_blocked"
	if action in ["ledge_grab","mantle"]: return actor.traversal.requirement(action)
	if action == "landing_roll": return &"landing_contact"
	if action == "jump" and not actor.movement.can_jump(): return &"requires_ground"
	var binding: Resource = actor.items.resolver.binding_for(action) if action in ITEM_ACTIONS else null
	return &"full_health" if binding != null and binding.executor == "heal" and actor.health >= actor.max_health else &""

func prepare_start(action: String) -> StringName:
	if action == "crawl": return actor.crawling.enter()
	if action == "crouch" and actor.crawling.active: return actor.crawling.rise()
	if action == "crouch": return actor.posture.toggle()
	if definition_for(action).requires_standing and not actor.posture.stand(): return &"standing_blocked"
	return &""

func wait_for_requirement(action: String, reason: StringName) -> bool:
	if action == "landing_roll": return reason in [&"requires_ground",&"landing_contact"]
	return action == "jump" and reason == &"requires_ground"

func begin_landing(duration: float) -> void:
	# Contact is a forced reaction, not a paid input request. It acquires the same
	# single action slot and releases every interrupted action/buffer first.
	if resetting or unloaded: return
	cancel(&"heavy_landing")
	if actor.dead or state != State.FREE: return
	active_definition = tuning.landing_action
	landing_duration = duration
	state = State.LAND
	timer = 0
	started.emit(active_definition.id)

func begin_ragdoll() -> void:
	if resetting or unloaded: return
	cancel(&"ragdoll")
	# Fatal reactions retain physical motion through ReactionController, without
	# acquiring a new action after death (including death inside cancel callbacks).
	if actor.dead:
		state = State.DEAD
		return
	active_definition = preload("res://features/abilities/data/ragdoll.tres")
	state = State.RAGDOLL
	started.emit(active_definition.id)

func begin_get_up() -> void:
	if not actor.dead and active_definition != null and active_definition.id == &"ragdoll":
		state = State.GET_UP

func clocks(delta: float) -> void:
	super.clocks(delta)
	combo_until -= delta

func finish_if_idle() -> void:
	if state == State.FREE: finish()

func after_motion(delta: float) -> void:
	if state in [State.LEDGE_GRAB,State.MANTLE]:
		actor.traversal.after_move(delta)
		return
	if state != State.DODGE: return
	if forward_dive.active: forward_dive.after_move(delta)
	elif ground_roll.active: ground_roll.after_move(delta)

func release_action() -> void:
	held_heavy_ticket = null
	held_heavy_serial = -1
	active_item = null
	_prepared_item = null
	clear_dodge()
	released = false
	landing_duration = 0
	state = State.DEAD if actor.dead else State.FREE

func interrupt_for_damage() -> void:
	if actor.dead or resetting or unloaded: return
	if heavy_charging():
		cancel(&"heavy_charge_damage")
		return
	cancel(&"damage")
	# A cancellation observer can deliver another hit and force death/ragdoll.
	# That newer reaction keeps priority over this ordinary hurt response.
	if not actor.dead and state == State.FREE: state = State.HURT

func die() -> void:
	cancel(&"death")
	state = State.DEAD

func reset() -> void:
	if resetting: return
	# Unlike ordinary cancellation, reset also suppresses forced action acquisition
	# from callbacks. The character then resets physical reactions and the motor.
	resetting = true
	cancel(&"reset")
	state = State.FREE
	combo = 0
	combo_until = 0
	combo_moveset = &""
	cast_spell = 0
	serial = 0
	dodge_dir = Vector3.ZERO
	resetting = false

func advance(delta: float) -> void:
	match state:
		State.LEDGE_GRAB, State.MANTLE: actor.traversal.before_move(delta)
		State.JUMP:
			if timer >= active_definition.active_seconds: state = State.FREE
		State.LAND:
			if timer >= landing_duration: state = State.FREE
		State.DODGE:
			if forward_dive.active:
				forward_dive.before_move(delta)
			elif ground_roll.active:
				ground_roll.before_move(delta)
		State.LIGHT, State.HEAVY:
			var heavy := state == State.HEAVY
			var windup := active_definition.windup
			var active := active_definition.active_seconds
			var recovery := active_definition.recovery
			if timer >= windup and timer < windup+active:
				request_motion(-actor.global_basis.z*1.5)
				if strike == null:
					strike = preload("res://features/combat/strike_token.gd").new()
					strike.id = StringName("player_%s_%s" % [actor.get_instance_id(),serial])
				actor.services.melee(actor,active_definition.damage,strike,actor.target)
			if timer >= windup+active+recovery:
				state = State.FREE
				combo_until = tuning.combo_grace if not heavy else 0
		State.CAST:
			var definition := active_definition
			var owner := serial
			if timer >= definition.windup and not released:
				released = true
				actor.services.cast(actor,definition,actor.get_aim(),strike)
				# Damage callbacks may cancel this cast or start another using the same definition.
				if active_definition != definition or serial != owner: return
			if timer >= definition.windup+definition.recovery: state = State.FREE
		State.HEAL:
			if timer >= active_definition.windup and not released:
				released = true
				actor.resources.heal(active_definition.heal_amount)
				actor.services.effect(actor.global_position+Vector3.UP,Color("eac77b"),0.8)
			if timer >= active_definition.windup+active_definition.recovery: state = State.FREE
		State.HURT:
			if timer >= tuning.hurt_duration: state = State.FREE

func start_action(action: String) -> void:
	if action == "heavy" and held_heavy_ticket != null and not held_heavy_ticket.resolved:
		held_heavy_serial = serial
	held_heavy_ticket = null
	active_item = _prepared_item if action in ITEM_ACTIONS else null
	_prepared_item = null
	var execution: String = active_item.executor if active_item != null else action
	match execution:
		"ledge_grab":
			state = State.LEDGE_GRAB
			actor.traversal.begin_grab()
		"mantle":
			state = State.MANTLE
			actor.traversal.begin_mantle()
		"jump":
			state = State.JUMP
			actor.movement.takeoff(actor.global_position.y)
			actor.motor.launch(sqrt(2.0*tuning.gravity*active_definition.height))
		"light", "heavy":
			state = State.LIGHT if execution == "light" else State.HEAVY
			var key: StringName = active_item.moveset_key if active_item != null else &"legacy"
			var count: int = active_item.combo_count if active_item != null else 2
			combo = posmod(combo+1,count) if combo_until > 0 and execution == "light" and combo_moveset == key else 0
			combo_moveset = key
			if actor.locked and is_instance_valid(actor.target): actor.face_direction(actor.target.global_position-actor.global_position)
			else: actor.face_direction(-Basis(Vector3.UP,actor.rig.rotation.y).z)
		"dodge", "landing_roll":
			# Direction and definition remain fixed throughout this action.
			state = State.DODGE
			dodge_phase = DodgePhase.AIRBORNE
			dodge_ground_time = 0.0
			var definition := active_definition as DodgeDefinition
			dodge_distance_left = definition.distance
			dodge_dir = -actor.global_basis.z if action == "landing_roll" else requested_dodge_direction()
			if action == "landing_roll": actor.presentation.jump.reset()
			if active_definition.variant == &"dodge_forward":
				forward_dive.begin(actor)
			elif active_definition.variant == &"dodge_ground":
				ground_roll.begin(actor)
		"cast":
			cast_spell = actor.selected_spell
			state = State.CAST
			if actor.locked and is_instance_valid(actor.target): actor.face_direction(actor.target.global_position-actor.global_position)
			else: actor.face_direction(-Basis(Vector3.UP,actor.rig.rotation.y).z)
		"heal":
			state = State.HEAL
		_: return
	timer = 0
	released = false

func clear_dodge() -> void:
	forward_dive.finish()
	ground_roll.finish()
	dodge_phase = DodgePhase.NONE
	dodge_ground_time = 0.0
	dodge_distance_left = 0.0
	actor.invulnerable = false
	if is_instance_valid(actor.model): actor.model.end_dodge()
