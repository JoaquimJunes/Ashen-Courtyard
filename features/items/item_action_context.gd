extends RefCounted
## Captured when accepted; never consult the selected slot during execution.
var instance_id: StringName
var definition_id: StringName
var upgrade_level := 0
var executor := ""
var ability: Resource
var presentation: Resource
var item_cost := 0

var animations: RefCounted
var moveset_key: StringName
var combo_count := 2
