## Rotor unloading transfers momentum through ordinary physics and recovers energy.
extends TestCase


## The free suit spins; a restrained suit shares the same momentum with its carrier.
func test_dump_transfers_momentum_to_free_and_held_bodies() -> void:
	var free_spin: float = 0.0
	for attached: bool in [false, true]:
		var fixture: Node3D = Node3D.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(fixture)
		var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
		player.input_enabled = false
		player.position = Vector3.RIGHT * 1.5
		fixture.add_child(player)
		var cargo: RigidBody3D = RigidBody3D.new()
		cargo.mass = 200.0
		cargo.inertia = Vector3.ONE * 20.0
		cargo.gravity_scale = 0.0
		cargo.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		cargo.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		cargo.linear_damp = 0.0
		cargo.angular_damp = 0.0
		cargo.can_sleep = false
		var collision: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = 0.5
		collision.shape = sphere
		cargo.add_child(collision)
		fixture.add_child(cargo)
		var grip: PhysicalGrip = PhysicalGrip.new()
		player.add_child(grip)
		grip.configure(player)
		await _steps(3)
		if attached:
			check(grip.grab_body(cargo, Vector3.RIGHT * 0.5), "ordinary physical joint catches carrier")
		await _steps(3)
		player.attitude.momentum_body = Vector3.UP * 4.0
		player.suit.battery_energy_j = 1000.0
		player.suit.propellant_kg = 0.0
		var initial: Vector3 = _momentum(player, cargo)
		player.set_wheel_dumping(true)
		await _steps(90)
		check_near(player.attitude.momentum_body.length(), 0.0, 0.001, "dump gradually unloads rotor")
		check(player.angular_velocity.y > 0.005, "dump reaction spins suit")
		check_near(_momentum(player, cargo).distance_to(initial), 0.0, 0.03, "total body, orbital and rotor angular momentum survives dumping")
		check_eq(player.suit.propellant_kg, 0.0, "dump works without any propellant")
		check(player.suit.battery_energy_j > 1000.0, "slowing rotor recovers electricity")
		check(player.suit.battery_energy_j < 1000.0 + 16.0 / (2.0 * SuitAttitude.ROTOR_INERTIA_KGM2), "recovered energy cannot exceed initial rotor energy")
		if attached:
			check(grip.is_attached(), "dump stays within grip strength")
			check_near(player.angular_velocity.distance_to(cargo.angular_velocity), 0.0, 0.001, "generic carrier gains rotation through joint")
			check(player.angular_velocity.length() < free_spin * 0.2, "larger combined inertia produces slower spin")
		else:
			free_spin = player.angular_velocity.length()
			check_near(cargo.angular_velocity.length(), 0.0, 1e-6, "unconnected object receives no magic momentum transfer")
		fixture.free()


## Explicit dump overrides normal motor suppression in seats and boots, and competing controls.
func test_dump_supported_modes_priority_and_release() -> void:
	for mode: String in ["seat", "boots"]:
		var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
		player.input_enabled = false
		(Engine.get_main_loop() as SceneTree).root.add_child(player)
		player.set_meta("seated", mode == "seat")
		player.surface_motion_active = mode == "boots"
		player.attitude.momentum_body = Vector3.BACK * 4.0
		player.set_braking(true)
		player.set_wheel_braking(true)
		player.set_motion_input(Vector3.FORWARD, -1.0)
		player.set_wheel_dumping(true)
		await _steps(15)
		check(player.attitude.momentum_body.z < 4.0, mode + " allows deliberate rotor dump")
		check(player.angular_velocity.z > 0.01, mode + " receives real motor reaction")
		check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, "dump overrides simultaneous jets and braking")
		player.call("_release_mouse")
		check(not player.is_wheel_dumping(), "focus loss cancels dump")
		player.free()
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_C
	check(InputMap.event_is_action(event, "wheel_dump"), "C is physical wheel dump input")


## Generator recharge is capped, invalid requests cannot create charge, and cycles lose energy.
func test_regeneration_capacity_and_round_trip_losses() -> void:
	var suit: SuitResources = SuitResources.new()
	suit.battery_energy_j -= 10.0
	check_eq(suit.charge_energy(20.0), 10.0, "generator accepts only battery headroom")
	check_eq(suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "charge stays bounded")
	for invalid: float in [-1.0, INF, NAN]:
		check_eq(suit.charge_energy(invalid), 0.0, "invalid recovered energy is ignored")
	var wheel: SuitAttitude = SuitAttitude.new()
	var omega: Vector3 = Vector3.ZERO
	for step: int in 100:
		omega += wheel.drive(Vector3.UP * 8.0, omega, 8.0, 0.01, suit) * 0.001
	var after_drive: float = suit.battery_energy_j
	for step: int in 110:
		omega += wheel.drive(wheel.momentum_body / 0.01, omega, 8.0, 0.01, suit) * 0.001
	check_near(wheel.momentum_body.length(), 0.0, 1e-5, "round trip returns wheel to rest")
	check_near(omega.length(), 0.0, 1e-5, "isolated body's spin returns to rest too")
	check(suit.battery_energy_j > after_drive, "deceleration returns some electricity")
	check(suit.battery_energy_j < SuitResources.BATTERY_CAPACITY_J, "round trip loses energy instead of minting charge")


func _momentum(player: Player, cargo: RigidBody3D) -> Vector3:
	var total: Vector3 = player.global_basis * player.attitude.momentum_body
	for body: RigidBody3D in [player, cargo]:
		total += body.get_inverse_inertia_tensor().inverse() * body.angular_velocity
		total += body.global_position.cross(body.linear_velocity * body.mass)
	return total


func _steps(count: int) -> void:
	for step: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
