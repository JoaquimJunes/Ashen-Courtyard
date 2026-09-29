extends SceneTree
## Content, ownership, persistence and scale contracts without rendering actors.
const Catalog = preload("res://features/items/item_catalog.gd")
const Definition = preload("res://features/items/item_definition.gd")
const Inventory = preload("res://features/items/inventory.gd")
const Equipment = preload("res://features/items/equipment_controller.gd")
const Resolver = preload("res://features/items/item_action_resolver.gd")
const Resources = preload("res://features/character/character_resources.gd")
const DATA = preload("res://features/items/data/catalog.tres")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func fresh() -> RefCounted:
	var inventory := Inventory.new()
	inventory.configure(DATA)
	return inventory

func run() -> void:
	check(DATA.build(),"All authored item profiles validate")
	var catalog := Catalog.new()
	catalog.definitions.assign(DATA.definitions)
	catalog.definitions.append(DATA.definitions[0])
	check(not catalog.build() and "Duplicate" in catalog.last_error,"Duplicate definition IDs fail catalog construction")
	var bad: Resource = DATA.find(&"azure_sword").duplicate()
	bad.id = &"bad"
	bad.max_stack = 0
	check(catalog.validate_definition(bad) != "","Invalid stack limit is rejected")
	bad = DATA.find(&"azure_bolt").duplicate()
	bad.actions = null
	check(catalog.validate_definition(bad) != "","Spell without a use action is rejected")
	bad = DATA.find(&"review_bow").duplicate(true)
	bad.equipment = DATA.find(&"review_bow").equipment.duplicate()
	bad.equipment.two_handed = false
	check(catalog.validate_definition(bad) != "","Incompatible bow hand profile is rejected")
	bad = DATA.find(&"azure_bolt").duplicate(true)
	bad.actions = DATA.find(&"azure_bolt").actions.duplicate(true)
	bad.actions.actions[0] = bad.actions.actions[0].duplicate(true)
	bad.actions.actions[0].ability = bad.actions.actions[0].ability.duplicate(true)
	bad.actions.actions[0].ability.mana_cost = NAN
	check(catalog.validate_definition(bad) != "","Nonfinite ability costs fail validation")
	bad.actions.actions[0].ability.mana_cost = 24
	bad.actions.actions[0].presentation = bad.actions.actions[0].presentation.duplicate()
	bad.actions.actions[0].presentation.role = &"heal"
	check(catalog.validate_definition(bad) != "","Incompatible execution and presentation profiles are rejected")
	bad = DATA.find(&"healing_flask").duplicate()
	bad.max_charges = 0
	check(catalog.validate_definition(bad) != "","A refillable item needs positive capacity")
	for subtype in [&"sword",&"axe",&"hammer",&"spear",&"greatsword",&"scythe"]:
		var weapon: Resource = DATA.find(&"azure_sword").duplicate()
		weapon.subtype = subtype
		check(catalog.validate_definition(weapon) == "","Melee subtype uses the shared composition: "+str(subtype))

	var inventory := fresh()
	check(inventory.grant(&"missing").is_empty() and inventory.entries.is_empty(),"Unknown grant is rejected without mutation")
	check(inventory.grant(&"practice_potion",0).is_empty(),"Nonpositive grant rejected")
	var potions: Array = inventory.grant(&"practice_potion",25)
	check(potions.size() == 2 and inventory.find(potions[0]).quantity == 20 and inventory.find(potions[1]).quantity == 5,"Grant splits stacks at the authored limit")
	var merged: Array = inventory.grant(&"practice_potion",3)
	check(merged == [potions[1]] and inventory.find(potions[1]).quantity == 8,"Compatible stacks merge")
	var swords: Array = inventory.grant(&"azure_sword",2)
	check(swords.size() == 2 and swords[0] != swords[1],"Reusable items are separate owned copies")
	check(inventory.set_upgrade(swords[0],1) and inventory.find(swords[1]).upgrade_level == 0,"Upgrade affects one copy")
	check(not inventory.set_upgrade(swords[0],3),"Unsupported upgrade is rejected")
	var flasks: Array = inventory.grant(&"healing_flask",2)
	inventory.spend_silent(flasks[0],1)
	check(inventory.find(flasks[0]).charges == 2 and inventory.find(flasks[1]).charges == 3,"Charges are isolated between copies")
	check(not inventory.can_pay(flasks[0],3) and not inventory.spend_silent(flasks[0],3),"Overspending cannot produce negative charges")
	check(inventory.refill(flasks[0]) and inventory.find(flasks[0]).charges == 3,"Refill uses authored capacity")

	var equipment := Equipment.new()
	equipment.configure(inventory)
	check(equipment.assign(&"primary",swords[0]),"Melee equips in the primary slot")
	check(not equipment.assign(&"spell",swords[1],0),"Sword cannot occupy a spell slot")
	var shield: StringName = inventory.grant(&"review_shield")[0]
	var bow: StringName = inventory.grant(&"review_bow")[0]
	check(equipment.assign(&"off_hand",shield) and equipment.off_hand_available(),"Shield occupies the off hand beside a sword")
	check(equipment.assign(&"primary",bow) and not equipment.off_hand_available() and equipment.off_hand == shield,"Two-handed bow suppresses but retains shield assignment")
	check(equipment.visual_plan().held == [&"bow"],"Visual plan draws only the bow while retaining the carried shield")
	equipment.assign(&"primary",swords[0])
	check(equipment.off_hand_available(),"Switching back restores off-hand availability")
	equipment.assign(&"gadget",flasks[0])
	var resolver := Resolver.new()
	resolver.configure(inventory,equipment)
	var snapshot: RefCounted = resolver.capture("light")
	check(is_equal_approx(snapshot.ability.damage,26.4) and DATA.find(&"azure_sword").actions.for_role(&"light").ability.damage == 24,"Upgrade resolves into private effective values")
	inventory.set_upgrade(swords[0],2)
	check(is_equal_approx(snapshot.ability.damage,26.4) and snapshot.upgrade_level == 1,"Captured values survive subsequent inventory edits")
	var resources := Resources.new()
	resources.configure(preload("res://features/character/data/resources.tres"),100)
	var cost: RefCounted = resolver.capture("heal")
	cost.ability.stamina_cost = 15
	cost.ability.mana_cost = 20
	resources.mana = 19
	check(not resolver.commit(cost,resources) and resources.stamina == 100 and inventory.find(flasks[0]).charges == 3,"Insufficient mana spends neither stamina nor item charges")
	resources.mana = 100
	inventory.set_charges(flasks[0],0)
	check(not resolver.commit(cost,resources) and resources.stamina == 100 and resources.mana == 100,"Insufficient charges spend no character resources")
	inventory.refill(flasks[0])
	var notifications: Array = []
	inventory.changed.connect(func(): notifications.append(true))
	check(resolver.commit(cost,resources) and resources.stamina == 85 and resources.mana == 80 and inventory.find(flasks[0]).charges == 2,"Combined cost succeeds exactly once")
	check(notifications.is_empty(),"Payment stays silent until action ownership is installed")

	var tool: StringName = inventory.grant(&"practice_tool")[0]
	equipment.assign(&"gadget",tool)
	check(resolver.commit(resolver.capture("heal"),resources) and inventory.find(tool).quantity == 1,"Reusable gadget spends no quantity")
	var small := fresh()
	var last: StringName = small.grant(&"practice_potion")[0]
	var slots := Equipment.new()
	slots.configure(small)
	slots.assign(&"gadget",last)
	small.spend_silent(last,1)
	small.changed.emit()
	check(small.find(last) == null and slots.gadgets[0] == &"","Last consumed unit clears the quick-slot reference")

	var records: Array = inventory.to_records()
	var restored := fresh()
	var decoded: Array = JSON.parse_string(JSON.stringify(records))
	check(restored.load_records(decoded) and restored.to_records() == records,"Item records round-trip through JSON with stable identities")
	var invalid: Array = records.duplicate(true)
	invalid[0].quantity = -1
	check(not restored.load_records(invalid) and restored.to_records() == records,"Invalid quantities leave the entire previous inventory intact")
	invalid = records.duplicate(true)
	invalid.append(invalid[0].duplicate(true))
	check(not restored.load_records(invalid) and restored.to_records() == records,"Duplicate instance IDs fail atomically")
	invalid = records.duplicate(true)
	invalid[0].definition_id = "removed_content"
	check(not restored.load_records(invalid),"Unknown definition is reported rather than silently discarded")
	var loadout := Equipment.new()
	loadout.configure(restored)
	check(loadout.load_record(equipment.to_record()) and loadout.to_record() == equipment.to_record(),"Equipment round trip preserves slots and selections")
	var invalid_loadout: Dictionary = equipment.to_record()
	invalid_loadout.primary = "missing_instance"
	check(not loadout.load_record(invalid_loadout) and loadout.to_record() == equipment.to_record(),"Missing slot references cannot partially replace equipment")
	inventory.edit_allowed = func(): return false
	var before: Array = inventory.to_records()
	check(inventory.grant(&"azure_sword").is_empty() and not inventory.set_upgrade(swords[0],0) and not inventory.remove(swords[0]) and not equipment.assign(&"primary",bow),"Committed edit guard protects all user inventory/loadout operations")
	check(inventory.to_records() == before,"Rejected edits leave owned state intact")

	var large_catalog := Catalog.new()
	for index in 1000:
		var definition: Resource = DATA.find(&"azure_sword").duplicate()
		definition.id = StringName("scale_%s" % index)
		large_catalog.definitions.append(definition)
	check(large_catalog.build(),"A thousand definitions validate into an indexed catalog")
	var large := Inventory.new()
	large.configure(large_catalog)
	var nodes := root.get_child_count()
	for definition in large_catalog.definitions: large.grant(definition.id,5)
	check(large.entries.size() == 5000 and root.get_child_count() == nodes,"Five thousand owned copies create no scene nodes")
	var sample: StringName = large.entries.keys()[4321]
	check(large.find(sample) != null and large.catalog.find(large.find(sample).definition_id) != null,"Instance and definition lookup use ID indexes")
	print("ITEMS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
