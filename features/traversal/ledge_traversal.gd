extends RefCounted
## Character feature: entry policy and attachment lifecycle; no level dependencies.
const Definition = preload("res://features/traversal/mantle_definition.gd")
const Candidate = preload("res://features/traversal/ledge_candidate.gd")
const Attachment = preload("res://features/traversal/surface_attachment.gd")
const Motion = preload("res://features/character/motion_request.gd")
const State = preload("res://features/character/character_states.gd").Action
const Result = preload("res://features/abilities/action_result.gd")
var release_ticket: RefCounted
var definition: Definition = preload("res://features/traversal/data/knight_mantle.tres")
var grab_definition: Resource = preload("res://features/traversal/data/ledge_grab.tres")
var probe := preload("res://features/traversal/ledge_probe.gd").new()
var mantle := preload("res://features/traversal/mantle_action.gd").new()
var shimmy := preload("res://features/traversal/ledge_shimmy.gd").new()
var actor: CharacterBody3D
var candidate: Candidate
var grab_from := Vector3.ZERO
var status: StringName = &"idle"
var reason: StringName = &"idle"
var cooldown := 0.0
var pull_retry := 0.0
var releasing := false

func configure(character: CharacterBody3D) -> void:
	actor = character
	probe.configure(actor,actor.motor,definition)
	shimmy.configure(self)
	actor.actions.cancelled.connect(on_cancelled)

func attached() -> bool: return actor.movement.attachment != null

func request_release() -> Result:
	if release_ticket != null: return release_ticket
	release_ticket = Result.new(false,&"queued")
	release_ticket.resolved = false
	return release_ticket

func intent_tick(intent: RefCounted, delta: float) -> void:
	if actor.crawling.active: return
	if release_ticket != null:
		var ticket := release_ticket
		release_ticket = null
		release(&"let_go")
		ticket.resolve(true,&"released")
		return
	cooldown = maxf(0,cooldown-delta)
	pull_retry = maxf(0,pull_retry-delta)
	if attached():
		if not probe.grip_valid(candidate):
			release(&"surface_lost")
			return
		if status == &"hang":
			shimmy.prepare(intent.surface_motion.x if intent.surface_motion.y <= 0.25 else 0.0,delta)
			reason = shimmy.reason
		var toward_water_exit: bool = candidate.from_water and intent.movement.dot(-candidate.normal) > 0.25
		if status == &"hang" and (intent.surface_motion.y > 0.25 or toward_water_exit) and pull_retry <= 0:
			actor.actions.request("mantle")
			pull_retry = 0.15
		return
	if cooldown > 0 or actor.dead or actor.reactions.active or not actor.actions.is_available(): return
	if actor.swimming.active:
		if not actor.swimming.can_exit(): return
		candidate = probe.find(intent.movement,delta,actor.swimming.water.surface_y(),actor.swimming.definition.ledge_height)
		reason = probe.reason
		if candidate != null and candidate.can_mantle: actor.actions.request("ledge_grab")
		else: candidate = null
		return
	if not actor.movement.ledge_jump or not actor.motor.is_airborne() or actor.velocity.y < -definition.maximum_descent_speed: return
	candidate = probe.find(intent.movement,delta)
	reason = probe.reason
	if candidate != null and not above_jump_height(candidate.lip.y):
		candidate = null
		reason = &"within_jump_height"
	if candidate != null: actor.actions.request("ledge_grab")

func above_jump_height(lip_y: float) -> bool:
	# Entry policy only: existing hanging/shimmy support is validated separately.
	# A millimetre of tolerance prevents equal-height surfaces passing on roundoff.
	return lip_y-actor.movement.jump_origin_y > actor.tuning.jump.height+0.001

