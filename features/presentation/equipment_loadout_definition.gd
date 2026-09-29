extends Resource
## Artist-editable visual loadout. IDs select a held layout without inventory logic.
@export var items: Array[Resource] = []
@export var layouts: Dictionary = {&"all_stowed": []}
@export var initial_layout: StringName = &"all_stowed"
