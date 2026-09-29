extends Resource
## Read-only tuning; input, posture and playback state remain per character.
@export var hold_seconds := 0.5
@export var speed := 1.0
@export var radius := 0.43
@export var length := 1.9
@export var center := Vector3(0,0.43,0)
@export var max_step := 0.02
@export var blend_seconds := 0.25
@export var clip: StringName = &"crawling/crawl"

func transform() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT,PI*0.5),center)
