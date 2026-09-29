extends "res://features/presentation/character_model.gd"
## Legacy Knight/Warden import adapter; retained for existing gameplay and comparison.

# Explicit paths keep exported dependencies independent from animation binding names.
const ACTION_CLIPS := {
	"roll_forward": preload("res://assets/animations/anim_legacy_knight_roll_forward_v01.tres"),
	"roll_left": preload("res://assets/animations/anim_legacy_knight_roll_left_v01.tres"),
	"roll_right": preload("res://assets/animations/anim_legacy_knight_roll_right_v01.tres"),
	"roll_back": preload("res://assets/animations/anim_legacy_knight_roll_back_v01.tres"),
	"jog": preload("res://assets/animations/anim_legacy_knight_jog_v01.tres"),
	"sprint": preload("res://assets/animations/anim_legacy_knight_sprint_v01.tres"),
	"jump_start": preload("res://assets/animations/anim_legacy_knight_jump_start_v01.tres"),
	"jump_air": preload("res://assets/animations/anim_legacy_knight_jump_air_v01.tres"),
	"jump_land": preload("res://assets/animations/anim_legacy_knight_jump_land_v01.tres"),
	"crouch_walk": preload("res://assets/animations/anim_legacy_knight_crouch_walk_v01.tres"),
	"crouch_idle": preload("res://assets/animations/anim_legacy_knight_crouch_idle_v01.tres"),
}

func _ready() -> void:
	skeleton = imported.find_child("Skeleton3D",true,false)
	contact_meshes.assign(skeleton.find_children("*","MeshInstance3D",true,false))
	locomotion.rig = rig
	locomotion.contact_meshes = contact_meshes
	animation = imported.find_child("AnimationPlayer",true,false)
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var rolls := AnimationLibrary.new()
	for clip in ["roll_forward","roll_left","roll_right","roll_back"]:
		rolls.add_animation(clip,ACTION_CLIPS[clip])
	animation.add_animation_library("dodge",rolls)
	var running := AnimationLibrary.new()
	for clip in ["jog","sprint"]: running.add_animation(clip,ACTION_CLIPS[clip])
	animation.add_animation_library("running",running)
	var jumps := AnimationLibrary.new()
	for clip in ["jump_start","jump_air","jump_land"]:
		jumps.add_animation(clip,ACTION_CLIPS[clip])
	animation.add_animation_library("jump",jumps)
	var crouch := AnimationLibrary.new()
	for clip in ["crouch_walk","crouch_idle"]:
		crouch.add_animation(clip,ACTION_CLIPS[clip])
	animation.add_animation_library("crouch",crouch)
	# Loop flags are instance setup, so never edit shared imported clip Resources.
	var source_library := animation.get_animation_library("")
	var local_library := source_library.duplicate() as AnimationLibrary
	for anim in ["k_idle","k_walk"]:
		var clip := source_library.get_animation(anim).duplicate() as Animation
		clip.loop_mode = Animation.LOOP_LINEAR
		local_library.remove_animation(anim)
		local_library.add_animation(anim,clip)
	animation.remove_animation_library("")
	animation.add_animation_library("",local_library)
	PSXStyle.apply(imported,preload("res://assets/third_party/fullplate_knight/knightlowres.png"),Color("9c8575") if boss_variant else Color("b2c0cf"))
	hand_attachment = attachment("Hand.r")
	left_hand_attachment = attachment("Hand.l")
	var source: Node3D = (preload("res://assets/models/cinder_warden.glb") if boss_variant else preload("res://assets/models/azure_knight.glb")).instantiate()
	var blade: Node3D = source.find_child("Sword",true,false).duplicate()
	source.free()
	hand_attachment.add_child(blade)
	blade.position = Vector3(0,0.045,0)
	var hand := skeleton.find_bone("Hand.r")
	blade.basis = skeleton.get_bone_global_rest(hand).basis.inverse()*Basis(Vector3.UP,PI)
	generated_material(blade,preload("res://assets/third_party/psx_dungeon/Textures/TEX_Metal_01.png"),Color("a8aeb5"))
	if boss_variant:
		# Original crown/cape are retained as accents over the third-party armor.
		var original := preload("res://assets/models/cinder_warden.glb").instantiate()
		var head_attachment := attachment("Head")
		var crown := Node3D.new()
		head_attachment.add_child(crown)
		crown.basis = skeleton.get_bone_global_rest(skeleton.find_bone("Head")).basis.inverse()*Basis(Vector3.UP,PI)
		for node in original.find_children("*","Node3D",true,false):
			if str(node.name).begins_with("CrownHorn") or str(node.name)=="CrownCrest":
				var ornament := node.duplicate() as Node3D
				crown.add_child(ornament)
				ornament.position -= Vector3(0,1.56,0)
		var cape := original.find_child("Cape",true,false).duplicate() as Node3D
		add_child(cape)
		generated_material(cape,preload("res://assets/third_party/psx_dungeon/Textures/TEX_Planks_01.png"),Color("542f34"))
		PSXStyle.apply(crown)
		original.free()
	update_pose(0.0)
