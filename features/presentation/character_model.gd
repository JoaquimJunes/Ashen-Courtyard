extends Node3D
## Shared presentation surface. Model adapters own import/material/appearance setup.
## Native profiles select authored poses; remaining adapters are explicit fallbacks.
@export var boss_variant := false
@onready var imported: Node3D = $Imported
@onready var weapon_pivot: Node3D = $WeaponPivot
const Rig = preload("res://features/presentation/character_rig.gd")
const AnimationProfile = preload("res://features/presentation/animation_profile.gd")
const ActionState = preload("res://features/character/character_states.gd").Action
@export var rig: Rig = preload("res://features/presentation/data/knight_rig.tres")
@export var animation_profile: AnimationProfile
## Appearance-review models retain their independent artist-authored layouts.
@export var gameplay_equipment := false
var equipment: RefCounted
var contact_meshes: Array[MeshInstance3D] = []
var skin_contacts = preload("res://features/presentation/skin_contact_cache.gd").new()
var skeleton: Skeleton3D
var animation: AnimationPlayer
var pose_driver: RefCounted
var base_clip := ""
var base_clock := 0.0
var action_exit_rotations: Array[Quaternion] = []
var action_exit_positions: Array[Vector3] = []
var action_exit_clock := 0.0
var casting := false
var dodging := false
var dodge_progress := 0.0
var dodge_clip := "roll_forward"
var dodge_airborne := false
var dodge_blend_duration := 0.08
var dodge_blend_time := 0.0
var dodge_blend_rotations: Array[Quaternion] = []
var dodge_blend_positions: Array[Vector3] = []
var dodge_local_direction := Vector3.FORWARD
var dodge_air_lowering := 0.0
var locomotion = preload("res://features/presentation/knight_locomotion.gd").new()
var gait_speed := 0.0
var base_rotations: Array[Quaternion] = []
var base_positions: Array[Vector3] = []

var hand_attachment: BoneAttachment3D
var left_hand_attachment: BoneAttachment3D

func attachment(bone_name: String) -> BoneAttachment3D:
	var bone := BoneAttachment3D.new()
	bone.bone_name = rig.bone_name(bone_name)
	skeleton.add_child(bone)
	return bone

func rotate_bone(bone_name: String, rotation_in_rig: Basis) -> void:
	var id := rig.bone(skeleton,bone_name)
	var global_rest := skeleton.get_bone_global_rest(id).basis.orthonormalized()
	var local_delta := global_rest.inverse()*rotation_in_rig*global_rest
	skeleton.set_bone_pose_rotation(id,skeleton.get_bone_pose_rotation(id)*local_delta.get_rotation_quaternion())

func begin_ground_roll(local_direction: Vector3, blend_duration: float = 0.08) -> void:
	if absf(local_direction.x) > absf(local_direction.z):
		dodge_clip = "roll_left" if local_direction.x < 0 else "roll_right"
	else:
		dodge_clip = "roll_forward" if local_direction.z <= 0 else "roll_back"
	dodging = true
	dodge_progress = 0.0
	dodge_blend_duration = blend_duration
	dodge_local_direction = local_direction.normalized()
	dodge_airborne = true
	set_dodge_airborne(false)
	# Ground the tucked silhouette relative to the body's feet, so the armor does
	# not float above the floor while blending from the landing into the roll.
	sample_air_pose()
	skeleton.force_update_all_bone_transforms()
	dodge_air_lowering = maxf(0,dodge_skin_min_height()-0.025)
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,dodge_blend_rotations[bone])
		skeleton.set_bone_pose_position(bone,dodge_blend_positions[bone])
	skeleton.force_update_all_bone_transforms()

func dodge_skin_min_height(normal: Vector3 = Vector3.UP) -> float:
	return skin_contacts.minimum(self,contact_meshes[0],skeleton,normal)

func sample_air_pose() -> void:
	var clip := "dodge/"+dodge_clip
	if animation.current_animation != clip: animation.play(clip)
	animation.seek(0.65,true)
	animation.advance(0)
	var body := rig.bone(skeleton,"Body")
	var rest := skeleton.get_bone_rest(body)
	# Imported model faces the opposite local Z direction to gameplay.
	var tilt_axis := Vector3.UP.cross(-dodge_local_direction).normalized()
	skeleton.set_bone_pose_rotation(body,(Basis(tilt_axis,deg_to_rad(20))*rest.basis).get_rotation_quaternion())
	skeleton.set_bone_pose_position(body,rest.origin)

func set_dodge_airborne(value: bool) -> void:
	if value == dodge_airborne: return
	dodge_airborne = value
	dodge_blend_time = 0.0
	dodge_blend_rotations.clear()
	dodge_blend_positions.clear()
	for bone in skeleton.get_bone_count():
		dodge_blend_rotations.append(skeleton.get_bone_pose_rotation(bone))
		dodge_blend_positions.append(skeleton.get_bone_pose_position(bone))

