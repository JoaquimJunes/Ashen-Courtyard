extends Node3D
## Visualizes the last accepted query; never probes, advances or moves gameplay.
var traversal: RefCounted
var hands: Array[MeshInstance3D] = []
var landing: MeshInstance3D
var route: MeshInstance3D
var route_points := PackedVector3Array()
var route_rebuilds := 0
var show_hands := true:
	set(value):
		if show_hands == value: return
		show_hands = value
		sync_processing()
var show_route := true:
	set(value):
		if show_route == value: return
		show_route = value
		sync_processing()

func configure(feature: RefCounted) -> void:
	traversal = feature
	for i in 2:
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		marker.material_override = Shapes.material(Color("65e6ce"))
		add_child(marker)
		hands.append(marker)
	landing = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.32
	cylinder.bottom_radius = 0.32
	cylinder.height = 0.015
	landing.mesh = cylinder
	landing.material_override = Shapes.material(Color("efcc76"))
	add_child(landing)
	route = MeshInstance3D.new()
	route.mesh = ImmediateMesh.new()
	route.material_override = Shapes.material(Color("65e6ce"))
	add_child(route)
	visibility_changed.connect(sync_processing)
	sync_processing()

func sync_processing() -> void:
	if route == null: return
	var active := is_visible_in_tree() and (show_hands or show_route)
	set_process(active)
	if active: _process(0.0)
	else:
		for hand in hands: hand.hide()
		landing.hide()
		route.hide()

func _process(_delta: float) -> void:
	if traversal == null: return
	var candidate: RefCounted = traversal.candidate
	var present: bool = is_visible_in_tree() and candidate != null
	for hand in hands: hand.visible = present and show_hands
	landing.visible = present and candidate.can_mantle and show_route if present else false
	route.visible = landing.visible
	if not present: return
	if show_hands:
		hands[0].global_position = candidate.left_hand
		hands[1].global_position = candidate.right_hand
	if not landing.visible: return
	landing.global_position = candidate.stand
	var points := PackedVector3Array()
	for point: Vector3 in [candidate.hang,candidate.lift,candidate.over,candidate.stand]:
		points.append(route.to_local(point))
	# Compare local vertices, so a moving parent also invalidates the cache.
	if points == route_points: return
	route_points = points
	route_rebuilds += 1
	var mesh: ImmediateMesh = route.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in route_points: mesh.surface_add_vertex(point)
	mesh.surface_end()
