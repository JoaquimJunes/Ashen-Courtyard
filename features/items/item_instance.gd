extends RefCounted
## Mutable owned copy (or stack). Only Inventory should mutate these fields.
var instance_id: StringName
var definition_id: StringName
var quantity := 1
var charges := 0
var upgrade_level := 0

func to_record() -> Dictionary:
	return {"instance_id":str(instance_id),"definition_id":str(definition_id),
		"quantity":quantity,"charges":charges,"upgrade_level":upgrade_level}
