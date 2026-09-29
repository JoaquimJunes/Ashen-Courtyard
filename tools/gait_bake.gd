extends RefCounted
## Offline source contact/cadence measurements; shared immutable clip metadata.
static func annotate(clip: Animation, source: Skeleton3D, player: AnimationPlayer, name: String, scale_ratio: float) -> void:
	var samples := 120
	var feet := {"l": [], "r": []}
	var minimum := {"l": INF, "r": INF}
	for frame in samples+1:
		player.play(name)
		player.seek(frame*clip.length/samples,true)
		player.advance(0)
		source.force_update_all_bone_transforms()
		for side: String in feet:
			var point := source.get_bone_global_pose(source.find_bone("foot_"+side)).origin
			feet[side].append(point)
			minimum[side] = minf(minimum[side],point.y)
	var speeds: Array[float] = []
	for side: String in feet:
		var weights := PackedFloat32Array()
		for frame in samples+1:
			var point: Vector3 = feet[side][frame]
			var contact := 1.0-smoothstep(minimum[side]+0.025,minimum[side]+0.12,point.y)
			weights.append(contact)
			if frame > 0 and contact > 0.6:
				var speed: float = (feet[side][frame-1].z-point.z)*samples/clip.length
				if speed > 2.0: speeds.append(speed*scale_ratio)
		clip.set_meta("plant_"+side,weights)
	speeds.sort()
	if not speeds.is_empty(): clip.set_meta("reference_speed",speeds[speeds.size()/2])
	clip.set_meta("source_clip",name)
