extends RefCounted
## Persistent ground stance, not a committed action or alternative body mover.
signal changed
const Definition = preload("res://features/crawling/crawl_definition.gd")
var definition: Definition = preload("res://features/crawling/crawling.tres")
var actor: CharacterBody3D
var active := false
var last_reason: StringName

func configure(character: CharacterBody3D) -> void:
	actor = character
	actor.motor.motion_reset.connect(on_motion_reset)

func available() -> bool:
	return actor.model.animation.has_animation(definition.clip)

func requirement() -> StringName:
	if not available(): return &"missing_animation"
	if actor.dead: return &"dead"
	if actor.swimming.active or actor.movement.attachment != null: return &"movement_mode"
	if not actor.actions.is_available(): return &"committed"
	if actor.motor.is_airborne(): return &"requires_ground"
	return &""

func enter() -> StringName:
	last_reason = requirement()
	if last_reason != &"" or active: return last_reason
	if not actor.motor.set_crawl_posture(definition):
		last_reason = &"posture_blocked"
		return last_reason
	active = true
	actor.posture.reset()
	actor.locked = false
	actor.sprinting = false
	actor.controller.reset_attack()
	actor.motor.stop()
	actor.model.clear_action_exit()
	actor.presentation.crouch.reset()
	changed.emit()
	return &""

func can_rise() -> bool:
	return actor.motor.crawl_can_rise(actor.posture.definition.crouch_height)

func rise() -> StringName:
	if not active: return &""
	if not actor.actions.is_available(): return &"committed"
	var height: float = actor.posture.definition.crouch_height
	if not actor.motor.rise_from_crawl(height):
		last_reason = &"crouch_blocked"
		return last_reason
	active = false
	actor.posture.crouched = true
	actor.posture.changed.emit(true)
	changed.emit()
	last_reason = &""
	return &""

func on_motion_reset() -> void:
	if not actor.motor.crawling_posture: reset()

func recovered_prone() -> void:
	active = true
	actor.posture.reset()
	actor.locked = false
	actor.sprinting = false
	changed.emit()
	# There is no authored prone recovery clip. Start from the safe crawl pose;
	# a standing get-up would visibly pass through the roof that blocked recovery.
	actor.presentation.crawl.from_pose.clear()
	actor.presentation.crawl.sample(0)

func reset() -> void:
	var was_active := active
	active = false
	last_reason = &""
	if actor != null: actor.controller.reset_stance()
	if was_active: changed.emit()
