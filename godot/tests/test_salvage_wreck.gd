## Compound wrecks preserve structure, poses, momentum, and value during real splits.
extends TestCase


## A connected graph becomes one undamped body with a collision shape for each part.
func test_compound_spawn_owns_all_parts_and_mass() -> void:
	var graph: ShipGraph = _chain()
	var pose: Transform3D = Transform3D(Basis(Vector3(1.0, 2.0, 3.0).normalized(), 0.7), Vector3(20.0, 3.0, -5.0))
	var wreck: SalvageWreck = _spawn(graph, pose)
	check_eq(wreck.bodies.size(), 1, "connected parts spawn as one body")
	var body: WreckBody = wreck.bodies[0]
	check_eq(body.mass, 60.0, "compound mass sums all parts")
	check_eq(body.part_ids, PackedStringArray(["a", "b", "c"]), "compound retains all identifiers")
	check_eq(body.get_shape_owners().size(), 3, "one physical box per part")
	check_eq(body.center_of_mass, Vector3.ZERO, "body origin is its centre of mass")
	check(body.inertia.x > 0.0 and body.inertia.y > 0.0 and body.inertia.z > 0.0, "principal inertia is positive")
	check_eq(body.gravity_scale, 0.0, "wreck has zero gravity")
	check_eq(body.linear_damp, 0.0, "no linear damping")
	check_eq(body.angular_damp, 0.0, "no angular damping")
	check_eq(wreck.body_for_part("missing"), null, "unknown part has no body")
	for id: String in graph.part_ids():
		check_eq(wreck.body_for_part(id), body, "part maps to shared body")
		_check_pose(wreck.part_pose(id), pose * graph.get_part(id).transform, "part preserves supplied assembly pose")
	var shape_parts: PackedStringArray = []
	for index: int in range(3):
		shape_parts.append(body.part_at_shape(index))
	shape_parts.sort()
	check_eq(shape_parts, graph.part_ids(), "ray shape mapping identifies each part")
	check_eq(body.part_at_shape(-1), "", "negative ray shape returns no part")
	var markers: int = 0
	for child: Node in body.get_children():
		if child is Area3D:
			markers += 1
	check_eq(markers, 4, "each joint exposes both endpoint cut markers")
	wreck.spawn(_chain(), Transform3D.IDENTITY)
	check_eq(wreck.bodies.size(), 1, "spawn cannot duplicate an existing assembly")
	wreck.free()


## Cut duration scales with thickness and material, with a minimum working time.
func test_cut_progress_respects_thickness_material_and_minimum() -> void:
	var steel: SalvageWreck = _spawn(_chain())
	var thick: SalvageWreck = _spawn(_chain(), Transform3D(Basis.IDENTITY, Vector3(20.0, 0.0, 0.0)))
	var aluminium: SalvageWreck = _spawn(_chain(), Transform3D(Basis.IDENTITY, Vector3(40.0, 0.0, 0.0)))
	steel.graph.get_part("a").definition.thickness_mm = 8.0
	thick.graph.get_part("a").definition.thickness_mm = 16.0
	aluminium.graph.get_part("a").definition.thickness_mm = 8.0
	aluminium.graph.get_part("a").definition.material = "aluminium"
	check(not steel.cut("ab", 0.3, "a"), "partial steel cut remains connected")
	check(not thick.cut("ab", 0.3, "a"), "partial thick cut remains connected")
	check(not aluminium.cut("ab", 0.3, "a"), "partial aluminium cut remains connected")
	check_near(steel.cut_progress["ab"], 0.15, 0.000001, "8 mm steel needs two seconds")
	check_near(thick.cut_progress["ab"], 0.075, 0.000001, "doubling thickness halves progress")
	check_near(aluminium.cut_progress["ab"], 0.25, 0.000001, "aluminium needs 60 percent steel time")
	steel.graph.get_part("b").definition.thickness_mm = 0.01
	check(not steel.cut("bc", 0.2, "b"), "thin joint still takes working time")
	check_near(steel.cut_progress["bc"], 0.5, 0.000001, "minimum cut time is 0.4 seconds")
	steel.free()
	thick.free()
	aluminium.free()


## Invalid or competing cuts cannot spend progress or sever multiple joints at once.
func test_cut_rejects_invalid_and_pending_requests() -> void:
	var wreck: SalvageWreck = _spawn(_chain())
	for seconds: float in [0.0, -1.0, NAN, INF, -INF]:
		check(not wreck.cut("ab", seconds, "a"), "invalid cutting interval rejected")
	check(not wreck.cut("absent", 1.0, "a"), "unknown edge rejected")
	check(not wreck.cut("ab", 1.0, "c"), "unrelated part cannot cut joint")
	check_eq(wreck.cut_progress.size(), 0, "invalid work creates no progress")
	check(wreck.cut("ab", 100.0, "a"), "enough work queues a cut")
	check_eq(wreck.graph.edge_ids().size(), 2, "cut waits for safe deferred update")
	check(not wreck.cut("bc", 100.0, "b"), "pending structural update blocks competing cut")
	await wreck.structure_changed
	check_eq(wreck.graph.edge_ids(), PackedStringArray(["bc"]), "only requested joint severed")
	check_eq(wreck.bodies.size(), 2, "safe update creates two components")
	check(not wreck.cut("ab", 100.0, "a"), "severed joint cannot be cut twice")
	wreck.queue_free()
	await _frames(1)


