extends RefCounted
## Reads accepted motor/action state. Rotates bones; never moves the collision body.
const IK = preload("res://features/presentation/limb_ik.gd")
const Pose = preload("res://features/traversal/mantle_pose.gd")
var hang: Pose = preload("res://features/traversal/data/pose_hang.tres")
var lifted: Pose = preload("res://features/traversal/data/pose_lift.tres")
var over: Pose = preload("res://features/traversal/data/pose_over.tres")
var standing: Pose = preload("res://features/traversal/data/pose_stand.tres")
var shimmy := preload("res://features/traversal/shimmy_presentation.gd").new()
var native := preload("res://features/traversal/native_mantle_presentation.gd").new()
var actor: CharacterBody3D
var skeleton: Skeleton3D
var idle: Array = []
var entry: Array = []
var idle_model: Array[Transform3D] = []
var bones: Dictionary = {}
var candidate: RefCounted
var active := false
var exit_pose: Array = []
var exit_time := 0.0
var weapon: Node3D
var weapon_parent: Node3D
var weapon_home := Transform3D.IDENTITY
var back: BoneAttachment3D
var equipment: RefCounted
const TRAVERSAL_HANDS := &"traversal"

func configure(character: CharacterBody3D) -> void:
	actor = character
	native.configure(character)
	skeleton = actor.model.skeleton
	standing = standing.duplicate()
	standing.pelvis.y = actor.model.rig.standing_height
	bones = actor.model.rig.indices(skeleton)
	equipment = actor.model.get("equipment")
	if equipment == null:
		weapon_parent = actor.model.hand_attachment
		weapon = weapon_parent.get_child(0)
		weapon_home = weapon.transform
		back = actor.model.attachment("Back")

func snapshot() -> Array:
	var poses: Array = []
	for i in skeleton.get_bone_count(): poses.append([skeleton.get_bone_pose_rotation(i),skeleton.get_bone_pose_position(i)])
	return poses

func apply(poses: Array) -> void:
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i,poses[i][0])
		skeleton.set_bone_pose_position(i,poses[i][1])
	skeleton.force_update_all_bone_transforms()

func begin(value: RefCounted) -> void:
	candidate = value
	native.reset()
	shimmy.reset()
	entry = snapshot()
	exit_pose.clear()
	actor.model.reset_locomotion()
	actor.model.animation.play("k_idle")
	actor.model.animation.seek(0,true)
	actor.model.animation.advance(0)
	idle = snapshot()
	idle_model.clear()
	for i in skeleton.get_bone_count():
		idle_model.append(actor.model.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(i))
	apply(entry)
	if equipment != null: equipment.request_hand_release(TRAVERSAL_HANDS)
	else: weapon.reparent(back,true)
	active = true

func blend(poses: Array, weight: float) -> void:
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i,poses[i][0].slerp(skeleton.get_bone_pose_rotation(i),weight))
		skeleton.set_bone_pose_position(i,poses[i][1].lerp(skeleton.get_bone_pose_position(i),weight))
	skeleton.force_update_all_bone_transforms()

