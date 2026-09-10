## Leave/revisit persistence of physical wreck components, cuts, scanning and finite reservoirs.
extends TestCase


## Captured components keep individual orbits and damage; secured parts never respawn from graph data.
func test_cut_wreck_survives_leave_and_revisit() -> void:
	var session: OrbitalSession = OrbitalSession.new()
	session.start_session()
	var scene: Node3D = Node3D.new()
	_tree().root.add_child(scene)
	var wreck: SalvageWreck = SalvageWreck.new()
	var hazards: SalvageHazards = SalvageHazards.new()
	scene.add_child(wreck)
	scene.add_child(hazards)
	var graph: ShipGraph = _graph()
	wreck.spawn(graph, Transform3D(Basis(Vector3.UP, 0.4), Vector3(100.0, 5.0, -8.0)))
	hazards.configure(wreck)
	await _steps(3)
	check(wreck.cut("hull_tank", 10.0, "hull"), "actual cutter queues severing")
	await wreck.structure_changed
	check_eq(wreck.bodies.size(), 3, "cut yields two loose groups plus cargo")
	check(not wreck.cut("tank_panel", 0.05, "tank"), "remaining cut incomplete")
	var progress: float = wreck.cut_progress.tank_panel
	check(progress > 0.0 and progress < 1.0, "partial cutting accumulated")
	graph.get_part("tank").scanned = true
	graph.get_part("panel").condition = 0.62
	graph.get_part("panel").intact_factor = 0.7
	check(hazards.trigger("tank"), "fuel reservoir ruptures before departure")
	# The hazard budget uses explicit simulation seconds. Drain it before taking
	# the departure snapshot; no continued venting is allowed during orbital warp.
	hazards._physics_process(SalvageHazards.FUEL_DURATION_S)
	check_eq(hazards.active_count(), 0, "finite fuel depleted before leaving")
	var cargo: WreckBody = wreck.body_for_part("cargo")
	wreck.bodies.erase(cargo)
	cargo.free()
	await _steps(2)
	var hull: WreckBody = wreck.body_for_part("hull")
	var tank: WreckBody = wreck.body_for_part("tank")
	hull.linear_velocity = Vector3(1.5, -0.25, 0.5)
	tank.linear_velocity = Vector3(-0.75, 0.5, -0.1)
	hull.angular_velocity = Vector3(0.0, 0.1, 0.0)
	tank.angular_velocity = Vector3(0.0, 0.0, -0.07)
	await _steps(3)
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	var reference: Dictionary = session.object_state("kestrel", session.world.time)
	frame.set_reference(reference.position, reference.velocity)
	var departure: Dictionary = {}
	for body: WreckBody in wreck.bodies:
		var key: String = "kestrel/" + "+".join(body.part_ids)
		departure[key] = {"position": frame.to_orbital_position(body.global_position), "velocity": frame.to_orbital_velocity(body.linear_velocity), "spin": body.angular_velocity, "basis": body.global_basis}
	EncounterStore.capture(session, "kestrel", frame, wreck, hazards)
	check_eq(session.encounters.kestrel.fragments.size(), 2, "only physically loose components captured")
	check_eq(session.encounters.kestrel.graph.edge_ids(), PackedStringArray(["tank_panel"]), "severed graph edge stays severed")
	for id: String in departure:
		var stored: Dictionary = session.object_state(id, session.world.time)
		check_near(SimVector.distance(stored.position, departure[id].position), 0.0, 1e-3, "stored fragment orbital position")
		check_near(SimVector.distance(stored.velocity, departure[id].velocity), 0.0, 1e-6, "stored fragment orbital velocity")
	var initial_gap: float = SimVector.distance(departure["kestrel/hull"].position, departure["kestrel/panel+tank"].position)
	wreck.free()
	hazards.free()
	session.world.time += 120.0
	reference = session.object_state("kestrel", session.world.time)
	frame.set_reference(reference.position, reference.velocity)
	frame.shift = SimVector.new(2048.0, -128.0, 64.0)
	var expected_hull: Dictionary = session.object_state("kestrel/hull", session.world.time)
	var expected_tank: Dictionary = session.object_state("kestrel/panel+tank", session.world.time)
	check(absf(SimVector.distance(expected_hull.position, expected_tank.position) - initial_gap) > 50.0, "fragments coast on different individual orbits")
	var restored: SalvageWreck = SalvageWreck.new()
	restored.position = Vector3(300.0, 200.0, -100.0)
	var restored_hazards: SalvageHazards = SalvageHazards.new()
	scene.add_child(restored)
	scene.add_child(restored_hazards)
	restored_hazards.configure(restored)
	EncounterStore.restore(session, "kestrel", frame, restored, restored_hazards)
	check_eq(restored.bodies.size(), 2, "revisit recreates two surviving components")
	check(restored.body_for_part("cargo") == null, "secured cargo stays absent despite retained graph definition")
	check(restored.body_for_part("tank") == restored.body_for_part("panel"), "uncut connection stays rigid")
	check(restored.body_for_part("hull") != restored.body_for_part("tank"), "cut components stay separate")
	check_near(restored.cut_progress.tank_panel, progress, 1e-12, "partial cut preserved")
	check(restored.graph.get_part("tank").scanned, "scanner discovery preserved")
	check_near(restored.graph.get_part("tank").condition, 0.75, 1e-6, "fuel rupture damage preserved once")
	check_near(restored.graph.get_part("panel").condition, 0.62, 1e-6, "impact condition preserved")
	check_near(restored.graph.get_part("panel").intact_factor, 0.7, 1e-6, "intact value factor preserved")
	check(restored_hazards.was_triggered("tank"), "spent fuel reservoir history restored")
	check(not restored_hazards.trigger("tank"), "revisit cannot refill spent fuel")
	for body: WreckBody in restored.bodies:
		var id: String = "kestrel/" + "+".join(body.part_ids)
		var expected: Dictionary = session.object_state(id, session.world.time)
		check(body.top_level, "restored physics component remains an independent root")
		check_near(body.global_position.distance_to(frame.to_local_position(expected.position)), 0.0, 1e-4, "propagated position restored in shifted local frame")
		check_near(body.linear_velocity.distance_to(frame.to_local_velocity(expected.velocity)), 0.0, 1e-6, "propagated relative velocity restored")
		check_near(body.angular_velocity.distance_to(departure[id].spin), 0.0, 1e-6, "fragment spin preserved")
		var spin: Vector3 = departure[id].spin
		var expected_basis: Basis = Basis(spin.normalized(), fmod(spin.length() * 120.0, TAU)) * Basis(departure[id].basis)
		check_near(body.global_basis.x.distance_to(expected_basis.x), 0.0, 1e-5, "fragment orientation advances while absent")
	EncounterStore.restore(session, "kestrel", frame, restored, restored_hazards)
	check_eq(restored.bodies.size(), 2, "repeated restore cannot duplicate salvage")
	await _steps(3)
	check(restored.body_for_part("hull").global_position.distance_to(frame.to_local_position(expected_hull.position)) < 1.0, "Jolt respects restored world pose under a translated organizational parent")
	# A second leave/revisit exercises persistent edits to the already restored graph.
	restored.graph.get_part("panel").condition = 0.5
	EncounterStore.capture(session, "kestrel", frame, restored, restored_hazards)
	check_near(session.encounters.kestrel.graph.get_part("panel").condition, 0.5, 1e-6, "later salvage damage updates the saved encounter")
	scene.free()
	session.free()


