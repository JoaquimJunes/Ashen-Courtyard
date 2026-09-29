extends RefCounted
## Per-action requested travel, never shared definition data. Walls consume it too.
var remaining := 0.0

func reset(distance: float = 0.0) -> void:
	remaining = maxf(0,distance) if is_finite(distance) else 0.0

func consume(requested: float, limit_ground_travel: bool) -> float:
	if not is_finite(requested) or requested <= 0: return 0.0
	var distance := minf(requested,remaining) if limit_ground_travel else requested
	remaining = maxf(0,remaining-distance)
	return distance
