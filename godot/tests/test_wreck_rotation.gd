## Imported asymmetric wrecks preserve angular momentum while freely tumbling.
extends TestCase


## Multi-axis spin precesses instead of rotating the world angular-momentum vector.
func test_imported_practice_wreck_preserves_tumbling_momentum_and_energy() -> void:
	var wreck: SalvageWreck = SalvageWreck.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(wreck)
	var orientation: Basis = Basis(Vector3(1.0, 2.0, 3.0).normalized(), 0.7)
	wreck.spawn(PracticeWreck.make_graph(), Transform3D(orientation, Vector3.ZERO),
		Vector3(0.4, -0.2, 0.1), Vector3(0.13, 0.17, -0.11))
	await _frames(3)
	check_eq(wreck.bodies.size(), 1, "imported eight-part wreck starts as one physical compound")
	var body: WreckBody = wreck.bodies[0]
	var before_momentum: Vector3 = _angular_momentum(body)
	var before_energy: float = 0.5 * body.angular_velocity.dot(before_momentum)
	var before_velocity: Vector3 = body.linear_velocity
	var before_spin: Vector3 = body.angular_velocity
	await _frames(Engine.physics_ticks_per_second * 2)
	var after_momentum: Vector3 = _angular_momentum(body)
	var after_energy: float = 0.5 * body.angular_velocity.dot(after_momentum)
	check(body.angular_velocity.distance_to(before_spin) > 0.001, "asymmetric tumbling changes angular velocity through precession")
	check_near(after_momentum.distance_to(before_momentum) / before_momentum.length(), 0.0, 0.001,
		"world angular momentum is conserved within integration tolerance")
	check_near(absf(after_energy - before_energy) / before_energy, 0.0, 0.001,
		"torque-free tumbling conserves rotational kinetic energy")
	check_near(body.linear_velocity.distance_to(before_velocity), 0.0, 1e-6,
		"gyroscopic torque cannot change translational momentum")
	wreck.free()


func _angular_momentum(body: WreckBody) -> Vector3:
	return body.global_basis * (body.inertia * (body.global_basis.transposed() * body.angular_velocity))


func _frames(count: int) -> void:
	for frame: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
