extends CanvasLayer
## Presentation review only. These controls do not equip gameplay inventory or add bindings.
const Style = preload("res://features/ui/ui_style.gd")
const CHEST = preload("res://assets/models/ual/chest_fixture.res")
const AppearanceDefinition = preload("res://features/presentation/appearance_definition.gd")
@export var armor_samples: Array[AppearanceDefinition] = [CHEST]
var label: Label
var armor_label: Label
var native_label: Label
var fallback_label: Label
var socket_toggle: CheckButton
var layout_buttons: Dictionary = {}
var actor: CharacterBody3D
var panel: PanelContainer
var menu: CanvasLayer
var hint: Label
var armor_selector: OptionButton
var wear_button: Button
var remove_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.theme = Style.make_theme()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.hide()
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	Style.paragraph(row,"UAL appearance review · changes affect visual equipment only")
	label = Style.paragraph(row,"Loading review character…")
	for entry in [[&"all_stowed","Carry all items"],[&"sword_shield","Hold sword + shield"],[&"bow","Hold bow marker"]]:
		layout_buttons[entry[0]] = Style.button(row,entry[1],choose_layout.bind(entry[0]))
		layout_buttons[entry[0]].toggle_mode = true
	socket_toggle = CheckButton.new()
	socket_toggle.text = "Show attachment labels"
	socket_toggle.toggled.connect(func(value):
		if is_instance_valid(actor) and actor.model.equipment != null: actor.model.equipment.set_socket_labels_visible(value))
	row.add_child(socket_toggle)
	Style.paragraph(row,"Sword and shield reuse existing meshes.\nThe bow is a position marker; artwork is pending.")
	armor_label = Style.paragraph(row,"")
	armor_selector = OptionButton.new()
	row.add_child(armor_selector)
	for index in armor_samples.size():
		var sample := armor_samples[index]
		if sample == null: continue
		var title := sample.resource_name.strip_edges()
		if title.is_empty(): title = str(sample.slot).capitalize()+" sample "+str(index+1)
		armor_selector.add_item(title,index)
	armor_selector.disabled = armor_selector.item_count == 0
	armor_selector.item_selected.connect(func(_index): update_sample_buttons())
	var armor_actions := HBoxContainer.new()
	row.add_child(armor_actions)
	wear_button = Style.button(armor_actions,"Wear selected armor",wear_selected)
	remove_button = Style.button(armor_actions,"Remove selected armor",remove_selected)
	update_sample_buttons()
	native_label = Style.paragraph(row,"")
	fallback_label = Style.paragraph(row,"")
	for text in [label,armor_label,native_label,fallback_label]:
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = Style.text("Appearance review: pause, then choose Appearance",16)
	hint.position = Vector2(16,140)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	bind_actor.call_deferred()

func bind_actor() -> void:
	actor = get_parent().player
	# Register a review-scene-only page with the existing focus/pause owner.
	# An independent overlay would cover the settings/modal controls on Escape.
	menu = get_parent().hud.menu
	panel.reparent(menu.pages.Home.get_parent(),false)
	menu.pages["Appearance"] = panel
	var navigation := Style.button(menu.navigation.Home.get_parent(),"Appearance",menu.navigate.bind("Appearance"))
	navigation.toggle_mode = true
	menu.navigation["Appearance"] = navigation
	menu.panel.visibility_changed.connect(func(): hint.visible = not menu.panel.visible)
	hint.visible = not menu.panel.visible
	if actor.model.equipment != null: actor.model.equipment.changed.connect(refresh)
	actor.model.appearance.body_changed.connect(refresh)
	refresh()

func choose_layout(layout: StringName) -> void:
	if not is_instance_valid(actor) or actor.model.equipment == null: return
	if not actor.model.equipment.set_layout(layout):
		label.text = actor.model.equipment.last_error
		return
	refresh()

func selected_sample() -> AppearanceDefinition:
	if armor_selector.selected < 0: return null
	return armor_samples[armor_selector.get_selected_id()]

func update_sample_buttons() -> void:
	var unavailable := not is_instance_valid(actor) or selected_sample() == null
	wear_button.disabled = unavailable
	remove_button.disabled = unavailable

func wear_selected() -> void:
	var sample := selected_sample()
	if not is_instance_valid(actor) or sample == null: return
	if not actor.model.appearance.equip(sample):
		label.text = actor.model.appearance.last_error
		return
	refresh()

func remove_selected() -> void:
	var sample := selected_sample()
	if not is_instance_valid(actor) or sample == null: return
	actor.model.appearance.unequip(sample.slot)
	refresh()

func refresh() -> void:
	if not is_instance_valid(actor): return
	update_sample_buttons()
	var equipment: RefCounted = actor.model.equipment
	if equipment != null:
		for id in layout_buttons: layout_buttons[id].set_pressed_no_signal(equipment.desired_layout == id)
		var status := "Carried layout: "+str(equipment.desired_layout).replace("_"," ")
		if equipment.death_frozen: status += " · frozen for death"
		elif not equipment.hand_release_reasons.is_empty(): status += " · hands temporarily free"
		label.text = status
		socket_toggle.set_pressed_no_signal(equipment.socket_labels_visible)
	else: label.text = "Equipment review is unavailable."
	var armor := PackedStringArray()
	for slot in [&"head",&"torso",&"hands",&"legs",&"feet"]:
		armor.append(str(slot).capitalize()+": "+("equipped" if actor.model.appearance.equipment.has(slot) else "base body"))
	armor_label.text = "Armor pieces · "+" / ".join(armor)
	var profile: Resource = actor.model.animation_profile
	if profile == null: return
	var native := PackedStringArray()
	for role in profile.native_source_clips: native.append(str(role).replace("_"," "))
	var attacks := PackedStringArray()
	for attack in profile.light_attacks:
		var clip: Animation = profile.clip_for(attack.clip)
		if clip != null: attacks.append(str(clip.get_meta("source_clip",attack.clip)).replace("_"," "))
	native_label.text = "Native movement: "+", ".join(native)
	if not attacks.is_empty(): native_label.text += "\nNative light attacks: "+", ".join(attacks)+" + recoveries"
	var actions := PackedStringArray()
	if profile.sword_idle != &"": actions.append("sword idle")
	if profile.heavy_attack != null: actions.append("heavy sword")
	if profile.spell_cast != null: actions.append("spell enter / idle / shoot / exit")
	if profile.mantle_clip != &"": actions.append("mantle")
	if not actions.is_empty(): native_label.text += "\nNative actions: "+", ".join(actions)
	fallback_label.text = "Temporary action animation: "+", ".join(profile.temporary_fallbacks)
