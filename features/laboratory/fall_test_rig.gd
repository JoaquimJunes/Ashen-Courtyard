extends Node3D
## The lab changes fixture height and spawn placement, never character mechanics.
@export var height := 4.5
var start: Marker3D
var geometry: Node3D

func _ready() -> void:
	start = Marker3D.new()
	start.name = "DropStart"
	add_child(start)
	configure_height(height)

func configure_height(value: float) -> void:
	height = clampf(value,1,20)
	if is_instance_valid(geometry): geometry.free()
	geometry = Node3D.new()
	add_child(geometry)
	Shapes.solid(geometry,Vector3(4,0.3,3),Vector3(0,height-0.15,0),Color("6f8291"))
	for x in [-1.7,1.7]:
		Shapes.solid(geometry,Vector3(0.18,height,0.18),Vector3(x,height/2,1.1),Color("43545f"))
	var label := Label3D.new()
	label.text = "%.1f m DROP\nWalk or dive forward off the edge\nTap Dodge just before landing" % height
	label.position = Vector3(0,height+1,1.2)
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	geometry.add_child(label)
	start.position = Vector3(0,height+0.025,0)
