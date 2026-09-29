extends RefCounted
## Camera targeting is independent of the motor's body-facing request.
var actor: CharacterBody3D
var target: Combatant
var locked := false

func configure(character: CharacterBody3D) -> void:
	actor = character

func toggle() -> void:
	locked = not locked and is_instance_valid(target) and not target.dead

func tick(delta: float) -> void:
	if not is_instance_valid(target) or target.dead: locked = false
	if locked:
		var offset := target.global_position-actor.global_position
		actor.yaw = lerp_angle(actor.yaw,atan2(-offset.x,-offset.z),minf(1,delta*10))
		actor.pitch = lerpf(actor.pitch,-0.17,delta*5)
