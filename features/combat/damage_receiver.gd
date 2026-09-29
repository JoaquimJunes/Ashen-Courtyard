extends RefCounted
## Collision shapes may delegate damage to a character through an explicit link.
static func resolve(body: Object) -> Node:
	if not is_instance_valid(body): return null
	if body is Combatant: return body
	if body.has_method("get_damage_receiver"):
		var receiver: Node = body.get_damage_receiver()
		if is_instance_valid(receiver) and receiver is Combatant: return receiver
	return null

