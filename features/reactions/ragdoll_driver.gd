extends RefCounted
## Owns physical bones and pose handover. Only CharacterMotor moves the actor.
const Bone = preload("res://features/reactions/ragdoll_bone.gd")
var actor: CharacterBody3D
var model: Node3D
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var bones: Array[PhysicalBone3D] = []
var joint_parents: Array[PhysicalBone3D] = []
var joint_reference_bases: Array[Basis] = []
var joint_constraints: Array[Dictionary] = []
var by_bone: Dictionary = {}
var collision_exclusions: Array[RID] = []
var torso: PhysicalBone3D
var saved_model_transform: Transform3D
var active := false

func configure(character: CharacterBody3D, settings: Resource) -> void:
	actor = character
	collision_exclusions.append(actor.get_rid())
	model = actor.model
	skeleton = model.skeleton
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "RagdollSimulator"
	skeleton.add_child(simulator)
	for part: Resource in settings.parts:
		var bone_name: String = part.bone_name
		var bone: PhysicalBone3D = Bone.new()
		bone.name = "Physical_"+bone_name.replace(".","_")
		bone.receiver = actor
		var index := skeleton.find_bone(bone_name)
		var length: float = part.length
		bone.body_offset = Transform3D(Basis.IDENTITY,Vector3(0,length*0.5,0))
		bone.joint_offset = bone.body_offset.affine_inverse()
		bone.mass = part.mass
		bone.gravity_scale = actor.tuning.gravity/float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))
		bone.angular_damp = settings.angular_damping
		bone.linear_damp = 0.1
		bone.friction = 0.9
		bone.collision_layer = 0
		bone.collision_mask = 0
		var collision := CollisionShape3D.new()
		if part.box_size != Vector3.ZERO:
			var shape := BoxShape3D.new()
			shape.size = part.box_size
			collision.shape = shape
		else:
			var shape := CapsuleShape3D.new()
			shape.radius = part.radius
			shape.height = length
			collision.shape = shape
		bone.add_child(collision)
		simulator.add_child(bone)
		bone.set("bone_name",bone_name)
		if bone_name == settings.anchor_bone: torso = bone
		elif part.joint_type == PhysicalBone3D.JOINT_TYPE_HINGE:
			var hinge_axis: Vector3 = part.hinge_axis
			var local_axis := skeleton.get_bone_global_rest(index).basis.inverse()*hinge_axis
			bone.joint_rotation = Basis(Quaternion(Vector3.BACK,local_axis.normalized())).get_euler()
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			bone.set("joint_constraints/angular_limit_enabled",true)
			bone.set("joint_constraints/angular_limit_lower",part.angular_lower)
			bone.set("joint_constraints/angular_limit_upper",part.angular_upper)
		elif part.joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
			bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			bone.set("joint_constraints/swing_span",part.swing_span)
			bone.set("joint_constraints/twist_span",part.twist_span)
		PhysicsServer3D.body_set_max_contacts_reported(bone.get_rid(),4)
		PhysicsServer3D.body_set_enable_continuous_collision_detection(bone.get_rid(),true)
		bones.append(bone)
		collision_exclusions.append(bone.get_rid())
		by_bone[index] = bone
	for bone in bones:
		var parent := skeleton.get_bone_parent(bone.get_bone_id())
		while parent >= 0 and not by_bone.has(parent):
			parent = skeleton.get_bone_parent(parent)
		var upper: PhysicalBone3D = by_bone.get(parent)
		joint_parents.append(upper)
		joint_reference_bases.append((upper.global_transform.affine_inverse()*bone.global_transform*bone.joint_offset).basis.orthonormalized() if upper != null else Basis.IDENTITY)
		var constraints := {}
		for property in bone.get_property_list():
			if str(property.name).begins_with("joint_constraints/"):
				constraints[property.name] = bone.get(property.name)
		joint_constraints.append(constraints)
	simulator.physical_bones_stop_simulation()
	simulator.active = false

func start(velocity: Vector3, settings: Resource) -> void:
	active = true
	saved_model_transform = model.transform
	model.reset_locomotion()
	model.set_process(false)
	model.animation.stop(true)
	var world_transform := model.global_transform
	model.top_level = true
	model.global_transform = world_transform
	skeleton.force_update_all_bone_transforms()
	for bone in bones:
		bone.collision_layer = actor.motor.controlled_layer
		bone.collision_mask = 1
		bone.floor_contact = false
	simulator.active = true
	simulator.physical_bones_start_simulation()
	rebind_joints()
	for bone in bones:
		bone.linear_velocity = velocity
		bone.angular_velocity = actor.global_basis.x*settings.tumble_speed

func rebind_joints() -> void:
	# Starting simulation moves every body to the incoming animation pose, but
	# Godot retains the parent-relative joint frames built during configuration.
	# Rebuild them now, before the first physics step, so skipped spine/clavicle
	# bones cannot leave separated anchors that inject corrective impulse.
	for index in bones.size():
		var bone := bones[index]
		var kind := bone.joint_type
		if kind == PhysicalBone3D.JOINT_TYPE_NONE: continue
		var upper := joint_parents[index]
		var incoming := bone.global_transform
		var anchor := incoming*bone.joint_offset
		# Preserve the authored angular reference instead of making every entry
		# pose the new neutral hinge/cone orientation. Only its anchor is rebound.
		var reference := upper.global_basis*joint_reference_bases[index]*bone.joint_offset.basis.inverse()
		bone.global_transform = Transform3D(reference,anchor.origin-reference*bone.joint_offset.origin)
		# Assigning the existing type does not rebuild its native joint. Preserve
		# every configured constraint because changing type resets native defaults.
		# Cache once to avoid accumulating degree/radian round-trip error on reuse.
		bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		bone.joint_type = kind
		for property in joint_constraints[index]: bone.set(property,joint_constraints[index][property])
		bone.global_transform = incoming

func contact() -> bool:
	for bone in bones:
		if bone.floor_contact: return true
	return false

func anchor() -> Vector3:
	return torso.global_position

func settled(settings: Resource) -> bool:
	return contact() and torso.linear_velocity.length() < settings.settle_speed and torso.angular_velocity.length() < settings.settle_angular_speed

func capture_physical_pose() -> Array[Transform3D]:
	# Read the modifier's physical result before stopping it. Retain the current
	# world pose as the actor is placed at a validated standing location.
	var world_poses: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		if by_bone.has(index):
			var bone: PhysicalBone3D = by_bone[index]
			world_poses.append(bone.global_transform*bone.body_offset.affine_inverse())
		else:
			var local := Transform3D(Basis(skeleton.get_bone_pose_rotation(index)),skeleton.get_bone_pose_position(index))
			var parent := skeleton.get_bone_parent(index)
			world_poses.append(world_poses[parent]*local if parent >= 0 else skeleton.global_transform*local)
	return world_poses

func restore_visual_parent() -> void:
	model.top_level = false
	model.transform = saved_model_transform

func stop_simulation() -> void:
	simulator.physical_bones_stop_simulation()
	simulator.active = false
	for bone in bones:
		bone.collision_layer = 0
		bone.collision_mask = 0
		bone.linear_velocity = Vector3.ZERO
		bone.angular_velocity = Vector3.ZERO
		bone.floor_contact = false

func reset() -> void:
	if not active: return
	stop_simulation()
	model.top_level = false
	model.transform = saved_model_transform
	model.animation.stop()
	model.reset_locomotion()
	model.set_process(true)
	active = false
