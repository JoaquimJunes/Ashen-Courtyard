extends RefCounted
## Owns the skeleton sampler and blends; consumes gameplay phases without moving a body.
var model: Node3D
var definition: Resource
var pose: RefCounted
var transition: Array = []
var transition_time := 0.0

func begin(knight: Node3D, settings: Resource) -> void:
	model = knight
	definition = settings
	model.reset_locomotion()
	pose = preload("res://features/presentation/forward_dive_pose.gd").new()
	pose.setup(model,true)
	pose.extension_duration = definition.extension
	transition.clear()
	transition_time = 0

func finish() -> void:
	if is_instance_valid(model):
		model.begin_action_exit()
		model.set_process(true)
		model.reset_locomotion()
		model.animation.stop()
	pose = null
	model = null
	definition = null
	transition.clear()
	transition_time = 0

func capture_launch() -> void:
	pose.capture_launch()

func start_transition() -> void:
	transition = pose.snapshot()
	transition_time = 0

func sample(phase: int, clock: float, flight_duration: float, delta: float) -> void:
	var started := Time.get_ticks_usec()
	pose.update(phase,clock,definition.preparation,flight_duration,definition.ground_duration)
	if not transition.is_empty():
		transition_time += delta
		var weight := smoothstep(0,definition.pose_blend,transition_time)
		pose.blend_pose(transition,pose.snapshot(),weight)
		var root: int = pose.root_bone
		model.rig.offset_world(pose.skeleton,root,model.global_basis*Vector3.UP*maxf(0,0.025-model.dodge_skin_min_height()))
		pose.skeleton.force_update_all_bone_transforms()
		if weight >= 1: transition.clear()
	if model.pose_driver != null: model.pose_driver.external_microseconds += Time.get_ticks_usec()-started
