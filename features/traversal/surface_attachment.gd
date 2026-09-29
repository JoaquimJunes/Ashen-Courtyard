extends RefCounted
## Per-character lease. Finishing an ability never implicitly releases this support.
signal motion_applied(result: RefCounted, request: RefCounted)
var motion: RefCounted
var token := 0
var candidate: RefCounted
var hold_position := Vector3.ZERO

func valid() -> bool:
	return candidate != null and candidate.valid()

func revoke() -> void:
	motion = null
	candidate = null
	token = 0