## Closing a graph cycle holds all parts after a non-bridge edge has been cut.
func test_cycle_cut_keeps_one_compound_until_bridge_removed() -> void:
	var graph: ShipGraph = _chain()
	check(graph.connect_parts("ca", "c", "right", "a", "left"), "third mount closes cycle")
	var wreck: SalvageWreck = _spawn(graph)
	check(wreck.cut("ab", 100.0, "a"), "first cycle edge completes")
	await wreck.structure_changed
	check_eq(wreck.bodies.size(), 1, "remaining cycle path keeps one physical body")
	check_eq(wreck.bodies[0].mass, 60.0, "non-bridge cut preserves whole mass")
	check_eq(wreck.salvaged_value(), 0.0, "connected assembly does not count as freed salvage")
	check(wreck.cut("ca", 100.0, "a"), "second cut releases end part")
	await wreck.structure_changed
	check_eq(wreck.bodies.size(), 2, "bridge cut creates separate physical components")
	check_eq(wreck.body_for_part("a").part_ids, PackedStringArray(["a"]), "released part is independent")
	check_eq(wreck.body_for_part("b"), wreck.body_for_part("c"), "remaining pair stays connected")
	wreck.queue_free()
	await _frames(1)


## Separate panel fasteners must both be cut before the shared compound separates.
func test_parallel_mounts_do_not_release_panel_early() -> void:
	var graph: ShipGraph = _chain()
	check(graph.connect_parts("ab_second", "a", "left", "b", "top"), "extra fastener uses separate sockets")
	var wreck: SalvageWreck = _spawn(graph)
	check(wreck.cut("ab", 100.0, "a"), "first fastener cut")
	await wreck.structure_changed
	check_eq(wreck.bodies.size(), 1, "second fastener still carries panel")
	check(wreck.cut("ab_second", 100.0, "a"), "last fastener cut")
	await wreck.structure_changed
	check_eq(wreck.bodies.size(), 2, "last fastener releases panel")
	wreck.queue_free()
	await _frames(1)


## Repeated splitting preserves each mesh pose and the parent's local velocity field.
func test_repeated_spinning_splits_preserve_pose_and_momentum() -> void:
	var pose: Transform3D = Transform3D(Basis(Vector3(1.0, 2.0, -1.0).normalized(), 0.6), Vector3(15.0, 6.0, -2.0))
	var velocity: Vector3 = Vector3(0.6, -0.2, 0.1)
	var spin: Vector3 = Vector3(0.07, 0.12, -0.09)
	var wreck: SalvageWreck = _spawn(_chain(), pose, velocity, spin)
	await _frames(4)
	check(wreck.part_pose("a").origin.distance_to((pose * wreck.graph.get_part("a").transform).origin) > 0.001, "assembled wreck actually drifts and rotates")
	for edge_id: String in ["ab", "bc"]:
		var target: String = "a" if edge_id == "ab" else "b"
		var before: Dictionary = {}
		# Snapshot live motion at the actual replacement boundary, after queued
		# forces have integrated and immediately before the old body is removed.
		wreck.structure_changing.connect(func() -> void:
			var parent: WreckBody = wreck.body_for_part(target)
			before["ids"] = parent.part_ids.duplicate()
			before["center"] = parent.global_position
			before["linear"] = parent.linear_velocity
			before["spin"] = parent.angular_velocity
			before["momentum"] = _momentum(wreck)
			var poses: Dictionary[String, Transform3D] = {}
			for id: String in wreck.graph.part_ids():
				poses[id] = wreck.part_pose(id)
			before["poses"] = poses
		, CONNECT_ONE_SHOT)
		check(wreck.cut(edge_id, 100.0, target), "spinning split requested")
		await wreck.structure_changed
		check(not before.is_empty(), "live state captured immediately before replacement")
		_check_vector(_momentum(wreck), before.momentum, 0.0002, "split conserves total linear momentum")
		for id: String in wreck.graph.part_ids():
			_check_pose(wreck.part_pose(id), before.poses[id], "split preserves each part world pose")
		for body: WreckBody in wreck.bodies:
			if not before.ids.has(body.part_ids[0]):
				continue
			var parent_linear: Vector3 = before.linear
			var parent_spin: Vector3 = before.spin
			var parent_center: Vector3 = before.center
			var expected: Vector3 = parent_linear + parent_spin.cross(body.global_position - parent_center)
			_check_vector(body.linear_velocity, expected, 0.00001, "new centre inherits tangential velocity")
			_check_vector(body.angular_velocity, parent_spin, 0.00001, "fragment inherits parent spin")
		await _frames(4)
		_check_vector(_momentum(wreck), before.momentum, 0.0002, "isolated fragments retain total momentum after physics resumes")
	check_eq(wreck.bodies.size(), 3, "two cuts leave three independent parts")
	check_near(_mass(wreck), 60.0, 0.000001, "repeated splits preserve mass")
	wreck.queue_free()
	await _frames(1)


