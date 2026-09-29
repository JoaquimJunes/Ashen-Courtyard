extends RefCounted
signal completed(result: RefCounted)
var accepted := false
var reason: StringName = &"unknown_action"
var resolved := true
func _init(ok: bool = false, why: StringName = &"unknown_action") -> void:
	accepted = ok
	reason = why

func resolve(ok: bool, why: StringName) -> void:
	if resolved: return
	accepted = ok
	reason = why
	resolved = true
	completed.emit(self)
