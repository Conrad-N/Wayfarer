## Cargo acquisition requires physical passage and conserves mass and momentum.
extends TestCase


## A real slow drift through an opened hatch secures the part once fully aboard.
func test_actual_drift_through_open_door_secures_cargo_once() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var body: WreckBody = fixture.body
	var hold: CargoHold = fixture.hold
	ship.api.set_cargo_door(true)
	await _frames(3)
	body.linear_velocity = Vector3.BACK * 0.45
	hold.set_physics_process(true)
	await _frames(285)
	var telemetry: Dictionary = ship.api.get_telemetry()
	check_eq(telemetry.cargo_manifest.size(), 1, "slow exterior drift crosses the door and clamps inside")
	check_eq((fixture.wreck as SalvageWreck).bodies.size(), 0, "secured part leaves loose simulation")
	check_near(float(telemetry.cargo_mass_kg), 100.0, 0.0001, "manifest carries cargo mass")
	check_near(float(telemetry.cargo_volume_m3), 1.0, 0.0001, "manifest carries occupied volume")
	check_near(ship.mass, 8140.0, 0.0001, "cargo becomes physical ship mass")
	await _frames(5)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "remaining ticks cannot register it twice")
	(fixture.root as Node).free()


## Merely appearing inside the bay or arriving sideways is not a doorway passage.
func test_unobserved_or_misaligned_arrival_does_not_register() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	var body: WreckBody = fixture.body
	ship.api.set_cargo_door(true)
	await _place(fixture, Vector3(0, 0, -4.5))
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "body not seen outside cannot become cargo")
	await _place(fixture, Vector3(1.3, 0, -8.5))
	hold._physics_process(1.0 / 60.0)
	await _place(fixture, Vector3(1.3, 0, -7.1))
	hold._physics_process(1.0 / 60.0)
	check(ship.api.last_message.contains("Align cargo"), "sideways approach explains alignment problem")
	await _place(fixture, Vector3(0, 0, -4.5))
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "invalid crossing cannot grant later interior acquisition")
	check(is_instance_valid(body), "unsecured body remains loose")
	(fixture.root as Node).free()


## Correcting alignment while the nose is at the threshold preserves exterior history.
func test_alignment_can_be_corrected_after_leading_edge_reaches_door() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	ship.api.set_cargo_door(true)
	await _place(fixture, Vector3(1.3, 0, -8.5))
	hold._physics_process(1.0 / 60.0)
	await _place(fixture, Vector3(1.3, 0, -7.1))
	hold._physics_process(1.0 / 60.0)
	await _place(fixture, Vector3(0, 0, -7.1))
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "corrected threshold alignment still waits for containment")
	await _place(fixture, Vector3(0, 0, -4.5))
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "correction at threshold permits the physical loading attempt")
	await _frames(1)
	(fixture.root as Node).free()


## Door width includes projected orientation and the entire connected component.
func test_oversized_or_rotated_component_cannot_register() -> void:
	for size: Vector3 in [Vector3(2.4, 1, 1), Vector3(1.8, 1.8, 1)]:
		var fixture: Dictionary = _fixture(size)
		var ship: PlayerShip = fixture.ship
		var body: WreckBody = fixture.body
		var hold: CargoHold = fixture.hold
		ship.api.set_cargo_door(true)
		if size.x < 2.0:
			body.basis = Basis(Vector3.FORWARD, PI / 4.0)
		await _frames(3)
		check(hold.bounds_in_bay(body).size.x > 2.2, "projected cargo is wider than the aperture")
		hold._physics_process(1.0 / 60.0)
		await _place(fixture, Vector3(0, 0, -7.1))
		hold._physics_process(1.0 / 60.0)
		await _place(fixture, Vector3(0, 0, -4.5))
		hold._physics_process(1.0 / 60.0)
		check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "oversized passage cannot become manifest entry")
		(fixture.root as Node).free()


## Rotated tapered parts use their actual silhouette, not empty mesh-box corners.
func test_rotated_tapered_mesh_avoids_false_oversize_rejection() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var hold: CargoHold = fixture.hold
	var body: WreckBody = fixture.body
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.8
	cone.height = 2.0
	cone.radial_segments = 8
	cone.rings = 1
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).mesh = cone
	body.basis = Basis(Vector3.BACK, PI / 4.0)
	await _frames(3)
	var box_projection: AABB = body.transform * cone.get_aabb()
	var true_bounds: AABB = hold.bounds_in_bay(body)
	check(box_projection.size.x > 2.2, "rotated source bounding box falsely exceeds the doorway")
	check(true_bounds.size.x < 2.2 and true_bounds.size.y < 2.2, "actual tapered silhouette fits the doorway")
	check_near(true_bounds.size.x, 2.8 / sqrt(2.0), 0.0001, "cone width follows transformed triangle vertices")
	check_eq(hold.bounds_in_bay(body), true_bounds, "cached vertices preserve the same physical bounds")
	(fixture.root as Node).free()


