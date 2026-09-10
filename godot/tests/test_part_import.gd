## Proves the Blender -> glTF -> Godot pipeline keeps what the game needs:
## the mesh, the SOCKET_/CUT_/HAZARD_ empties, and the custom properties.
## The sample part is produced by tools/blender/make_part.py.
extends TestCase

const PART := "res://assets/models/parts/hull_segment_a.glb"


func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for c in node.get_children():
		var hit: Node = _find(c, name)
		if hit != null:
			return hit
	return null


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var hit: MeshInstance3D = _find_mesh(c)
		if hit != null:
			return hit
	return null


func test_part_loads_with_sockets_and_meta() -> void:
	var packed: PackedScene = load(PART)
	check(packed != null, "glb loads as PackedScene")
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var mesh: MeshInstance3D = _find_mesh(root)
	check(mesh != null, "has a MeshInstance3D")
	for n in ["SOCKET_fore", "SOCKET_aft", "CUT_fore", "CUT_aft", "HAZARD_coolant_1"]:
		var e: Node = _find(root, n)
		check(e != null and e is Node3D, "empty %s imported as Node3D" % n)
	var fore: Node3D = _find(root, "SOCKET_fore") as Node3D
	var aft: Node3D = _find(root, "SOCKET_aft") as Node3D
	if fore != null and aft != null:
		# Blender +Y (forward) becomes Godot -Z.
		check(fore.position.z < aft.position.z, "SOCKET_fore is forward (-Z) of SOCKET_aft")
		check_near(aft.position.z - fore.position.z, 6.0, 0.01, "socket spacing equals part length")
	# Godot imports glTF extras as ONE meta entry named "extras" (a Dictionary)
	# on the node that carried them (the Blender object = the MeshInstance3D).
	check(mesh != null and mesh.has_meta("extras"), "custom properties imported as meta 'extras'")
	if mesh != null and mesh.has_meta("extras"):
		var extras: Dictionary = mesh.get_meta("extras")
		check_near(float(extras.get("mass_kg", 0.0)), 4200.0, 0.01, "mass_kg value")
		check_eq(str(extras.get("part_kind", "")), "hull", "part_kind")
		check_eq(str(extras.get("material", "")), "steel", "material")
	root.free()
