extends RefCounted
signal changed
const Instance = preload("res://features/items/item_instance.gd")
const Definition = preload("res://features/items/item_definition.gd")
var catalog: Resource
var entries: Dictionary = {}
var last_error := ""
## Injected by composition: no mutable operations while committed or queued.
var edit_allowed: Callable
var _stack_index: Dictionary = {}

func configure(value: Resource) -> void:
	catalog = value

func can_edit() -> bool:
	return not edit_allowed.is_valid() or edit_allowed.call()

func find(id: StringName) -> Instance:
	return entries.get(id)

func fail(message: String) -> bool:
	last_error = message
	return false

func grant(definition_id: StringName, count: int = 1) -> Array[StringName]:
	last_error = ""
	var result: Array[StringName] = []
	var definition: Definition = catalog.find(definition_id)
	if not can_edit():
		fail("Finish the current action before editing inventory.")
		return result
	if definition == null or count < 1:
		fail("Unknown item or invalid quantity.")
		return result
	var key := str(definition_id)+":0"
	if definition.supply == Definition.Supply.STACK:
		for id in _stack_index.get(key,[]):
			var existing: Instance = find(id)
			var added := mini(count,definition.max_stack-existing.quantity)
			if added > 0:
				existing.quantity += added
				count -= added
				result.append(id)
			if count == 0: break
	while count > 0:
		var item := Instance.new()
		item.instance_id = StringName(Crypto.new().generate_random_bytes(16).hex_encode())
		while entries.has(item.instance_id): item.instance_id = StringName(Crypto.new().generate_random_bytes(16).hex_encode())
		item.definition_id = definition_id
		item.quantity = mini(count,definition.max_stack)
		item.charges = definition.max_charges
		entries[item.instance_id] = item
		if definition.supply == Definition.Supply.STACK:
			if not _stack_index.has(key): _stack_index[key] = []
			_stack_index[key].append(item.instance_id)
		count -= item.quantity
		result.append(item.instance_id)
	changed.emit()
	return result

func remove(id: StringName, count: int = 1) -> bool:
	var item := find(id)
	if not can_edit(): return fail("Finish the current action before editing inventory.")
	if item == null or count < 1 or count > item.quantity: return fail("Invalid removal quantity.")
	item.quantity -= count
	if item.quantity == 0: erase_entry(item)
	changed.emit()
	return true

func erase_entry(item: Instance) -> void:
	entries.erase(item.instance_id)
	var key := str(item.definition_id)+":"+str(item.upgrade_level)
	if _stack_index.has(key): _stack_index[key].erase(item.instance_id)

func set_upgrade(id: StringName, level: int) -> bool:
	var item := find(id)
	if not can_edit(): return fail("Finish the current action before upgrading.")
	if item == null or level < 0 or level > catalog.find(item.definition_id).maximum_upgrade(): return fail("Unsupported upgrade level.")
	item.upgrade_level = level
	reindex()
	changed.emit()
	return true

func set_charges(id: StringName, value: int, notify: bool = true) -> bool:
	if notify and not can_edit(): return fail("Finish the current action before changing charges.")
	var item := find(id)
	if item == null: return fail("Unknown charged item.")
	var definition: Definition = catalog.find(item.definition_id)
	if definition.supply != Definition.Supply.CHARGES or value < 0 or value > definition.max_charges: return fail("Invalid charge count.")
	item.charges = value
	if notify: changed.emit()
	return true

func refill(id: StringName) -> bool:
	var item := find(id)
	if not can_edit() or item == null: return fail("Cannot refill this item now.")
	return set_charges(id,catalog.find(item.definition_id).max_charges)

func can_pay(id: StringName, cost: int) -> bool:
	var item := find(id)
	if item == null or cost < 0: return false
	var definition: Definition = catalog.find(item.definition_id)
	match definition.supply:
		Definition.Supply.STACK: return item.quantity >= cost
		Definition.Supply.CHARGES: return item.charges >= cost
	return cost == 0

## Internal action transaction: caller validates the complete cost first and
## publishes changed only after action ownership is installed.
func spend_silent(id: StringName, cost: int) -> bool:
	if not can_pay(id,cost): return false
	var item := find(id)
	match catalog.find(item.definition_id).supply:
		Definition.Supply.STACK:
			item.quantity -= cost
			if item.quantity == 0: erase_entry(item)
		Definition.Supply.CHARGES: item.charges -= cost
	return true

func to_records() -> Array:
	var result: Array = []
	for item in entries.values(): result.append(item.to_record())
	return result

func load_records(records: Array) -> bool:
	if not can_edit(): return fail("Finish the current action before restoring inventory.")
	var staged := {}
	for record in records:
		if not record is Dictionary: return fail("Invalid item record.")
		for key in ["instance_id","definition_id"]:
			if not record.get(key) is String or record[key].is_empty(): return fail("Item record needs stable IDs.")
		for key in ["quantity","charges","upgrade_level"]:
			var value = record.get(key)
			if not (value is int or value is float) or not is_finite(value) or value != floor(value): return fail("Item counts must be finite integers.")
		var definition: Definition = catalog.find(StringName(record.definition_id))
		if definition == null or staged.has(StringName(record.instance_id)): return fail("Unknown definition or duplicate instance ID.")
		if record.quantity < 1 or record.quantity > definition.max_stack or record.charges < 0 or record.charges > definition.max_charges or record.upgrade_level < 0 or record.upgrade_level > definition.maximum_upgrade(): return fail("Item record is outside authored limits.")
		var item := Instance.new()
		item.instance_id = StringName(record.instance_id)
		item.definition_id = StringName(record.definition_id)
		item.quantity = int(record.quantity)
		item.charges = int(record.charges)
		item.upgrade_level = int(record.upgrade_level)
		staged[item.instance_id] = item
	entries = staged
	reindex()
	return true

func reindex() -> void:
	_stack_index.clear()
	for item in entries.values():
		if catalog.find(item.definition_id).supply != Definition.Supply.STACK: continue
		var key := str(item.definition_id)+":"+str(item.upgrade_level)
		if not _stack_index.has(key): _stack_index[key] = []
		_stack_index[key].append(item.instance_id)
