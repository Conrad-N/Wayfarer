## Salvage-side save data: ShipGraph/ShipPart, EncounterStore records and CargoHold
## all round-trip through SaveCodec's full JSON encode/decode and rebuild the same
## structure, state and mass they started with.
extends TestCase


## A practice wreck with a cut, damage and a scan survives to_save -> stringify ->
## parse -> from_save with the same parts, edges, components and component masses.
func test_ship_graph_round_trip_through_json() -> void:
	var graph: ShipGraph = PracticeWreck.make_graph()
	if graph.part_ids().is_empty():
		check(false, "practice wreck fixture failed to load; see test_practice_wreck.gd")
		return
	check(graph.sever_edge("Joint_Fuel"), "fuel mount cut before saving")
	graph.get_part("Antenna").scanned = true
	graph.get_part("Shield").condition = 0.4
	graph.get_part("Shield").intact_factor = 0.75
	var before_components: Array[PackedStringArray] = graph.components()
	var before_masses: Dictionary = _component_masses(graph, before_components)

	var decoded: Dictionary = SaveCodec.parse(SaveCodec.stringify(graph.to_save()))
	var restored: ShipGraph = ShipGraph.from_save(decoded)

	check_eq(restored.part_ids(), graph.part_ids(), "same parts after round trip")
	check_eq(restored.edge_ids(), graph.edge_ids(), "same surviving edges after round trip")
	var after_components: Array[PackedStringArray] = restored.components()
	check_eq(after_components.size(), before_components.size(), "same component count")
	for index: int in mini(after_components.size(), before_components.size()):
		check_eq(after_components[index], before_components[index], "identical component membership and order")
	var after_masses: Dictionary = _component_masses(restored, after_components)
	for key: String in before_masses:
		check_near(float(after_masses.get(key, -1.0)), float(before_masses[key]), 0.0001, "component mass preserved: %s" % key)
	check(restored.get_part("Antenna").scanned, "scan state preserved")
	check_near(restored.get_part("Shield").condition, 0.4, 1e-6, "condition preserved")
	check_near(restored.get_part("Shield").intact_factor, 0.75, 1e-6, "intact factor preserved")
	check(restored.get_part("Nose").definition == graph.get_part("Nose").definition, "shared catalog definition reused, not duplicated")
	check(restored.get_part("Spine").transform.is_equal_approx(graph.get_part("Spine").transform), "assembly transform preserved")
	var edge: Dictionary = restored.get_edge(restored.edge_ids()[0])
	check(edge.has("a") and edge.has("b") and edge.has("socket_a") and edge.has("socket_b"), "restored edge keeps both endpoint sockets")


## capture() only reads live wreck-body state and writes into session-owned
## dictionaries; it never frees, moves or otherwise touches the live bodies.
func test_capture_does_not_disturb_live_wreck_bodies() -> void:
	var session: OrbitalSession = OrbitalSession.new()
	session.start_session()
	var scene: Node3D = Node3D.new()
	_tree().root.add_child(scene)
	var wreck: SalvageWreck = SalvageWreck.new()
	var hazards: SalvageHazards = SalvageHazards.new()
	scene.add_child(wreck)
	scene.add_child(hazards)
	var graph: ShipGraph = PracticeWreck.make_graph()
	wreck.spawn(graph, Transform3D(Basis(Vector3.UP, 0.2), Vector3(50.0, 2.0, -4.0)))
	hazards.configure(wreck)
	await _steps(3)
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	var reference: Dictionary = session.object_state("kestrel", session.world.time)
	frame.set_reference(reference.position, reference.velocity)
	var body_before: Array[WreckBody] = wreck.bodies.duplicate()
	var instance_ids_before: Array[int] = []
	var poses_before: Array[Transform3D] = []
	for body: WreckBody in body_before:
		instance_ids_before.append(body.get_instance_id())
		poses_before.append(body.global_transform)
	EncounterStore.capture(session, "kestrel", frame, wreck, hazards)
	check_eq(wreck.bodies.size(), body_before.size(), "capture leaves the same live bodies in place")
	for index: int in body_before.size():
		check(is_instance_valid(body_before[index]), "capture does not free a live body")
		check_eq(body_before[index].get_instance_id(), instance_ids_before[index], "capture does not replace a live body")
		check(body_before[index].global_transform.is_equal_approx(poses_before[index]), "capture does not move a live body")
		check(body_before[index].is_inside_tree(), "capture leaves live bodies attached to the scene")
	scene.free()
	session.free()


