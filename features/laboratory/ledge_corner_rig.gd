extends Node3D
## Reusable static courses; character rules live exclusively in traversal features.
var starts: Array[Marker3D] = []

func _ready() -> void:
	for index in 3:
		var x := index*8.0
		var wall := Shapes.solid(self,Vector3(4,1.5,2),Vector3(x,0.75,-1),Color("74929b"))
		wall.name = "CornerWall%d" % index
		if index == 1:
			Shapes.solid(self,Vector3(1,1.5,4),Vector3(x+2.5,0.75,1),Color("74929b"))
		if index == 2:
			# An adjacent excluded segment must stop lateral traversal.
			var stop := Shapes.solid(self,Vector3(0.8,1.5,2),Vector3(x+2.4,0.75,-1),Color("bc9376"))
			stop.add_to_group(&"no_ledge_grab")
		var start := Marker3D.new()
		start.position = Vector3(x,0.04,0.5)
		add_child(start)
		starts.append(start)
		var label := Label3D.new()
		label.text = ["OUTSIDE CORNERS", "INSIDE CORNER / MOVE RIGHT", "EXCLUDED EDGE / STOP SAFELY"][index]
		label.font_size = 38
		label.pixel_size = 0.005
		label.position = Vector3(x,0.025,2)
		label.rotation.x = -PI/2
		add_child(label)
