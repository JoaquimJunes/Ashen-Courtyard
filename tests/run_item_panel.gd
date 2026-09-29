extends SceneTree
## Exercise production controls using real GUI input, not direct button callbacks.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)
func settle() -> void:
	for frame in 5: await process_frame
func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_screen_transform()*control.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)
func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = code if code >= 32 and code <= 126 else 0
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
func run() -> void:
	var scene = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 8: await physics_frame
	await settle()
	var actor: CharacterBody3D = scene.player
	var menu: CanvasLayer = scene.hud.menu
	var panel: VBoxContainer = menu.item_tests
	actor.set_physics_process(false)
	actor.model.set_process(false)
	check(not panel.is_visible_in_tree(),"Item controls stay hidden during play")
	key(KEY_ESCAPE)
	await settle()
	click(menu.navigation["Test Grounds"])
	await settle()
	var item_button: Button
	for button in menu.tools.find_children("*","Button",true,false):
		if button.text == "Item testing": item_button = button
	check(item_button != null,"Test Grounds exposes item testing")
	click(item_button)
	await settle()
	check(menu.current == "Items" and panel.is_visible_in_tree() and paused,"Item panel uses shared pause navigation")
	check(panel.owned_list.item_count == 4 and panel.catalog_selector.item_count == 9,"Panel lists owned inventory and catalog definitions")
	# Choose the first catalog item through keyboard input to its popup.
	panel.catalog_selector.grab_focus()
	key(KEY_SPACE)
	await settle()
	key(KEY_HOME)
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_DOWN)
	key(KEY_ENTER)
	await settle()
	check(panel.catalog_selector.get_item_metadata(panel.catalog_selector.selected) == &"practice_blade","Catalog selection works through keyboard navigation")
	click(panel.grant_button)
	await settle()
	check(panel.owned_list.item_count == 5 and "granted" in panel.status.text,"Grant button adds and selects an independent owned copy")
	click(panel.equip_button)
	await settle()
	check(actor.items.equipment.definition(actor.items.equipment.primary).id == &"practice_blade","Equip button assigns the selected copy")
	panel.level.get_line_edit().grab_focus()
	panel.level.get_line_edit().select_all()
	key(KEY_1)
	key(KEY_ENTER)
	await settle()
	panel.upgrade_button.grab_focus()
	key(KEY_ENTER)
	await settle()
	check(actor.items.inventory.find(actor.items.equipment.primary).upgrade_level == 1,"Upgrade control changes only the equipped copy")
	check(actor.items.catalog.find(&"azure_sword").actions.for_role(&"light").ability.damage == 24,"Panel editing leaves shared base damage unchanged")
	click(panel.clear_button)
	await settle()
	check(actor.items.equipment.primary == &"" and actor.model.equipment.items.is_empty(),"Clear slot removes held visuals without deleting inventory")
	click(panel.equip_button)
	await settle()
	check(actor.items.equipment.primary != &"","Cleared item can be re-equipped")
	var scroll: ScrollContainer = menu.pages.Items.get_child(0)
	check(scroll.get_global_rect().end.y <= root.get_visible_rect().end.y and panel.size.x <= scroll.size.x,"Item page stays inside the menu viewport")
	if "--item-panel-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.artifacts/tests/item-panel.png")
	key(KEY_ESCAPE)
	await settle()
	check(menu.current == "Test Grounds" and paused,"Escape returns from items to Test Grounds")
	menu.close_menu()
	actor.combat_enabled = true
	var pending: RefCounted = actor.request_action(&"light")
	menu.open_menu("Items")
	await settle()
	check(not pending.resolved and panel.grant_button.disabled and panel.equip_button.disabled,"Paused pending action disables inventory edits")
	menu.close_menu()
	actor.actions.cancel(&"test")
	menu.open_menu("Items")
	await settle()
	check(not panel.grant_button.disabled,"Controls re-enable when the action is resolved")
	menu.close_menu()
	scene.free()
	await settle()
	print("ITEM PANEL: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