## A decoded encounter record round-trips and EncounterStore.restore rebuilds the
## same fragments, cut progress, part state and spent reservoirs from it.
func test_encounter_record_round_trip_restores_fragments() -> void:
	var session: OrbitalSession = OrbitalSession.new()
	session.start_session()
	var scene: Node3D = Node3D.new()
	_tree().root.add_child(scene)
	var wreck: SalvageWreck = SalvageWreck.new()
	var hazards: SalvageHazards = SalvageHazards.new()
	scene.add_child(wreck)
	scene.add_child(hazards)
	var graph: ShipGraph = PracticeWreck.make_graph()
	if graph.part_ids().is_empty():
		check(false, "practice wreck fixture failed to load; see test_practice_wreck.gd")
		scene.free()
		session.free()
		return
	check(graph.sever_edge("Joint_Fuel"), "fuel mount cut before spawn produces two loose fragments")
	graph.get_part("Antenna").scanned = true
	graph.get_part("Shield").condition = 0.4
	wreck.spawn(graph, Transform3D(Basis(Vector3.UP, 0.2), Vector3(50.0, 2.0, -4.0)))
	hazards.configure(wreck)
	hazards.restore_spent_reservoirs({"Fuel": ["fuel"]})
	await _steps(3)
	check_eq(wreck.bodies.size(), 2, "severed fuel tank spawns as its own fragment")
	wreck.cut_progress["Joint_Shield"] = 0.35
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	var reference: Dictionary = session.object_state("kestrel", session.world.time)
	frame.set_reference(reference.position, reference.velocity)
	EncounterStore.capture(session, "kestrel", frame, wreck, hazards)
	var record: Dictionary = session.encounters.kestrel

	var decoded: Dictionary = SaveCodec.parse(SaveCodec.stringify(EncounterStore.record_to_save(record)))
	var restored_record: Dictionary = EncounterStore.record_from_save(decoded)
	check_eq((restored_record.fragments as Array).size(), (record.fragments as Array).size(), "fragment count survives the round trip")
	check_eq((restored_record.graph as ShipGraph).part_ids(), graph.part_ids(), "decoded graph keeps every part")
	check_eq((restored_record.graph as ShipGraph).edge_ids(), graph.edge_ids(), "decoded graph keeps every surviving edge")
	session.encounters["kestrel_decoded"] = restored_record

	var restored: SalvageWreck = SalvageWreck.new()
	var restored_hazards: SalvageHazards = SalvageHazards.new()
	scene.add_child(restored)
	scene.add_child(restored_hazards)
	restored_hazards.configure(restored)
	EncounterStore.restore(session, "kestrel_decoded", frame, restored, restored_hazards)
	check_eq(restored.bodies.size(), 2, "decoded record still restores both fragments")
	check(restored.body_for_part("Fuel") != null, "decoded record restores the severed tank as its own body")
	check(restored.body_for_part("Fuel") != restored.body_for_part("Spine"), "decoded record keeps the cut apart")
	check(restored.graph.get_part("Antenna").scanned, "decoded record preserves scan state")
	check_near(restored.graph.get_part("Shield").condition, 0.4, 1e-6, "decoded record preserves condition")
	check_near(float(restored.cut_progress.get("Joint_Shield", 0.0)), 0.35, 1e-9, "decoded record preserves cut progress")
	check(restored_hazards.was_triggered("Fuel"), "decoded record preserves spent reservoir history")
	for body: WreckBody in restored.bodies:
		var expected_mass: float = 0.0
		for id: String in body.part_ids:
			expected_mass += restored.graph.get_part(id).definition.mass_kg
		check_near(body.mass, expected_mass, 0.01, "restored fragment mass matches its parts' definitions")
	for body: WreckBody in restored.bodies:
		var id: String = "kestrel/" + "+".join(body.part_ids)
		var expected: Dictionary = session.object_state(id, session.world.time)
		check_near(body.global_position.distance_to(frame.to_local_position(expected.position)), 0.0, 1e-3, "decoded record restores fragment position")
	scene.free()
	session.free()


