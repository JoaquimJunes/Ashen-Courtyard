extends RefCounted
const Bank = preload("res://features/presentation/animation_bank.gd")
var animation_bank := Bank.new()
var animation_actor: Node
const Context = preload("res://features/items/item_action_context.gd")
var inventory: RefCounted
var equipment: RefCounted
## Legacy prototype tuning stays an adapter at the composition boundary.
var legacy_abilities: Dictionary = {}
var legacy_tuning: Resource

func configure(owned: RefCounted, loadout: RefCounted) -> void:
	inventory = owned
	equipment = loadout

func configure_animations(model: Node3D) -> void:
	animation_bank.configure(model.animation,model.rig,model.animation_profile)
	animation_actor = model.get_parent()
	equipment.changed.connect(refresh_banks)
	animation_actor.actions.finished.connect(on_action_finished)
	animation_actor.actions.cancelled.connect(on_action_cancelled)
	animation_actor.tree_exiting.connect(unload_animations,CONNECT_ONE_SHOT)

func profiles_for(loadout: RefCounted) -> Array:
	var profiles: Array = []
	var ids: Array = [loadout.primary,loadout.off_hand]
	ids.append_array(loadout.spells)
	ids.append_array(loadout.gadgets)
	for id in ids:
		var definition: Resource = loadout.definition(id)
		if definition == null or definition.actions == null: continue
		for binding in definition.actions.actions:
			if binding.presentation.animations != null: profiles.append(binding.presentation.animations)
	return profiles

func prepare_loadout(loadout: RefCounted) -> bool:
	return animation_bank.prepare(profiles_for(loadout))

func validate_loadout_animations(loadout: RefCounted) -> String:
	return "" if prepare_loadout(loadout) else animation_bank.last_error

func refresh_banks() -> void:
	var context: RefCounted = animation_actor.actions.active_item if is_instance_valid(animation_actor) else null
	animation_bank.prune(profiles_for(equipment),context.animations if context != null else null)

func on_action_finished(_id: StringName) -> void: refresh_banks()
func on_action_cancelled(_id: StringName, _reason: StringName) -> void: refresh_banks()

func unload_animations() -> void:
	if equipment.changed.is_connected(refresh_banks): equipment.changed.disconnect(refresh_banks)
	if is_instance_valid(animation_actor):
		animation_actor.actions.finished.disconnect(on_action_finished)
		animation_actor.actions.cancelled.disconnect(on_action_cancelled)
	animation_bank.unload()
	animation_actor = null

func source_for(action: String) -> StringName:
	match action:
		"light","heavy": return equipment.primary
		"cast": return equipment.slot_item(&"spell",equipment.selected_spell)
		"heal","use_gadget": return equipment.slot_item(&"gadget",equipment.selected_gadget)
	return &""

func binding_for(action: String) -> Resource:
	var item: RefCounted = inventory.find(source_for(action))
	if item == null: return null
	var definition: Resource = inventory.catalog.find(item.definition_id)
	if definition.actions == null: return null
	return definition.actions.for_role(StringName(action) if action in ["light","heavy"] else &"use")

func ability_for(action: String) -> Resource:
	var binding := binding_for(action)
	if binding == null: return null
	# The five old tuning setters remain useful for prototype fixtures. Only
	# starter bindings opt into this adapter; newly authored content does not.
	var ability: Resource = binding.ability
	if legacy_tuning != null and legacy_abilities.has(ability): return legacy_tuning.get(legacy_abilities[ability])
	return ability

func capture(action: String) -> RefCounted:
	var binding := binding_for(action)
	var source: RefCounted = inventory.find(source_for(action))
	if binding == null or source == null: return null
	var definition: Resource = inventory.catalog.find(source.definition_id)
	var context := Context.new()
	context.instance_id = source.instance_id
	context.definition_id = source.definition_id
	context.upgrade_level = source.upgrade_level
	context.executor = binding.executor
	context.ability = ability_for(action).duplicate(true)
	# Charges are inventory-owned; the old cost field must not charge twice.
	context.ability.flask_cost = 0
	context.presentation = binding.presentation.duplicate()
	context.item_cost = binding.item_cost
	context.animations = animation_bank.get_binding(binding.presentation.animations)
	context.moveset_key = StringName(str(definition.actions.get_instance_id())+":"+str(context.animations.profile.get_instance_id() if context.animations != null else 0))
	context.combo_count = maxi(1,context.animations.profile.light_attacks.size()) if context.animations != null else 2
	if source.upgrade_level > 0:
		var step: Resource = definition.upgrades.levels[source.upgrade_level-1]
		context.ability.damage *= step.damage_multiplier
		context.ability.heal_amount *= step.healing_multiplier
	return context

func can_pay(action: String) -> bool:
	var binding := binding_for(action)
	return binding != null and inventory.can_pay(source_for(action),binding.item_cost)

func presentation_available(action: String, _animation: AnimationPlayer) -> bool:
	var binding := binding_for(action)
	if binding == null: return false
	var resolved: RefCounted = animation_bank.get_binding(binding.presentation.animations)
	if resolved == null: return binding.presentation.animations == null and animation_bank.default_binding == null
	var profile: Resource = resolved.profile
	var clips: Array = []
	match binding.executor:
		"light":
			if profile.light_attacks.is_empty(): return false
			for attack in profile.light_attacks: clips.append_array([attack.clip,attack.recovery_clip])
		"heavy":
			if profile.heavy_attack == null: return false
			clips = [profile.heavy_attack.clip,profile.heavy_attack.recovery_clip]
		"cast":
			var spell: Resource = profile.spell_cast
			if spell == null: return false
			clips = [spell.enter_clip,spell.idle_clip,spell.shoot_clip,spell.exit_clip]
	return animation_bank.available(resolved,clips)

func commit(context: RefCounted, resources: RefCounted) -> bool:
	if context == null or not inventory.can_pay(context.instance_id,context.item_cost): return false
	var ability: Resource = context.ability
	if not resources.can_spend(ability.stamina_cost,ability.mana_cost): return false
	# These operations are synchronous and silent. Notifications happen after
	# the lifecycle installs the accepted action, so observers never see half a cost.
	resources.try_spend(ability.stamina_cost,ability.mana_cost)
	inventory.spend_silent(context.instance_id,context.item_cost)
	return true
