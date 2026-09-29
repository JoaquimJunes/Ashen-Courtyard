extends Node3D
## Fixtures and spawn markers only; all traversal belongs to the shared character.
var starts: Array[Marker3D] = []
const TITLES := ["1.5 m / PULL-UP", "2.5 m / HIGH REACH", "LOW CEILING / HANG ONLY", "EXCLUDED / NO GRAB"]

func _ready() -> void:
	for index in 4:
		var x := index*5.0
		var height := 2.5 if index == 1 else 1.5
		var wall := Shapes.solid(self,Vector3(3,height,2),Vector3(x,height/2,-1),Color("74929b"))
		wall.name = "Wall%d" % index
		if index == 2:
			Shapes.solid(self,Vector3(3,0.2,1.9),Vector3(x,2.8,-1),Color("bc9376"))
		if index == 3: wall.add_to_group(&"no_ledge_grab")
		var start := Marker3D.new()
		start.name = "Start%d" % index
		start.position = Vector3(x,0.04,0.5)
		add_child(start)
		starts.append(start)
		var label := Label3D.new()
		label.text = TITLES[index]
		label.font_size = 40
		label.pixel_size = 0.005
		label.position = Vector3(x,0.02,2)
		label.rotation.x = -PI/2
		add_child(label)
		Shapes.box(self,Vector3(1,0.015,1),Vector3(x,0.01,0.7),Color("c4be80"))
