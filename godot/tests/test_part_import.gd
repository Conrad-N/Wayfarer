## Proves the Blender -> glTF -> Godot pipeline keeps what the game needs:
## the mesh, the SOCKET_/CUT_/HAZARD_ empties, and the custom properties.
## The kit is produced by tools/blender/make_part_kit.py.
extends TestCase

const PART := "res://assets/models/parts/hull_segment_a.glb"
const KIT: Dictionary = {
	"hull_segment_a": ["hull", Vector3(4, 4, 6)],
	"hull_segment_b": ["hull", Vector3(1.6, 1.6, 2)],
	"hull_segment_c": ["hull", Vector3(4, 4, 9)],
	"cap_nose_a": ["cap", Vector3(1.6, 1.6, 1)],
	"cap_tail_a": ["cap", Vector3(1.6, 1.6, .25)],
	"tank_fuel_a": ["tank", Vector3(.84, .84, 1.5)],
	"tank_coolant_a": ["tank", Vector3(.84, .84, 1.5)],
	"engine_chemical_a": ["engine", Vector3(1.2, 1.2, 1.2)],
	"engine_ion_a": ["engine", Vector3(1, 1, .8)],
	"radiator_panel_a": ["radiator", Vector3(2, 1, .12)],
	"radiator_panel_b": ["radiator", Vector3(1.2, 1.6, .12)],
	"radiator_panel_c": ["radiator", Vector3(3, 1, .12)],
	"truss_segment_a": ["truss", Vector3(1, 1, 2)],
	"truss_segment_b": ["truss", Vector3(1, 1, 4)],
	"truss_segment_c": ["truss", Vector3(1, 1, 6)],
	"sensor_mast_a": ["mast", Vector3(.65, .4, 2)],
	"plating_panel_a": ["plating", Vector3(2, 1.8, .1)],
}


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


## Every kit model retains physical metadata, small geometry, and convex collision.
func test_whole_kit_imports_with_collision_and_physical_metadata() -> void:
	check_eq(KIT.size(), 17, "the kit has seventeen parts")
	var kinds: Dictionary = {}
	for part_name: String in KIT:
		var packed: PackedScene = load("res://assets/models/parts/%s.glb" % part_name)
		check(packed != null, "%s loads" % part_name)
		if packed == null:
			continue
		var root: Node3D = packed.instantiate() as Node3D
		var mesh: MeshInstance3D = _find_mesh(root)
		check(mesh != null and mesh.mesh != null, "%s has a mesh" % part_name)
		if mesh == null or mesh.mesh == null:
			root.free()
			continue
		check_eq(str(mesh.name), part_name, "%s collision suffix stripped" % part_name)
		var extras: Dictionary = mesh.get_meta("extras", {})
		check_eq(str(extras.get("part_kind", "")), KIT[part_name][0], "%s kind" % part_name)
		kinds[str(extras.get("part_kind", ""))] = true
		for field: String in ["mass_kg", "value_cr", "volume_m3", "thickness_mm"]:
			var number: float = float(extras.get(field, 0.0))
			check(is_finite(number) and number > 0.0, "%s positive finite %s" % [part_name, field])
		check(not str(extras.get("material", "")).is_empty(), "%s material survives" % part_name)
		var triangles: int = mesh.mesh.get_faces().size() / 3
		check(triangles > 0 and triangles < 2000, "%s stays under 2000 triangles" % part_name)
		var pose: Transform3D = _relative_pose(mesh, root)
		var bounds: AABB = pose * mesh.mesh.get_aabb()
		var expected: Vector3 = KIT[part_name][1]
		check(bounds.size.is_equal_approx(expected), "%s metre-sized bounds %s" % [part_name, bounds.size])
		var shapes: Array[CollisionShape3D] = []
		_collect_shapes(root, shapes)
		check_eq(shapes.size(), 1, "%s has one imported convex collider" % part_name)
		for collision: CollisionShape3D in shapes:
			check(collision.shape is ConvexPolygonShape3D, "%s collider is convex" % part_name)
			check(collision.get_parent() is StaticBody3D, "%s default import owns collider" % part_name)
			if collision.shape is ConvexPolygonShape3D:
				var convex: ConvexPolygonShape3D = collision.shape as ConvexPolygonShape3D
				check(convex.points.size() >= 4, "%s collision has a volume" % part_name)
		var sockets: Array[Node3D] = []
		_collect_markers(root, "SOCKET_", sockets)
		check(not sockets.is_empty(), "%s has attachment sockets" % part_name)
		for marker: Node3D in sockets:
			var socket_name: String = str(marker.name).trim_prefix("SOCKET_")
			var size_code: String = socket_name.get_slice("_", socket_name.get_slice_count("_") - 1)
			if size_code in ["S", "M", "L"]:
				socket_name = socket_name.left(socket_name.length() - 2)
			else:
				check(part_name in ["hull_segment_a", "hull_segment_c"], "only the big hulls omit the default M suffix")
			check(_find(root, "CUT_" + socket_name) is Node3D, "%s socket has a matching cut marker" % part_name)
			var socket_pose: Transform3D = _relative_pose(marker, root)
			check_near(socket_pose.basis.determinant(), 1.0, .0001, "%s socket keeps a unit right-handed basis" % part_name)
			check((-socket_pose.basis.z).dot(socket_pose.origin) > 0.0, "%s socket -Z faces out of part" % part_name)
		root.free()
	check_eq(kinds.size(), 8, "kit covers hull, cap, tank, engine, radiator, truss, mast, and plating")


