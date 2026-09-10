## Reaction-wheel angular momentum, motor energy, saturation and paid desaturation.
extends TestCase


## A wheel exchanges equal opposite momentum and cannot keep driving after saturation.
func test_wheel_momentum_and_saturation() -> void:
	var wheel: SuitAttitude = SuitAttitude.new()
	var suit: SuitResources = SuitResources.new()
	var body_impulse: Vector3 = Vector3.ZERO
	for step: int in 1500:
		body_impulse += wheel.drive(Vector3.RIGHT * 8.0, Vector3.ZERO, 8.0, 0.01, suit) * 0.01
	check_near(body_impulse.distance_to(-wheel.momentum_body), 0.0, 0.0001, "wheel stores opposite body momentum")
	check_near(wheel.momentum_body.x, -100.0, 0.0001, "finite rotor speed saturates wheel")
	check_near(wheel.drive(Vector3.RIGHT * 8.0, Vector3.ZERO, 8.0, 0.1, suit).length(), 0.0, 1e-5, "saturated axis supplies no additional torque")
	check_near(wheel.utilization(), 1.0, 1e-5, "saturation visible in telemetry")
	check(wheel.drive(Vector3.LEFT * 8.0, Vector3.ZERO, 8.0, 0.1, suit).x < 0.0, "reversing torque can recover headroom")
	check_eq(suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, "motors use no propellant")


## Even the last battery fraction pays all produced rotational kinetic energy.
func test_partial_battery_pays_for_body_and_rotor_energy() -> void:
	var wheel: SuitAttitude = SuitAttitude.new()
	var suit: SuitResources = SuitResources.new()
	suit.battery_energy_j = 0.5
	var impulse: Vector3 = wheel.drive(Vector3(5.0, 5.0, 5.0), Vector3.ZERO, 8.0, 0.1, suit) * 0.1
	var rotor_energy: float = wheel.momentum_body.length_squared() / (2.0 * SuitAttitude.ROTOR_INERTIA_KGM2)
	var body_energy: float = impulse.length_squared() / (2.0 * 5.0)
	check(impulse.length() > 0.0 and impulse.length() < 0.8, "last battery fraction produces partial impulse")
	check(rotor_energy + body_energy <= 0.5, "created kinetic energy cannot exceed battery expenditure")
	check_eq(suit.battery_energy_j, 0.0, "battery reaches zero exactly")
	check_near(wheel.drive(Vector3.RIGHT, Vector3.ZERO, 8.0, 0.1, suit).length(), 0.0, 1e-6, "empty battery gives no motor torque")
	check_near((wheel.momentum_body + impulse).length(), 0.0, 1e-6, "partial supply preserves opposite momentum")


## Physical spin and rotor momentum cancel after a powered free-space roll.
func test_jolt_body_plus_wheels_conserve_angular_momentum() -> void:
	var player: Player = _spawn_player()
	await _steps(3)
	var initial_energy: float = player.suit.battery_energy_j
	player.set_motion_input(Vector3.ZERO, 1.0)
	await _steps(60)
	player.set_motion_input(Vector3.ZERO, 0.0)
	await _steps(3)
	var body_inertia: Basis = player.get_inverse_inertia_tensor().inverse()
	var body_momentum: Vector3 = body_inertia * player.angular_velocity
	var wheel_momentum: Vector3 = player.global_basis * player.attitude.momentum_body
	check_near((body_momentum + wheel_momentum).length(), 0.0, 0.03, "Jolt body momentum balances rotor momentum")
	var kinetic: float = 0.5 * player.angular_velocity.dot(body_momentum) + wheel_momentum.length_squared() / (2.0 * SuitAttitude.ROTOR_INERTIA_KGM2)
	check(initial_energy - player.suit.battery_energy_j >= kinetic, "electricity covers body and wheel kinetic energy")
	var stored: Vector3 = player.attitude.momentum_body
	var battery: float = player.suit.battery_energy_j
	await _steps(12)
	check_near(player.attitude.momentum_body.distance_to(stored), 0.0, 1e-6, "coasting does not unload momentum for free")
	check_eq(player.suit.battery_energy_j, battery, "coasting needs no motor electricity")
	player.free()


## With no motors, changing rotor-axis directions transfers momentum through the suit.
func test_unpowered_precession_preserves_world_momentum_and_energy() -> void:
	var player: Player = _spawn_player()
	await _steps(3)
	player.attitude.momentum_body = Vector3(1.5, -0.5, 0.8)
	player.angular_velocity = Vector3(0.1, 0.3, 0.2)
	player.suit.battery_energy_j = 0.0
	await _steps(3)
	var inertia_before: Basis = player.get_inverse_inertia_tensor().inverse()
	var momentum_before: Vector3 = inertia_before * player.angular_velocity + player.global_basis * player.attitude.momentum_body
	var energy_before: float = 0.5 * player.angular_velocity.dot(inertia_before * player.angular_velocity)
	await _steps(180)
	var inertia_after: Basis = player.get_inverse_inertia_tensor().inverse()
	var momentum_after: Vector3 = inertia_after * player.angular_velocity + player.global_basis * player.attitude.momentum_body
	var energy_after: float = 0.5 * player.angular_velocity.dot(inertia_after * player.angular_velocity)
	check_near(momentum_after.distance_to(momentum_before), 0.0, 0.05, "unpowered rotor-axis precession preserves world angular momentum")
	check_near(energy_after, energy_before, 0.02, "gyroscopic reaction does not create mechanical energy")
	check_eq(player.suit.battery_energy_j, 0.0, "passive gyro reaction does not need battery")
	player.free()


