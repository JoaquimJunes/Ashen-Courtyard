extends RefCounted
## Retargeted Mixamo poses run on the shared physics pose clock, before sensing.
var actor: CharacterBody3D
var clock := 0.0
var blend_time := 0.0
var from_pose: Array = []

func configure(character: CharacterBody3D) -> void:
	actor = character
	actor.crawling.changed.connect(on_changed)

func on_changed() -> void:
	from_pose = actor.presentation.capture_pose()
	blend_time = 0
	actor.model.reset_locomotion()
	if not actor.crawling.active: reset()

func sample(delta: float) -> bool:
	if not actor.crawling.active: return false
	var model: Node3D = actor.model
	var speed: float = Vector2(actor.motor.last_result.velocity.x,actor.motor.last_result.velocity.z).length()
	if actor.is_on_floor() and actor.actions.is_available():
		var reverse := -1.0 if actor.velocity.dot(-actor.global_basis.z) < -0.05 else 1.0
		clock += delta*minf(speed/actor.crawling.definition.speed,1.5)*reverse
	model.skeleton.reset_bone_poses()
	model.animation.play(actor.crawling.definition.clip,0)
	model.animation.seek(fposmod(clock,model.animation.get_animation(actor.crawling.definition.clip).length),true)
	model.animation.advance(0)
	blend_time += delta
	if not from_pose.is_empty():
		var weight := smoothstep(0,actor.crawling.definition.blend_seconds,blend_time)
		for bone in model.skeleton.get_bone_count():
			model.skeleton.set_bone_pose_rotation(bone,from_pose[bone][0].slerp(model.skeleton.get_bone_pose_rotation(bone),weight))
			model.skeleton.set_bone_pose_position(bone,from_pose[bone][1].lerp(model.skeleton.get_bone_pose_position(bone),weight))
		if weight >= 1: from_pose.clear()
	model.skeleton.force_update_all_bone_transforms()
	return true

func reset() -> void:
	clock = 0
	blend_time = 0
	from_pose.clear()