## The tally includes only single loose parts and reads current condition and integrity.
func test_salvaged_tally_counts_only_individual_parts() -> void:
	var graph: ShipGraph = _chain()
	graph.get_part("a").condition = 0.5
	graph.get_part("b").intact_factor = 0.25
	var wreck: SalvageWreck = _spawn(graph)
	check_eq(wreck.salvaged_value(), 0.0, "whole wreck starts uncounted")
	check(wreck.cut("ab", 100.0, "a"), "release first part")
	await wreck.structure_changed
	check_eq(wreck.salvaged_value(), 50.0, "only loose first part contributes its reduced value")
	check(wreck.cut("bc", 100.0, "b"), "release final pair")
	await wreck.structure_changed
	check_eq(wreck.salvaged_value(), 400.0, "all loose parts use condition and intact multipliers")
	graph.get_part("c").condition = 0.1
	check_eq(wreck.salvaged_value(), 130.0, "later damage reduces live tally without a sale")
	wreck.queue_free()
	await _frames(1)


## Harmless and invalid impacts do nothing; damage above threshold is bounded and cumulative.
func test_impact_damage_threshold_mass_scaling_and_bounds() -> void:
	var wreck: SalvageWreck = _spawn(_chain())
	var ids: PackedStringArray = wreck.graph.part_ids()
	for energy: float in [0.0, -1000.0, 1999.0, 2000.0, NAN, INF, -INF]:
		wreck.damage_component(ids, energy)
		check_eq(wreck.graph.get_part("a").condition, 1.0, "small or invalid impact cannot damage")
	wreck.damage_component(ids, 3800.0)
	for id: String in ids:
		check_near(wreck.graph.get_part(id).condition, 0.9, 0.000001, "excess energy spreads over component mass")
	wreck.damage_component(ids, 1e12)
	for id: String in ids:
		check_near(wreck.graph.get_part(id).condition, 0.4, 0.000001, "single impact loses at most half condition")
	wreck.damage_component(ids, 1e12)
	wreck.damage_component(ids, 1e12)
	for id: String in ids:
		check_eq(wreck.graph.get_part(id).condition, 0.0, "repeated damage reaches zero and never wraps or goes negative")
		check_eq(wreck.graph.get_part(id).salvage_value(), 0.0, "destroyed condition has no value")
	wreck.damage_component([], 10000.0)
	check_eq(wreck.graph.get_part("a").condition, 0.0, "empty component damage is harmless")
	wreck.free()


func _chain() -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	for index: int in range(3):
		var definition: PartDefinition = PartDefinition.new()
		definition.kind = "hull"
		definition.size_m = Vector3(0.7, 0.8, 0.9)
		definition.mass_kg = 10.0 * (index + 1)
		definition.value_cr = 100.0 * (index + 1)
		definition.thickness_mm = 8.0
		definition.sockets = {"left": Transform3D(Basis.IDENTITY, Vector3.LEFT * 0.35),
			"right": Transform3D(Basis.IDENTITY, Vector3.RIGHT * 0.35),
			"top": Transform3D(Basis.IDENTITY, Vector3.UP * 0.4)}
		var part: ShipPart = ShipPart.new()
		part.id = ["a", "b", "c"][index]
		part.definition = definition
		part.transform.origin = Vector3(float(index - 1) * 3.0, float(index % 2), 0.0)
		graph.add_part(part)
	graph.connect_parts("ab", "a", "right", "b", "left")
	graph.connect_parts("bc", "b", "right", "c", "left")
	return graph


func _spawn(graph: ShipGraph, pose: Transform3D = Transform3D.IDENTITY,
		velocity: Vector3 = Vector3.ZERO, spin: Vector3 = Vector3.ZERO) -> SalvageWreck:
	var wreck: SalvageWreck = SalvageWreck.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(wreck)
	wreck.spawn(graph, pose, velocity, spin)
	return wreck


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame


func _momentum(wreck: SalvageWreck) -> Vector3:
	var momentum: Vector3 = Vector3.ZERO
	for body: WreckBody in wreck.bodies:
		momentum += body.mass * body.linear_velocity
	return momentum


func _mass(wreck: SalvageWreck) -> float:
	var mass: float = 0.0
	for body: WreckBody in wreck.bodies:
		mass += body.mass
	return mass


func _check_pose(actual: Transform3D, expected: Transform3D, message: String) -> void:
	_check_vector(actual.origin, expected.origin, 0.00005, message + " origin")
	for axis: int in range(3):
		_check_vector(actual.basis[axis], expected.basis[axis], 0.00001, message + " axis")


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s, got %s" % [message, expected, actual])
