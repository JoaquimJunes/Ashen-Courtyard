extends RefCounted
signal changed
const Definition = preload("res://features/items/item_definition.gd")
var inventory: RefCounted
var primary: StringName
var off_hand: StringName
var spells: Array[StringName] = [&"",&""]
var gadgets: Array[StringName] = [&""]
var selected_spell := 0
var selected_gadget := 0
var last_error := ""
var hands_blocked: Callable
var visual_validator: Callable
## Returns an empty string on success, otherwise a useful compatibility error.
var animation_validator: Callable

func configure(value: RefCounted) -> void:
	inventory = value
	inventory.changed.connect(on_inventory_changed)

func fail(message: String) -> bool:
	last_error = message
	return false

func definition(id: StringName) -> Resource:
	if inventory == null: return null
	var item: RefCounted = inventory.find(id)
	return inventory.catalog.find(item.definition_id) if item != null else null

func slot_item(slot: StringName, index: int = 0) -> StringName:
	match slot:
		&"primary": return primary
		&"off_hand": return off_hand
		&"spell": return spells[index] if index >= 0 and index < spells.size() else &""
		&"gadget": return gadgets[index] if index >= 0 and index < gadgets.size() else &""
	return &""

func assign(slot: StringName, id: StringName, index: int = 0) -> bool:
	if not inventory.can_edit(): return fail("Finish the current action before changing equipment.")
	if slot not in [&"primary",&"off_hand",&"spell",&"gadget"]: return fail("Unknown equipment slot.")
	if index < 0 or (slot == &"spell" and index >= spells.size()) or (slot == &"gadget" and index >= gadgets.size()): return fail("Unknown quick slot.")
	var previous := to_record()
	match slot:
		&"primary": primary = id
		&"off_hand": off_hand = id
		&"spell": spells[index] = id
		&"gadget": gadgets[index] = id
	var error := validate_slots()
	if error != "":
		apply_record(previous)
		return fail(error)
	last_error = ""
	changed.emit()
	return true

func select(slot: StringName, index: int) -> bool:
	if slot == &"spell" and index >= 0 and index < spells.size(): selected_spell = index
	elif slot == &"gadget" and index >= 0 and index < gadgets.size(): selected_gadget = index
	else: return fail("Unknown quick slot.")
	changed.emit()
	return true

func validate_slots() -> String:
	var used := {}
	for slot in [&"primary",&"off_hand",&"spell",&"gadget"]:
		var ids: Array = [primary] if slot == &"primary" else ([off_hand] if slot == &"off_hand" else (spells if slot == &"spell" else gadgets))
		for id in ids:
			if id == &"": continue
			var item: Resource = definition(id)
			if item == null or used.has(id): return "Missing item or duplicate assignment."
			used[id] = true
			if slot == &"spell" and item.category != "magic": return "Spell slots require magic."
			if slot == &"gadget" and item.category != "gadget": return "Gadget slots require gadgets."
			if slot in [&"primary",&"off_hand"] and (item.equipment == null or item.equipment.slot != slot): return "Item does not fit that hand slot."
	if visual_validator.is_valid() and not visual_validator.call(self): return "Equipment visuals do not fit this character's sockets."
	if animation_validator.is_valid():
		var error: String = animation_validator.call(self)
		if error != "": return error
	return ""

func primary_two_handed() -> bool:
	var item := definition(primary)
	return item != null and item.equipment.two_handed

func off_hand_available() -> bool:
	return off_hand != &"" and not primary_two_handed() and (not hands_blocked.is_valid() or not hands_blocked.call())

func visual_plan() -> Dictionary:
	var items: Array = []
	var held: Array = []
	for id in [primary,off_hand]:
		var item := definition(id)
		if item == null or item.visual == null: continue
		items.append(item.visual)
		if id == primary or not primary_two_handed(): held.append(item.visual.id)
	return {"items":items,"held":held}

func on_inventory_changed() -> void:
	var removed := false
	if primary != &"" and inventory.find(primary) == null:
		primary = &""
		removed = true
	if off_hand != &"" and inventory.find(off_hand) == null:
		off_hand = &""
		removed = true
	for slots in [spells,gadgets]:
		for index in slots.size():
			if slots[index] != &"" and inventory.find(slots[index]) == null:
				slots[index] = &""
				removed = true
	if removed: changed.emit()

func to_record() -> Dictionary:
	var spell_ids: Array = []
	var gadget_ids: Array = []
	for id in spells: spell_ids.append(str(id))
	for id in gadgets: gadget_ids.append(str(id))
	return {"primary":str(primary),"off_hand":str(off_hand),"spells":spell_ids,"gadgets":gadget_ids,
		"selected_spell":selected_spell,"selected_gadget":selected_gadget}

func load_record(record: Dictionary) -> bool:
	for key in ["primary","off_hand"]:
		if not record.get(key) is String: return fail("Invalid hand slot record.")
	for key in ["spells","gadgets"]:
		if not record.get(key) is Array or record[key].size() != (spells.size() if key == "spells" else gadgets.size()): return fail("Quick-slot count does not match this loadout.")
		for id in record[key]:
			if not id is String: return fail("Invalid quick-slot reference.")
	for key in ["selected_spell","selected_gadget"]:
		var value = record.get(key)
		var count := spells.size() if key == "selected_spell" else gadgets.size()
		if not (value is int or value is float) or not is_finite(value) or value != floor(value) or value < 0 or value >= count: return fail("Invalid quick-slot selection.")
	var before := to_record()
	apply_record(record)
	var error := validate_slots()
	if error != "":
		apply_record(before)
		return fail(error)
	return true

func apply_record(record: Dictionary) -> void:
	primary = StringName(record.primary)
	off_hand = StringName(record.off_hand)
	spells.clear()
	gadgets.clear()
	for id in record.spells: spells.append(StringName(id))
	for id in record.gadgets: gadgets.append(StringName(id))
	selected_spell = int(record.selected_spell)
	selected_gadget = int(record.selected_gadget)
