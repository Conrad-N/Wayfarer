## Rotation-only wheel braking stores angular momentum without spending propellant.
extends TestCase


## X slows spin using electricity while linear drift survives, even with an empty tank.
func test_wheel_brake_slows_spin_without_changing_drift_or_fuel() -> void:
	var player: Player = _player()
	player.suit.propellant_kg = 0.0
	player.linear_velocity = Vector3(1.0, -0.5, 0.25)
	player.angular_velocity = Vector3.BACK * 0.3
	await _steps(3)
	var drift: Vector3 = player.linear_velocity
	var body_momentum: Vector3 = player.get_inverse_inertia_tensor().inverse() * player.angular_velocity
	player.set_wheel_braking(true)
	check(player.is_wheel_braking(), "wheel brake reports held command")
	await _steps(6)
	check(player.angular_velocity.z > 0.1 and player.angular_velocity.z < 0.3, "wheel torque slows rotation gradually")
	await _steps(180)
	check(player.angular_velocity.length() < 0.002, "normal spin stops within wheel capacity")
	check_near(player.linear_velocity.distance_to(drift), 0.0, 1e-5, "wheel brake does not change linear drift")
	check_eq(player.suit.propellant_kg, 0.0, "wheel braking never needs propellant")
	check_near(player.mass, 100.0, 1e-5, "no expelled fuel means no mass loss")
	check(player.suit.battery_energy_j < SuitResources.BATTERY_CAPACITY_J, "wheel braking consumes electricity")
	var total: Vector3 = player.get_inverse_inertia_tensor().inverse() * player.angular_velocity + player.global_basis * player.attitude.momentum_body
	check_near(total.distance_to(body_momentum), 0.0, 0.03, "body momentum is stored in wheels rather than deleted")
	player.set_wheel_braking(false)
	check(not player.is_wheel_braking(), "wheel brake reports release")
	player.free()


## Saturated wheels and empty batteries cannot reset rotation or silently use jets.
func test_saturation_and_empty_battery_leave_spin() -> void:
	for exhausted: String in ["wheel", "battery"]:
		var player: Player = _player()
		player.angular_velocity = Vector3.BACK * 0.5
		if exhausted == "wheel":
			player.attitude.momentum_body = Vector3.BACK * SuitAttitude.MOMENTUM_LIMIT_NMS
		else:
			player.suit.battery_energy_j = 0.01
		await _steps(3)
		player.set_wheel_braking(true)
		await _steps(60)
		check(player.angular_velocity.z > 0.499, exhausted + " exhaustion preserves unmanageable spin")
		check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, exhausted + " exhaustion cannot trigger hidden RCS")
		if exhausted == "battery":
			check_eq(player.suit.battery_energy_j, 0.0, "last battery fraction is exhausted")
		else:
			check_near(player.attitude.momentum_body.z, SuitAttitude.MOMENTUM_LIMIT_NMS, 1e-5, "X cannot desaturate its own full wheel")
		player.free()


## X overrides roll and body-follow but permits deliberately requested translation.
func test_wheel_brake_priorities_and_input_release() -> void:
	var player: Player = _player()
	player.set_wheel_braking(true)
	player.set_motion_input(Vector3.FORWARD, 1.0)
	player.queue_mouse_look(Vector2(0.8 / player.mouse_sensitivity, 0.0))
	await _steps(12)
	check(player.linear_velocity.length() > 0.1, "separate WASD request still fires translation jets")
	check(player.angular_velocity.length() < 1e-5, "X overrides held roll and mouse body-follow")
	check_near(player.head_angles_rad.x, -0.8, 1e-5, "X preserves free head aim")
	player.set_motion_input(Vector3.ZERO, 0.0)
	player.attitude.momentum_body = Vector3.BACK * 2.0
	player.set_braking(true)
	var fuel: float = player.suit.propellant_kg
	await _steps(12)
	check(player.attitude.momentum_body.z < 2.0, "Alt takes priority and unloads wheel even with X held")
	check(player.suit.propellant_kg < fuel, "Alt remains the explicit propellant brake")
	player.call("_release_mouse")
	check(not player.is_wheel_braking(), "Escape/focus cancellation clears wheel brake")
	check(not player.is_braking(), "Escape/focus cancellation clears RCS brake")
	player.free()


## Boots and restraints own supported movement; X cannot fight those attachments.
func test_supported_modes_suppress_wheel_brake() -> void:
	for mode: String in ["seat", "boots"]:
		var player: Player = _player()
		player.angular_velocity = Vector3.BACK * 0.3
		player.set_meta("seated", mode == "seat")
		player.surface_motion_active = mode == "boots"
		player.set_wheel_braking(true)
		await _steps(12)
		check_near(player.angular_velocity.z, 0.3, 1e-5, mode + " prevents wheel brake fighting support")
		check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, mode + " disables X motor power draw")
		check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, mode + " does not fire hidden jets")
		player.free()


## A fixed handhold transmits finite wheel torque and massive loads exhaust storage.
func test_held_load_wheel_brake_transmits_torque_and_saturates() -> void:
	for cargo_mass: float in [200.0, 10000.0]:
		var fixture: Node3D = Node3D.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(fixture)
		var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
		player.input_enabled = false
		player.position = Vector3.RIGHT * 1.5
		fixture.add_child(player)
		var cargo: RigidBody3D = RigidBody3D.new()
		cargo.mass = cargo_mass
		cargo.inertia = Vector3.ONE * cargo_mass * 0.1
		cargo.gravity_scale = 0.0
		cargo.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		cargo.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		cargo.linear_damp = 0.0
		cargo.angular_damp = 0.0
		cargo.can_sleep = false
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = 0.5
		collision.shape = shape
		cargo.add_child(collision)
		fixture.add_child(cargo)
		cargo.angular_velocity = Vector3.UP * 0.3
		var grip: PhysicalGrip = PhysicalGrip.new()
		player.add_child(grip)
		grip.configure(player)
		player.brake_reference = grip.brake_state
		await _steps(3)
		check(grip.grab_body(cargo, Vector3.RIGHT * 0.5), "suit catches spinning load")
		await _steps(20)
		var speed_before: float = cargo.angular_velocity.length()
		var drift_before: Vector3 = (player.linear_velocity * player.mass + cargo.linear_velocity * cargo.mass) / (player.mass + cargo.mass)
		player.set_wheel_braking(true)
		await _steps(840)
		check(grip.is_attached(), "wheel braking keeps physical grip")
		check(cargo.angular_velocity.length() < speed_before, "wheel brake slows the held load too")
		check_near(player.angular_velocity.distance_to(cargo.angular_velocity), 0.0, 0.002, "held load and player keep shared rotation")
		var drift_after: Vector3 = (player.linear_velocity * player.mass + cargo.linear_velocity * cargo.mass) / (player.mass + cargo.mass)
		check_near(drift_after.distance_to(drift_before), 0.0, 0.0001, "combined centre-of-mass drift is unchanged")
		check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, "coupled wheel brake uses no propellant")
		if cargo_mass < 1000.0:
			check(cargo.angular_velocity.length() < 0.002, "small load fits wheel storage and stops")
		else:
			check(cargo.angular_velocity.length() > 0.03, "massive load remains spinning after storage fills")
			check_near(player.attitude.utilization(), 1.0, 0.001, "massive load saturates suit wheel")
		fixture.free()


func _player() -> Player:
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	player.input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


func _steps(count: int) -> void:
	for step: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
