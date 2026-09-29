extends RefCounted
const State = preload("res://features/character/character_states.gd").Action
var actor: CharacterBody3D
var dive = preload("res://features/presentation/dive_presentation.gd").new()
var jump = preload("res://features/presentation/jump_presentation.gd").new()
var get_up = preload("res://features/presentation/get_up_presentation.gd").new()
var mantle = preload("res://features/traversal/mantle_presentation.gd").new()
var crouch = preload("res://features/presentation/crouch_presentation.gd").new()
var crawl = preload("res://features/crawling/crawl_presentation.gd").new()
var swim = preload("res://features/swimming/swim_presentation.gd").new()
var equipment_bridge = preload("res://features/presentation/equipment_action_bridge.gd").new()
var sword_attack = preload("res://features/presentation/sword_attack_presentation.gd").new()
var spell = preload("res://features/presentation/spell_presentation.gd").new()
func configure(character: CharacterBody3D) -> void:
	actor = character
	equipment_bridge.configure(character)
	sword_attack.configure(character)
	spell.configure(character)
	jump.configure(character)
	get_up.configure(character)
	mantle.configure(character)
	crouch.configure(character)
	crawl.configure(character)
	swim.configure(character)

func begin_ground_roll(local_direction: Vector3, blend_duration: float) -> void:
	actor.model.begin_ground_roll(local_direction,blend_duration)

func capture_pose() -> Array:
	var skeleton: Skeleton3D = actor.model.skeleton
	var pose: Array = []
	for bone in skeleton.get_bone_count():
		pose.append([skeleton.get_bone_pose_rotation(bone),skeleton.get_bone_pose_position(bone)])
	return pose

func blend_ground_roll_from(pose: Array) -> void:
	# Releasing a manually sampled dive stops its AnimationPlayer, which can reset
	# the skeleton. Restore the contact pose before the new roll captures its blend.
	restore_pose(pose)
	actor.model.dodge_airborne = true
	actor.model.set_dodge_airborne(false)

func restore_pose(pose: Array) -> void:
	var skeleton: Skeleton3D = actor.model.skeleton
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,pose[bone][0])
		skeleton.set_bone_pose_position(bone,pose[bone][1])
	skeleton.force_update_all_bone_transforms()

func camera_anchor(height: float) -> Vector3:
	var anchor: Vector3 = actor.global_position+Vector3.UP*height
	# A saved high camera pivot must not begin its collision sweep inside a roof.
	# Keep room for the shoulder probe while crouched, without rewriting preferences.
	var lowered: float = minf(height-actor.posture.definition.camera_lowering,actor.posture.definition.crouch_height-0.3)
	anchor.y = actor.global_position.y+lerpf(height,lowered,crouch.camera_weight)
	if actor.crawling.active: anchor.y = actor.global_position.y+0.5
	if actor.reactions != null and actor.reactions.active:
		# The capsule's logical feet may lie below the floor while the torso is
		# prone. Keep the camera pivot above nearby geometry without moving the actor.
		var floor: Dictionary = actor.motor.floor_probe(anchor+Vector3.UP,anchor-Vector3.UP)
		if not floor.is_empty(): anchor.y = maxf(anchor.y,floor.position.y+0.4)
	return anchor

func prepare() -> void:
	equipment_bridge.refresh()
	actor.casting_light.visible = actor.state == State.CAST or actor.state == State.HEAL
	actor.model.casting = actor.casting_light.visible
	actor.model.dodging = actor.state == State.DODGE
	if actor.casting_light.visible:
		actor.casting_light.scale = Vector3.ONE*(0.5+minf(actor.timer,1.0))
		var color := Color("edc474") if actor.state == State.HEAL else (Color("72dfe5") if actor.cast_spell == 0 else Color("bc99ef"))
		if actor.actions.active_item != null: color = actor.actions.active_item.presentation.color
		actor.casting_light.material_override.albedo_color = color
		actor.casting_light.material_override.emission = color
	actor.sword.rotation = Vector3.ZERO
	if not actor.swimming.active:
		actor.model.rotation.x = 0
		actor.model.rotation.z = 0
	match actor.state:
		State.LIGHT, State.HEAVY:
			var definition: Resource = actor.actions.active_definition
			var swing := clampf((actor.timer-definition.windup)/maxf(0.0001,definition.active_seconds),0,1)
			actor.sword.rotation.y = lerpf(-1.4,1.4,swing)*(-1 if actor.combo == 1 else 1)
		State.CAST: actor.sword.rotation.z = -1.2
		State.HEAL: actor.sword.rotation.z = -2.0
		State.HURT:
			if not actor.crawling.active: actor.model.rotation.z = 0.15
