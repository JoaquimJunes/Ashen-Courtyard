extends RefCounted
## World-space aim supplied by a controller, never a camera dependency in a spell.
var origin := Vector3.ZERO
var point := Vector3.FORWARD
func _init(from: Vector3 = Vector3.ZERO, to: Vector3 = Vector3.FORWARD) -> void:
	origin = from
	point = to
func direction() -> Vector3:
	var offset := point-origin
	return offset.normalized() if offset.length_squared() > 0.000001 else Vector3.FORWARD