func sample(delta: float) -> bool:
	if not active: return false
	var runtime: RefCounted = actor.traversal
	shimmy.update(candidate,runtime,delta)
	var from := hang
	var to := hang
	var u := 0.0
	var hand_release := 0.0
	if runtime.status == &"mantle":
		var action: RefCounted = runtime.mantle
		u = smoothstep(0,1,action.progress())
		match action.phase:
			action.Phase.LIFT: to = lifted
			action.Phase.OVER:
				from = lifted; to = over
				hand_release = smoothstep(0.15,0.7,u)
			action.Phase.STAND:
				from = over; to = standing
				hand_release = 1
			_:
				from = standing; to = standing
				hand_release = 1
	if runtime.status == &"mantle" and native.sample(runtime.mantle,idle):
		constrain_native(hand_release)
		return true
	apply(idle)
	var model_transform: Transform3D = actor.model.global_transform
	var pelvis: Vector3 = from.pelvis.lerp(to.pelvis,u)+actor.model.rig.traversal_offset*(1.0-hand_release)
	if runtime.status == &"hang": pelvis.y += shimmy.sway
	var tilt := Basis(Vector3.RIGHT,deg_to_rad(lerpf(from.pitch,to.pitch,u)))
	var body: int = bones["Body"]
	var body_world := Transform3D(model_transform.basis*tilt*idle_model[body].basis,model_transform*pelvis)
	var local := preload("res://features/presentation/character_rig.gd").parent_world(skeleton,body).affine_inverse()*body_world
	skeleton.set_bone_pose_position(body,local.origin)
	skeleton.set_bone_pose_rotation(body,local.basis.orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
	for side in ["l","r"]:
		var sign_value := -1.0 if side == "l" else 1.0
		var foot: Vector3 = from.left_foot.lerp(to.left_foot,u) if side == "l" else from.right_foot.lerp(to.right_foot,u)
		foot += actor.model.rig.traversal_offset*(1.0-hand_release)
		var hand: Vector3 = shimmy.hands[0 if side == "l" else 1]
		hand += (shimmy.normals[0 if side == "l" else 1]*actor.model.rig.grip_offset.x+Vector3.UP*actor.model.rig.grip_offset.y)*(1.0-hand_release)
		var resting := model_transform*Vector3(sign_value*0.28,pelvis.y-0.05,-0.03)
		hand = hand.lerp(resting,hand_release)
		IK.solve(skeleton,bones["UpperArm."+side],bones["LowerArm."+side],bones["Hand."+side],hand,model_transform.basis*Vector3(sign_value,0,0.3))
		IK.solve(skeleton,bones["UpperLeg."+side],bones["LowerLeg."+side],bones["Foot."+side],model_transform*foot,model_transform.basis*Vector3(sign_value*lerpf(from.knees_out,to.knees_out,u),lerpf(from.knee_up,to.knee_up,u),lerpf(from.knee_forward,to.knee_forward,u)))
		IK.set_world_basis(skeleton,bones["Foot."+side],model_transform.basis*idle_model[bones["Foot."+side]].basis)
		var grip_normal: Vector3 = shimmy.normals[0 if side == "l" else 1]
		var hand_basis := Basis(Vector3.UP,candidate.normal.signed_angle_to(grip_normal,Vector3.UP)*(1-hand_release))*model_transform.basis
		IK.set_world_basis(skeleton,bones["Hand."+side],hand_basis*Basis(Vector3.RIGHT,PI/2*(1-hand_release))*idle_model[bones["Hand."+side]].basis)
	if runtime.status == &"grab": blend(entry,smoothstep(0,runtime.grab_definition.active_seconds,actor.actions.timer))
	elif runtime.status == &"mantle" and runtime.mantle.phase == runtime.mantle.Phase.STAND and u > 0.8:
		var current := snapshot()
		apply(idle)
		blend(current,smoothstep(0.8,1,u))
	if equipment == null:
		var body_at := skeleton.global_transform*skeleton.get_bone_global_pose(body)
		var back_at := Transform3D(body_at.basis*idle_model[body].basis.inverse()*Basis(Vector3.FORWARD,0.4)*Basis(Vector3.RIGHT,PI/2),body_at.origin+model_transform.basis*Vector3(0.14,0.2,0.20))
		weapon.global_transform = weapon.global_transform.interpolate_with(back_at,1.0-exp(-26.0*delta) if runtime.status == &"grab" else 1.0)
	return true

func constrain_native(hand_release: float) -> void:
	# Keep the authored pelvis and leg articulation. The procedural hang/lift
	# pelvis offsets belong to the legacy pose and collapse the native knee lift.
	var model_transform: Transform3D = actor.model.global_transform
	var body: int = bones["Body"]
	var fitting: Vector3 = model_transform.basis*actor.model.rig.traversal_offset+candidate.normal*actor.model.rig.grip_offset.x
	preload("res://features/presentation/character_rig.gd").offset_world(skeleton,body,fitting*native.entry_weight*(1-hand_release))
	var contact_offset := Vector3.ZERO
	# Align the whole pose to the accepted hand anchors. Prefer vertical reach
	# correction so it cannot pull the native feet through the wall face.
	for iteration in 4:
		var correction := Vector3.ZERO
		for side in ["l","r"]:
			var index := 0 if side == "l" else 1
			var shoulder := IK.position(skeleton,bones["UpperArm."+side])
			var elbow := IK.position(skeleton,bones["LowerArm."+side])
			var wrist := IK.position(skeleton,bones["Hand."+side])
			var target: Vector3 = shimmy.hands[index]+shimmy.normals[index]*actor.model.rig.grip_offset.x+Vector3.UP*actor.model.rig.grip_offset.y
			var reach := shoulder.distance_to(elbow)+elbow.distance_to(wrist)-0.005
			var offset := target-shoulder
			var horizontal := Vector2(offset.x,offset.z).length()
			if horizontal < reach:
				var vertical := sqrt(maxf(0,reach*reach-horizontal*horizontal))
				correction.y += signf(offset.y)*maxf(0,absf(offset.y)-vertical)
			else:
				correction += offset.normalized()*maxf(0,offset.length()-reach)
		correction *= 0.5
		contact_offset += correction
		preload("res://features/presentation/character_rig.gd").offset_world(skeleton,body,correction)
		skeleton.force_update_all_bone_transforms()
	# Weight the converged correction once. Weighting every solve iteration
	# would keep pulling the body down while the hands are already releasing.
	preload("res://features/presentation/character_rig.gd").offset_world(skeleton,body,-contact_offset*hand_release)
	skeleton.force_update_all_bone_transforms()
	for side in ["l","r"]:
		var sign_value := -1.0 if side == "l" else 1.0
		var index := 0 if side == "l" else 1
		var target: Vector3 = shimmy.hands[index]+shimmy.normals[index]*actor.model.rig.grip_offset.x+Vector3.UP*actor.model.rig.grip_offset.y
		var hand_basis := Basis(Vector3.UP,candidate.normal.signed_angle_to(shimmy.normals[index],Vector3.UP))*model_transform.basis*Basis(Vector3.RIGHT,PI/2)*idle_model[bones["Hand."+side]].basis
		native.constrain_hand(skeleton,bones["UpperArm."+side],bones["LowerArm."+side],bones["Hand."+side],target,model_transform.basis*Vector3(sign_value,0,0.3),hand_basis,1-hand_release,candidate.lip,candidate.normal)
	# The pull-up owns its leg motion. Terrain and ledge foot solvers must not
	# replace its knee lift or rotate feet toward a surface during this action.

func finish() -> void:
	if not active: return
	if not skeleton.is_inside_tree():
		reset()
		return
	exit_pose = snapshot()
	exit_time = 0
	active = false
	native.reset()
	candidate = null
	if equipment != null: equipment.release_hand_release(TRAVERSAL_HANDS)
	else: weapon.reparent(weapon_parent,true)

func blend_exit(delta: float) -> void:
	if exit_pose.is_empty(): return
	if actor.motor.tucked:
		apply(exit_pose)
		return
	exit_time += delta
	blend(exit_pose,smoothstep(0,0.12,exit_time))
	if equipment == null: weapon.transform = weapon.transform.interpolate_with(weapon_home,smoothstep(0,0.12,exit_time))
	if exit_time >= 0.12:
		exit_pose.clear()
		if equipment == null: weapon.transform = weapon_home

func reset() -> void:
	shimmy.reset()
	native.reset()
	active = false
	candidate = null
	exit_pose.clear()
	entry.clear()
	idle.clear()
	idle_model.clear()
	if equipment != null: equipment.release_hand_release(TRAVERSAL_HANDS)
	elif is_instance_valid(weapon) and is_instance_valid(weapon_parent):
		if weapon.get_parent() != weapon_parent: weapon.reparent(weapon_parent,false)
		weapon.transform = weapon_home
