extends RefCounted
## Owned by an attack or projectile. No permanent per-victim strike history.
var id: StringName
var victims: Dictionary = {}
func _init(identity: StringName = &"") -> void: id = identity
func claim(victim: Node) -> bool:
	var key := victim.get_instance_id()
	if victims.has(key): return false
	victims[key] = true
	return true
