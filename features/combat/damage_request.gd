extends RefCounted
var source: Node
var strike_id: StringName
var strike: RefCounted
var damage_type: StringName = &"physical"
var amount := 0.0
var impact := Vector3.ZERO
var region: StringName = &""
func _init(value: float = 0, identity: StringName = &"", token: RefCounted = null) -> void:
	amount = value
	strike_id = identity
	strike = token