## A closed hatch cannot authorize passage even if a test teleports a body through it.
func test_closed_door_rejects_crossing() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	await _frames(3)
	hold._physics_process(1.0 / 60.0)
	await _place(fixture, Vector3(0, 0, -7.1))
	hold._physics_process(1.0 / 60.0)
	check(ship.api.last_message.contains("closed"), "closed door reports obstruction")
	await _place(fixture, Vector3(0, 0, -4.5))
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "closed door never authorizes cargo")
	(fixture.root as Node).free()


## Cargo must be fully inside and slow in both translation and rotation to clamp.
func test_clamp_waits_for_full_containment_and_safe_relative_motion() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	var body: WreckBody = fixture.body
	ship.api.set_cargo_door(true)
	await _cross(fixture)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "part straddling threshold remains loose")
	await _place(fixture, Vector3(0, 0, -4.5))
	body.linear_velocity = Vector3.BACK
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "fast translation delays clamp")
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.UP
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "fast tumbling delays clamp")
	body.angular_velocity = Vector3.ZERO
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "slowed fully contained cargo clamps")
	await _frames(1)
	(fixture.root as Node).free()


## A passed doorway stays loose without power; restoring power allows the clamps.
func test_cargo_clamps_require_available_ship_power() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	ship.api.set_cargo_door(true)
	await _cross(fixture)
	await _place(fixture, Vector3(0, 0, -4.5))
	ship.api.set_system_enabled("power", false)
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "unpowered clamp cannot merge cargo")
	check(ship.api.last_message.contains("POWER"), "unpowered clamp explains the power requirement")
	ship.api.set_system_enabled("power", true)
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "restoring power allows pending cargo to clamp")
	await _frames(1)
	(fixture.root as Node).free()


## Active fuel/coolant recoil remains physical; clamps wait until the plume finishes.
func test_active_leak_delays_clamp_until_reservoir_finishes() -> void:
	var fixture: Dictionary = _fixture(Vector3.ONE)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	var vents: SalvageHazards = fixture.hazards
	var wreck: SalvageWreck = fixture.wreck
	wreck.graph.get_part("cargo_a").definition.hazards = [{"kind": "coolant", "transform": Transform3D.IDENTITY}]
	ship.api.set_cargo_door(true)
	await _cross(fixture)
	await _place(fixture, Vector3(0, 0, -4.5))
	check(vents.trigger("cargo_a"), "test cargo starts venting")
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 0, "active reservoir cannot be clamped")
	check(ship.api.last_message.contains("active leak"), "clamp explains the active hazard")
	vents._physics_process(SalvageHazards.COOLANT_DURATION_S)
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "depleted plume allows acquisition")
	await _frames(1)
	(fixture.root as Node).free()


