extends RefCounted
## Shared request/cost/commitment lifecycle. Requests resolve in physics ticks or
## actual contact callbacks, always through the same atomic payment path.
signal started(id: StringName)
signal finished(id: StringName)
signal cancelled(id: StringName, reason: StringName)
signal request_completed(action: StringName, result: RefCounted)
const Result = preload("res://features/abilities/action_result.gd")
const Definition = preload("res://features/abilities/ability_definition.gd")
const Motion = preload("res://features/character/motion_request.gd")
const Budget = preload("res://features/character/motion_budget.gd")
var motion := Motion.new()
var travel := Budget.new()
var actor: CharacterBody3D
var tuning: CombatTuning
var active_definition: Definition
var capabilities: Array[StringName] = []
var strike: RefCounted
var serial := 0
var timer := 0.0
var buffered := ""
var buffer_time := 0.0
var pending_result: RefCounted
var pending_may_wait := false
var pending_owner_serial := -1
var cancelling := false
var unloaded := false

func configure(character: CharacterBody3D) -> void:
	actor = character
	tuning = character.tuning
	unloaded = false
	if not actor.movement.mode_changed.is_connected(on_mode_changed):
		actor.movement.mode_changed.connect(on_mode_changed)

func definition_for(_action: String) -> Definition: return null
func is_available() -> bool: return active_definition == null
func can_buffer() -> bool: return true
func retains_pending() -> bool: return false
func start_action(_action: String) -> void: pass
func release_action() -> void: pass
func advance(_delta: float) -> void: pass
func after_motion(_delta: float) -> void: pass
func finish_if_idle() -> void: pass

func begin_motion_frame() -> void:
	motion = Motion.new()

func request_motion(velocity: Vector3, airborne_velocity: Vector3 = Vector3.ZERO, steps: bool = false, air_gravity: float = 1.0, budget: Budget = null) -> void:
	motion = Motion.new()
	motion.kind = Motion.Kind.VELOCITY
	motion.ground_velocity = velocity
	motion.air_velocity = airborne_velocity
	motion.air_policy = active_definition.airborne_motion if active_definition != null else Motion.AirPolicy.INHERIT
	motion.allow_step = steps
	motion.air_gravity_scale = air_gravity
	motion.budget = budget

func release_motion() -> void:
	motion = Motion.new()
	travel.reset()

func additional_requirement(_action: String) -> StringName: return &""
## Commit-time physical preparation, after validation and before payment.
func prepare_start(_action: String) -> StringName: return &""
func wait_for_requirement(_action: String, _reason: StringName) -> bool: return false

## Extension points keep all costs inside the same acceptance transaction.
func can_pay(action: String, definition: Definition) -> bool:
	return actor.resources.can_spend(definition.stamina_cost,definition.mana_cost,definition.flask_cost)

func capture_definition(_action: String, definition: Definition) -> Definition:
	return definition

func pay_cost(_action: String, definition: Definition) -> bool:
	return actor.resources.try_spend(definition.stamina_cost,definition.mana_cost,definition.flask_cost)

func notify_cost_changed(_action: String) -> void: pass

func reject_request(action: String, reason: StringName) -> Result:
	var rejected := Result.new(false,reason)
	request_completed.emit(StringName(action),rejected)
	return rejected

func request(action: String, allow_buffer: bool = false) -> Result:
	# Early rejection reports a completed request without changing action ownership
	# or costs. Acceptance/spending occurs in tick(), after ongoing costs and revalidation.
	var reason := validate(action,allow_buffer)
	if reason != &"": return reject_request(action,reason)
	var previous_action := buffered
	var previous_ticket := pending_result
	buffered = action
	var definition := definition_for(action)
	buffer_time = definition.input_buffer_seconds if definition.input_buffer_seconds >= 0 else tuning.input_buffer
	pending_may_wait = allow_buffer
	pending_owner_serial = serial
	var ticket := Result.new(false,&"queued")
	ticket.resolved = false
	pending_result = ticket
	# Publish the replacement before notifying observers. A callback may enqueue
	# an even newer request or cancel this one; never overwrite its result afterward.
	if previous_ticket != null:
		previous_ticket.resolve(false,&"superseded")
		request_completed.emit(StringName(previous_action),previous_ticket)
	return ticket