## Volatile markers retain their kinds and local jet directions through glTF.
func test_hazard_markers_and_small_socket_survive() -> void:
	for part_name: String in ["tank_fuel_a", "tank_coolant_a", "radiator_panel_a", "radiator_panel_b"]:
		var packed: PackedScene = load("res://assets/models/parts/%s.glb" % part_name)
		var root: Node3D = packed.instantiate() as Node3D
		var kind: String = "fuel" if part_name == "tank_fuel_a" else "coolant"
		var marker: Node3D = _find(root, "HAZARD_%s_0" % kind) as Node3D
		check(marker != null, "%s hazard marker exists" % part_name)
		if marker != null:
			var direction: Vector3 = -_relative_pose(marker, root).basis.z
			var expected: Vector3 = Vector3.DOWN if part_name.begins_with("tank") else Vector3.LEFT
			check(direction.is_equal_approx(expected), "%s vent points outwards" % part_name)
		root.free()
	var hull: Node3D = (load("res://assets/models/parts/hull_segment_b.glb") as PackedScene).instantiate() as Node3D
	var mount: Node3D = _find(hull, "SOCKET_instrument_S") as Node3D
	check(mount != null, "small instrument socket is present")
	if mount != null:
		var pose: Transform3D = _relative_pose(mount, hull)
		check(pose.origin.is_equal_approx(Vector3(0, .8, .6)), "mast socket position")
		check((-pose.basis.z).is_equal_approx(Vector3.UP), "mast socket faces upward")
	hull.free()


func _relative_pose(node: Node3D, root: Node3D) -> Transform3D:
	var pose: Transform3D = node.transform
	var parent: Node3D = node.get_parent() as Node3D
	while parent != null and parent != root:
		pose = parent.transform * pose
		parent = parent.get_parent() as Node3D
	return pose


func _collect_shapes(node: Node, shapes: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		shapes.append(node as CollisionShape3D)
	for child: Node in node.get_children():
		_collect_shapes(child, shapes)


func _collect_markers(node: Node, prefix: String, markers: Array[Node3D]) -> void:
	if node is Node3D and str(node.name).begins_with(prefix):
		markers.append(node as Node3D)
	for child: Node in node.get_children():
		_collect_markers(child, prefix, markers)
