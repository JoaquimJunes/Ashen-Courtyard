extends RefCounted
## One visual instance per item. Temporary hand release never changes the chosen layout.
const Socket = preload("res://features/presentation/equipment_socket_definition.gd")
const Item = preload("res://features/presentation/equipment_visual_definition.gd")
signal changed
var skeleton: Skeleton3D
var sockets: Dictionary = {}
var items: Dictionary = {}
var current_sockets: Dictionary = {}
var hand_release_reasons: Dictionary = {}
var desired_layout: StringName = &"all_stowed"
var death_frozen := false
var last_error := ""
var socket_labels_visible := false
var layouts: Dictionary = {&"all_stowed": []}
var _socket_labels: Array[Label3D] = []

func configure(value: Skeleton3D, definitions: Array, layout_definitions: Dictionary = {&"all_stowed": []}) -> bool:
	last_error = ""
	if not is_instance_valid(value): return fail("Equipment requires a character skeleton.")
	var ids := {}
	for definition in definitions:
		if not definition is Socket or definition.id == &"" or ids.has(definition.id):
			return fail("Socket IDs must be nonempty and unique.")
		if value.find_bone(definition.bone_name) < 0 or not valid_transform(definition.local_transform):
			return fail("Unknown bone or invalid transform for socket: "+str(definition.id))
		ids[definition.id] = true
	for layout in layout_definitions:
		if not layout_definitions[layout] is Array: return fail("Layouts must list held item IDs.")
		for id in layout_definitions[layout]:
			if not (id is StringName or id is String) or str(id).is_empty(): return fail("Layout item IDs must be nonempty names.")
	if not layout_definitions.has(&"all_stowed") or not layout_definitions[&"all_stowed"].is_empty():
		return fail("Equipment needs an empty all_stowed layout.")
	clear_items()
	for socket in sockets.values():
		if is_instance_valid(socket): socket.free()
	sockets.clear()
	_socket_labels.clear()
	skeleton = value
	layouts = layout_definitions.duplicate(true)
	desired_layout = &"all_stowed"
	hand_release_reasons.clear()
	death_frozen = false
	for definition in definitions:
		var socket := BoneAttachment3D.new()
		socket.name = "Equipment_"+str(definition.id)
		socket.bone_name = definition.bone_name
		socket.override_pose = false
		skeleton.add_child(socket)
		# BoneAttachment owns its transform; the configured offset belongs to a child.
		var frame := Node3D.new()
		frame.name = "SocketFrame"
		socket.add_child(frame)
		frame.transform = definition.local_transform
		sockets[definition.id] = socket
		var label := Label3D.new()
		label.text = str(definition.id)
		label.font_size = 28
		label.pixel_size = 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.visible = socket_labels_visible
		frame.add_child(label)
		_socket_labels.append(label)
	return true

func valid_transform(value: Transform3D) -> bool:
	return value.is_finite() and absf(value.basis.determinant()) > 0.000001

func fail(message: String) -> bool:
	last_error = message
	return false

func socket_frame(id: StringName) -> Node3D:
	var socket: BoneAttachment3D = sockets.get(id)
	return socket.get_node("SocketFrame") if is_instance_valid(socket) else null

func instantiate_visual(definition: Item) -> Node3D:
	var visual: Node3D
	if definition.visual != null:
		var instance := definition.visual.instantiate()
		if not instance is Node3D:
			instance.free()
			fail("Equipment visual must have a Node3D root: "+str(definition.id))
			return null
		visual = instance
		if not visual.find_children("*","Skeleton3D",true,false).is_empty() or visual is Skeleton3D or visual is CollisionObject3D or not visual.find_children("*","CollisionObject3D",true,false).is_empty():
			visual.free()
			fail("Rigid equipment cannot add a skeleton or collision: "+str(definition.id))
			return null
	elif not definition.placeholder_label.is_empty():
		visual = Node3D.new()
		var label := Label3D.new()
		label.text = definition.placeholder_label
		label.font_size = 30
		label.pixel_size = 0.003
		label.modulate = Color("f0c879")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		visual.add_child(label)
	else:
		fail("Equipment needs a visual or an explicit review marker: "+str(definition.id))
		return null
	visual.name = "Item_"+str(definition.id)
	return visual

func set_loadout(definitions: Array) -> bool:
	last_error = ""
	if death_frozen: return fail("Reset before replacing frozen equipment.")
	if not is_instance_valid(skeleton): return fail("Configure equipment before setting a loadout.")
	var staged := {}
	for definition in definitions:
		if not definition is Item or definition.id == &"" or staged.has(definition.id):
			free_staged(staged)
			return fail("Item IDs must be nonempty and unique.")
		if socket_frame(definition.stowed_socket) == null or (definition.held_socket != &"" and socket_frame(definition.held_socket) == null):
			free_staged(staged)
			return fail("Equipment references an unknown socket: "+str(definition.id))
		if not valid_transform(definition.held_transform) or not valid_transform(definition.stowed_transform):
			free_staged(staged)
			return fail("Equipment has an invalid placement transform: "+str(definition.id))
		for hand in definition.occupied_hands:
			if socket_frame(hand) == null:
				free_staged(staged)
				return fail("Equipment references an unknown hand socket: "+str(hand))
		var visual := instantiate_visual(definition)
		if visual == null:
			free_staged(staged)
			return false
		staged[definition.id] = {"definition":definition,"visual":visual}
	# Validate the desired layout and its temporary stowed form independently.
	# A cast/climb in progress must not conceal conflicts that appear on restore.
	for layout in [desired_layout,&"all_stowed"]:
		if placement_plan(staged,layout,false).is_empty() and not staged.is_empty():
			free_staged(staged)
			return false
	clear_items()
	items = staged
	apply_layout()
	return true