## Securing a compound preserves its geometry, linear momentum and angular momentum.
func test_compound_clamp_preserves_world_geometry_and_momentum() -> void:
	var fixture: Dictionary = _fixture(Vector3(0.6, 0.6, 0.6), true)
	var ship: PlayerShip = fixture.ship
	var hold: CargoHold = fixture.hold
	var body: WreckBody = fixture.body
	var ship_pose: Transform3D = Transform3D(Basis(Vector3(1, 2, -1).normalized(), 0.7), Vector3(11, 4, -3))
	ship.global_transform = ship_pose
	body.global_transform = ship_pose * body.global_transform
	ship.api.set_cargo_door(true)
	await _cross(fixture)
	await _place(fixture, Vector3(0.3, 0.1, -4.5))
	ship.linear_velocity = Vector3(0.3, -0.1, 0.2)
	ship.angular_velocity = Vector3(0.01, 0.015, -0.01)
	body.linear_velocity = ship.linear_velocity + Vector3(0.1, 0.02, 0.05)
	body.angular_velocity = Vector3(-0.02, 0.03, 0.01)
	var changes: Array[bool] = []
	(fixture.wreck as SalvageWreck).structure_changed.connect(func() -> void: changes.append(true))
	var before_mass: float = ship.mass + body.mass
	var before_momentum: Vector3 = ship.linear_velocity * ship.mass + body.linear_velocity * body.mass
	var center: Vector3 = (ship.to_global(ship.center_of_mass) * ship.mass + body.global_position * body.mass) / before_mass
	var before_angular: Vector3 = _angular(ship, center) + _angular(body, center)
	var original_meshes: Array[Transform3D] = []
	var original_shape_count: int = ship.get_shape_owners().size()
	for child: Node in body.get_children():
		if child is MeshInstance3D:
			original_meshes.append((child as Node3D).global_transform)
	hold._physics_process(1.0 / 60.0)
	check_eq(ship.api.get_telemetry().cargo_manifest.size(), 1, "connected pair becomes one cargo manifest entry")
	check_eq(changes.size(), 1, "acquisition signals navigation clients to choose a remaining target")
	check_eq(ship.api.get_telemetry().cargo_manifest[0].parts.size(), 2, "manifest retains both identities")
	check_near(ship.mass, before_mass, 0.0001, "combined physical mass is conserved")
	_check_vector(ship.linear_velocity * ship.mass, before_momentum, 0.0001, "clamp conserves linear momentum")
	_check_vector(ship.to_global(ship.center_of_mass), center, 0.00001, "clamp moves centre of mass to weighted centre")
	var new_tensor: Basis = ship.global_basis * Basis.from_scale(ship.inertia) * ship.global_basis.transposed()
	_check_vector(new_tensor * ship.angular_velocity, before_angular, 0.01, "clamp conserves angular momentum about new centre")
	check_eq(ship.get_shape_owners().size(), original_shape_count + 2, "compound collision retains both cargo shapes")
	var matched: int = 0
	for child: Node in ship.get_children():
		if not child is MeshInstance3D or not child.has_meta("system_id"):
			continue
		for pose: Transform3D in original_meshes:
			if (child as Node3D).global_transform.is_equal_approx(pose):
				matched += 1
	check_eq(matched, 2, "both cargo meshes retain their world poses")
	await _frames(5)
	_check_vector(ship.linear_velocity * ship.mass, before_momentum, 0.02, "resuming Jolt keeps combined linear momentum")
	_check_vector(_angular(ship, ship.to_global(ship.center_of_mass)), before_angular, before_angular.length() * 0.001, "resuming Jolt keeps angular momentum within solver tolerance")
	check_eq((fixture.wreck as SalvageWreck).bodies.size(), 0, "old independent body is removed")
	(fixture.root as Node).free()


func _fixture(size: Vector3, compound: bool = false) -> Dictionary:
	var root: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var ship: PlayerShip = load("res://scenes/player_ship.tscn").instantiate() as PlayerShip
	root.add_child(ship)
	var graph: ShipGraph = ShipGraph.new()
	for index: int in range(2 if compound else 1):
		var part: ShipPart = ShipPart.new()
		part.id = "cargo_a" if index == 0 else "cargo_b"
		part.definition = PartDefinition.new()
		part.definition.kind = "hull"
		part.definition.mass_kg = 100.0 * float(index + 1)
		part.definition.volume_m3 = size.x * size.y * size.z
		part.definition.value_cr = 100.0
		part.definition.size_m = size
		part.definition.sockets = {"mount": Transform3D.IDENTITY}
		if compound:
			part.transform.origin = Vector3(-0.4 if index == 0 else 0.4, 0, 0)
		graph.add_part(part)
	if compound:
		graph.connect_parts("pair", "cargo_a", "mount", "cargo_b", "mount")
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
	return {"root": root, "ship": ship, "wreck": wreck, "body": wreck.bodies[0], "hazards": hazards, "hold": hold}


func _place(fixture: Dictionary, point: Vector3) -> void:
	var body: WreckBody = fixture.body
	body.position = (fixture.ship as PlayerShip).to_global(point)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await _frames(1)


func _cross(fixture: Dictionary) -> void:
	await _frames(3)
	(fixture.hold as CargoHold)._physics_process(1.0 / 60.0)
	await _place(fixture, Vector3(0, 0, -7.1))
	(fixture.hold as CargoHold)._physics_process(1.0 / 60.0)


func _angular(body: RigidBody3D, about: Vector3) -> Vector3:
	return body.get_inverse_inertia_tensor().inverse() * body.angular_velocity + (body.to_global(body.center_of_mass) - about).cross(body.linear_velocity * body.mass)


func _frames(count: int) -> void:
	for index: int in range(count):
		await (Engine.get_main_loop() as SceneTree).physics_frame


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, label: String) -> void:
	check(actual.distance_to(expected) < tolerance, "%s expected %s got %s" % [label, expected, actual])