func end_dodge() -> void:
	if dodging: begin_action_exit()
	dodge_air_lowering = 0.0
	dodging = false
	dodge_airborne = false
	dodge_progress = 0.0
	dodge_blend_time = 0.0
	dodge_blend_rotations.clear()
	dodge_blend_positions.clear()

func begin_action_exit() -> void:
	action_exit_rotations.clear()
	action_exit_positions.clear()
	action_exit_clock = 0.0
	for bone in skeleton.get_bone_count():
		action_exit_rotations.append(skeleton.get_bone_pose_rotation(bone))
		action_exit_positions.append(skeleton.get_bone_pose_position(bone))

func clear_action_exit() -> void:
	action_exit_rotations.clear()
	action_exit_positions.clear()
	action_exit_clock = 0.0

func blend_action_exit(delta: float) -> void:
	if action_exit_rotations.is_empty(): return
	action_exit_clock += maxf(delta,0)
	var weight := smoothstep(0,locomotion.tuning.transition_seconds,action_exit_clock)
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,action_exit_rotations[bone].slerp(skeleton.get_bone_pose_rotation(bone),weight))
		skeleton.set_bone_pose_position(bone,action_exit_positions[bone].lerp(skeleton.get_bone_pose_position(bone),weight))
	# Blend arcs can dip below either endpoint. Ease the action's clearance out
	# with its pose; this is not terrain foot placement over an idle animation.
	var lift := maxf(0,0.025-dodge_skin_min_height())*(1.0-weight)
	rig.offset_world(skeleton,rig.bone(skeleton,"Body"),global_basis*Vector3.UP*lift)
	if weight >= 1: clear_action_exit()

func reset_locomotion() -> void:
	locomotion.reset()
	gait_speed = 0
	base_rotations.clear()
	base_positions.clear()

func smooth_base_pose(delta: float) -> void:
	# Filter the sampled gait before ground adaptation, never after foot placement.
	var blend := 1.0 if locomotion.tuning.pose_smoothing <= 0 else 1.0-exp(-delta/locomotion.tuning.pose_smoothing)
	for bone in skeleton.get_bone_count():
		var rotation := skeleton.get_bone_pose_rotation(bone)
		var position := skeleton.get_bone_pose_position(bone)
		if base_rotations.size() <= bone:
			base_rotations.append(rotation)
			base_positions.append(position)
		else:
			base_rotations[bone] = base_rotations[bone].slerp(rotation,blend)
			base_positions[bone] = base_positions[bone].lerp(position,blend)
		skeleton.set_bone_pose_rotation(bone,base_rotations[bone])
		skeleton.set_bone_pose_position(bone,base_positions[bone])

func idle_clip() -> String:
	# Read actual placement: temporary stowing must also leave the armed stance.
	var actor := get_parent() as CharacterBody3D
	var grounded := actor != null and actor.is_on_floor()
	# Godot retains its old floor flag after teleport until the next collision
	# step. The motor clears its result immediately, so a reset in midair cannot
	# seed the next falling pose from a stale grounded sword stance.
	if grounded and actor.get("motor") != null: grounded = actor.motor.last_result.grounded
	var armed := false
	if equipment != null:
		if gameplay_equipment and actor != null and actor.get("items") != null:
			var item: Resource = actor.items.equipment.definition(actor.items.equipment.primary)
			armed = item != null and item.equipment.idle_role == &"sword" and equipment.current_sockets.get(item.visual.id,&"") == item.visual.held_socket
		else: armed = equipment.current_sockets.get(&"sword",&"") == &"right_hand"
	if grounded and animation_profile != null and animation_profile.sword_idle != &"" and armed:
		return String(animation_profile.sword_idle)
	return "k_idle"

func foot_placement_enabled() -> bool:
	var actor := get_parent() as CharacterBody3D
	if actor != null and actor.get("crawling") != null and actor.crawling.active: return false
	if actor != null and actor.get("swimming") != null and actor.swimming.active: return false
	if actor == null or not actor.is_on_floor() or actor.get("state") != ActionState.FREE or dodging or casting: return false
	return animation.assigned_animation in ["k_walk","running/jog","running/sprint","crouch/crouch_walk"]

