extends "res://features/presentation/character_model.gd"
## UAL-specific setup, retaining the presentation surface consumed by the player.
const AppearanceDefinition = preload("res://features/presentation/appearance_definition.gd")
const LoadoutDefinition = preload("res://features/presentation/equipment_loadout_definition.gd")
var appearance = preload("res://features/presentation/character_appearance.gd").new()
@export var body_appearance: AppearanceDefinition = preload("res://assets/models/ual/mannequin_body.res")
@export var equipment_loadout: LoadoutDefinition

func _ready() -> void:
	imported.scale = Vector3.ONE*rig.visual_scale
	imported.rotation.y = rig.visual_yaw
	skeleton = imported.find_child("Skeleton3D",true,false)
	animation = imported.find_child("AnimationPlayer",true,false)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if animation_profile == null or not animation_profile.install(animation,rig):
		push_error("UAL animation profile: "+(animation_profile.last_error if animation_profile != null else "missing profile"))
		return
	for node in skeleton.find_children("*","MeshInstance3D",true,false): node.free()
	appearance.configure(skeleton,rig.identifier)
	appearance.body_changed.connect(on_body_changed)
	if not appearance.set_body(body_appearance):
		push_error(appearance.last_error)
		return
	locomotion.rig = rig
	hand_attachment = attachment("Hand.r")
	left_hand_attachment = attachment("Hand.l")
	equipment = preload("res://features/presentation/equipment_visual_controller.gd").new()
	var layouts: Dictionary = equipment_loadout.layouts if equipment_loadout != null else {&"all_stowed": []}
	var items: Array = equipment_loadout.items if equipment_loadout != null else []
	var initial: StringName = equipment_loadout.initial_layout if equipment_loadout != null else &"all_stowed"
	if not equipment.configure(skeleton,rig.socket_definitions,layouts) or not equipment.set_loadout(items) or not equipment.set_layout(initial):
		push_error("UAL equipment: "+equipment.last_error)
		return
	update_pose(0)

func on_body_changed() -> void:
	contact_meshes.assign([appearance.contact])
	skin_contacts.configure(contact_meshes[0],skeleton)
	locomotion.contact_meshes = contact_meshes
	locomotion.sole_points.clear()
	reset_locomotion()

func sample_air_pose() -> void:
	animation.play("dodge/"+dodge_clip)
	animation.seek(0.65,true)
	animation.advance(0)
	var body: int = rig.bone(skeleton,"Body")
	var pose := skeleton.global_transform*skeleton.get_bone_global_pose(body)
	var axis := Vector3.UP.cross(-dodge_local_direction).normalized()
	pose.basis = skeleton.global_basis*Basis(axis,deg_to_rad(20))*skeleton.get_bone_global_rest(body).basis
	rig.set_world_pose(skeleton,body,pose)
