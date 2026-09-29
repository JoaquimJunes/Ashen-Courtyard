extends RefCounted
## Shared policy; Resources owns amounts/timers. No flight exception is active yet.
static func stamina_allowed(actor: CharacterBody3D, movement: RefCounted, action_available: bool, reacting: bool = false) -> bool:
	var supported: bool = (movement.mode == &"grounded" and not actor.motor.is_airborne()) or movement.mode in [&"surface_swimming",&"underwater_swimming"]
	return not actor.dead and not reacting and action_available and supported