## Secured cargo round-trips: manifest entry, mass frame, part state and geometry.
func test_cargo_hold_round_trip_rebuilds_manifest_and_geometry() -> void:
	var root: Node3D = Node3D.new()
	_tree().root.add_child(root)
	var fixture: Dictionary = _cargo_fixture(root)
	var ship: PlayerShip = fixture.ship
	var wreck: SalvageWreck = fixture.wreck
	var hold: CargoHold = fixture.hold
	wreck.graph.get_part("cargo_a").condition = 0.55
	wreck.graph.get_part("cargo_a").scanned = true
	var body: WreckBody = wreck.bodies[0]
	ship.api.set_cargo_door(true)
	hold._secure(body, hold.bounds_in_bay(body))
	await _steps(1)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "fixture secures one cargo item")
	var before_mass_kg: float = float(ship.api.get_telemetry().cargo_mass_kg)
	var before_center: Vector3 = ship.center_of_mass
	var before_inertia: Vector3 = ship.inertia
	var before_transforms: Array[Transform3D] = _tagged_transforms(ship)
	check(before_transforms.size() > 0, "securing added at least one tagged geometry node")

	var decoded: Dictionary = SaveCodec.parse(SaveCodec.stringify(hold.to_save()))
	var decoded_api: Dictionary = SaveCodec.parse(SaveCodec.stringify(ship.api.to_save()))

	var root2: Node3D = Node3D.new()
	_tree().root.add_child(root2)
	var fixture2: Dictionary = _cargo_fixture(root2)
	var ship2: PlayerShip = fixture2.ship
	var hold2: CargoHold = fixture2.hold
	# The manifest returns with the ship's own save, in the same order as a game load.
	ship2.api.apply_save(decoded_api)
	ship2.api.set_cargo_door(false)
	hold2.apply_save(decoded)
	check(not bool(ship2.api.get_telemetry().cargo_door_open), "cargo comes back with the door shut")
	var telemetry: Dictionary = ship2.api.get_telemetry()
	check_eq(telemetry.cargo_manifest.size(), 1, "decoded save restores the manifest entry")
	check_near(float(telemetry.cargo_mass_kg), before_mass_kg, 0.001, "restored manifest mass matches original cargo mass")
	check_near(ship2.center_of_mass.distance_to(before_center), 0.0, 0.0001, "restored centre of mass matches")
	check_near((ship2.inertia - before_inertia).length(), 0.0, 0.0001, "restored inertia matches")
	var after_transforms: Array[Transform3D] = _tagged_transforms(ship2)
	check_eq(after_transforms.size(), before_transforms.size(), "restored cargo produces the same number of tagged geometry nodes")
	for pose: Transform3D in before_transforms:
		check(_has_close_transform(after_transforms, pose, 0.0001), "restored geometry keeps an original mesh/collision placement")
	var restored_save: Dictionary = (hold2._cargo["cargo_a"] as Dictionary).part_saves["cargo_a"]
	check_near(float(restored_save.condition), 0.55, 1e-6, "restored cargo part keeps condition")
	check(bool(restored_save.scanned), "restored cargo part keeps scan state")
	root.free()
	root2.free()


func _component_masses(graph: ShipGraph, components: Array[PackedStringArray]) -> Dictionary:
	var result: Dictionary = {}
	for component: PackedStringArray in components:
		var key: String = "+".join(component)
		var mass: float = 0.0
		for id: String in component:
			mass += graph.get_part(id).definition.mass_kg
		result[key] = mass
	return result


func _cargo_fixture(root: Node3D) -> Dictionary:
	var ship: PlayerShip = load("res://scenes/player_ship.tscn").instantiate() as PlayerShip
	root.add_child(ship)
	var graph: ShipGraph = ShipGraph.new()
	var part: ShipPart = ShipPart.new()
	part.id = "cargo_a"
	part.definition = PartCatalog.definition("plating_panel_a")
	graph.add_part(part)
	var wreck: SalvageWreck = SalvageWreck.new()
	root.add_child(wreck)
	wreck.spawn(graph, Transform3D(Basis.IDENTITY, Vector3(0, 0, -8.5)))
	var hazards: SalvageHazards = SalvageHazards.new()
	root.add_child(hazards)
	hazards.configure(wreck)
	hazards.set_physics_process(false)
	var hold: CargoHold = CargoHold.new()
	root.add_child(hold)
	hold.configure(ship, wreck, hazards)
	hold.set_physics_process(false)
	return {"ship": ship, "wreck": wreck, "hazards": hazards, "hold": hold}


func _tagged_transforms(ship: PlayerShip) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for child: Node in ship.get_children():
		if child is Node3D and child.has_meta("system_id") and str(child.get_meta("system_id")) == "cargo":
			result.append((child as Node3D).transform)
	return result


func _has_close_transform(list: Array[Transform3D], target: Transform3D, tol: float) -> bool:
	for candidate: Transform3D in list:
		if candidate.origin.distance_to(target.origin) <= tol and candidate.basis.is_equal_approx(target.basis):
			return true
	return false


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _steps(count: int) -> void:
	for _index: int in range(count):
		await _tree().physics_frame
