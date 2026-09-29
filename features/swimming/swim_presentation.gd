extends RefCounted
## One physics-owned pose supplies both the requested capsule and visible body.
## The motor accepts a swept transform; presentation follows that accepted frame.
var actor: CharacterBody3D
var was_swimming := false
var blend_time := 0.0
var from_pose: Array = []
var pitch := 0.0
var prone_weight := 0.0
var surface_lift := 0.0
var sampled_frame := -1
var pose_ticks := 0
var requested_capsule := Transform3D.IDENTITY
var requested_model := Transform3D.IDENTITY

func configure(character: CharacterBody3D) -> void: actor = character

func sample(_delta: float) -> bool:
	# Render and collision queries may read the pose, never advance water animation.
	if actor.swimming.active and not actor.dead and actor.movement.attachment == null: return true
	if was_swimming: reset()
	return false

func prepare(delta: float) -> Transform3D:
	if sampled_frame == Engine.get_physics_frames(): return requested_capsule
	var started := Time.get_ticks_usec()
	sampled_frame = Engine.get_physics_frames()
	pose_ticks += 1
	var swim: RefCounted = actor.swimming
	var model: Node3D = actor.model
	var skeleton: Skeleton3D = model.skeleton
	var animation: AnimationPlayer = model.animation
	if not was_swimming:
		from_pose = actor.presentation.capture_pose()
		blend_time = 0
		was_swimming = true
	model.reset_locomotion()
	model.transform = Transform3D.IDENTITY
	var moving: bool = swim.direction != Vector3.ZERO
	prone_weight = move_toward(prone_weight,1.0 if moving else 0.0,delta/swim.definition.blend_seconds)
	var native := animation.has_animation("swimming/swim_idle")
	var clip := ("swimming/swim_forward" if moving else "swimming/swim_idle") if native else "k_idle"
	if animation.current_animation != clip: animation.play(clip,swim.definition.blend_seconds)
	animation.advance(delta*(1.35 if swim.fast else 1.0))
	blend_time += delta
	var weight := smoothstep(0,swim.definition.blend_seconds,blend_time)
	if weight < 1 and from_pose.size() == skeleton.get_bone_count():
		for bone in from_pose.size():
			skeleton.set_bone_pose_rotation(bone,from_pose[bone][0].slerp(skeleton.get_bone_pose_rotation(bone),weight))
			skeleton.set_bone_pose_position(bone,from_pose[bone][1].lerp(skeleton.get_bone_pose_position(bone),weight))
	var wanted: float = asin(clampf(swim.heading.y,-1,1)) if swim.underwater and moving else 0.0
	pitch = lerpf(pitch,wanted,1.0-exp(-8.0*delta))
	skeleton.force_update_all_bone_transforms()
	var head: int = model.rig.bone(skeleton,"Head")
	var pelvis: int = model.rig.bone(skeleton,"Body")
	# Authored UAL swim clips use a waterline origin. The legacy standing clip
	# needs a torso pivot instead. Neither adapter edits the imported keyframes.
	var origin: Vector3 = swim.definition.upright_origin.lerp(swim.definition.prone_origin,prone_weight)*weight if native else Vector3.ZERO
	var pivot: Vector3 = actor.global_transform.affine_inverse()*(skeleton.global_transform*skeleton.get_bone_global_pose(pelvis)).origin
	var rotation := Basis(Vector3.RIGHT,pitch-(PI*0.5*prone_weight if not native else 0.0))
	model.transform = Transform3D(rotation,origin+pivot-rotation*pivot+Vector3.UP*surface_lift)
	skeleton.force_update_all_bone_transforms()
	if not swim.underwater:
		var mouth: Vector3 = actor.global_transform.affine_inverse()*(skeleton.global_transform*skeleton.get_bone_global_pose(head)*model.rig.hitbox_profile.breathing_offset)
		var adjustment: float = (swim.definition.head_offset-mouth.y)*weight
		surface_lift += adjustment
		model.position.y += adjustment
	# The capsule's long axis and center come from this completed torso/head pose,
	# including pitch and entry/idle blends. No independent "direction" collider.
	var to_actor: Transform3D = actor.global_transform.affine_inverse()*skeleton.global_transform
	var head_point: Vector3 = (to_actor*skeleton.get_bone_global_pose(head)).origin
	var body_point: Vector3 = (to_actor*skeleton.get_bone_global_pose(pelvis)).origin
	var axis := (head_point-body_point).normalized()
	var basis := Basis(Quaternion(Vector3.UP,axis))
	var center: Vector3 = head_point-axis*(swim.definition.collider_height*0.5-actor.motor.capsule.radius*0.65)
	requested_capsule = Transform3D(basis,center)
	requested_model = model.transform
	if model.pose_driver != null: model.pose_driver.external_microseconds += Time.get_ticks_usec()-started
	return requested_capsule

func accept() -> void:
	# A blocked change keeps the last clear capsule. Map the requested body frame
	# onto that accepted frame, so an idle/turn transition cannot stand into a roof.
	actor.model.transform = actor.motor.shape_node.transform*requested_capsule.affine_inverse()*requested_model
	actor.model.skeleton.force_update_all_bone_transforms()

func reset() -> void:
	if was_swimming and is_instance_valid(actor.model):
		actor.model.transform = Transform3D.IDENTITY
		actor.model.reset_locomotion()
		actor.model.animation.stop()
	was_swimming = false
	blend_time = 0
	from_pose.clear()
	pitch = 0
	prone_weight = 0
	surface_lift = 0
	sampled_frame = -1
	requested_capsule = Transform3D.IDENTITY
	requested_model = Transform3D.IDENTITY
