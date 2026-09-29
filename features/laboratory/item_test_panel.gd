extends VBoxContainer
## Debug authoring controls. Inventory/equipment remain the only mutable owners.
const Style = preload("res://features/ui/ui_style.gd")
const Definition = preload("res://features/items/item_definition.gd")
const CATEGORY_NAMES := {"melee":"Swords","magic":"Magic","gadget":"Gadgets","bow":"Bows","shield":"Shields"}
var actor: CharacterBody3D
var catalog_selector: OptionButton
var count: SpinBox
var grant_button: Button
var owned_list: ItemList
var details: Label
var loadout_text: Label
var slot_selector: OptionButton
var equip_button: Button
var clear_button: Button
var level: SpinBox
var upgrade_button: Button
var refill_button: Button
var status: Label
var _selected: StringName
var _slots: Array = []

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(Style.text("ITEM TESTING",24))
	Style.paragraph(self,"Grant items and try loadouts here. Changes last until a station reset or retry. Bow and shield entries test equipment only.")
	var grant_row := HBoxContainer.new()
	add_child(grant_row)
	catalog_selector = OptionButton.new()
	catalog_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for definition in actor.items.catalog.definitions:
		catalog_selector.add_item(definition.display_name)
		catalog_selector.set_item_metadata(catalog_selector.item_count-1,definition.id)
	grant_row.add_child(catalog_selector)
	count = SpinBox.new()
	count.min_value = 1
	count.max_value = 1000
	count.value = 1
	count.custom_minimum_size.x = 85
	grant_row.add_child(count)
	grant_button = Style.button(grant_row,"Grant",grant_selected)
	owned_list = ItemList.new()
	owned_list.custom_minimum_size.y = 120
	owned_list.item_selected.connect(select_owned)
	add_child(owned_list)
	details = Style.paragraph(self,"")
	loadout_text = Style.paragraph(self,"")
	var assign_row := HBoxContainer.new()
	add_child(assign_row)
	slot_selector = OptionButton.new()
	slot_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_slot("Main hand",&"primary",0)
	add_slot("Off hand",&"off_hand",0)
	for index in actor.items.equipment.spells.size(): add_slot("Spell %s" % (index+1),&"spell",index)
	for index in actor.items.equipment.gadgets.size(): add_slot("Gadget %s" % (index+1),&"gadget",index)
	assign_row.add_child(slot_selector)
	equip_button = Style.button(assign_row,"Equip selected",equip_selected)
	clear_button = Style.button(assign_row,"Clear slot",clear_slot)
	var upgrade_row := HBoxContainer.new()
	add_child(upgrade_row)
	upgrade_row.add_child(Style.text("Upgrade"))
	level = SpinBox.new()
	level.custom_minimum_size.x = 80
	upgrade_row.add_child(level)
	upgrade_button = Style.button(upgrade_row,"Set level",upgrade_selected)
	refill_button = Style.button(upgrade_row,"Refill charges",refill_selected)
	status = Style.paragraph(self,"")
	Style.paragraph(self,"Resume to use the equipped items. Enable combat through Movement practice → Stationary target. Loadout changes require an idle character with no queued action.")
	actor.items.inventory.changed.connect(on_changed)
	actor.items.equipment.changed.connect(on_changed)
	refresh()

func add_slot(label: String, slot: StringName, index: int) -> void:
	slot_selector.add_item(label)
	_slots.append([slot,index])

func open() -> void:
	refresh()
	catalog_selector.grab_focus()

func on_changed() -> void:
	if is_visible_in_tree(): refresh()

