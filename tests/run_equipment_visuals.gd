extends SceneTree
const Controller = preload("res://features/presentation/equipment_visual_controller.gd")
const Item = preload("res://features/presentation/equipment_visual_definition.gd")
const Defaults = preload("res://features/presentation/review_equipment_loadout.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func make_skeleton(parent: Node) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for bone in ["hand_r","hand_l","pelvis","spine_03"]: skeleton.add_bone(bone)
	parent.add_child(skeleton)
	return skeleton
func make_items() -> Array:
	var result := []
	for source in Defaults.items():
		var item: Item = source.duplicate()
		item.visual = null
		item.placeholder_label = str(item.id)
		result.append(item)
	return result
func placed(controller: RefCounted, sword: StringName, shield: StringName, bow: StringName) -> bool:
	return controller.current_sockets == {&"sword":sword,&"shield":shield,&"bow":bow}
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var skeleton := make_skeleton(world)
	var controller := Controller.new()
	var layouts := Defaults.layouts().duplicate(true)
	layouts[&"conflict"] = [&"sword",&"bow"]
	check(controller.configure(skeleton,Defaults.sockets(),layouts),"Rigid attachment validates four required bones without a body bind manifest")
	check(controller.set_loadout(make_items()),"Load independent marker instances")
	check(placed(controller,&"left_hip",&"back_shield",&"back_bow"),"All three carried sockets")
	check(controller.set_layout(&"sword_shield"),"Choose sword and shield")
	check(placed(controller,&"right_hand",&"left_hand",&"back_bow"),"Sword and shield held while bow stays on back")
	var sword: Node3D = controller.items[&"sword"].visual
	var count := skeleton.get_child_count()
	for i in 3:
		controller.set_layout(&"sword_shield")
		controller.request_hand_release(&"action_hands")
	check(controller.hand_release_reasons.size() == 1,"Repeated release reason is idempotent")
	check(placed(controller,&"left_hip",&"back_shield",&"back_bow"),"Cast frees hands and retains all items")
	controller.request_hand_release(&"traversal")
	controller.release_hand_release(&"action_hands")
	check(placed(controller,&"left_hip",&"back_shield",&"back_bow"),"Overlapping traversal prevents early restore")
	check(not controller.set_layout(&"conflict") and controller.desired_layout == &"sword_shield","Desired hand conflict rejects even during a temporary hand release")
	var conflicting := make_items()
	conflicting[1].held_socket = &"right_hand"
	check(not controller.set_loadout(conflicting),"Conflicting replacement rejects while hands are temporarily free")
	check(controller.items[&"sword"].visual == sword,"Rejected replacement preserves live visual identity")
	check(controller.set_layout(&"bow"),"Desired layout may change while hands are free")
	check(placed(controller,&"left_hip",&"back_shield",&"back_bow"),"Changing desired layout does not defeat the active release")
	controller.release_hand_release(&"traversal")
	check(placed(controller,&"left_hip",&"back_shield",&"left_hand"),"Final release restores latest desired layout")
	var valid_replacement := make_items()
	controller.request_hand_release(&"action_hands")
	check(controller.set_loadout(valid_replacement),"Valid replacement accepted during release")
	check(placed(controller,&"left_hip",&"back_shield",&"back_bow"),"Replacement preserves temporary stow")
	controller.release_hand_release(&"action_hands")
	check(placed(controller,&"left_hip",&"back_shield",&"left_hand"),"Replacement restores desired held bow")
	controller.request_hand_release(&"traversal")
	var frozen := controller.current_sockets.duplicate()
	var visual: Node3D = controller.items[&"bow"].visual
	var frozen_parent := visual.get_parent()
	var frozen_transform := visual.transform
	controller.freeze_for_death()
	controller.release_hand_release(&"traversal")
	controller.request_hand_release(&"late_action")
	controller.release_hand_release(&"late_action")
	check(controller.current_sockets == frozen and visual.get_parent() == frozen_parent and visual.transform == frozen_transform,"Death freezes exact placement despite late release callbacks")
	check(not controller.set_loadout(make_items()),"Death blocks live loadout replacement")
	controller.reset()
	check(not controller.death_frozen and controller.hand_release_reasons.is_empty() and controller.desired_layout == &"bow","Reset clears transient state while retaining desired layout")
	check(placed(controller,&"left_hip",&"back_shield",&"left_hand"),"Reset reapplies chosen held layout")
	controller.reset()
	check(skeleton.get_child_count() == count and controller.items.size() == 3,"Reset and repeated transitions never duplicate sockets or items")
	controller.set_socket_labels_visible(true)
	for socket in controller.sockets:
		check(controller.socket_frame(socket).get_child(0).visible,"Attachment label visible: "+str(socket))
	controller.set_socket_labels_visible(false)
	var before: Dictionary = controller.sockets.duplicate()
	check(not controller.configure(skeleton,Defaults.sockets(),{&"all_stowed":17}),"Malformed layout reports validation failure instead of invoking methods on scalars")
	check(controller.sockets == before and controller.items.size() == 3,"Invalid configure preserves existing live attachments")
	var unknown: Resource = Defaults.sockets()[0].duplicate()
	unknown.bone_name = &"missing"
	check(not controller.configure(skeleton,[unknown],layouts),"Reject missing attachment bone")
	for kind in ["missing_socket","duplicate_id","invalid_transform","empty_visual","collision","second_skeleton"]:
		var invalid := make_items()
		match kind:
			"missing_socket": invalid[0].stowed_socket = &"absent"
			"duplicate_id": invalid[1].id = &"sword"
			"invalid_transform": invalid[0].stowed_transform = Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO)
			"empty_visual": invalid[0].placeholder_label = ""
			_:
				var bad: Node3D = StaticBody3D.new() if kind == "collision" else Skeleton3D.new()
				var packed := PackedScene.new()
				packed.pack(bad)
				bad.free()
				invalid[0].visual = packed
		check(not controller.set_loadout(invalid),"Reject malformed visual definition: "+kind)
		check(controller.items.size() == 3 and controller.items[&"bow"].visual == visual,"Rejected definition retains entire live loadout: "+kind)
	var other_skeleton := make_skeleton(world)
	var other := Controller.new()
	check(other.configure(other_skeleton,Defaults.sockets(),Defaults.layouts()) and other.set_loadout(Defaults.items()),"Existing staged rigid geometry loads without skinned appearance metadata")
	check(other.items[&"sword"].visual != controller.items[&"sword"].visual,"Actors never share visual nodes")
	other.set_layout(&"sword_shield")
	check(controller.desired_layout == &"bow","Other actor selection is independent")
	var hand_index := other_skeleton.find_bone("hand_r")
	other_skeleton.set_bone_pose_position(hand_index,Vector3(1,2,3))
	other_skeleton.force_update_all_bone_transforms()
	# Skeleton pose notifications are deferred; inspect after the next completed frame.
	for frame in 2: await process_frame
	check(other.sockets[&"right_hand"].position.is_equal_approx(Vector3(1,2,3)),"Attachment follows live skeleton bone pose")
	check(other.items[&"bow"].visual.get_child(0) is Label3D,"Missing bow art remains a clearly labeled text marker")
	var sword_definition: Resource = Defaults.items()[0]
	check((sword_definition.stowed_transform.basis*Vector3.FORWARD).normalized().dot(Vector3.DOWN) > 0.95,"Carried sword points down from left hip")
	world.free()
	print("EQUIPMENT VISUALS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
