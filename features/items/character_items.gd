extends RefCounted
## Composes the item subsystem without owning action timing or scene-tree effects.
const Inventory = preload("res://features/items/inventory.gd")
const Equipment = preload("res://features/items/equipment_controller.gd")
const Resolver = preload("res://features/items/item_action_resolver.gd")
const ItemDefinition = preload("res://features/items/item_definition.gd")
const CATALOG = preload("res://features/items/data/catalog.tres")
var catalog: Resource
var inventory := Inventory.new()
var equipment := Equipment.new()
var resolver := Resolver.new()
var actor: CharacterBody3D
var flask_id: StringName
var last_error := ""
var starter: Resource = preload("res://features/items/data/starter_loadout.tres")

func configure(character: CharacterBody3D, source: Resource = CATALOG) -> bool:
	actor = character
	starter = character.starter_loadout
	catalog = source
	if not catalog.build():
		last_error = catalog.last_error
		return false
	inventory.configure(catalog)
	inventory.changed.connect(on_inventory_changed)
	inventory.edit_allowed = can_edit
	equipment.configure(inventory)
	equipment.hands_blocked = hands_blocked
	resolver.configure(inventory,equipment)
	resolver.configure_animations(actor.model)
	equipment.animation_validator = resolver.validate_loadout_animations
	resolver.legacy_tuning = actor.tuning
	resolver.legacy_abilities = {
		preload("res://features/abilities/data/light.tres"): &"light",
		preload("res://features/abilities/data/heavy.tres"): &"heavy",
		preload("res://features/abilities/data/bolt.tres"): &"bolt",
		preload("res://features/abilities/data/burst.tres"): &"burst",
		preload("res://features/abilities/data/heal.tres"): &"heal"}
	if not reset_starter(): return false
	actor.resources.item_charges = self
	return true

func can_edit() -> bool:
	return is_instance_valid(actor) and not actor.dead and not actor.actions.unloaded and not actor.actions.cancelling and actor.actions.is_available() and actor.actions.active_definition == null and actor.actions.pending_result == null

func hands_blocked() -> bool:
	if not is_instance_valid(actor) or actor.dead: return true
	var context: RefCounted = actor.actions.active_item
	return actor.movement.attachment != null or actor.state in [actor.State.LEDGE_GRAB,actor.State.MANTLE,actor.State.RAGDOLL,actor.State.GET_UP] or (context != null and context.presentation.free_hands)

func reset_starter() -> bool:
	# Assemble privately, then publish the complete reset once.
	if starter == null or starter.spells.is_empty() or starter.gadgets.is_empty(): return fail("Starter loadout needs spell and gadget slots.")
	var staged := Inventory.new()
	staged.configure(catalog)
	var record := {"primary":"","off_hand":"","spells":[],"gadgets":[],"selected_spell":0,"selected_gadget":0}
	var new_flask := &""
	for slot in ["primary","off_hand","spells","gadgets"]:
		var ids: Array = [starter.get(slot)] if slot in ["primary","off_hand"] else starter.get(slot)
		for id in ids:
			var instance := &""
			if id != &"":
				var granted := staged.grant(id)
				if granted.is_empty(): return fail(staged.last_error)
				instance = granted[0]
				if id == starter.legacy_flask: new_flask = instance
			if slot in ["primary","off_hand"]: record[slot] = str(instance)
			else: record[slot].append(str(instance))
	var loadout := Equipment.new()
	loadout.spells.resize(starter.spells.size())
	loadout.gadgets.resize(starter.gadgets.size())
	loadout.configure(staged)
	loadout.visual_validator = equipment.visual_validator
	loadout.animation_validator = equipment.animation_validator
	if not loadout.load_record(record): return fail(loadout.last_error)
	inventory.entries = staged.entries
	inventory.reindex()
	equipment.apply_record(record)
	flask_id = new_flask
	inventory.changed.emit()
	equipment.changed.emit()
	return true

func get_flasks() -> int:
	var flask: RefCounted = inventory.find(flask_id)
	return flask.charges if flask != null else 0

func on_inventory_changed() -> void:
	if inventory.find(flask_id) == null: flask_id = &""

func set_flasks(value: int) -> void:
	if inventory.find(flask_id) != null: inventory.set_charges(flask_id,value,false)

func reset_flasks() -> void:
	var flask: RefCounted = inventory.find(flask_id)
	if flask != null: set_flasks(catalog.find(flask.definition_id).max_charges)

func selected_name(slot: StringName) -> String:
	var index: int = equipment.selected_spell if slot == &"spell" else equipment.selected_gadget
	var definition: Resource = equipment.definition(equipment.slot_item(slot,index))
	return definition.display_name if definition != null else "Empty"

func gadget_status() -> String:
	var item: RefCounted = inventory.find(equipment.slot_item(&"gadget",equipment.selected_gadget))
	if item == null: return "Gadget: Empty"
	var definition: Resource = catalog.find(item.definition_id)
	match definition.supply:
		ItemDefinition.Supply.STACK: return "%s: %s" % [definition.display_name,item.quantity]
		ItemDefinition.Supply.CHARGES: return "%s: %s" % [definition.display_name,item.charges]
	return definition.display_name

func to_record() -> Dictionary:
	return {"version":1,"items":inventory.to_records(),"equipment":equipment.to_record(),"legacy_flask":str(flask_id)}

func restore(record: Dictionary) -> bool:
	if not can_edit(): return fail("Finish the current action before restoring inventory.")
	var version = record.get("version")
	if not (version is int or version is float) or version != 1 or not record.get("items") is Array or not record.get("equipment") is Dictionary or not record.get("legacy_flask") is String: return fail("Invalid inventory record version or structure.")
	var staged := Inventory.new()
	staged.configure(catalog)
	if not staged.load_records(record.items): return fail(staged.last_error)
	var loadout := Equipment.new()
	loadout.spells.resize(equipment.spells.size())
	loadout.gadgets.resize(equipment.gadgets.size())
	loadout.configure(staged)
	loadout.visual_validator = equipment.visual_validator
	loadout.animation_validator = equipment.animation_validator
	var legacy: RefCounted = staged.find(StringName(record.legacy_flask))
	if record.legacy_flask != "" and (legacy == null or legacy.definition_id != starter.legacy_flask): return fail("Invalid legacy flask reference.")
	# Preparing valid equipment can install animation banks. All unrelated record
	# checks must finish first so a rejected restore cannot publish partial state.
	if not loadout.load_record(record.equipment): return fail(loadout.last_error)
	# All validation has finished. Preserve object identities and observers.
	inventory.entries = staged.entries
	inventory.reindex()
	equipment.apply_record(loadout.to_record())
	flask_id = StringName(record.legacy_flask)
	inventory.changed.emit()
	equipment.changed.emit()
	last_error = ""
	return true

func fail(message: String) -> bool:
	last_error = message
	return false