func refresh() -> void:
	owned_list.clear()
	var totals := {}
	var copies := {}
	for item in actor.items.inventory.entries.values(): totals[item.definition_id] = totals.get(item.definition_id,0)+1
	for item in actor.items.inventory.entries.values():
		var definition: Resource = actor.items.catalog.find(item.definition_id)
		copies[item.definition_id] = copies.get(item.definition_id,0)+1
		var amount := " ×%s" % item.quantity if definition.supply == Definition.Supply.STACK else ("  %s/%s charges" % [item.charges,definition.max_charges] if definition.supply == Definition.Supply.CHARGES else "")
		var upgrade := " +%s" % item.upgrade_level if definition.maximum_upgrade() > 0 else ""
		var copy_label := " · Copy %s" % copies[item.definition_id] if totals[item.definition_id] > 1 else ""
		owned_list.add_item("%s · %s%s%s%s" % [CATEGORY_NAMES[definition.category],definition.display_name,upgrade,amount,copy_label])
		var index := owned_list.item_count-1
		owned_list.set_item_metadata(index,item.instance_id)
		if item.instance_id == _selected: owned_list.select(index)
	if not owned_list.is_anything_selected() and owned_list.item_count > 0:
		owned_list.select(0)
		_selected = owned_list.get_item_metadata(0)
	owned_list.ensure_current_is_visible()
	refresh_details()
	var equipment: RefCounted = actor.items.equipment
	var parts: Array[String] = []
	for slot in _slots:
		var definition: Resource = equipment.definition(equipment.slot_item(slot[0],slot[1]))
		parts.append("%s: %s" % [slot_selector.get_item_text(parts.size()),definition.display_name if definition != null else "Empty"])
	loadout_text.text = " · ".join(parts)

func select_owned(index: int) -> void:
	_selected = owned_list.get_item_metadata(index)
	refresh_details()

func refresh_details() -> void:
	var item: RefCounted = actor.items.inventory.find(_selected)
	var editable: bool = actor.items.can_edit()
	grant_button.disabled = not editable
	clear_button.disabled = not editable
	equip_button.disabled = not editable or item == null
	if item == null:
		details.text = "No item selected."
		upgrade_button.disabled = true
		refill_button.disabled = true
		return
	var definition: Resource = actor.items.catalog.find(item.definition_id)
	details.text = definition.description
	level.max_value = definition.maximum_upgrade()
	level.value = item.upgrade_level
	upgrade_button.disabled = not editable or definition.maximum_upgrade() == 0
	refill_button.disabled = not editable or definition.supply != Definition.Supply.CHARGES
	if not editable: status.text = "Resume and finish the current action before editing items."

func report(ok: bool, success: String, error: String) -> void:
	status.text = success if ok else error

func grant_selected() -> void:
	var id: StringName = catalog_selector.get_item_metadata(catalog_selector.selected)
	var granted: Array = actor.items.inventory.grant(id,int(count.value))
	if not granted.is_empty(): _selected = granted[-1]
	refresh()
	report(not granted.is_empty(),"Item granted.",actor.items.inventory.last_error)

func equip_selected() -> void:
	var slot: Array = _slots[slot_selector.selected]
	var ok: bool = actor.items.equipment.assign(slot[0],_selected,slot[1])
	report(ok,"Loadout updated.",actor.items.equipment.last_error)

func clear_slot() -> void:
	var slot: Array = _slots[slot_selector.selected]
	var ok: bool = actor.items.equipment.assign(slot[0],&"",slot[1])
	report(ok,"Slot cleared.",actor.items.equipment.last_error)

func upgrade_selected() -> void:
	var ok: bool = actor.items.inventory.set_upgrade(_selected,int(level.value))
	report(ok,"Upgrade applied to this copy.",actor.items.inventory.last_error)

func refill_selected() -> void:
	var ok: bool = actor.items.inventory.refill(_selected)
	report(ok,"Charges refilled.",actor.items.inventory.last_error)

func _exit_tree() -> void:
	if not is_instance_valid(actor): return
	if actor.items.inventory.changed.is_connected(on_changed): actor.items.inventory.changed.disconnect(on_changed)
	if actor.items.equipment.changed.is_connected(on_changed): actor.items.equipment.changed.disconnect(on_changed)
