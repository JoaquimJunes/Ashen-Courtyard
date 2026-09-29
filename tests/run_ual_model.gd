extends SceneTree
const MODEL = preload("res://scenes/models/ual_mannequin.tscn")
const CHEST = preload("res://assets/models/ual/chest_fixture.res")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(30,1,30),Vector3(0,-0.5,0),Color.GRAY)
	var player = load("res://scenes/player.tscn").instantiate()
	player.model_scene = MODEL
	player.controller.manual = true
	world.add_child(player)
	for i in 10: await physics_frame
	player.set_physics_process(false)
	var model = player.model
	model.set_process(false)
	check(model.skeleton.get_bone_count() == 65,"Canonical 65-joint UAL skeleton")
	check(model.appearance.body.size() == 15,"All independently hideable body regions")
	check(model.appearance.equip(CHEST),"Compatible chest equips: "+model.appearance.last_error)
	check(not model.appearance.body[&"torso"].visible,"Chest hides torso")
	check(model.appearance.body[&"head"].visible,"Chest preserves head")
	check(model.find_children("*","Skeleton3D",true,false).size() == 1,"Equipment uses one skeleton")
	var invalid = CHEST.duplicate(true)
	invalid.rig_id = &"wrong"
	check(not model.appearance.equip(invalid),"Reject wrong rig")
	check(model.appearance.equipment[&"torso"].definition == CHEST,"Failed replacement retains valid armor")
	model.appearance.unequip(&"torso")
	check(model.appearance.body[&"torso"].visible,"Unequip restores torso")
	check(player.reactions.driver.torso != null,"Explicit ragdoll anchor exists")
	check(player.reactions.driver.torso.bone_name == &"pelvis","Ragdoll anchors pelvis, not root")
	var changed_bind = CHEST.duplicate(true)
	changed_bind.rest_transforms[1].origin.x += 0.01
	check(not model.appearance.equip(changed_bind),"Reject rest-pose mismatch despite matching names")
	var layered = CHEST.duplicate()
	layered.slot = &"hands"
	check(model.appearance.equip(CHEST) and model.appearance.equip(layered),"Two slots may cover the same region")
	model.appearance.unequip(&"torso")
	check(not model.appearance.body[&"torso"].visible,"Coverage union keeps body hidden")
	model.appearance.unequip(&"hands")
	check(model.appearance.body[&"torso"].visible,"Removing final covering restores body")
	var original_pose: Array = player.presentation.capture_pose()
	check(model.appearance.set_body(load("res://assets/models/ual/mannequin_body.res")),"Body can be replaced on existing skeleton")
	check(original_pose == player.presentation.capture_pose(),"Appearance swap preserves pose")
	check(model.contact_meshes[0] == model.appearance.contact,"Body swap refreshes contact geometry")
	var second = MODEL.instantiate()
	world.add_child(second)
	second.set_process(false)
	check(model.appearance.equip(CHEST),"Equip after body replacement")
	check(second.appearance.body[&"torso"].visible and second.appearance.equipment.is_empty(),"Appearance state is independent across actors")
	second.free()
	var replacement = load("res://assets/models/ual/mannequin_body.res").duplicate()
	replacement.regions = replacement.regions.duplicate()
	var changed_mesh := ArrayMesh.new()
	var previous: ArrayMesh = replacement.regions[&"torso"]
	for surface in previous.get_surface_count():
		var builder := SurfaceTool.new()
		builder.create_from(previous,surface)
		builder.deindex()
		builder.commit(changed_mesh)
	replacement.regions[&"torso"] = changed_mesh
	check(model.appearance.set_body(replacement),"Body with different mesh layout binds to the same rig")
	check(not model.appearance.body[&"torso"].visible,"Body replacement preserves armor coverage")
	var rigid = CHEST.duplicate()
	rigid.slot = &"head"
	var uncovered: Array[StringName] = []
	rigid.covered_regions = uncovered
	rigid.attachment_bone = &"Head"
	check(model.appearance.equip(rigid),"Rigid accessories use bone attachments")
	check(model.appearance.equipment[&"head"].nodes[0] is BoneAttachment3D,"Rigid equipment has no second skeleton")
	model.appearance.unequip(&"head")
	var before_reset: int = model.skeleton.get_child_count()
	player.reset_for_lab(Transform3D.IDENTITY)
	player.reset_for_lab(Transform3D.IDENTITY)
	model.set_process(false)
	check(model.skeleton.get_child_count() == before_reset,"Repeated reset does not duplicate equipment or sockets")
	for clip in model.animation.get_animation_list():
		var animation: Animation = model.animation.get_animation(clip)
		var walking: bool = clip in ["k_walk", "running/jog", "running/sprint", "crouch/crouch_walk"]
		var low := INF
		var high := -INF
		var finite := true
		var authored_pose := true
		var contacts_cleared := true
		for frame in 13:
			model.skeleton.reset_bone_poses()
			model.animation.play(clip)
			model.animation.seek(animation.length*frame/12.0,true)
			model.animation.advance(0)
			var sampled: Array[Transform3D] = []
			for bone in model.skeleton.get_bone_count(): sampled.append(model.skeleton.get_bone_pose(bone))
			# Walking receives terrain fit. Idle and action clips retain every
			# sampled local transform, including authored foot height and rotation.
			model.finalize_native_pose(1.0/60,player)
			low = minf(low,model.dodge_skin_min_height())
			high = maxf(high,-model.dodge_skin_min_height(Vector3.DOWN))
			for i in model.skeleton.get_bone_count():
				finite = finite and model.skeleton.get_bone_global_pose(i).is_finite()
				if not walking: authored_pose = authored_pose and sampled[i].is_equal_approx(model.skeleton.get_bone_pose(i))
			if not walking:
				contacts_cleared = contacts_cleared and model.locomotion.contacts.is_empty() and model.locomotion.anchors.is_empty() and model.locomotion.transition_targets.is_empty() and is_zero_approx(model.locomotion.pelvis_lowering)
		check(finite,clip+": all sampled bones finite")
		if walking: check(low >= -0.005,clip+": walking floor clearance %.3f" % low)
		else:
			check(authored_pose,clip+": idle/action pose remains identical to the sampled animation")
			check(contacts_cleared,clip+": idle/action releases foot targets and pelvis correction")
		if clip.begins_with("crouch/"): check(high <= 1.4,clip+": crouch capsule fit %.3f" % high)
		if clip == "k_idle": check(high <= 1.8,clip+": standing capsule fit %.3f" % high)
	print("UAL RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
