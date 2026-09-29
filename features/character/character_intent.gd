extends RefCounted
## A controller's request, independent of keyboard, AI, camera or preview UI.
var movement := Vector3.ZERO
## Camera-relative 3D direction and independent world-up input; also usable by AI.
var swim_direction := Vector3.ZERO
var swim_vertical := 0.0
## Surface-relative intent: +Y is Forward/up, regardless of the camera.
var surface_motion := Vector2.ZERO
var facing := Vector3.ZERO
var sprint := false
var crouch_held := false
var action: StringName = &""
const Aim = preload("res://features/combat/aim_request.gd")
var aim: Aim
