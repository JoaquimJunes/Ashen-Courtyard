extends Node3D
## Follow the character's body, never its rolling/attacking visual mesh.
var subject: CharacterBody3D
var arm: SpringArm3D
var camera: Camera3D
var follow_point := Vector3.ZERO
var initialized := false
var shoulder_offset := 0.0
# Continuous orbit state: Node3D Euler angles wrap after a full turn.
var follow_yaw := 0.0
var follow_pitch := 0.0
var probe := SphereShape3D.new()

func _ready() -> void:
 if not CameraPreferences.loaded: CameraPreferences.load_settings()
 process_mode = Node.PROCESS_MODE_ALWAYS
 top_level = true
 probe.radius = 0.24
 arm = SpringArm3D.new()
 arm.name = "CollisionArm"
 arm.margin = 0.12
 arm.collision_mask = 1
 arm.shape = probe
 add_child(arm)
 camera = Camera3D.new()
 camera.name = "ShoulderView"
 camera.near = 0.08
 camera.current = true
 arm.add_child(camera)

func weight(delta: float, seconds: float) -> float:
 return 1.0 if seconds <= 0 else 1.0-exp(-delta/seconds)

func reset_follow() -> void:
 initialized = false
 update_follow(1.0)

func _physics_process(delta: float) -> void:
 update_follow(delta)

func update_follow(delta: float) -> void:
 if not is_instance_valid(subject): return
 var settings := CameraPreferences.values
 var anchor := subject.global_position + Vector3.UP*float(settings.height)
 if subject.has_method("camera_anchor"): anchor = subject.camera_anchor(float(settings.height))
 var blend := weight(delta,float(settings.smoothing))
 if not initialized or anchor.distance_to(follow_point) > 4.0:
  follow_point = anchor
  follow_yaw = subject.yaw
  follow_pitch = subject.pitch
  shoulder_offset = float(settings.side)*float(settings.offset)
  initialized = true
 else:
  follow_point = follow_point.lerp(anchor,blend)
  follow_pitch = lerpf(follow_pitch,subject.pitch,blend)
  # Preserve mouse travel even when smoothing lags by more than half a turn.
  # Shortest-angle interpolation would reverse direction at that boundary.
  follow_yaw = lerpf(follow_yaw,subject.yaw,blend)
 rotation = Vector3(follow_pitch,wrapf(follow_yaw,-PI,PI),0)
 # Sweep the shoulder pivot too: a rear spring arm alone misses sideways walls.
 shoulder_offset = lerpf(shoulder_offset,float(settings.side)*float(settings.offset),weight(delta,0.15))
 var desired := follow_point + Basis(Vector3.UP,rotation.y).x*shoulder_offset
 var motion := desired-anchor
 var query := PhysicsShapeQueryParameters3D.new()
 query.shape = probe
 query.transform = Transform3D(Basis.IDENTITY,anchor)
 query.motion = motion
 query.collision_mask = 1
 var fractions := get_world_3d().direct_space_state.cast_motion(query)
 global_position = anchor+motion*maxf(0.0,fractions[0]-0.02)
 arm.spring_length = float(settings.distance)
 camera.fov = float(settings.fov)

func _process(delta: float) -> void:
 if not is_instance_valid(subject): return
 # Keep the locked enemy on the reticle despite the lateral shoulder offset.
 var desired := Basis.IDENTITY
 if subject.locked and is_instance_valid(subject.target) and not subject.target.dead:
  var aim: Vector3 = subject.target.global_position+Vector3.UP*1.3
  if camera.global_position.distance_squared_to(aim) > 0.01:
   var world_basis := Basis.looking_at(aim-camera.global_position,Vector3.UP)
   desired = arm.global_basis.inverse()*world_basis
 camera.quaternion = camera.quaternion.slerp(desired.get_rotation_quaternion(),weight(delta,0.09))