func update_pose(delta: float) -> void:
	var owner := get_parent()
	if owner.get("state") != ActionState.FREE: clear_action_exit()
	# Clear old walking locks even when an action driver returns before locomotion.
	if not foot_placement_enabled(): locomotion.reset_contacts()
	if dodging:
		reset_locomotion()
		var clip := "dodge/"+dodge_clip
		if animation.current_animation != clip: animation.play(clip)
		# Hold tucked limbs in flight; the somersault clock belongs to floor contact.
		if dodge_airborne:
			sample_air_pose()
			var body := rig.bone(skeleton,"Body")
			rig.offset_world(skeleton,body,global_basis*Vector3.DOWN*dodge_air_lowering)
		else:
			animation.seek(clampf(dodge_progress,0,1),true)
			animation.advance(0)
		dodge_blend_time = minf(dodge_blend_duration,dodge_blend_time+delta)
		var blend := smoothstep(0, maxf(0.0001,dodge_blend_duration),dodge_blend_time)
		if dodge_blend_rotations.size() == skeleton.get_bone_count():
			for bone in skeleton.get_bone_count():
				skeleton.set_bone_pose_rotation(bone,dodge_blend_rotations[bone].slerp(skeleton.get_bone_pose_rotation(bone),blend))
				skeleton.set_bone_pose_position(bone,dodge_blend_positions[bone].lerp(skeleton.get_bone_pose_position(bone),blend))
			if blend < 1.0:
				# Interpolating two clear poses can still sweep a boot through the floor.
				var lift := maxf(0,0.025-dodge_skin_min_height())
				var body := rig.bone(skeleton,"Body")
				rig.offset_world(skeleton,body,global_basis*Vector3.UP*lift)
		skeleton.force_update_all_bone_transforms()
		return
	var actor = get_parent()
	if not boss_variant and actor is CharacterBody3D and actor.get("presentation") != null and actor.presentation.jump.actor != null:
		if actor.presentation.mantle.sample(delta): return
		if actor.presentation.swim.sample(delta): return
		if actor.presentation.crawl.sample(delta): return
		if actor.presentation.crouch.sample(delta): return
		if actor.presentation.jump.sample(delta):
			actor.presentation.mantle.blend_exit(delta)
			actor.presentation.crouch.blend()
			if not actor.presentation.sword_attack.sample(delta,true) and not actor.presentation.spell.sample(delta,true): apply_combat_pose(actor)
			return
	var speed := 0.0
	if actor is CharacterBody3D: speed = Vector2(actor.velocity.x,actor.velocity.z).length()
	var free_running: bool = not boss_variant and actor is CharacterBody3D and actor.get("state") == 0 and not casting
	var resting := idle_clip()
	var desired := "k_walk" if speed > 0.3 else resting
	if free_running and speed > 0.3:
		# Use displacement speed so a blocked character does not run against the wall.
		speed = Vector2(actor.get_real_velocity().x,actor.get_real_velocity().z).length()
		var sprinting: bool = actor.sprinting
		desired = ("running/sprint" if sprinting else "running/jog") if speed > 0.3 else resting
	if free_running and desired == resting and animation.current_animation != desired and foot_placement_enabled():
		# Foot locks end immediately, but blend from the last displayed pose so
		# removing slope correction cannot snap the legs on the first idle frame.
		base_rotations.clear()
		base_positions.clear()
		for bone in skeleton.get_bone_count():
			base_rotations.append(skeleton.get_bone_pose_rotation(bone))
			base_positions.append(skeleton.get_bone_pose_position(bone))
	skeleton.reset_bone_poses()
	if base_clip != desired:
		# A new/reset character has no outgoing pose to blend. AnimationPlayer can
		# retain the last sampled action even after stop(), so seed the first base
		# clip immediately instead of pulling old dive/recovery transforms forward.
		var first_pose := base_clip.is_empty()
		var phase := 0.0
		var preserve_phase := desired.begins_with("running/") and base_clip.begins_with("running/")
		if preserve_phase: phase = base_clock/animation.get_animation(base_clip).length
		if free_running: locomotion.begin_gait_transition(locomotion.tuning.transition_seconds)
		animation.play(desired,locomotion.tuning.transition_seconds if free_running and not first_pose else 0.0)
		base_clip = desired
		base_clock = phase*animation.get_animation(desired).length if preserve_phase else 0.0
		# Preserve the clock without applying an unblended pose ahead of advance().
		if preserve_phase or first_pose: animation.seek(base_clock,false)
	elif animation.current_animation != desired:
		# Action sampling uses the same player, but never owns the base clock.
		# Returning from an action still needs its ordinary exit crossfade.
		animation.play(desired,locomotion.tuning.transition_seconds if free_running else 0.0)
		animation.seek(base_clock,false)
	if free_running:
		gait_speed = lerpf(gait_speed,speed,1.0-exp(-delta/locomotion.tuning.cadence_smoothing))
	var active_clip := animation.get_animation(desired)
	var reference_speed: float = active_clip.get_meta("reference_speed",6.5 if desired == "running/sprint" else 4.0)
	if active_clip.has_meta("reference_speed"): reference_speed *= skeleton.global_basis.get_scale().y
	var playback := clampf((gait_speed if free_running else speed)/maxf(reference_speed,0.01),0.1,1.5)
	if desired == "k_walk": playback = clampf(speed/3.0,0.7,1.7)
	if desired == resting and active_clip.loop_mode == Animation.LOOP_NONE:
		# Sword_Idle is authored cyclically but imports without a loop flag.
		# Advance normally so the outgoing gait's blend clock also progresses.
		# Only wrap at the endpoint, leaving shared source keys/loop flags intact.
		var next_position := animation.current_animation_position+delta
		animation.advance(delta)
		if next_position >= active_clip.length:
			animation.play(desired,0.0)
			animation.seek(fposmod(next_position,active_clip.length),false)
			animation.advance(0)
	else:
		animation.advance(delta if desired == resting else delta*playback)
	base_clock = animation.current_animation_position
	if free_running and delta > 0:
		# AnimationPlayer already blends transitions. Re-filtering every gait sample
		# delays contact timing and flattens the authored knee/ankle articulation.
		if not active_clip.has_meta("plant_l"): smooth_base_pose(delta)
		else:
			base_rotations.clear()
			base_positions.clear()
	elif not free_running:
		reset_locomotion()
	if not boss_variant and actor is CharacterBody3D and actor.get("presentation") != null and actor.presentation.jump.actor != null:
		actor.presentation.jump.blend_exit(delta)
		actor.presentation.mantle.blend_exit(delta)
		actor.presentation.crouch.blend()
	var native_attack := false
	if not boss_variant and actor is CharacterBody3D and actor.get("presentation") != null:
		native_attack = actor.presentation.sword_attack.sample(delta)
		if not native_attack: native_attack = actor.presentation.spell.sample(delta)
	if free_running: blend_action_exit(delta)
	# Walking/running contact correction comes last, after pose blends.
	if free_running and delta > 0:
		locomotion.update(delta,actor,skeleton,locomotion.clip_contacts(active_clip,animation.current_animation_position))
	elif delta > 0 and actor is CharacterBody3D:
		finalize_native_pose(delta,actor)
	if not native_attack: apply_combat_pose(actor)

