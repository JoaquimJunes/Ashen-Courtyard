extends SceneTree
const REVIEW = "res://scenes/ual_validation.tscn"
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func settle() -> void:
	for frame in 6: await process_frame
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_screen_transform()*control.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate() as InputEventMouseButton
	released.pressed = false
	Input.parse_input_event(released)
func run() -> void:
	var scene = load(REVIEW).instantiate()
	# Reuse an existing skinned region to verify an artist-configured second slot.
	# No extra geometry or special-case equipment implementation is needed.
	var head_sample = load("res://assets/models/ual/mannequin_body.res").duplicate()
	head_sample.resource_name = "Head fitting sample"
	head_sample.slot = &"head"
	head_sample.regions = {&"head":head_sample.regions[&"head"]}
	head_sample.covered_regions.assign([&"head"])
	scene.get_node("AppearanceReview").armor_samples.append(head_sample)
	root.add_child(scene)
	current_scene = scene
	for frame in 10: await physics_frame
	var actor: CharacterBody3D = scene.player
	actor.set_physics_process(false)
	actor.model.set_process(false)
	var equipment: RefCounted = actor.model.equipment
	var review = scene.get_node("AppearanceReview")
	check(not review.panel.is_visible_in_tree(),"Review controls do not overlap gameplay or the closed pause menu")
	key(KEY_ESCAPE)
	await settle()
	check(paused and review.menu.panel.visible,"Shared pause input exposes review navigation")
	click(review.menu.navigation.Appearance)
	await settle()
	check(review.panel.is_visible_in_tree() and review.menu.current == "Appearance","Appearance controls share menu focus and modal ownership")
	check(equipment != null and equipment.items.size() == 3,"UAL review loads all three visual items")
	check(actor.model.hand_attachment.get_child_count() == 0,"UAL compatibility hand anchor does not contain a fixed first-child sword")
	check(review.layout_buttons.size() == 3,"Review exposes carry, sword/shield and bow layouts")
	for id in [&"all_stowed",&"sword_shield",&"bow"]:
		click(review.layout_buttons[id])
		await settle()
		check(equipment.desired_layout == id and review.layout_buttons[id].button_pressed,"Review selects layout: "+str(id))
	review.socket_toggle.button_pressed = true
	check(equipment.socket_labels_visible,"Review toggles socket labels")
	review.socket_toggle.button_pressed = false
	check(not equipment.socket_labels_visible,"Review hides socket labels")
	for slot in ["Head:","Torso:","Hands:","Legs:","Feet:"]:
		check(slot in review.armor_label.text,"Review shows armor slot: "+slot)
	check(review.armor_selector.item_count == 2 and review.armor_selector.get_item_text(1) == "Head fitting sample","Configured sample uses its friendly resource name")
	check(review.armor_selector.get_item_text(0) == "Torso sample 1","Unnamed sample gets a friendly slot/index label")
	review.wear_button.grab_focus()
	await settle()
	key(KEY_ENTER)
	await settle()
	check(actor.model.appearance.equipment.has(&"torso") and not actor.model.appearance.body[&"torso"].visible,"Review chest control equips fixture and hides covered torso")
	# OptionButton keyboard interaction selects the next artist-provided sample.
	review.armor_selector.grab_focus()
	key(KEY_SPACE)
	await settle()
	key(KEY_DOWN)
	key(KEY_ENTER)
	await settle()
	check(review.selected_sample() == head_sample,"Selector activates the configured second armor sample through input")
	review.wear_button.grab_focus()
	await settle()
	key(KEY_ENTER)
	await settle()
	check(actor.model.appearance.equipment.has(&"head") and not actor.model.appearance.body[&"head"].visible,"Selected sample equips its declared slot and hides its covered region")
	check(actor.model.appearance.equipment.has(&"torso"),"Equipping selected head sample retains the chest slot")
	review.remove_button.grab_focus()
	await settle()
	key(KEY_ENTER)
	await settle()
	check(not actor.model.appearance.equipment.has(&"head") and actor.model.appearance.body[&"head"].visible and actor.model.appearance.equipment.has(&"torso"),"Removing selected head sample restores that body region and preserves chest armor")
	review.armor_selector.select(0)
	key(KEY_ENTER)
	await settle()
	check(not actor.model.appearance.equipment.has(&"torso") and actor.model.appearance.body[&"torso"].visible,"Review remove control restores base torso")
	check("Native movement:" in review.native_label.text and "idle" in review.native_label.text and "walk" in review.native_label.text,"Review labels native source locomotion")
	check("Native light attacks:" in review.native_label.text and "Sword Regular A" in review.native_label.text and "Sword Regular B" in review.native_label.text,"Review identifies the profile's native sword attacks")
	check("heavy sword" in review.native_label.text and "spell enter / idle / shoot / exit" in review.native_label.text and "mantle" in review.native_label.text,"Review identifies the newly native heavy, spell and mantle actions")
	check("Temporary action animation:" in review.fallback_label.text and "Heal / hurt" in review.fallback_label.text and not "Heavy attack" in review.fallback_label.text,"Review labels only the remaining temporary action adapters")
	for frame in 2: await process_frame
	check(review.panel.get_global_rect().end.y <= root.get_visible_rect().end.y,"Review controls remain inside viewport with scrollable content")
	review.menu.navigate("Settings")
	check(not review.panel.is_visible_in_tree(),"Settings page hides appearance controls")
	review.menu.close_menu()
	var mantle: RefCounted = actor.presentation.mantle
	check(mantle.equipment == equipment and mantle.weapon == null,"Mantle uses equipment owner without a child-index sword assumption")
	equipment.set_layout(&"sword_shield")
	var socket_count: int = actor.model.skeleton.get_child_count()
	mantle.begin(RefCounted.new())
	check(equipment.hand_release_reasons.has(&"traversal") and equipment.current_sockets[&"sword"] == &"left_hip" and equipment.current_sockets[&"shield"] == &"back_shield","Mantle begin stows both held items")
	mantle.finish()
	check(not equipment.hand_release_reasons.has(&"traversal") and equipment.current_sockets[&"sword"] == &"right_hand" and equipment.current_sockets[&"shield"] == &"left_hand","Mantle finish restores chosen held items")
	equipment.request_hand_release(&"action_hands")
	mantle.begin(RefCounted.new())
	mantle.finish()
	check(equipment.current_sockets[&"sword"] == &"left_hip" and equipment.hand_release_reasons.has(&"action_hands"),"Finishing traversal respects other hand release owners")
	equipment.release_hand_release(&"action_hands")
	check(equipment.current_sockets[&"sword"] == &"right_hand","Last owner restores held layout after traversal")
	mantle.begin(RefCounted.new())
	mantle.reset()
	mantle.reset()
	check(not mantle.active and not equipment.hand_release_reasons.has(&"traversal") and equipment.current_sockets[&"shield"] == &"left_hand","Mantle reset clears only traversal release and restores presentation")
	mantle.begin(RefCounted.new())
	equipment.freeze_for_death()
	mantle.finish()
	check(equipment.current_sockets[&"sword"] == &"left_hip" and equipment.death_frozen,"Traversal finish cannot restore an item after death")
	equipment.reset()
	mantle.reset()
	check(actor.model.skeleton.get_child_count() == socket_count,"Repeated mantle start/end/reset leaves one set of sockets")
	scene.free()
	await process_frame
	print("EQUIPMENT REVIEW: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
