extends Resource
## Starter definition IDs, expanded into fresh owned instances on retry/reset.
@export var primary: StringName = &"azure_sword"
@export var off_hand: StringName
@export var spells: Array[StringName] = [&"azure_bolt",&"violet_burst"]
@export var gadgets: Array[StringName] = [&"healing_flask"]
@export var legacy_flask: StringName = &"healing_flask"