## Full rated wheel momentum cannot amplify an unpowered suit's tumble.
func test_full_capacity_precession_preserves_energy_and_momentum() -> void:
	var player: Player = _spawn_player()
	await _steps(3)
	player.attitude.momentum_body = Vector3.UP * SuitAttitude.MOMENTUM_LIMIT_NMS
	player.angular_velocity = Vector3.BACK * 0.3
	player.suit.battery_energy_j = 0.0
	var initial_body: Vector3 = player.get_inverse_inertia_tensor().inverse() * player.angular_velocity
	var initial_momentum: Vector3 = initial_body + player.global_basis * player.attitude.momentum_body
	var initial_energy: float = 0.5 * player.angular_velocity.dot(initial_body)
	await _steps(180)
	var final_body: Vector3 = player.get_inverse_inertia_tensor().inverse() * player.angular_velocity
	var final_momentum: Vector3 = final_body + player.global_basis * player.attitude.momentum_body
	var final_energy: float = 0.5 * player.angular_velocity.dot(final_body)
	check_near(final_energy, initial_energy, 0.001, "full rotor precession does not create or destroy body kinetic energy")
	check_near(final_momentum.distance_to(initial_momentum), 0.0, 0.03, "full rotor precession retains world angular momentum")
	check_eq(player.suit.battery_energy_j, 0.0, "stable gyro needs no hidden motor electricity")
	player.free()


## Alt stops body spin and unloads rotor momentum by expelling propellant.
func test_alt_desaturates_only_with_fuel_and_motor_power() -> void:
	var player: Player = _spawn_player()
	await _steps(3)
	player.attitude.momentum_body = Vector3(0.0, 0.0, -4.0)
	player.set_braking(true)
	var initial_fuel: float = player.suit.propellant_kg
	await _steps(45)
	check(player.attitude.momentum_body.length() < 0.001, "Alt empties wheel momentum")
	check(player.suit.propellant_kg < initial_fuel, "desaturation expels propellant even when body starts stationary")
	check(player.angular_velocity.length() < 0.001, "opposed motor and jets avoid spinning body during unload")
	player.attitude.momentum_body = Vector3.BACK * 4.0
	player.suit.propellant_kg = 0.0
	await _steps(12)
	check_near(player.attitude.momentum_body.z, 4.0, 1e-5, "no fuel prevents unloading")
	player.suit.propellant_kg = 1.0
	player.suit.battery_energy_j = 0.0
	await _steps(12)
	check_near(player.attitude.momentum_body.z, 4.0, 1e-5, "no motor power prevents unloading")
	check_eq(player.suit.propellant_kg, 1.0, "failed stationary unload does not waste propellant")
	player.free()


## Seats and boots disable suit motors/jets while retaining bounded head aim.
func test_supported_modes_suppress_suit_actuators() -> void:
	for mode: String in ["seat", "boots"]:
		var player: Player = _spawn_player()
		if mode == "seat":
			player.set_meta("seated", true)
		else:
			player.surface_motion_active = true
		player.set_motion_input(Vector3.FORWARD, 1.0)
		player.set_freelooking(true)
		player.queue_mouse_look(Vector2(0.6 / player.mouse_sensitivity, 0.0))
		await _steps(12)
		check_near(player.linear_velocity.length(), 0.0, 1e-5, mode + " suppresses translation jets")
		check_near(player.angular_velocity.length(), 0.0, 1e-5, mode + " suppresses suit motor torque")
		check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, mode + " does not waste suit propellant")
		check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, mode + " does not waste wheel electricity")
		check_near(player.head_angles_rad.x, -0.6, 1e-5, mode + " preserves free head look")
		player.free()


## A hand grip can disable automatic follow without removing deliberate wheel control.
func test_grip_head_look_does_not_fight_attachment() -> void:
	var player: Player = _spawn_player()
	player.body_follow_enabled = false
	player.set_freelooking(true)
	player.queue_mouse_look(Vector2(0.8 / player.mouse_sensitivity, 0.0))
	await _steps(12)
	check_near(player.angular_velocity.length(), 0.0, 1e-5, "head aim does not torque held cargo")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "grip head aim cannot saturate wheels")
	player.set_motion_input(Vector3.ZERO, 1.0)
	await _steps(12)
	check(player.angular_velocity.length() > 0.01, "explicit roll remains available while hand grip is active")
	player.free()


## Rotor-axis precession creates the necessary passive reaction, not an external torque.
func test_gyroscopic_reaction_matches_rotor_axis_motion() -> void:
	var wheel: SuitAttitude = SuitAttitude.new()
	wheel.momentum_body = Vector3.RIGHT * 5.0
	check_near(wheel.gyroscopic_torque(Vector3.UP * 2.0).distance_to(Vector3.BACK * 10.0), 0.0, 1e-6, "body reaction opposes change in rotor momentum direction")
	check_near(wheel.gyroscopic_torque(Vector3.RIGHT).length(), 0.0, 1e-6, "aligned spin requires no precession torque")


func _spawn_player() -> Player:
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	player.input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


func _steps(count: int) -> void:
	for i: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
