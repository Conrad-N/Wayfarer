## Graph connectivity, socket validation, and salvage value remain pure data rules.
extends TestCase


## Empty graphs and isolated parts produce stable, independent component lists.
func test_empty_and_isolated_components() -> void:
	var graph: ShipGraph = ShipGraph.new()
	check_eq(graph.components().size(), 0, "empty graph has no components")
	check_eq(graph.part_ids().size(), 0, "empty graph has no parts")
	check_eq(graph.edge_ids().size(), 0, "empty graph has no edges")
	check_eq(graph.get_part("missing"), null, "unknown part is absent")
	check_eq(graph.get_edge("missing"), {}, "unknown edge is absent")
	for id: String in ["c", "a", "b"]:
		check(graph.add_part(_part(id)), "isolated part added")
	check_eq(graph.part_ids(), PackedStringArray(["a", "b", "c"]), "IDs sorted")
	_check_components(graph, [["a"], ["b"], ["c"]])
	var ids: PackedStringArray = graph.part_ids()
	ids.append("outsider")
	var groups: Array[PackedStringArray] = graph.components()
	groups[0].append("outsider")
	check_eq(graph.part_ids().size(), 3, "ID copies cannot mutate graph")
	_check_components(graph, [["a"], ["b"], ["c"]])


## Cutting a chain separates precisely the branches reachable without that edge.
func test_chain_split_and_reconnect() -> void:
	var graph: ShipGraph = _graph(["d", "c", "b", "a"])
	check(graph.connect_parts("ab", "a", "front", "b", "aft"), "first link")
	check(graph.connect_parts("bc", "b", "front", "c", "aft"), "second link")
	check(graph.connect_parts("cd", "c", "front", "d", "aft"), "third link")
	_check_components(graph, [["a", "b", "c", "d"]])
	check(graph.sever_edge("bc"), "middle cut succeeds")
	_check_components(graph, [["a", "b"], ["c", "d"]])
	check(not graph.sever_edge("bc"), "repeated cut does not succeed twice")
	check(not graph.sever_edge("unknown"), "unknown cut is safe")
	check_eq(graph.edge_ids(), PackedStringArray(["ab", "cd"]), "cut removed only its own edge")
	check(graph.connect_parts("bc", "b", "front", "c", "aft"), "severed sockets are reusable")
	_check_components(graph, [["a", "b", "c", "d"]])


## A closed cycle stays connected after one cut, then separates after a second.
func test_cycle_needs_more_than_one_cut() -> void:
	var graph: ShipGraph = _graph(["c", "b", "a"])
	check(graph.connect_parts("ab", "a", "front", "b", "aft"), "cycle link AB")
	check(graph.connect_parts("bc", "b", "front", "c", "aft"), "cycle link BC")
	check(graph.connect_parts("ca", "c", "front", "a", "aft"), "cycle link CA")
	check(graph.sever_edge("ab"), "first cycle cut")
	_check_components(graph, [["a", "b", "c"]])
	check(graph.sever_edge("ca"), "second cycle cut")
	_check_components(graph, [["a"], ["b", "c"]])


## Two separate fasteners hold a panel until both sockets are severed.
func test_parallel_mounts_require_last_cut() -> void:
	var graph: ShipGraph = _graph(["hull", "panel"])
	check(graph.connect_parts("mount_1", "hull", "front", "panel", "aft"), "first mount")
	check(graph.connect_parts("mount_2", "panel", "front", "hull", "aft"), "second independent mount")
	check(graph.sever_edge("mount_1"), "first mount cut")
	_check_components(graph, [["hull", "panel"]])
	check(graph.sever_edge("mount_2"), "last mount cut")
	_check_components(graph, [["hull"], ["panel"]])


## Edges cannot reuse IDs, missing parts, missing sockets, or occupied endpoints.
func test_invalid_connections_do_not_change_graph() -> void:
	var graph: ShipGraph = _graph(["a", "b", "c"])
	check(not graph.connect_parts(" ", "a", "front", "b", "aft"), "blank edge ID rejected")
	check(not graph.connect_parts("self", "a", "front", "a", "aft"), "self connection rejected")
	check(not graph.connect_parts("missing", "a", "front", "absent", "aft"), "missing part rejected")
	check(not graph.connect_parts("missing", "absent", "front", "a", "aft"), "missing first part rejected")
	check(not graph.connect_parts("socket", "a", "absent", "b", "aft"), "unknown first socket rejected")
	check(not graph.connect_parts("socket", "a", "front", "b", "absent"), "unknown second socket rejected")
	check(graph.connect_parts("ab", "a", "front", "b", "aft"), "valid edge survives invalid attempts")
	check(not graph.connect_parts("ab", "b", "front", "c", "aft"), "duplicate edge ID rejected")
	check(not graph.connect_parts("again", "a", "front", "b", "aft"), "duplicate endpoint pair rejected")
	check(not graph.connect_parts("reverse", "b", "aft", "a", "front"), "reverse duplicate rejected")
	check(not graph.connect_parts("occupied", "c", "front", "a", "front"), "occupied socket at second endpoint rejected")
	check(not graph.connect_parts("occupied", "b", "aft", "c", "aft"), "occupied socket at first endpoint rejected")
	check_eq(graph.edge_ids(), PackedStringArray(["ab"]), "failed connects are atomic")
	_check_components(graph, [["a", "b"], ["c"]])