func finalize_native_pose(delta: float, actor: CharacterBody3D) -> void:
	# Only walking clips may adapt feet to terrain; authored action/idle legs stay intact.
	if not foot_placement_enabled():
		locomotion.reset_contacts()
		return
	if animation_profile == null or not animation_profile.is_native(animation.assigned_animation): return
	var clip := animation.get_animation(animation.assigned_animation)
	locomotion.apply_contacts(delta,actor,skeleton,locomotion.clip_contacts(clip,animation.current_animation_position))

func apply_combat_pose(actor: Node) -> void:
	# Native locomotion keeps its authored arm motion. The old procedural weapon
	# poses remain an explicitly temporary fallback only during committed actions.
	if animation_profile != null and animation_profile.is_native(animation.current_animation) and not casting:
		var state = actor.get("state")
		if state not in [ActionState.LIGHT,ActionState.HEAVY]: return
	# Imported character faces +Z, rotated 180 degrees to match gameplay -Z.
	var swing := weapon_pivot.rotation
	rotate_bone("UpperArm.r",Basis(Vector3.UP,swing.y)*Basis(Vector3.RIGHT,-swing.x)*Basis(Vector3.FORWARD,-swing.z))
	rotate_bone("LowerArm.r",Basis(Vector3.RIGHT,-0.42))
	if casting:
		rotate_bone("UpperArm.l",Basis(Vector3.RIGHT,-1.15))
		rotate_bone("LowerArm.l",Basis(Vector3.RIGHT,-0.35))
	skeleton.force_update_all_bone_transforms()
	if actor is CharacterBody3D and actor.get("casting_light") != null and casting:
		position_cast_light(actor)

func position_cast_light(actor: CharacterBody3D) -> void:
	var hand := rig.bone(skeleton,"Hand.l")
	actor.casting_light.global_position = (skeleton.global_transform*skeleton.get_bone_global_pose(hand)).origin+Vector3(0,0,-0.10)

func _process(delta: float) -> void:
	if pose_driver != null:
		pose_driver.display()
		return
	var actor = get_parent()
	if actor is CharacterBody3D and actor.dead:
		locomotion.reset_contacts()
		return
	update_pose(delta)

func generated_material(node: Node, texture: Texture2D, tint: Color) -> void:
	if node is MeshInstance3D:
		var material := PSXStyle.material(texture,tint).duplicate() as ShaderMaterial
		material.set_shader_parameter("generated_uv",true)
		material.set_shader_parameter("brightness",4.0 if "Metal" in texture.resource_path else 1.0)
		node.material_override = material
	for child in node.get_children(): generated_material(child,texture,tint)
