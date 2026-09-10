## Suit wheel unloading reaches the hull through ordinary magnetic sole contact.
extends TestCase


## Passive soles carry dump torque; independent hull compensation stores it afterward.
func test_boot_dump_then_independent_ship_compensation() -> void:
	var main: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	var player: Player = main.get_node("Player") as Player
	player.input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await _frames(4)
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	var boots: MagneticBoots = player.get_node("MagneticBoots") as MagneticBoots
	ship.api.set_attitude_mode("manual")
	ship.api.set_system_enabled("rcs", false)
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.7, -0.48, 0.0))
	await _frames(4)
	check(boots.try_latch(), "aligned suit soles latch actual ship steel floor")
	check(boots.target_body() == ship, "magnetic contact uses physical hull")
	player.attitude.momentum_body = Vector3.UP * 8.0
	player.suit.battery_energy_j -= 2000.0 # Leave storage room for recovered rotor energy.
	var initial_momentum: Vector3 = _momentum(player, ship, flight)
	var initial_energy: float = _energy(player, ship, flight)
	var initial_battery: float = player.suit.battery_energy_j
	var suit_fuel: float = player.suit.propellant_kg
	var ship_fuel: float = ship.api.get_telemetry().propellant_kg
	player.set_wheel_dumping(true)
	await _frames(100)
	player.set_wheel_dumping(false)
	await _frames(90)
	check(boots.is_attached(), "ordinary soles remain attached during motor reaction")
	check(player.attitude.momentum_body.length() < 0.0001, "latched suit wheels unload")
	check(SimVector.length(flight.session.world.reaction_wheel.momentum_body) < 0.001, "AUTO OFF leaves ship wheel storage unchanged")
	var hull_momentum: Vector3 = ship.get_inverse_inertia_tensor().inverse() * ship.angular_velocity
	check(hull_momentum.length() > 7.0, "sole reaction physically gives momentum to the hull")
	check(_momentum(player, ship, flight).distance_to(initial_momentum) < 0.08, "sole transfer conserves combined angular momentum")
	check(player.suit.battery_energy_j > initial_battery + 800.0, "unloading recovers substantial electrical energy")
	var loss: float = initial_energy - _energy(player, ship, flight)
	check(loss >= -0.1 and loss < 600.0, "mechanical plus electrical energy stays bounded by motor losses")
	var spin: float = ship.angular_velocity.length()
	ship.api.set_attitude_mode("kill")
	await _frames(180)
	check(boots.is_attached(), "soles stay attached through hull compensation")
	check(ship.angular_velocity.length() < spin * 0.05, "ship controller independently stops hull rotation")
	check(SimVector.length(flight.session.world.reaction_wheel.momentum_body) > 7.0, "ship wheel receives momentum after automatic compensation starts")
	check(_momentum(player, ship, flight).distance_to(initial_momentum) < 0.1, "independent compensation preserves total angular momentum")
	check(_energy(player, ship, flight) <= initial_energy + 0.1, "compensation creates no mechanical or electrical energy")
	check_eq(player.suit.propellant_kg, suit_fuel, "boot-assisted dump uses no suit fuel")
	check_eq(ship.api.get_telemetry().propellant_kg, ship_fuel, "wheel compensation uses no ship RCS fuel")
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


func _energy(player: Player, ship: PlayerShip, flight: OrbitalFlight) -> float:
	var result: float = player.suit.battery_energy_j + float(ship.api.get_telemetry().battery_energy_j)
	result += player.attitude.momentum_body.length_squared() / (2.0 * SuitAttitude.ROTOR_INERTIA_KGM2)
	result += float(flight.session.world.reaction_wheel.snapshot().stored_energy_j)
	for body: RigidBody3D in [player, ship]:
		result += 0.5 * body.angular_velocity.dot(body.get_inverse_inertia_tensor().inverse() * body.angular_velocity)
		result += 0.5 * body.mass * body.linear_velocity.length_squared()
	return result


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in count:
		await tree.physics_frame
		await tree.process_frame
