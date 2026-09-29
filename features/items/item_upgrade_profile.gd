extends Resource
const Step = preload("res://features/items/item_upgrade_step.gd")
## Entry zero is upgrade +1. An empty profile allows only the base level.
@export var levels: Array[Step] = []
