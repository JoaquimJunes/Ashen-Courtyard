extends Node3D
## Measured, reusable fixture shared by the laboratory, tests and native captures.
@export var gap: float = 0.6
@export var source_height: float = 0.6
@export var target_height: float = 1.0
@export var width: float = 3.0
@export var landing_length: float = 7.0
@export var show_labels: bool = true

func _ready() -> void:
	Shapes.solid(self,Vector3(width,source_height,3),Vector3(0,source_height/2,1.5),Color("788e98"))
	Shapes.solid(self,Vector3(width,target_height,landing_length),
		Vector3(0,target_height/2,-gap-landing_length/2),Color("9ca790"))
	Shapes.box(self,Vector3(width,0.012,0.06),Vector3(0,source_height+0.009,0.08),Color("efc274"))
	Shapes.box(self,Vector3(width,0.012,0.06),Vector3(0,target_height+0.009,-gap-0.08),Color("efc274"))
	var start := Marker3D.new()
	start.name = "DiveStart"
	start.position = Vector3(0,source_height+0.02,0.35)
	add_child(start)
	if show_labels:
		label("START %.2f m" % source_height,Vector3(0,source_height+0.06,1.6))
		label("LAND %.2f m" % target_height,Vector3(0,target_height+0.06,-gap-2.2))
		label("%.2f m GAP" % gap,Vector3(0,0.035,-gap/2))

func label(words: String, at: Vector3) -> void:
	var text := Label3D.new()
	text.text = words
	text.font_size = 48
	text.pixel_size = 0.009
	text.rotation.x = -PI/2
	text.position = at
	add_child(text)