## A fresh encounter instantiates its graph only once at the reference's current floating origin.
func test_first_visit_reference_and_empty_survivors() -> void:
	var session: OrbitalSession = OrbitalSession.new()
	session.start_session()
	var scene: Node3D = Node3D.new()
	_tree().root.add_child(scene)
	var wreck: SalvageWreck = SalvageWreck.new()
	var hazards: SalvageHazards = SalvageHazards.new()
	scene.add_child(wreck)
	scene.add_child(hazards)
	hazards.configure(wreck)
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	var reference: Dictionary = session.object_state("kestrel", 0.0)
	frame.set_reference(reference.position, reference.velocity)
	frame.shift = SimVector.new(2300.0, 0.0, 0.0)
	EncounterStore.restore(session, "kestrel", frame, wreck, hazards)
	check_eq(wreck.bodies.size(), 1, "first visit intact practice wreck")
	check_near(wreck.bodies[0].assembly_pose().origin.distance_to(Vector3(-2300.0, 0.0, 0.0)), 0.0, 0.001, "new reference honours accumulated floating shift")
	for body: WreckBody in wreck.bodies:
		body.free()
	wreck.bodies.clear()
	EncounterStore.capture(session, "kestrel", frame, wreck, hazards)
	check_eq(session.encounters.kestrel.fragments.size(), 0, "entirely recovered wreck stores no survivors")
	EncounterStore.restore(session, "kestrel", frame, wreck, hazards)
	check_eq(wreck.bodies.size(), 0, "entirely recovered wreck stays empty on revisit")
	scene.free()
	session.free()


func _graph() -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	for index: int in range(4):
		var part: ShipPart = ShipPart.new()
		part.id = ["hull", "tank", "panel", "cargo"][index]
		part.definition = PartDefinition.new()
		part.definition.kind = "fixture"
		part.definition.mass_kg = 100.0
		part.definition.size_m = Vector3.ONE
		part.definition.value_cr = 100.0
		part.definition.sockets = {"left": Transform3D.IDENTITY, "right": Transform3D.IDENTITY}
		part.transform.origin = Vector3(float(index) * 3.0, 0.0, 0.0)
		if part.id == "tank":
			part.definition.hazards = [{"kind": "fuel", "transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.51))}]
		graph.add_part(part)
	graph.connect_parts("hull_tank", "hull", "right", "tank", "left")
	graph.connect_parts("tank_panel", "tank", "right", "panel", "left")
	return graph


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _steps(count: int) -> void:
	for _index: int in range(count):
		await _tree().physics_frame
