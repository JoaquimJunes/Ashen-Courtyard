extends RefCounted
## Persistent stance, independent of movement mode and committed action.
## The motor alone edits collision; presentation only reads this state.
signal changed(crouched: bool)
const Definition = preload("res://features/character/posture_definition.gd")
var definition: Definition = preload("res://features/character/data/knight_posture.tres")
var actor: CharacterBody3D
var crouched := false
var last_reason: StringName = &""

func configure(character: CharacterBody3D) -> void:
	actor = character
	actor.landing.landed.connect(on_landed)
	actor.motor.motion_reset.connect(on_motion_reset)

func toggle() -> StringName:
	last_reason = &""
	if actor.dead: last_reason = &"dead"
	elif not actor.actions.is_available() or actor.movement.attachment != null: last_reason = &"committed"
	elif actor.motor.is_airborne(): last_reason = &"requires_ground"
	elif crouched:
		if not stand(): last_reason = &"standing_blocked"
	else:
		# Collision gains clearance immediately; presentation owns the visual blend.
		var height := minf(1.0,minf(definition.crouch_height,actor.motor.standing_height))
		if actor.motor.set_posture(height,height*0.5,true,true):
			crouched = true
			changed.emit(true)
		else: last_reason = &"posture_blocked"
	return last_reason

func can_stand() -> bool:
	return not crouched or actor.motor.standing_clear()

func stand() -> bool:
	if not crouched: return true
	if not actor.motor.restore_posture():
		last_reason = &"standing_blocked"
		return false
	crouched = false
	last_reason = &""
	changed.emit(false)
	return true

func on_landed(severity: StringName, _height: float, _damage: float) -> void:
	# Soft landings keep stance; forced recoveries may stand only when safe.
	if severity != &"soft" and not actor.reactions.active: stand()

func on_motion_reset() -> void:
	# Teleport and ragdoll restore motor posture. Ordinary stops do not.
	if not actor.motor.persistent_posture: reset()

func reset() -> void:
	crouched = false
	last_reason = &""
	changed.emit(false)
