extends RefCounted
## Serialization boundary only. Gameplay saves/generation are later milestones.
var entity_id: StringName
var definition_id: StringName
var state_version := 1
var changes: Dictionary = {}
func to_record() -> Dictionary:
	return {"entity_id": str(entity_id), "definition_id": str(definition_id),
		"state_version": state_version, "changes": changes.duplicate(true)}
