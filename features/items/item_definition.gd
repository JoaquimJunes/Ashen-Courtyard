extends Resource
## Shared authoring data. Never store an owner's quantities or timers here.
const Equipment = preload("res://features/items/item_equipment_profile.gd")
const Actions = preload("res://features/items/item_action_profile.gd")
const Visual = preload("res://features/presentation/equipment_visual_definition.gd")
const Upgrades = preload("res://features/items/item_upgrade_profile.gd")
enum Supply { REUSABLE, STACK, CHARGES }
@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export_enum("magic", "gadget", "melee", "bow", "shield") var category := "melee"
@export var subtype: StringName
@export var icon: Texture2D
@export var supply: Supply = Supply.REUSABLE
@export var max_stack := 1
@export var max_charges := 0
@export var equipment: Equipment
@export var actions: Actions
@export var visual: Visual
@export var upgrades: Upgrades

func maximum_upgrade() -> int:
	return 0 if upgrades == null else upgrades.levels.size()
