extends RefCounted
## Shared pose sampler for the isolated preview and optional laboratory trial.
const SKIN_CLEARANCE := 0.025
var model: Node3D
var skeleton: Skeleton3D
var root_bone: int
var idle: Array = []
var dive: Array = []
var contact: Array = []
var lean: Array = []
var launch: Array = []
var extension_duration := 0.12
var parent_frame := Transform3D.IDENTITY
var feet: Dictionary = {}
var foot_bases: Dictionary = {}

func setup(knight: Node3D, from_current_pose: bool = false) -> void:
 model = knight
 model.set_process(false)
 skeleton = model.skeleton
 root_bone = model.rig.bone(skeleton,"Body")
 if not from_current_pose: sample(0.0)
 # Capture a supported action baseline even when the incoming idle has no
 # terrain correction. Shift the whole pose before saving its ankle targets;
 # otherwise planting them later undoes this action's armor clearance.
 var clearance: float = maxf(0.0,SKIN_CLEARANCE-model.dodge_skin_min_height())
 model.rig.offset_world(skeleton,root_bone,model.global_basis*Vector3.UP*clearance)
 skeleton.force_update_all_bone_transforms()
 idle = snapshot()
 var parent := skeleton.get_bone_parent(root_bone)
 parent_frame = skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
 for side in ["l", "r"]:
  var foot: int = model.rig.bone(skeleton,"Foot."+side)
  feet[side] = model.locomotion.world_position(skeleton,foot)
  foot_bases[side] = skeleton.global_basis*skeleton.get_bone_global_pose(foot).basis
 # Bend the knees with feet supporting the body, then tip the chest forward.
 skeleton.set_bone_pose_rotation(root_bone,(parent_frame.basis.inverse()*Basis(Vector3.RIGHT,deg_to_rad(35))*parent_frame.basis*Basis(idle[root_bone][0])).get_rotation_quaternion())
 skeleton.set_bone_pose_position(root_bone,idle[root_bone][1]+parent_frame.basis.inverse()*Vector3(0,-0.18,0.22))
 plant_feet()
 lean = snapshot()
 launch = lean.duplicate(true)
 sample(0.24)
 contact = snapshot()
 sample(0.20)
 dive = snapshot()
 sample(0.25)
 var extended: Array = snapshot()
 for i in skeleton.get_bone_count():
  if i in [model.rig.bone(skeleton,"UpperLeg.l"),model.rig.bone(skeleton,"LowerLeg.l"),model.rig.bone(skeleton,"Foot.l"),model.rig.bone(skeleton,"UpperLeg.r"),model.rig.bone(skeleton,"LowerLeg.r"),model.rig.bone(skeleton,"Foot.r")]:
   dive[i] = extended[i]
 for target in [dive,contact]:
  var at: Vector3 = parent_frame*target[root_bone][1]
  var origin: Vector3 = parent_frame*idle[root_bone][1]
  at.x = origin.x
  at.z = origin.z
  target[root_bone][1] = parent_frame.affine_inverse()*at

func plant_feet() -> void:
 skeleton.force_update_all_bone_transforms()
 # Different rigs have different leg lengths. Lower the visual pelvis enough
 # to keep both captured ankle targets reachable during the forward lean.
 var lowering := 0.0
 for side in ["l", "r"]:
  var hip: Vector3 = model.locomotion.world_position(skeleton,model.rig.bone(skeleton,"UpperLeg."+side))
  var knee: Vector3 = model.locomotion.world_position(skeleton,model.rig.bone(skeleton,"LowerLeg."+side))
  var ankle: Vector3 = model.locomotion.world_position(skeleton,model.rig.bone(skeleton,"Foot."+side))
  var reach := hip.distance_to(knee)+knee.distance_to(ankle)-0.015
  var to_target: Vector3 = hip-feet[side]
  var horizontal_squared := Vector2(to_target.x,to_target.z).length_squared()
  if horizontal_squared < reach*reach:
   lowering = maxf(lowering,to_target.y-sqrt(reach*reach-horizontal_squared))
 if lowering > 0:
  model.rig.offset_world(skeleton,root_bone,Vector3.DOWN*lowering)
  skeleton.force_update_all_bone_transforms()
 for side in ["l", "r"]:
  model.locomotion.solve_leg(skeleton,side,feet[side],-model.global_basis.z,true)
  var foot: int = model.rig.bone(skeleton,"Foot."+side)
  var current := skeleton.global_basis*skeleton.get_bone_global_pose(foot).basis
  model.locomotion.rotate_world(skeleton,foot,foot_bases[side]*current.inverse())

func capture_launch() -> void:
 launch = snapshot()

func sample(progress: float) -> void:
 model.animation.play("dodge/roll_forward")
 model.animation.seek(progress, true)
 model.animation.advance(0)

func snapshot() -> Array:
 var result: Array = []
 for i in skeleton.get_bone_count():
  result.append([skeleton.get_bone_pose_rotation(i), skeleton.get_bone_pose_position(i)])
 return result

func blend_pose(a: Array, b: Array, weight: float) -> void:
 for i in skeleton.get_bone_count():
  skeleton.set_bone_pose_rotation(i, a[i][0].slerp(b[i][0], weight))
  skeleton.set_bone_pose_position(i, a[i][1].lerp(b[i][1], weight))

func update(phase: int, time: float, push_duration: float, flight_duration: float, roll_duration: float) -> void:
 var shoulder := 0.0
 match phase:
  0: # Visible knee bend and lean while the feet still support the body.
   var weight := smoothstep(0, push_duration, time)
   blend_pose(idle, lean, weight)
   shoulder = 0.35*weight
  1: # Extend from the last supported pose after takeoff, never snap prone.
   if time < extension_duration:
    var weight := smoothstep(0,extension_duration,time)
    blend_pose(launch,dive,weight)
    shoulder = weight # Launch snapshot already contains the initial shoulder tilt.
   else:
    blend_pose(dive, contact, smoothstep(flight_duration-0.10, flight_duration, time))
    shoulder = 1.0
  2: # Skip the clip's standing opening; start at the actual contact pose.
   var progress := clampf(time / roll_duration, 0, 1)
   sample(lerpf(0.24, 1.0, progress))
   shoulder = 1.0-smoothstep(0.55, 1.0, progress)
  _:
   blend_pose(idle, idle, 0.0)
 var rotation := skeleton.get_bone_pose_rotation(root_bone)
 skeleton.set_bone_pose_rotation(root_bone, (parent_frame.basis.inverse()*Basis(Vector3.FORWARD, deg_to_rad(10)*shoulder)*parent_frame.basis*Basis(rotation)).get_rotation_quaternion())
 # Remove clip root translation: the collision body owns horizontal travel.
 var position := parent_frame*skeleton.get_bone_pose_position(root_bone)
 if phase == 2:
  position.x = (parent_frame*idle[root_bone][1]).x
  position.z = (parent_frame*idle[root_bone][1]).z
 skeleton.set_bone_pose_position(root_bone, parent_frame.affine_inverse()*position)
 # Ground the armor, including interpolated poses. Airborne clearance comes
 # exclusively from the collision body's arc, never a second visual hop.
 position.y += (SKIN_CLEARANCE-model.dodge_skin_min_height())/skeleton.global_basis.y.length()
 skeleton.set_bone_pose_position(root_bone, parent_frame.affine_inverse()*position)
 # Whole-body clearance shifts the ankles too. Apply supported constraints last.
 if phase == 0: plant_feet()
 skeleton.force_update_all_bone_transforms()
