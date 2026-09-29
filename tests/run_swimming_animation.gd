extends "res://tools/build_ual_combat_library.gd"
const Stage = preload("res://tests/fixtures/swim_stage.gd")
const PROFILE = preload("res://features/presentation/data/ual_animation_profile.tres")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func run() -> void:
	var original := preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	var source: AnimationPlayer = original.find_child("AnimationPlayer",true,false)
	var hash := FileAccess.get_sha256(preload("res://tools/ual_animation_build_manifest.tres").source_scene.resource_path)
	for role in ["swim_idle","swim_forward"]:
		var clip: Animation = PROFILE.native_swimming.get_animation(role)
		check(same_clip(source.get_animation(clip.get_meta("source_clip")),clip),role+": original keys, paths, duration and loop flags preserved")
		check(clip.get_meta("source_sha256") == hash and clip.get_meta("source_glb_clip").ends_with("_Loop"),role+": native UAL provenance")
	original.free()
	var stage := Stage.new()
	root.add_child(stage)
	current_scene = stage
	var p: CharacterBody3D = stage.player
	await stage.reset_at()
	await stage.tick(0.3)
	p.model.update_pose(0.016)
	check(p.model.animation.assigned_animation == "swimming/swim_idle","Surface idle selects UAL tread-water")
	check(p.model.equipment.current_sockets.get(&"sword") == &"left_hip","Swimming stows held sword")
	stage.intent.movement = Vector3.FORWARD
	stage.intent.swim_direction = Vector3.FORWARD
	await stage.tick(0.3)
	p.model.update_pose(0.016)
	check(p.model.animation.assigned_animation == "swimming/swim_forward" and not p.model.foot_placement_enabled(),"Forward swimming selects UAL without ground foot placement")
	var head: int = p.model.rig.bone(p.model.skeleton,"Head")
	p.model.skeleton.force_update_all_bone_transforms()
	var head_point: Vector3 = p.model.skeleton.global_transform*p.model.skeleton.get_bone_global_pose(head)*p.hitboxes.profile.breathing_offset
	check(absf(head_point.y-0.12) < 0.01,"Surface animation mouth/nose aligns above the waterline")
	stage.intent.swim_vertical = -1
	await stage.tick(0.4)
	p.model.update_pose(0.016)
	check(p.model.rotation.x < -0.05,"Underwater forward pose pitches into descent")
	for bone in p.model.skeleton.get_bone_count():
		check(p.model.skeleton.get_bone_global_pose(bone).is_finite(),"Finite swimming bone "+str(bone))
	var ui: CanvasLayer = p.get_node("SwimmingHUD")
	p.camera.global_position = Vector3(4,1,0)
	ui._process(0)
	check(not ui.camera_submerged and ui.panel.visible,"Submerged player can have a dry camera and visible breath")
	p.camera.global_position = Vector3(4,-1,0)
	ui._process(0)
	check(ui.camera_submerged and ui.tint.visible,"Underwater camera controls tint independently")
	p.resources.breath = 3
	p.resources.breath_changed.emit(3,20)
	check(ui.warning.text.contains("LOW BREATH"),"Low breath warning is readable")
	await stage.reset_at(Vector3(-9,-0.4,0))
	p.model.update_pose(0.016)
	check(p.model.equipment.current_sockets.get(&"sword") == &"right_hand" and not p.model.animation.assigned_animation.begins_with("swimming/"),"Dry reset restores held sword and land animation")
	stage.queue_free()
	await process_frame
	print("SWIMMING ANIMATION: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