func validate_gameplay_loadout(definitions: Array, held: Array) -> bool:
	var ids := {}
	var stowed := {}
	var placed := {}
	var hands := {}
	for definition in definitions:
		if not definition is Item or ids.has(definition.id): return false
		ids[definition.id] = true
		if socket_frame(definition.stowed_socket) == null or socket_frame(definition.held_socket) == null: return false
		if not valid_transform(definition.held_transform) or not valid_transform(definition.stowed_transform): return false
		if stowed.has(definition.stowed_socket): return false
		stowed[definition.stowed_socket] = true
		var target: StringName = definition.held_socket if definition.id in held else definition.stowed_socket
		if placed.has(target): return false
		placed[target] = true
		if definition.id in held:
			for hand in definition.occupied_hands:
				if hands.has(hand): return false
				hands[hand] = true
	return true

func set_gameplay_loadout(definitions: Array, held: Array) -> bool:
	if not validate_gameplay_loadout(definitions,held): return fail("Incompatible gameplay equipment visuals.")
	var previous_layouts := layouts
	var previous_desired := desired_layout
	layouts = {&"all_stowed":[],&"equipped":held.duplicate()}
	# Preserve the old per-visual layout interface for pose/review callers.
	# These aliases are derived from data; gameplay still chooses "equipped".
	for definition in definitions:
		if definition.id not in [&"all_stowed",&"equipped"] and validate_gameplay_loadout(definitions,[definition.id]):
			layouts[definition.id] = [definition.id]
	desired_layout = &"equipped"
	if set_loadout(definitions): return true
	layouts = previous_layouts
	desired_layout = previous_desired
	return false

func free_staged(staged: Dictionary) -> void:
	for item in staged.values(): item.visual.free()

func clear_items() -> void:
	for item in items.values():
		if is_instance_valid(item.visual): item.visual.free()
	items.clear()
	current_sockets.clear()

func placement_plan(loadout: Dictionary, layout: StringName, honor_release: bool = true) -> Dictionary:
	var plan := {}
	var occupied := {}
	var held_hands := {}
	var held: Array = [] if honor_release and not hand_release_reasons.is_empty() else layouts[layout]
	for id in loadout:
		var definition: Item = loadout[id].definition
		var is_held: bool = id in held
		var target := definition.held_socket if is_held else definition.stowed_socket
		if target == &"" or occupied.has(target):
			fail("Equipment layout has an unavailable or occupied socket: "+str(target))
			return {}
		occupied[target] = id
		if is_held:
			for hand in definition.occupied_hands:
				if held_hands.has(hand):
					fail("Equipment layout uses the same hand twice: "+str(hand))
					return {}
				held_hands[hand] = id
		plan[id] = {"socket":target,"held":is_held}
	return plan

func set_layout(layout: StringName) -> bool:
	last_error = ""
	if not layouts.has(layout): return fail("Unknown equipment layout: "+str(layout))
	if placement_plan(items,layout,false).is_empty() and not items.is_empty(): return false
	if desired_layout == layout: return true
	desired_layout = layout
	apply_layout()
	return true

func request_hand_release(reason: StringName) -> void:
	if reason == &"" or hand_release_reasons.has(reason): return
	hand_release_reasons[reason] = true
	apply_layout()

func release_hand_release(reason: StringName) -> void:
	if not hand_release_reasons.erase(reason): return
	apply_layout()

func freeze_for_death() -> void:
	if death_frozen: return
	death_frozen = true
	changed.emit()

func reset() -> void:
	death_frozen = false
	hand_release_reasons.clear()
	apply_layout()

func apply_layout() -> void:
	if death_frozen or not is_instance_valid(skeleton): return
	var plan := placement_plan(items,desired_layout)
	if plan.is_empty() and not items.is_empty(): return
	for id in plan:
		var visual: Node3D = items[id].visual
		var placement: Dictionary = plan[id]
		var target := socket_frame(placement.socket)
		if target == null: continue
		if visual.get_parent() == null:
			target.add_child(visual)
		elif visual.get_parent() != target:
			visual.reparent(target,false)
		var definition: Item = items[id].definition
		visual.transform = definition.held_transform if placement.held else definition.stowed_transform
		current_sockets[id] = placement.socket
	changed.emit()

func set_socket_labels_visible(value: bool) -> void:
	socket_labels_visible = value
	for label in _socket_labels:
		if is_instance_valid(label): label.visible = value