## Explicit socket size suffixes must agree; absent suffixes mean medium.
func test_socket_size_matching() -> void:
	var graph: ShipGraph = _graph(["a", "b", "c", "d", "e", "f"])
	check(graph.connect_parts("medium", "a", "front", "b", "medium_M"), "implicit M matches explicit M")
	check(graph.connect_parts("small", "c", "small_S", "d", "small_S"), "small matches small")
	check(graph.connect_parts("large", "e", "large_L", "f", "large_L"), "large matches large")
	check(not graph.connect_parts("mismatch", "a", "small_S", "b", "large_L"), "small does not match large")
	check(not graph.connect_parts("mismatch", "a", "aft", "b", "small_S"), "implicit medium does not match small")
	check_eq(graph.edge_ids(), PackedStringArray(["large", "medium", "small"]), "only compatible edges retained")


## Part admission rejects missing or corrupted state without replacing existing parts.
func test_part_validation_and_live_state() -> void:
	var graph: ShipGraph = ShipGraph.new()
	check(not graph.add_part(null), "null part rejected")
	check(not graph.add_part(ShipPart.new()), "empty part rejected")
	check(not graph.add_part(_part(" \t")), "blank ID rejected")
	var original: ShipPart = _part("a")
	check(graph.add_part(original), "valid part admitted")
	check(not graph.add_part(_part("a")), "duplicate ID rejected")
	check_eq(graph.get_part("a"), original, "original object retained")
	original.condition = 0.4
	check_eq(graph.get_part("a").condition, 0.4, "condition is live state")
	var invalid: ShipPart = _part("invalid")
	invalid.transform.origin.x = INF
	check(not graph.add_part(invalid), "nonfinite placement rejected")
	invalid.transform = Transform3D(Basis.from_scale(Vector3(2.0, 1.0, 1.0)), Vector3.ZERO)
	check(not graph.add_part(invalid), "scaled physical part rejected")
	invalid.transform = Transform3D.IDENTITY
	invalid.definition = null
	check(not graph.add_part(invalid), "missing definition rejected")
	check(graph.add_part(_part("b")), "second valid part admitted")
	original.definition.mass_kg = NAN
	check(not graph.connect_parts("bad", "a", "front", "b", "aft"), "invalidated definition cannot be connected")
	original.definition.mass_kg = 10.0
	original.id = "renamed"
	check(not graph.connect_parts("bad", "a", "front", "b", "aft"), "mutated identity cannot be connected under old key")
	check_eq(graph.edge_ids().size(), 0, "corrupt connection attempts leave no edges")


## Definitions enforce finite SI properties and marker shapes before physical use.
func test_definition_numeric_validation() -> void:
	var definition: PartDefinition = _part("test").definition
	check(definition.is_valid(), "fixture definition is valid")
	for property: String in ["mass_kg", "thickness_mm"]:
		for invalid: float in [0.0, -1.0, NAN, INF, -INF]:
			definition.set(property, invalid)
			check(not definition.is_valid(), "%s rejects nonpositive/nonfinite data" % property)
		definition.set(property, 1.0)
	for property: String in ["value_cr", "volume_m3"]:
		for invalid: float in [-1.0, NAN, INF, -INF]:
			definition.set(property, invalid)
			check(not definition.is_valid(), "%s rejects negative/nonfinite data" % property)
		definition.set(property, 0.0)
		check(definition.is_valid(), "%s permits zero" % property)
	for size: Vector3 in [Vector3.ZERO, Vector3(-1.0, 1.0, 1.0), Vector3(1.0, INF, 1.0)]:
		definition.size_m = size
		check(not definition.is_valid(), "invalid dimensions rejected")
	definition.size_m = Vector3.ONE
	definition.kind = ""
	check(not definition.is_valid(), "missing kind rejected")
	definition.kind = "hull"
	definition.material = " "
	check(not definition.is_valid(), "missing material rejected")


