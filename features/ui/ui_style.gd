extends RefCounted
## Shared, original stone/olive UI styling. The 3D resolution never scales this text.
static var cached: Theme

static func box(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	return style

static func make_theme() -> Theme:
	if cached != null: return cached
	cached = Theme.new()
	cached.default_font_size = 18
	for type in ["Label","Button","CheckButton","OptionButton","RichTextLabel"]:
		cached.set_color("font_color",type,Color("eee6cc"))
	cached.set_color("font_disabled_color","Button",Color("939681"))
	for type in ["Button","OptionButton"]:
		cached.set_stylebox("normal",type,box(Color("34372d"),Color("777963")))
		cached.set_stylebox("hover",type,box(Color("484c3b"),Color("e0ce96")))
		cached.set_stylebox("pressed",type,box(Color("252820"),Color("e0ce96")))
		cached.set_stylebox("disabled",type,box(Color("292c24"),Color("565a49")))
		var focus := box(Color.TRANSPARENT,Color("e0ce96"))
		focus.draw_center = false
		focus.set_border_width_all(2)
		cached.set_stylebox("focus",type,focus)
	# Small tiled-looking grain and bevel, generated once without external assets.
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var color := Color("34372d").lightened(0.018 if (x*13+y*7)%5==0 else 0)
			if x<2 or y<2: color = Color("92937a")
			elif x>61 or y>61: color = Color("161a15")
			image.set_pixel(x,y,color)
	var panel := StyleBoxTexture.new()
	panel.texture = ImageTexture.create_from_image(image)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		panel.set_texture_margin(side,3)
		panel.set_content_margin(side,18)
	cached.set_stylebox("panel","PanelContainer",panel)
	cached.set_stylebox("panel","PopupMenu",box(Color("252820"),Color("92937a")))
	cached.set_constant("separation","VBoxContainer",10)
	cached.set_constant("separation","HBoxContainer",12)
	return cached

static func text(value: String, size: int = 18) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size)
	return label

static func button(parent: Node, value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 40
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

static func paragraph(parent: Node, value: String) -> Label:
	var label := text(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
