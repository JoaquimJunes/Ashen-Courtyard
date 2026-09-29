extends CanvasLayer
## Shared navigation and focus ownership. Hosts inject the character and lab commands.
signal settings_applied
const Style = preload("res://features/ui/ui_style.gd")
var actor: CharacterBody3D
var lab: Node3D
var root: Control
var shade: ColorRect
var panel: PanelContainer
var title: Label
var breadcrumb: Label
var back_button: Button
var resume: Button
var pages: Dictionary = {}
var navigation: Dictionary = {}
var settings: VBoxContainer
var diagnostics: Node
var geometry: Node3D
var live_panel: PanelContainer
var live_text: Label
var live_toggle: CheckButton
var live_enabled := false
var current := "Home"
var history: Array[Dictionary] = []
var ended := false
var debug_snapshot: Dictionary = {}
var debug_text: RichTextLabel
var debug_tab := "Movement"
var debug_buttons: Dictionary = {}
var confirm: VBoxContainer
var confirmation_overlay: ColorRect
var confirmation_panel: PanelContainer
var keep_editing_button: Button
var discard_changes_button: Button
var confirmation_focus: WeakRef
var confirmation: Callable
var confirmation_message: Label
var apply_changes_button: Button
var refresh_time := 0.0
var tools: VBoxContainer
var practice: PanelContainer
var item_tests: VBoxContainer