## Marker maps accept rotations and positions, but never invalid names or transforms.
func test_definition_marker_validation() -> void:
	var definition: PartDefinition = _part("test").definition
	var marker: Transform3D = Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(1.0, 2.0, 3.0))
	definition.sockets = {"front": marker}
	definition.cut_points = {"front": marker}
	definition.hazards = [{"kind": "coolant", "transform": marker}]
	check(definition.is_valid(), "rotated local markers are valid")
	for invalid: Dictionary in [{"": marker}, {1: marker}, {"front": Vector3.ZERO}, {"front": Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)}]:
		definition.sockets = invalid
		check(not definition.is_valid(), "malformed sockets rejected")
	definition.sockets = {"front": marker}
	definition.cut_points = {"cut": 5}
	check(not definition.is_valid(), "malformed cut rejected")
	definition.cut_points = {}
	for hazard: Dictionary in [{}, {"kind": "unknown", "transform": marker}, {"kind": "fuel", "transform": Vector3.ZERO}, {"kind": 5, "transform": marker}]:
		definition.hazards = [hazard]
		check(not definition.is_valid(), "malformed hazard rejected")
	for kind: String in ["fuel", "coolant", "pressure", "power"]:
		definition.hazards = [{"kind": kind, "transform": marker}]
		check(definition.is_valid(), "documented hazard kind is valid")


## Edge lookup returns a snapshot so consumers cannot bypass connectivity checks.
func test_edge_snapshot_and_deterministic_order() -> void:
	var first: ShipGraph = _graph(["c", "a", "b"])
	var second: ShipGraph = _graph(["b", "c", "a"])
	check(first.connect_parts("z", "a", "front", "b", "aft"), "first graph edge Z")
	check(first.connect_parts("a", "b", "front", "c", "aft"), "first graph edge A")
	check(second.connect_parts("a", "b", "front", "c", "aft"), "second graph edge A")
	check(second.connect_parts("z", "a", "front", "b", "aft"), "second graph edge Z")
	check_eq(first.part_ids(), second.part_ids(), "part order independent of insertion")
	check_eq(first.edge_ids(), second.edge_ids(), "edge order independent of insertion")
	check_eq(first.components(), second.components(), "component order independent of insertion")
	check_eq(first.get_edge("z"), {"a": "a", "b": "b", "socket_a": "front", "socket_b": "aft"}, "connection records both endpoint sockets")
	var edge: Dictionary = first.get_edge("z")
	edge["a"] = "invalid"
	check_eq(first.get_edge("z")["a"], "a", "edge copy does not mutate stored connection")


## Damage and broken material multiply value; bad assignments cannot create credits.
func test_salvage_value_and_clamped_state() -> void:
	var part: ShipPart = _part("valuable")
	part.definition.value_cr = 1000.0
	check_eq(part.salvage_value(), 1000.0, "undamaged value")
	check(not part.scanned, "unknown part starts unscanned")
	part.condition = 0.8
	part.intact_factor = 0.25
	check_eq(part.salvage_value(), 200.0, "condition and intact factor both multiply value")
	part.condition = 8.0
	part.intact_factor = 4.0
	check_eq(part.condition, 1.0, "condition upper bound")
	check_eq(part.intact_factor, 1.0, "intact upper bound")
	for invalid: float in [-1.0, INF, -INF, NAN]:
		part.condition = invalid
		part.intact_factor = invalid
		check_eq(part.condition, 0.0, "invalid condition becomes worthless")
		check_eq(part.intact_factor, 0.0, "invalid intact factor becomes worthless")
		check_eq(part.salvage_value(), 0.0, "invalid state cannot create value")
	part.condition = 1.0
	part.intact_factor = 1.0
	for invalid: float in [-1.0, INF, NAN]:
		part.definition.value_cr = invalid
		check_eq(part.salvage_value(), 0.0, "bad base value fails soft")
	part.definition = null
	check_eq(part.salvage_value(), 0.0, "undefined part has no value")


func _part(id: String) -> ShipPart:
	var definition: PartDefinition = PartDefinition.new()
	definition.kind = "hull"
	definition.mass_kg = 10.0
	definition.sockets = {"front": Transform3D.IDENTITY, "aft": Transform3D.IDENTITY,
		"small_S": Transform3D.IDENTITY, "medium_M": Transform3D.IDENTITY, "large_L": Transform3D.IDENTITY}
	var part: ShipPart = ShipPart.new()
	part.id = id
	part.definition = definition
	return part


func _graph(ids: PackedStringArray) -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	for id: String in ids:
		graph.add_part(_part(id))
	return graph


func _check_components(graph: ShipGraph, expected: Array) -> void:
	var actual: Array[PackedStringArray] = graph.components()
	check_eq(actual.size(), expected.size(), "component count")
	for index: int in mini(actual.size(), expected.size()):
		check_eq(actual[index], PackedStringArray(expected[index]), "component membership and order")
