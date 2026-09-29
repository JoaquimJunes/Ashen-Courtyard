extends Resource
const Definition = preload("res://features/items/item_definition.gd")
@export var definitions: Array[Definition] = []
var _by_id: Dictionary = {}
var last_error := ""

func build() -> bool:
	var staged := {}
	for definition in definitions:
		var error := validate_definition(definition)
		if error != "": return fail(error)
		if staged.has(definition.id): return fail("Duplicate item ID: "+str(definition.id))
		staged[definition.id] = definition
	_by_id = staged
	last_error = ""
	return true

func find(id: StringName) -> Definition:
	return _by_id.get(id)

func fail(message: String) -> bool:
	last_error = message
	return false

func validate_definition(item: Definition) -> String:
	if item == null or item.id == &"" or item.display_name.strip_edges().is_empty(): return "Item needs an ID and display name."
	if item.category not in ["magic","gadget","melee","bow","shield"]: return "Unknown category: "+str(item.id)
	if item.supply not in [Definition.Supply.REUSABLE,Definition.Supply.STACK,Definition.Supply.CHARGES]: return "Unknown supply policy."
	if item.max_stack < 1 or (item.supply != Definition.Supply.STACK and item.max_stack != 1): return "Invalid stack limit: "+str(item.id)
	if item.max_charges < 0 or (item.supply == Definition.Supply.CHARGES and item.max_charges < 1) or (item.supply != Definition.Supply.CHARGES and item.max_charges != 0): return "Invalid charge limit: "+str(item.id)
	if item.category != "gadget" and item.supply != Definition.Supply.REUSABLE: return "Only gadgets consume stacks or charges."
	if item.category in ["melee","bow","shield"]:
		if item.equipment == null or item.visual == null: return "Hand equipment needs gameplay and visual profiles: "+str(item.id)
		var expected := &"off_hand" if item.category == "shield" else &"primary"
		if item.equipment.slot != expected or (expected == &"off_hand" and item.equipment.two_handed): return "Incompatible equipment slot: "+str(item.id)
		if item.category == "bow" and not item.equipment.two_handed: return "Bows require both hands."
	elif item.equipment != null: return "Quick-slot items cannot occupy an equipment slot."
	if item.visual != null:
		if item.visual.id == &"" or item.visual.stowed_socket == &"": return "Visual needs an ID and stowed socket."
		if item.visual.visual == null and item.visual.placeholder_label.is_empty(): return "Visual needs a scene or explicit marker."
		if item.equipment != null:
			var hands: Array = item.visual.occupied_hands
			if item.visual.held_socket == &"" or hands.is_empty(): return "Held visual needs a hand socket."
			if item.equipment.two_handed != (hands.size() == 2): return "Gameplay and visual hand requirements disagree."
	if item.upgrades != null:
		for step in item.upgrades.levels:
			if step == null or not is_finite(step.damage_multiplier) or step.damage_multiplier < 0 or not is_finite(step.healing_multiplier) or step.healing_multiplier < 0: return "Invalid upgrade step."
	# Empty action sets are allowed for explicitly nonfunctional equipment fixtures.
	var roles := {}
	if item.actions != null:
		for binding in item.actions.actions:
			if binding == null or binding.role == &"" or roles.has(binding.role): return "Action roles must be unique and nonempty."
			roles[binding.role] = true
			if binding.executor not in ["light","heavy","cast","heal"]: return "Unknown item executor."
			if binding.item_cost < 0 or (item.supply == Definition.Supply.REUSABLE and binding.item_cost != 0): return "Invalid item cost."
			if item.supply == Definition.Supply.STACK and binding.item_cost > item.max_stack: return "Item cost exceeds stack capacity."
			if item.supply == Definition.Supply.CHARGES and binding.item_cost > item.max_charges: return "Item cost exceeds charge capacity."
			var ability := binding.ability
			if ability == null or ability.id == &"" or binding.presentation == null: return "Action needs an ability and presentation."
			if binding.presentation.role not in [&"melee_light",&"melee_heavy",&"spell",&"heal"]: return "Unknown presentation role."
			var expected_role: StringName = {"light":&"melee_light","heavy":&"melee_heavy","cast":&"spell","heal":&"heal"}[binding.executor]
			if binding.presentation.role != expected_role: return "Executor and presentation roles disagree."
			var profile: Resource = binding.presentation.animations
			if profile != null:
				if not profile.validate(): return "Invalid animation profile: "+profile.last_error
				if binding.executor == "light":
					if profile.light_attacks.is_empty(): return "Light moveset needs attack animations."
					for attack in profile.light_attacks:
						if attack == null or not attack.valid(profile): return "Invalid light animation profile."
				if binding.executor == "heavy" and (profile.heavy_attack == null or not profile.heavy_attack.valid(profile)): return "Invalid heavy animation profile."
				if binding.executor == "cast" and (profile.spell_cast == null or not profile.spell_cast.valid(profile)): return "Invalid spell animation profile."
			for value in [ability.stamina_cost,ability.mana_cost,ability.windup,ability.active_seconds,ability.recovery,ability.damage,ability.heal_amount]:
				if not is_finite(value) or value < 0: return "Invalid ability value."
			if ability.flask_cost < 0: return "Invalid legacy flask cost."
			if binding.executor == "cast" and ability.variant not in [&"projectile",&"burst"]: return "Unknown spell delivery."
	if item.category in ["magic","gadget"] and not roles.has(&"use"): return "Quick-slot item needs a use action."
	return ""
