extends Resource
const Ability = preload("res://features/abilities/ability_definition.gd")
const Presentation = preload("res://features/items/item_presentation_profile.gd")
## An input role maps to a reusable executor, independently of the item's identity.
@export var role: StringName = &"use"
@export_enum("light", "heavy", "cast", "heal") var executor := "cast"
@export var ability: Ability
@export var presentation: Presentation
## Units for stacks, charges for refillables, zero for reusable items.
@export var item_cost := 0