func validate(action: String, allow_buffer: bool = false, allow_replacement: bool = false) -> StringName:
	var blocked := request_block_reason()
	if blocked != &"": return blocked
	if actor.dead: return &"dead"
	if not allow_replacement and not is_available() and (not allow_buffer or not can_buffer()): return &"committed"
	var definition := definition_for(action)
	if definition == null: return &"unknown_action"
	if not actor.combat_enabled and definition.combat_action: return &"disabled"
	for required in definition.required_capabilities:
		if not capabilities.has(required): return &"missing_capability"
	if allow_buffer: return &""
	if not definition.allowed_modes.has(actor.movement.mode): return &"movement_mode"
	if definition.requires_ground and not actor.is_on_floor(): return &"requires_ground"
	if not can_pay(action,definition): return &"insufficient_resources"
	return additional_requirement(action)

func request_block_reason() -> StringName:
	if unloaded: return &"unloaded"
	return &"cancelling" if cancelling else &""

func clocks(delta: float) -> void:
	timer += delta
	if not retains_pending():
		buffer_time -= delta
		if buffer_time <= 0: reject_pending(&"expired")

func tick(ongoing_stamina: float = 0, ongoing_mana: float = 0) -> bool:
	if request_block_reason() != &"": return false
	var ongoing_paid: bool = actor.resources.try_spend(ongoing_stamina,ongoing_mana)
	if not is_available() or buffered.is_empty(): return ongoing_paid
	var action := buffered
	var reason := validate(action)
	# Only an explicitly bufferable physical requirement may wait for contact.
	# Costs are still checked and paid once, on the tick that actually launches.
	if pending_may_wait and wait_for_requirement(action,reason): return ongoing_paid
	resolve_pending(reason)
	return ongoing_paid

func resolve_pending(reason: StringName, replacement_reason: StringName = &"") -> Result:
	# Contact reactions may replace an action. Detach the one queued request first
	# so cancelling its predecessor cannot also cancel the accepted replacement.
	var action := buffered
	var ticket := pending_result
	buffered = ""
	buffer_time = 0
	pending_result = null
	pending_may_wait = false
	pending_owner_serial = -1
	var definition := definition_for(action)
	if reason == &"": definition = capture_definition(action,definition)
	if reason == &"": reason = prepare_start(action)
	if reason == &"" and not pay_cost(action,definition):
		reason = &"insufficient_resources"
	if reason == &"":
		if replacement_reason != &"": cancel(replacement_reason)
		active_definition = definition
		serial += 1
		timer = 0
		strike = preload("res://features/combat/strike_token.gd").new()
		strike.id = StringName("%s_%s" % [actor.get_instance_id(),serial])
		start_action(action)
		started.emit(definition.id)
	var result: RefCounted = ticket if ticket != null else Result.new(false,&"queued")
	result.resolved = false
	result.resolve(reason == &"",&"accepted" if reason == &"" else reason)
	request_completed.emit(StringName(action),result)
	if result.accepted: notify_cost_changed(action)
	return result

func reject_pending(reason: StringName) -> void:
	var action := buffered
	buffered = ""
	buffer_time = 0
	pending_may_wait = false
	pending_owner_serial = -1
	var ticket := pending_result
	pending_result = null
	if ticket != null:
		ticket.resolve(false,reason)
		request_completed.emit(StringName(action),ticket)

func finish() -> void:
	if active_definition == null: return
	var id := active_definition.id
	release_action()
	release_motion()
	active_definition = null
	strike = null
	finished.emit(id)

func cancel(reason: StringName) -> void:
	# Cancellation is one transaction, including synchronous ticket and lifecycle
	# callbacks. Observers see released ownership and cannot queue a replacement
	# until this method returns. Nested cancellation is already handled by its owner.
	if cancelling: return
	cancelling = true
	var id: StringName = active_definition.id if active_definition != null else &""
	release_action()
	release_motion()
	active_definition = null
	strike = null
	timer = 0
	reject_pending(reason)
	if id != &"": cancelled.emit(id,reason)
	cancelling = false

func unload() -> void:
	# Teardown is terminal even after its cancellation callbacks return.
	unloaded = true
	cancel(&"unload")

func on_mode_changed(_previous: StringName, current: StringName) -> void:
	if active_definition != null and not active_definition.allowed_modes.has(current):
		if active_definition.mode_exit_policy == Definition.ModeExit.CANCEL:
			cancel(&"movement_mode_changed")
