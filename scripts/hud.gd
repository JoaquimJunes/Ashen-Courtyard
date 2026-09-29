extends CanvasLayer
var player: Combatant
var boss: Combatant
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var mana_bar: ProgressBar
var boss_bar: ProgressBar
var status: Label
var overlay: PanelContainer
var title: Label
var resume: Button
var reticle: Label
var camera_options: PanelContainer
var keybindings: PanelContainer
var guide: Label
var menu: CanvasLayer

func label(text: String, size: int, color: Color = Color("dfded7")) -> Label:
 var node := Label.new()
 node.text = text
 node.add_theme_font_size_override("font_size",size)
 node.add_theme_color_override("font_color",color)
 return node

func bar(parent: Node, color: Color, width: float, height: float = 12) -> ProgressBar:
 var node := ProgressBar.new()
 node.custom_minimum_size = Vector2(width,height)
 node.show_percentage = false
 var bg := StyleBoxFlat.new()
 bg.bg_color = Color("222b31")
 var fill := StyleBoxFlat.new()
 fill.bg_color = color
 node.add_theme_stylebox_override("background",bg)
 node.add_theme_stylebox_override("fill",fill)
 parent.add_child(node)
 return node

func _ready() -> void:
 layer = 2
 process_mode = Node.PROCESS_MODE_ALWAYS
 var root := Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(root)
 var top := VBoxContainer.new()
 top.position = Vector2(32,26)
 top.add_theme_constant_override("separation",8)
 root.add_child(top)
 top.add_child(label("ASHEN / COURTYARD",21,Color("e1c390")))
 top.add_child(label("HEALTH",11))
 health_bar = bar(top,Color("bb635c"),270)
 top.add_child(label("STAMINA",11))
 stamina_bar = bar(top,Color("8ba878"),270,7)
 top.add_child(label("MANA",11))
 mana_bar = bar(top,Color("74baca"),270,7)
 status = label("",15)
 top.add_child(status)
 var bottom := VBoxContainer.new()
 root.add_child(bottom)
 bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 bottom.position = Vector2(390,595)
 bottom.add_child(label("THE CINDER WARDEN",18,Color("e1c390")))
 boss_bar = bar(bottom,Color("b1705e"),500,10)
 guide = label("",13)
 root.add_child(guide)
 guide.position = Vector2(32,650)
 guide.size.x = 1216
 guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 refresh_guide()
 reticle = label("·",28,Color("e2d7b4"))
 root.add_child(reticle)
 reticle.position = Vector2(635,341)

func refresh_guide() -> void:
 guide.text = "%s/%s/%s/%s Move · Mouse Look · %s Sprint · %s Jump · %s Dodge · %s/%s Light/Heavy\n%s Lock · %s/%s Spell · %s Cast · %s Heal · %s Pause · %s Debug · %s PS1 effects" % [GameInput.key("forward"),GameInput.key("left"),GameInput.key("back"),GameInput.key("right"),GameInput.key("sprint"),GameInput.key("jump"),GameInput.key("dodge"),GameInput.key("light"),GameInput.key("heavy"),GameInput.key("lock"),GameInput.key("spell_one"),GameInput.key("spell_two"),GameInput.key("cast"),GameInput.key("heal"),GameInput.key("pause"),GameInput.key("diagnostics"),GameInput.key("retro")]

func open_camera_options() -> void:
 if not menu.panel.visible: menu.open_menu()
 menu.navigate("Settings")
 menu.settings.select("Camera")

func bind(p: Combatant, b: Combatant) -> void:
 player = p
 boss = b
 menu = preload("res://features/ui/pause_menu.tscn").instantiate()
 add_child(menu)
 menu.configure(p)
 menu.settings_applied.connect(refresh_guide)
 overlay = menu.panel
 title = menu.title
 resume = menu.resume
 camera_options = menu.settings.editors.Camera
 keybindings = menu.settings.editors.Controls
 health_bar.max_value = p.max_health
 health_bar.value = p.health
 stamina_bar.max_value = p.tuning.stamina_max
 mana_bar.max_value = p.tuning.mana_max
 boss_bar.max_value = b.max_health
 boss_bar.value = b.health
 p.health_changed.connect(func(value, _maximum): health_bar.value = value)
 b.health_changed.connect(func(value, _maximum): boss_bar.value = value)
 p.resources_changed.connect(func(stamina,mana,flasks,spell):
  stamina_bar.value = stamina
  mana_bar.value = mana
  status.text = "%02d  %s   /   %s" % [spell+1,p.items.selected_name(&"spell"),p.items.gadget_status()]
 )

func _process(_delta: float) -> void:
 if is_instance_valid(player): reticle.text = "◇" if player.locked else "·"

func toggle_pause() -> void:
 menu.toggle_pause()

func show_end(won: bool) -> void:
 menu.show_end(won)

func restart() -> void:
 GameSession.retry()

func open_test_grounds() -> void:
 GameSession.change_world("res://scenes/movement_lab.tscn")