func configure(character: CharacterBody3D, laboratory: Node3D = null) -> void:
	actor = character
	lab = laboratory
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Style.make_theme()
	add_child(root)
	shade = ColorRect.new()
	shade.color = Color(0.04,0.05,0.03,0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	panel = PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 110
	panel.offset_right = -110
	panel.offset_top = 28
	panel.offset_bottom = -28
	var column := VBoxContainer.new()
	panel.add_child(column)
	title = Style.text("ASHEN / PAUSED",26)
	column.add_child(title)
	column.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 200
	body.add_child(sidebar)
	resume = Style.button(sidebar,"Resume",request_close)
	for name in ["Home","Settings","Test Grounds","Debug","Credits","Quit"]:
		navigation[name] = Style.button(sidebar,name,navigate.bind(name))
		navigation[name].toggle_mode = true
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	for name in ["Home","Test Grounds","Practice","Items","Debug","Credits","Quit"]:
		var page := VBoxContainer.new()
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(page)
		pages[name] = page
	settings = preload("res://features/ui/settings_panel.tscn").instantiate()
	content.add_child(settings)
	pages.Settings = settings
	settings.applied.connect(func():
		live_toggle.text = "Show live diagnostics ("+GameInput.key("diagnostics")+")"
		settings_applied.emit())
	for editor in settings.editors.values(): editor.closed.connect(back)
	build_home()
	build_tests()
	build_debug()
	build_credits()
	Style.paragraph(pages.Quit,"Quit Ashen Courtyard?")
	Style.button(pages.Quit,"Quit game",func(): get_tree().quit())
	Style.button(pages.Quit,"Keep playing",back)
	var footer := HBoxContainer.new()
	column.add_child(HSeparator.new())
	column.add_child(footer)
	back_button = Style.button(footer,"Back · Esc",back)
	breadcrumb = Style.text("")
	footer.add_child(breadcrumb)
	diagnostics = preload("res://features/ui/character_diagnostics.gd").new()
	add_child(diagnostics)
	diagnostics.configure(actor)
	geometry = preload("res://features/ui/debug_geometry.gd").new()
	actor.add_child(geometry)
	geometry.configure(actor)
	live_panel = PanelContainer.new()
	root.add_child(live_panel)
	live_panel.position = Vector2(870,24)
	live_panel.size = Vector2(380,180)
	live_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_text = Style.paragraph(live_panel,"")
	live_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_panel.visibility_changed.connect(sync_live_processing)
	live_panel.hide()
	sync_live_processing()
	build_confirmation()
	panel.hide()
	shade.hide()
	_show("Home")

func build_confirmation() -> void:
	confirmation_overlay = ColorRect.new()
	confirmation_overlay.color = Color(0,0,0,0.55)
	confirmation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Stops clicks outside the dialog reaching the menu beneath it.
	confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(confirmation_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirmation_overlay.add_child(center)
	confirmation_panel = PanelContainer.new()
	confirmation_panel.custom_minimum_size.x = 560
	center.add_child(confirmation_panel)
	confirm = VBoxContainer.new()
	confirmation_panel.add_child(confirm)
	confirm.add_child(Style.text("Unapplied changes",24))
	confirmation_message = Style.paragraph(confirm,"")
	confirmation_message.custom_minimum_size.y = 80
	var buttons := HBoxContainer.new()
	confirm.add_child(buttons)
	apply_changes_button = Style.button(buttons,"Apply changes",apply_and_continue)
	discard_changes_button = Style.button(buttons,"Discard changes",func(): settings.discard(); confirmation.call())
	keep_editing_button = Style.button(buttons,"Keep editing",keep_editing)
	# Keep keyboard navigation inside the modal as well as pointer input.
	var choices: Array[Button] = [apply_changes_button,discard_changes_button,keep_editing_button]
	for i in choices.size():
		var before := choices[i].get_path_to(choices[(i+choices.size()-1)%choices.size()])
		var after := choices[i].get_path_to(choices[(i+1)%choices.size()])
		choices[i].focus_previous = before
		choices[i].focus_next = after
		choices[i].focus_neighbor_left = before
		choices[i].focus_neighbor_right = after
		choices[i].focus_neighbor_top = before
		choices[i].focus_neighbor_bottom = after
	confirmation_overlay.hide()

func keep_editing() -> void:
	_show("Settings")
	var focus: Control = confirmation_focus.get_ref() if confirmation_focus != null else null
	if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	else: settings.tabs[settings.selected].grab_focus()

func build_home() -> void:
	Style.paragraph(pages.Home,"Character Test Grounds" if lab != null else "Ashen Courtyard")
	Style.paragraph(pages.Home,"Settings and debug tools use the same interface in every level.")
	if lab == null: Style.button(pages.Home,"Retry encounter",GameSession.retry)
	else: Style.button(pages.Home,"Reset station",func(): tools.run(lab.reset_station))

func build_tests() -> void:
	if lab == null:
		Style.paragraph(pages["Test Grounds"],"Movement stations, ledges, corners and fall tests.")
		Style.button(pages["Test Grounds"],"Enter Character Test Grounds",func(): GameSession.change_world("res://scenes/movement_lab.tscn"))
		return
	tools = preload("res://features/ui/lab_tools.gd").new()
	tools.lab = lab
	tools.menu = self
	pages["Test Grounds"].add_child(tools)
	practice = preload("res://features/laboratory/movement_practice_panel.gd").new()
	practice.lab = lab
	practice.hud = lab.hud
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.Practice.add_child(scroll)
	scroll.add_child(practice)
	practice.closed.connect(back)
	practice.position = Vector2.ZERO
	practice.custom_minimum_size = Vector2.ZERO
	item_tests = preload("res://features/laboratory/item_test_panel.gd").new()
	item_tests.actor = actor
	var item_scroll := ScrollContainer.new()
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.Items.add_child(item_scroll)
	item_scroll.add_child(item_tests)

func build_debug() -> void:
	live_toggle = CheckButton.new()
	live_toggle.text = "Show live diagnostics ("+GameInput.key("diagnostics")+")"
	live_toggle.toggled.connect(set_debug)
	pages.Debug.add_child(live_toggle)
	var tabs := HBoxContainer.new()
	pages.Debug.add_child(tabs)
	for name in ["Movement","Actions","Resources","Camera","Contacts","Events"]:
		debug_buttons[name] = Style.button(tabs,name,select_debug.bind(name))
		debug_buttons[name].toggle_mode = true
	debug_text = RichTextLabel.new()
	debug_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_text.bbcode_enabled = false
	pages.Debug.add_child(debug_text)
	var options := HBoxContainer.new()
	pages.Debug.add_child(options)
	for item in [["Hand anchors","hands_enabled"],["Pull-up path","route_enabled"],["Collision capsule","capsule_enabled"],["Fitted hitboxes / breath","hitboxes_enabled"]]:
		var check := CheckButton.new()
		check.text = item[0]
		check.toggled.connect(func(value): geometry.set(item[1],value); geometry.visible = panel.visible or live_enabled)
		options.add_child(check)
	Style.paragraph(pages.Debug,"Paused inspection · Values come from the character’s existing state. Contact overlays show the last query.")

func build_credits() -> void:
	var credits := RichTextLabel.new()
	credits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	credits.bbcode_enabled = true
	credits.text = "[b]ASSET CREDITS[/b]\n\nFullplate Armor Knight — Luana Coppio · CC0\nArmor photograph — Petr Kratochvil · CC0\nModified mesh, material tint, poses and boss accents.\n[url=https://magicalgothgirrl.itch.io/fullplate-armor-knight]Knight source[/url]\n\nUniversal Animation Library — Quaternius · CC0\nContributor: Gonzalo Furnier. Retargeted rolls, jog and sprint.\n[url=https://quaternius.itch.io/universal-animation-library]Animation source[/url]\n\nPSX Dungeon — Goblinatron · CC BY 4.0\nModified placement, scale, atlas assignment and shaders.\n[url=https://goblinatron.itch.io/psx-dungeon]Dungeon source[/url] · [url=https://creativecommons.org/licenses/by/4.0/]License[/url]\n\nPS1 / PSX Visuals — snotbane · Unlicense\nAdapted Bayer dithering.\n[url=https://github.com/snotbane/psx_visuals]Shader source[/url]\n\nMenu styling created locally. Full details: CREDITS.md."
	credits.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	pages.Credits.add_child(credits)

func _show(page: String) -> void:
	current = page
	var background := "Settings" if page == "Confirm" else page
	for name in pages: pages[name].visible = name == background
	for name in navigation: navigation[name].set_pressed_no_signal(name == background)
	confirmation_overlay.visible = page == "Confirm"
	if breadcrumb != null: breadcrumb.text = "Paused / "+background
	if geometry != null: geometry.visible = live_enabled or (panel.visible and page == "Debug")
	if page == "Debug":
		debug_snapshot = diagnostics.snapshot()
		select_debug(debug_tab,false)

func guard(command: Callable) -> void:
	if current in ["Settings","Confirm"] and settings.dirty():
		if current != "Confirm":
			var focus := get_viewport().gui_get_focus_owner()
			confirmation_focus = weakref(focus) if focus != null else null
		confirmation = command
		confirmation_message.text = "Apply your changes before leaving? This includes changes in all settings tabs."
		_show("Confirm")
		keep_editing_button.grab_focus()
	else: command.call()

func apply_and_continue() -> void:
	var failed: String = settings.apply_changes()
	if not failed.is_empty():
		confirmation_message.text = "Could not save %s settings. Some changes are still unapplied. Try Apply again, discard them, or keep editing." % failed
		return
	confirmation.call()

func navigate(page: String) -> void:
	if current == page: return
	guard(func(): _navigate(page))

func _navigate(page: String) -> void:
	if ended: GameSession.set_paused(true)
	var focused: Control = confirmation_focus.get_ref() if current == "Confirm" and confirmation_focus != null else get_viewport().gui_get_focus_owner()
	# Save the originating button, not a node path that may point at another page.
	history.append({"page":"Settings" if current == "Confirm" else current,"focus":weakref(focused) if focused != null else null})
	_show(page)
	if page == "Settings": settings.open()
	elif page == "Debug":
		debug_buttons[debug_tab].grab_focus()
	elif page == "Test Grounds" and tools != null: tools.open()
	elif page == "Practice" and practice != null: practice.open()
	elif page == "Items" and item_tests != null: item_tests.open()
	else:
		var buttons: Array[Node] = pages[page].find_children("*","Button",true,false)
		if not buttons.is_empty(): buttons[0].grab_focus()

func back() -> void:
	if current == "Confirm":
		keep_editing()
		return
	guard(_back)

func _back() -> void:
	if history.is_empty():
		request_close()
		return
	var previous: Dictionary = history.pop_back()
	_show(previous.page)
	if ended and previous.page == "Home":
		GameSession.set_paused(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var focus: Control = previous.focus.get_ref() if previous.focus != null else null
	if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	else: navigation.get(previous.page,resume).grab_focus()

func open_menu(page: String = "Home") -> void:
	GameSession.set_paused(true)
	panel.show()
	shade.show()
	live_panel.hide()
	history.clear()
	_show("Home")
	if not ended: resume.grab_focus()
	else: navigation.Home.grab_focus()
	if page != "Home": navigate(page)

func request_close() -> void:
	if ended: return
	guard(close_menu)

func close_menu() -> void:
	if ended: return
	settings.discard()
	confirmation_overlay.hide()
	panel.hide()
	shade.hide()
	history.clear()
	GameSession.set_paused(false)
	live_panel.visible = live_enabled
	geometry.visible = live_enabled

func toggle_pause() -> void:
	if panel.visible: request_close()
	else: open_menu()

func show_end(won: bool) -> void:
	ended = true
	open_menu()
	title.text = "WARDEN DEFEATED" if won else "YOU FELL"
	resume.hide()
	# Preserve the existing death ragdoll while the result screen is displayed.
	GameSession.set_paused(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	# Menu shortcuts precede GUI navigation (for example, Pause bound to Tab).
	# This menu is the single raw-input owner shared by every HUD host.
	if panel != null: handle_input(event)

func _unhandled_input(_event: InputEvent) -> void:
	# The dialog's controls still receive keyboard and pointer input. Any event
	# they do not use must not reach global shortcuts behind the modal.
	if panel != null and panel.visible and current == "Confirm":
		get_viewport().set_input_as_handled()

func handle_input(event: InputEvent) -> void:
	if settings.editors.Controls.capture_input(event):
		get_viewport().set_input_as_handled()
		return
	if current == "Confirm" and panel.visible:
		if GameInput.pause_pressed(event):
			keep_editing()
			get_viewport().set_input_as_handled()
		return
	var focus := get_viewport().gui_get_focus_owner()
	# Printable shortcut bindings must not steal text entry. Escape remains the
	# guaranteed way back even while a text field owns keyboard focus.
	if panel.visible and (focus is LineEdit or focus is TextEdit) and not GameInput.escape_pressed(event): return
	if event.is_action_pressed("diagnostics") and not event.is_echo():
		set_debug(not live_enabled)
		get_viewport().set_input_as_handled()
	elif GameInput.pause_pressed(event):
		if panel.visible: back()
		else: open_menu()
		get_viewport().set_input_as_handled()

func set_debug(value: bool) -> void:
	live_enabled = value
	live_toggle.set_pressed_no_signal(value)
	live_panel.visible = value and not panel.visible
	geometry.visible = value or (panel.visible and current == "Debug")

func select_debug(name: String, focus: bool = true) -> void:
	debug_tab = name
	for key in debug_buttons: debug_buttons[key].set_pressed_no_signal(key == name)
	var rows: Array = debug_snapshot.get(name,[])
	var lines := PackedStringArray()
	for row in rows:
		lines.append(String(row) if row is String else "%s:  %s" % [row[0],row[1]])
	debug_text.text = "No events recorded yet." if lines.is_empty() else "\n".join(lines)
	if focus: debug_buttons[name].grab_focus()

func sync_live_processing() -> void:
	var active := live_panel.is_visible_in_tree()
	set_process(active)
	refresh_time = 0.0
	if active: live_text.text = diagnostics.compact()

func _process(delta: float) -> void:
	if not is_instance_valid(actor) or live_panel == null: return
	refresh_time += delta
	if refresh_time >= 0.10 and live_enabled and not panel.visible:
		refresh_time = 0
		live_text.text = diagnostics.compact()

func _exit_tree() -> void:
	if is_instance_valid(geometry): geometry.queue_free()
