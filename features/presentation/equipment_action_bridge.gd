extends RefCounted
## Observes committed gameplay actions; equipment never changes their timing or costs.
var actor: CharacterBody3D
var equipment: RefCounted
var free_hand_actions: Array[StringName] = []
var bound_items: Array = []
var bound_held: Array = []
const ACTION_HANDS := &"action_hands"

func configure(character: CharacterBody3D) -> void:
	actor = character
	equipment = actor.model.equipment
	if equipment == null: return
	free_hand_actions.assign(actor.model.animation_profile.free_hand_actions)
	if actor.model.gameplay_equipment:
		actor.items.equipment.visual_validator = validate_loadout
		actor.items.equipment.changed.connect(sync_loadout)
		sync_loadout()
	actor.actions.started.connect(on_started)
	actor.actions.finished.connect(on_finished)
	actor.actions.cancelled.connect(on_cancelled)
	actor.movement.mode_changed.connect(on_mode_changed)
	# Combatant commits death before health notifications. Freeze before reaction
	# callbacks can release traversal or interrupt a cast during the same hit.
	actor.health_changed.connect(on_health_changed)
	actor.died.connect(on_died)
	refresh()

func refresh() -> void:
	if equipment == null: return
	if actor.dead:
		equipment.freeze_for_death()
		return
	var definition: Resource = actor.actions.active_definition
	var context: RefCounted = actor.actions.active_item
	var release: bool = context.presentation.free_hands if context != null else (definition != null and definition.id in free_hand_actions)
	var water_grip: bool = actor.movement.attachment != null and actor.traversal.candidate != null and actor.traversal.candidate.from_water
	release = release or actor.swimming.active or water_grip or actor.crawling.active
	if release:
		equipment.request_hand_release(ACTION_HANDS)
	else:
		equipment.release_hand_release(ACTION_HANDS)

func validate_loadout(loadout: RefCounted) -> bool:
	var plan: Dictionary = loadout.visual_plan()
	return equipment.validate_gameplay_loadout(plan.items,plan.held)

func sync_loadout() -> void:
	if equipment == null or equipment.death_frozen: return
	var plan: Dictionary = actor.items.equipment.visual_plan()
	if plan.items == bound_items and plan.held == bound_held: return
	if equipment.set_gameplay_loadout(plan.items,plan.held):
		bound_items = plan.items.duplicate()
		bound_held = plan.held.duplicate()
	else: push_error(equipment.last_error)

func on_started(_id: StringName) -> void: refresh()
func on_finished(_id: StringName) -> void: refresh()
func on_cancelled(_id: StringName, _reason: StringName) -> void: refresh()
func on_mode_changed(_before: StringName, _after: StringName) -> void: refresh()
func on_health_changed(_health: float, _maximum: float) -> void:
	if actor.dead: equipment.freeze_for_death()
func on_died() -> void: equipment.freeze_for_death()

func reset() -> void:
	if equipment == null: return
	equipment.reset()
	if actor.model.gameplay_equipment:
		sync_loadout()
		equipment.set_layout(&"equipped")
	refresh()

func unload() -> void:
	if equipment == null: return
	# Stop observing before the actor cancels its last action and frees its model.
	equipment.freeze_for_death()
	if actor.model.gameplay_equipment:
		actor.items.equipment.changed.disconnect(sync_loadout)
		actor.items.equipment.visual_validator = Callable()
	actor.actions.started.disconnect(on_started)
	actor.actions.finished.disconnect(on_finished)
	actor.actions.cancelled.disconnect(on_cancelled)
	actor.movement.mode_changed.disconnect(on_mode_changed)
	actor.health_changed.disconnect(on_health_changed)
	actor.died.disconnect(on_died)
	equipment = null
	actor = null
