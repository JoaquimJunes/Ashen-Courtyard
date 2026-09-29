extends PhysicalBone3D
## Physical contacts and an explicit damage receiver, independent of world hosts.
var receiver: Node
var floor_contact := false
func get_damage_receiver() -> Node:
	return receiver
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	floor_contact = false
	for contact in state.get_contact_count():
		# Godot supplies the contacting surface normal in world axes here.
		var normal := state.get_contact_local_normal(contact)
		if normal.y > 0.5: floor_contact = true