func requirement(action: String) -> StringName:
	if action == "ledge_grab":
		if candidate == null or not probe.grip_valid(candidate): return &"no_ledge"
		if candidate.from_water:
			if not actor.swimming.can_exit() or not probe.update_mantle(candidate): return &"water_exit_blocked"
		elif not above_jump_height(candidate.lip.y): return &"within_jump_height"
		if Engine.get_physics_frames()-candidate.query_tick > 1: return &"stale_ledge"
		if not actor.motor.posture_path_clear(actor.global_transform,candidate.hang-actor.global_position,definition.tuck_height,definition.tuck_offset,0.003): return &"blocked_grip"
		return &""
	if not attached() or status != &"hang": return &"not_hanging"
	probe.update_mantle(candidate)
	reason = candidate.reason
	return &"" if candidate.can_mantle else candidate.reason

func begin_grab() -> void:
	if candidate.from_water: actor.swimming.begin_exit()
	grab_from = actor.global_position
	actor.presentation.mantle.begin(candidate)
	actor.presentation.jump.reset()
	actor.landing.animation_duration = 0
	actor.motor.set_posture(definition.tuck_height,definition.tuck_offset)
	actor.motor.stop()
	actor.motor.face_direction(-candidate.normal)
	var lease := Attachment.new()
	lease.motion_applied.connect(shimmy.after_move)
	lease.candidate = candidate
	lease.hold_position = candidate.hang
	actor.movement.attach(lease)
	status = &"grab"
	reason = &"gripping"

func begin_mantle() -> void:
	shimmy.reset()
	actor.movement.attachment.motion = null
	status = &"mantle"
	reason = &"pulling_up"
	mantle.begin(candidate,definition)

func before_move(delta: float) -> void:
	if not attached(): return
	if status == &"grab":
		var motion := Motion.new()
		motion.kind = Motion.Kind.CONSTRAINED
		motion.attachment_token = actor.movement.attachment.token
		motion.target_position = grab_from.lerp(candidate.hang,smoothstep(0,grab_definition.active_seconds,actor.actions.timer))
		actor.actions.motion = motion
	elif status == &"mantle":
		if mantle.phase == mantle.Phase.SETTLE and actor.motor.tucked:
			if not actor.motor.restore_posture():
				release(&"standing_blocked")
				return
		actor.actions.motion = mantle.request(delta,actor.movement.attachment.token)

func after_move(_delta: float) -> void:
	if not attached(): return
	var result: RefCounted = actor.motor.last_result
	if status == &"grab":
		if result.blocked:
			release(&"blocked_grip")
		elif actor.actions.timer >= grab_definition.active_seconds:
			status = &"hang"
			reason = &"hanging"
			actor.actions.state = State.FREE
	elif status == &"mantle":
		var outcome := mantle.after_move(result)
		if outcome == &"complete": complete()
		elif outcome != &"": release(outcome)

func complete() -> void:
	shimmy.reset()
	status = &"idle"
	reason = &"completed"
	actor.actions.finish()
	actor.movement.detach(true)
	actor.motor.stop()
	actor.presentation.mantle.finish()
	mantle.reset()
	candidate = null

func release(why: StringName = &"released") -> void:
	if releasing: return
	releasing = true
	shimmy.reset()
	if release_ticket != null:
		release_ticket.resolve(false,why)
		release_ticket = null
	if attached():
		actor.actions.cancel(why)
		actor.movement.detach()
		actor.motor.motion_reset.emit()
		actor.motor.restore_posture()
		actor.presentation.mantle.finish()
		actor.swimming.prepare(0.0)
	status = &"idle"
	reason = why
	candidate = null
	mantle.reset()
	cooldown = definition.release_cooldown
	pull_retry = 0
	releasing = false

func on_cancelled(id: StringName, why: StringName) -> void:
	if id in [&"ledge_grab",&"mantle"] and attached(): release(why)

func reset() -> void:
	if release_ticket != null:
		release_ticket.resolve(false,&"reset")
		release_ticket = null
	release(&"reset")
	cooldown = 0
	reason = &"idle"
