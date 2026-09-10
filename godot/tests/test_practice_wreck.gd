## Real imported kit parts form an accessible, non-overlapping eight-part exercise.
extends TestCase


## The hand-authored tug contains the intended parts and one connected structure.
func test_practice_graph_contains_eight_real_parts_and_seven_connections() -> void:
	var graph: ShipGraph = PracticeWreck.make_graph()
	var expected: PackedStringArray = ["Antenna", "Drive", "Engine", "Fuel", "Nose", "Radiator", "Shield", "Spine"]
	check_eq(graph.part_ids(), expected, "all eight practice parts are present")
	check_eq(graph.edge_ids().size(), 7, "seven joints join the practice wreck")
	check_eq(graph.components().size(), 1, "the initial wreck is connected")
	for id: String in graph.part_ids():
		var part: ShipPart = graph.get_part(id)
		check(part.is_valid(), "%s has a valid kit definition and pose" % id)
		check(ResourceLoader.exists(part.definition.model_path), "%s uses a real imported model" % id)
		check(not PartCatalog.geometry(part.definition).get("shapes", []).is_empty(), "%s has imported collision" % id)
	var hazard_kinds: PackedStringArray = []
	for id: String in ["Fuel", "Radiator"]:
		for hazard: Dictionary in graph.get_part(id).definition.hazards:
			hazard_kinds.append(str(hazard.kind))
	check(hazard_kinds.has("fuel") and hazard_kinds.has("coolant"), "both M2 hazards exist on the practice wreck")


## Mated sockets face each other across a small exposed joint, without crossed parts.
func test_practice_socket_alignment_and_non_overlapping_parts() -> void:
	var graph: ShipGraph = PracticeWreck.make_graph()
	for edge_id: String in graph.edge_ids():
		var edge: Dictionary = graph.get_edge(edge_id)
		var first: ShipPart = graph.get_part(edge.a)
		var second: ShipPart = graph.get_part(edge.b)
		var mount_a: Transform3D = first.transform * first.definition.sockets[edge.socket_a]
		var mount_b: Transform3D = second.transform * second.definition.sockets[edge.socket_b]
		check_near(mount_a.origin.distance_to(mount_b.origin), 0.12, 0.00001, "%s leaves a 12 cm joint gap" % edge_id)
		check_near(mount_a.basis.z.dot(mount_b.basis.z), -1.0, 0.00001, "%s socket normals oppose each other" % edge_id)
		var outward_gap: Vector3 = -mount_a.basis.z * 0.12
		check((mount_b.origin - mount_a.origin).distance_to(outward_gap) < 0.00001, "%s gap follows the mounting normal" % edge_id)
	var ids: PackedStringArray = graph.part_ids()
	for index: int in range(ids.size()):
		var first: ShipPart = graph.get_part(ids[index])
		var first_box: AABB = first.transform * AABB(-first.definition.size_m * 0.5, first.definition.size_m)
		for other: int in range(index + 1, ids.size()):
			var second: ShipPart = graph.get_part(ids[other])
			var second_box: AABB = second.transform * AABB(-second.definition.size_m * 0.5, second.definition.size_m)
			var overlap: AABB = first_box.intersection(second_box)
			check(overlap.size.x <= 0.001 or overlap.size.y <= 0.001 or overlap.size.z <= 0.001,
				"%s and %s have no overlapping physical bounds" % [first.id, second.id])


## Sized sockets resolve unsized CUT markers after arbitrary assembly rotation.
func test_real_cut_areas_use_imported_surface_markers() -> void:
	var graph: ShipGraph = PracticeWreck.make_graph()
	var pose: Transform3D = Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.61), Vector3(15, -2, 8))
	var wreck: SalvageWreck = _spawn(graph, pose)
	check_eq(wreck.bodies.size(), 1, "real graph produces one compound body")
	var body: WreckBody = wreck.bodies[0]
	check_eq(body.get_shape_owners().size(), 8, "compound owns one imported collider per real part")
	var markers: int = 0
	for child: Node in body.get_children():
		if not child is Area3D:
			continue
		var area: Area3D = child as Area3D
		markers += 1
		var part_id: String = str(area.get_meta("part_id"))
		var edge: Dictionary = graph.get_edge(str(area.get_meta("edge_id")))
		var socket: String = edge.socket_a if edge.a == part_id else edge.socket_b
		var part: ShipPart = graph.get_part(part_id)
		# The Blender contract names CUT_fore beside SOCKET_fore_M, and so on.
		var cut_name: String = socket.left(socket.length() - 2)
		check(part.definition.cut_points.has(cut_name), "%s has an imported unsized CUT marker" % area.name)
		if not part.definition.cut_points.has(cut_name):
			continue
		var cut: Transform3D = part.definition.cut_points[cut_name]
		var mount: Transform3D = part.definition.sockets[socket]
		check(cut.origin.distance_to(mount.origin) > 0.005, "%s fixture distinguishes surface cut from socket fallback" % area.name)
		var expected: Transform3D = pose * part.transform * cut
		check(area.global_position.distance_to(expected.origin) < 0.00001, "%s uses the imported surface position" % area.name)
		for axis: int in range(3):
			check(area.global_basis[axis].distance_to(expected.basis[axis]) < 0.00001, "%s preserves imported marker orientation" % area.name)
	check_eq(markers, 14, "all seven joints expose both endpoint markers")
	wreck.free()


## Every gold joint can be reached from outside using the cutter's actual ray layers.
func test_all_practice_cut_markers_have_an_external_approach() -> void:
	var wreck: SalvageWreck = _spawn(PracticeWreck.make_graph())
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for frame: int in range(3):
		await tree.physics_frame
		await tree.process_frame
	var body: WreckBody = wreck.bodies[0]
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var markers: int = 0
	for child: Node in body.get_children():
		if not child is Area3D:
			continue
		markers += 1
		var area: Area3D = child as Area3D
		var reachable: bool = false
		for elevation: int in range(-3, 4):
			if reachable:
				break
			for azimuth: int in range(16):
				var phi: float = float(elevation) * PI / 8.0
				var theta: float = float(azimuth) * TAU / 16.0
				var offset: Vector3 = Vector3(cos(phi) * cos(theta), sin(phi), cos(phi) * sin(theta)) * 7.5
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(area.global_position + offset, area.global_position, 3)
				query.collide_with_areas = true
				var hit: Dictionary = space.intersect_ray(query)
				if not hit.is_empty() and hit.collider == area:
					reachable = true
					break
		check(reachable, "%s has an unobstructed exterior approach within cutter range" % area.name)
	check_eq(markers, 14, "visibility audit checks every real cut endpoint")
	wreck.free()


## The four tool slots use distinct physical number keys in the shipped input map.
func test_tool_slots_are_bound_to_number_keys() -> void:
	for slot: int in range(1, 5):
		var action: String = "tool_slot_%d" % slot
		check(InputMap.has_action(action), "%s exists" % action)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = KEY_0 + slot
		event.pressed = true
		check(InputMap.event_is_action(event, action), "number %d selects its tool slot" % slot)
		for other: int in range(1, 5):
			if other != slot:
				check(not InputMap.event_is_action(event, "tool_slot_%d" % other), "number %d cannot select slot %d" % [slot, other])


func _spawn(graph: ShipGraph, pose: Transform3D = Transform3D.IDENTITY) -> SalvageWreck:
	var wreck: SalvageWreck = SalvageWreck.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(wreck)
	wreck.spawn(graph, pose)
	return wreck
