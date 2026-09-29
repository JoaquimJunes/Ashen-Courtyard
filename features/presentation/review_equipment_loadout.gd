extends RefCounted
## Compatibility accessors for the editable review assets used by scene/test fixtures.
const DEFINITION = preload("res://features/presentation/data/review_equipment_loadout.tres")
const RIG = preload("res://features/presentation/data/ual_rig.tres")

static func sockets() -> Array[Resource]:
	return RIG.socket_definitions

static func layouts() -> Dictionary:
	return DEFINITION.layouts

static func items() -> Array[Resource]:
	return DEFINITION.items
