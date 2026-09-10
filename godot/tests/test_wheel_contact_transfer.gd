## Wheel unloading acts through ordinary physical contacts and independent ship control.
extends TestCase


## A handhold passes motor reaction into the hull; only a later controller command loads ship wheels.
func test_hand_dump_then_independent_ship_compensation() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	var grip: PhysicalGrip = player.get_node("PhysicalGrip") as PhysicalGrip
	ship.api.set_attitude_mode("manual")
	ship.api.set_system_enabled("rcs", false)
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.0))
	await _frames(3)
	check(grip.grab_body(ship, ship.to_global(Vector3(1.9, 0, 0))), "ordinary handhold catches physical hull")
	player.body_follow_enabled = false
	player.attitude.momentum_body = Vector3.UP * 8.0
	var initial: Vector3 = _momentum(player, ship, flight)
	var suit_fuel: float = player.suit.propellant_kg
	var ship_fuel: float = ship.api.get_telemetry().propellant_kg
	player.set_wheel_dumping(true)
	await _frames(100)
	player.set_wheel_dumping(false)
	await _frames(30)
	check(grip.is_attached(), "handhold transmits unloading without breaking")
	check(player.attitude.momentum_body.length() < 0.0001, "suit wheel unloads")
	check(SimVector.length(flight.session.world.reaction_wheel.momentum_body) < 0.001, "AUTO OFF leaves ship wheel untouched")
	var hull_momentum: Vector3 = ship.get_inverse_inertia_tensor().inverse() * ship.angular_velocity
	check(hull_momentum.length() > 7.0, "hull physically gains the unloaded angular momentum")
	check(_momentum(player, ship, flight).distance_to(initial) < 0.06, "manual transfer conserves total angular momentum")
	var spin: float = ship.angular_velocity.length()
	ship.api.set_attitude_mode("kill")
	await _frames(180)
	check(ship.angular_velocity.length() < spin * 0.05, "independent attitude controller stops resulting hull rotation")
	check(SimVector.length(flight.session.world.reaction_wheel.momentum_body) > 7.0, "ship controller stores momentum only after observing rotation")
	check(_momentum(player, ship, flight).distance_to(initial) < 0.08, "automatic compensation preserves total angular momentum")
	check_eq(player.suit.propellant_kg, suit_fuel, "suit dump never fires jets")
	check_eq(ship.api.get_telemetry().propellant_kg, ship_fuel, "independent ship wheel uses no RCS propellant")
	main.free()


## A seated dump wakes the physical hull, retains rotor state and settles before returning to orbit.
func test_seated_dump_uses_joint_and_preserves_handoff() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	var interaction: ShipInteraction = main.get_node("ShipInteraction") as ShipInteraction
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, PlayerShip.SEAT_POSITION)
	await _frames(3)
	check(interaction.strap_in(), "pilot fastens actual seat restraint")
	player.input_enabled = false
	await _frames(5)
	check(not flight.ship_is_local, "unloaded restrained pilot permits analytic coast")
	ship.api.set_attitude_mode("kill")
	player.attitude.momentum_body = Vector3.UP * 4.0
	player.set_wheel_dumping(true)
	await _frames(8)
	check(flight.ship_is_local and not ship.freeze, "dump wakes live hull before transmitting torque")
	check(not ship.api.set_warp(10.0), "unsettled restraint cannot bypass physical transfer with warp")
	await _frames(100)
	check(interaction.is_seated(), "harness holds throughout wheel reaction")
	check(player.attitude.momentum_body.length() < 0.0001, "seated suit wheel can unload")
	player.set_wheel_dumping(false)
	await _frames(100)
	check(not flight.ship_is_local, "settled empty suit wheels permit analytic flight again")
	check(SimVector.length(flight.session.world.reaction_wheel.momentum_body) > 3.8, "ship wheel state survives physical to orbital handoff")
	var snapshot: Dictionary = ship.api.get_telemetry().flight.reaction_wheel
	check(float(snapshot.utilization) > 0.0, "wheel storage is published through ShipApi")
	snapshot.momentum_nms.y = 99999.0
	check(float(ship.api.get_telemetry().flight.reaction_wheel.momentum_nms.y) != 99999.0, "wheel telemetry cannot mutate simulation")
	check(ship.api.set_warp(10.0), "settled restrained pilot can warp again")
	flight.enabled = false
	flight.session.world.reaction_wheel.momentum_body = SimVector.new(100000, -100000, 100000)
	flight._begin_open_space_eva()
	var expected_rotors: Vector3 = LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(flight.session.world.reaction_wheel.momentum_body)
	check_eq(ship.rotor_momentum_body, expected_rotors, "local entry restores rotor gyro state before the first physical tick")
	main.free()


## Full ship wheels retain passive gyro reactions even with the entire power bus off.
func test_unpowered_full_ship_wheels_do_not_create_rotational_energy() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	player.global_position = ship.to_global(Vector3(8, 0, 0))
	ship.api.set_attitude_mode("manual")
	ship.api.set_system_enabled("power", false)
	flight.session.world.reaction_wheel.momentum_body = SimVector.new(100000, -100000, 100000)
	ship.angular_velocity = ship.global_basis * Vector3(0.02, 0.03, -0.01)
	await _frames(2)
	var initial: Vector3 = _momentum(player, ship, flight)
	var energy: float = 0.5 * ship.angular_velocity.dot(ship.get_inverse_inertia_tensor().inverse() * ship.angular_velocity)
	var charge: float = ship.api.get_telemetry().battery_energy_j
	await _frames(180)
	var final_energy: float = 0.5 * ship.angular_velocity.dot(ship.get_inverse_inertia_tensor().inverse() * ship.angular_velocity)
	check(absf(final_energy - energy) / energy < 0.002, "saturated passive ship wheels cannot generate rotational energy")
	check(_momentum(player, ship, flight).distance_to(initial) / initial.length() < 0.001, "physical hull and full rotors retain world angular momentum")
	check_eq(ship.api.get_telemetry().battery_energy_j, charge, "passive precession does not need a powered bus")
	check_eq(flight.session.world.reaction_wheel.momentum_body.x, 100000.0, "power loss retains rotor momentum")
	main.free()


func _momentum(player: Player, ship: PlayerShip, flight: OrbitalFlight) -> Vector3:
	var center: Vector3 = (player.global_position * player.mass + ship.to_global(ship.center_of_mass) * ship.mass) / (player.mass + ship.mass)
	var drift: Vector3 = (player.linear_velocity * player.mass + ship.linear_velocity * ship.mass) / (player.mass + ship.mass)
	var result: Vector3 = player.global_basis * player.attitude.momentum_body
	result += ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(flight.session.world.reaction_wheel.momentum_body)
	for body: RigidBody3D in [player, ship]:
		result += body.get_inverse_inertia_tensor().inverse() * body.angular_velocity
		result += (body.to_global(body.center_of_mass) - center).cross((body.linear_velocity - drift) * body.mass)
	return result


func _main() -> Node3D:
	var main: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	(main.get_node("Player") as Player).input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await _frames(4)
	return main


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in count:
		await tree.physics_frame
		await tree.process_frame
