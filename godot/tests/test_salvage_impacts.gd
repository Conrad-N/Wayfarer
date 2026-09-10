## Real Jolt contacts must damage salvage using incoming, not already stopped, motion.
extends TestCase


## A fast wall impact loses condition once; a gentle bump stays below the threshold.
func test_wall_collision_uses_incoming_speed_and_charges_once() -> void:
	for speed: float in [3.0, 10.0]:
		var wreck: SalvageWreck = _wreck([Vector3(-3.0, 0.0, 0.0)])
		wreck.bodies[0].linear_velocity = Vector3(speed, 0.0, 0.0)
		var wall: StaticBody3D = StaticBody3D.new()
		_shape(wall, Vector3(1.0, 10.0, 10.0))
		wreck.add_child(wall)
		await _frames(70)
		check(absf(wreck.bodies[0].linear_velocity.x) < 0.1, "wall actually stops incoming part")
		var expected: float = 1.0 if speed == 3.0 else 0.9
		check_near(wreck.graph.get_part("part_0").condition, expected, 0.0001,
			"incoming kinetic energy is charged once despite multiple contact points")
		wreck.free()


## A moving ordinary body can damage a stationary wreck using both incoming velocities.
func test_incoming_dynamic_body_damages_stationary_wreck() -> void:
	var wreck: SalvageWreck = _wreck([Vector3.ZERO])
	var projectile: RigidBody3D = RigidBody3D.new()
	projectile.mass = 100.0
	projectile.gravity_scale = 0.0
	projectile.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	projectile.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	projectile.linear_damp = 0.0
	projectile.angular_damp = 0.0
	projectile.position = Vector3(-4.0, 0.0, 0.0)
	projectile.linear_velocity = Vector3(12.0, 0.0, 0.0)
	_shape(projectile, Vector3.ONE)
	wreck.add_child(projectile)
	await _frames(35)
	check(wreck.bodies[0].linear_velocity.x > 4.0, "projectile transfers motion to formerly stationary wreck")
	var expected: float = 1.0 - (0.5 * 50.0 * 12.0 * 12.0 - 2000.0) / (100.0 * 300.0)
	check_near(wreck.graph.get_part("part_0").condition, expected, 0.0001,
		"dynamic impact uses reduced mass and pre-solver approach speed")
	wreck.free()


## Sister fragments ignore initial separation contacts but damage each other later.
func test_sibling_fragments_damage_after_initial_contact_grace() -> void:
	for initial_contact: bool in [true, false]:
		var spacing: float = 0.55 if initial_contact else 3.0
		var wreck: SalvageWreck = _wreck([Vector3(-spacing, 0.0, 0.0), Vector3(spacing, 0.0, 0.0)])
		wreck.bodies[0].linear_velocity = Vector3(6.0, 0.0, 0.0)
		wreck.bodies[1].linear_velocity = Vector3(-6.0, 0.0, 0.0)
		await _frames(40)
		check(absf(wreck.bodies[0].linear_velocity.x) < 0.1, "sister fragments actually collide")
		var expected: float = 1.0 if initial_contact else 1.0 - 1600.0 / 30000.0
		for id: String in wreck.graph.part_ids():
			check_near(wreck.graph.get_part(id).condition, expected, 0.0001,
				"initial contact is harmless" if initial_contact else "later sibling collision reduces both conditions")
		wreck.free()


func _wreck(positions: Array[Vector3]) -> SalvageWreck:
	var graph: ShipGraph = ShipGraph.new()
	for index: int in range(positions.size()):
		var part: ShipPart = ShipPart.new()
		part.id = "part_%d" % index
		part.definition = PartDefinition.new()
		part.definition.kind = "hull"
		part.definition.mass_kg = 100.0
		part.transform.origin = positions[index]
		graph.add_part(part)
	var wreck: SalvageWreck = SalvageWreck.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(wreck)
	wreck.spawn(graph, Transform3D.IDENTITY)
	return wreck


func _shape(body: PhysicsBody3D, size: Vector3) -> void:
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _frames(count: int) -> void:
	for index: int in range(count):
		await (Engine.get_main_loop() as SceneTree).physics_frame
