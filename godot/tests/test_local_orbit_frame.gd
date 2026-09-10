## Orbital/local handoff and floating-origin checks across scalar64 and real Jolt bodies.
extends TestCase


## Architecture handoff 1: immediate enter/exit preserves nondegenerate orbital elements to 1e-6 relative.
func test_immediate_handoff_preserves_orbit() -> void:
	var body: Dictionary = SimConstants.cradle()
	var elements: Dictionary = {"a": 7.2e6, "e": 0.06, "i": 0.9, "raan": 0.3, "argp": 0.6, "mean_anomaly_at_epoch": 0.8, "epoch": 0.0}
	var reference_elements: Dictionary = elements.duplicate()
	reference_elements.mean_anomaly_at_epoch = 0.7999
	var state: Dictionary = OrbitMath.propagate(elements, body, 1234.0)
	var reference: Dictionary = OrbitMath.propagate(reference_elements, body, 1234.0)
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	frame.set_reference(reference.position, reference.velocity)
	var local_position: Vector3 = frame.to_local_position(state.position)
	var local_velocity: Vector3 = frame.to_local_velocity(state.velocity)
	var returned: Dictionary = ManeuverMath.state_to_elements(frame.to_orbital_position(local_position), frame.to_orbital_velocity(local_velocity), body, 1234.0)
	var expected: Dictionary = ManeuverMath.state_to_elements(state.position, state.velocity, body, 1234.0)
	for key: String in ["a", "e", "i", "raan", "argp", "mean_anomaly_at_epoch"]:
		check_close(returned[key], expected[key], 1e-6, "immediate handoff " + key)
	check_near(SimVector.distance(frame.to_orbital_position(local_position), state.position), 0.0, 1e-4, "no position jump")
	check_near(SimVector.distance(frame.to_orbital_velocity(local_velocity), state.velocity), 0.0, 1e-6, "no velocity jump")


## Architecture handoff 2: one kilometre and a known impulse return as additions to reference state.
func test_translated_handoff_and_au_precision() -> void:
	var reference_position: SimVector = SimVector.new(SimConstants.AU, -2.0 * SimConstants.AU, 3.0 * SimConstants.AU)
	var reference_velocity: SimVector = SimVector.new(30000.125, -12500.25, 7100.5)
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	frame.set_reference(reference_position, reference_velocity)
	var local: Vector3 = frame.to_local_position(reference_position)
	local.x += 1000.0
	var known_velocity: Vector3 = Vector3(12.5, -4.25, 0.125)
	var returned: SimVector = frame.to_orbital_position(local)
	check_eq(returned.x, reference_position.x + 1000.0, "known kilometre x offset")
	check_eq(returned.y, reference_position.y, "no unwanted y offset")
	check_eq(returned.z, reference_position.z, "no unwanted z offset")
	var returned_velocity: SimVector = frame.to_orbital_velocity(known_velocity)
	check_eq(returned_velocity.x, reference_velocity.x + 12.5, "known velocity x")
	check_eq(returned_velocity.y, reference_velocity.y - 4.25, "known velocity y")
	check_eq(returned_velocity.z, reference_velocity.z + 0.125, "known velocity z")
	var centimetres: SimVector = SimVector.add(reference_position, SimVector.new(0.01, -0.02, 0.03))
	var near: Vector3 = frame.to_local_position(centimetres)
	check_near(near.x, 0.01, 4e-5, "AU centimetres survive before narrowing")
	check_near(near.y, -0.02, 4e-5, "AU centimetres y")
	check_near(near.z, 0.03, 4e-5, "AU centimetres z")
	check_near(SimVector.distance(centimetres, frame.to_orbital_position(near)), 0.0, 1e-8, "AU round trip exact stored doubles")
	frame.recentre([], Vector3(2048.0, -1024.0, 512.0))
	check_near(SimVector.distance(returned, frame.to_orbital_position(frame.to_local_position(returned))), 0.0, 1e-8, "floating shift reversible at AU")


## Architecture handoff 3: real moving Jolt bodies and attached children keep relative poses and velocities.
func test_actual_physics_recentre_preserves_motion() -> void:
	var scene: Node3D = Node3D.new()
	_tree().root.add_child(scene)
	var first: RigidBody3D = _body(scene, Vector3(2100.0, 4.0, -10.0), Vector3(2.0, 1.0, -3.0))
	var second: RigidBody3D = _body(scene, Vector3(2112.0, -3.0, 8.0), Vector3(-1.0, 0.5, 2.0))
	var panel: Node3D = Node3D.new()
	panel.position = Vector3(0.0, 2.0, 0.0)
	first.add_child(panel)
	await _steps(3)
	var frame: LocalOrbitFrame = LocalOrbitFrame.new()
	frame.set_reference(SimVector.new(SimConstants.AU, 7e6, 0.0), SimVector.new(0.0, 30000.0, 0.0))
	var relative_before: Vector3 = second.global_position - first.global_position
	var panel_before: Vector3 = panel.global_position - first.global_position
	var first_velocity: Vector3 = first.linear_velocity
	var second_velocity: Vector3 = second.linear_velocity
	var first_spin: Vector3 = first.angular_velocity
	var orbital_before: SimVector = frame.to_orbital_position(first.global_position)
	var displacement: Vector3 = first.global_position
	frame.recentre([first, second], displacement)
	check_near(first.global_position.length(), 0.0, 1e-5, "player root recentred to origin")
	check_near((second.global_position - first.global_position).distance_to(relative_before), 0.0, 0.0003, "all body separations unchanged")
	check_near((panel.global_position - first.global_position).distance_to(panel_before), 0.0, 0.0003, "attached panel follows parent once")
	check_near(SimVector.distance(frame.to_orbital_position(first.global_position), orbital_before), 0.0, 1e-5, "recentring leaves orbital position unchanged")
	await _steps(4)
	check_near(first.linear_velocity.distance_to(first_velocity), 0.0, 1e-5, "Jolt retains first linear velocity")
	check_near(second.linear_velocity.distance_to(second_velocity), 0.0, 1e-5, "Jolt retains second linear velocity")
	check_near(first.angular_velocity.distance_to(first_spin), 0.0, 1e-5, "Jolt retains angular velocity")
	check(first.global_position.length() < 1.0, "Jolt does not snap to old inertial position")
	var relative_after: Vector3 = second.global_position - first.global_position
	var delta_relative: Vector3 = relative_after - relative_before
	check(delta_relative.dot(second_velocity - first_velocity) > 0.0, "relative drift continues in same direction")
	scene.free()


## Scene -Z thrust and legacy +X attitude mappings are exact inverse conventions.
func test_ship_attitude_adapter() -> void:
	var orientation: Dictionary = FlightMath.q_normalize({"w": 0.8, "x": 0.1, "y": 0.3, "z": -0.4})
	var basis: Basis = LocalOrbitFrame.ship_basis(orientation)
	var expected: Vector3 = LocalOrbitFrame.native(FlightMath.thrust_axis_world(orientation))
	check_near((-basis.z).distance_to(expected), 0.0, 1e-6, "ship nose follows simulation thrust")
	var restored: Dictionary = LocalOrbitFrame.orbital_orientation(basis)
	check_near(SimVector.distance(FlightMath.thrust_axis_world(orientation), FlightMath.thrust_axis_world(restored)), 0.0, 1e-6, "attitude round trip")


func _body(scene: Node3D, at: Vector3, velocity: Vector3) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	body.position = at
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(0.0, 0.05, 0.0)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	scene.add_child(body)
	return body


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _steps(count: int) -> void:
	for _index: int in range(count):
		await _tree().physics_frame
