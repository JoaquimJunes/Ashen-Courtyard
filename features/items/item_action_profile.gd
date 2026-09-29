extends Resource
const Binding = preload("res://features/items/item_action_binding.gd")
@export var actions: Array[Binding] = []

func for_role(role: StringName) -> Binding:
	for binding in actions:
		if binding.role == role: return binding
	return null
