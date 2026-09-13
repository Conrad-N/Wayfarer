## Physical starter-ship regression tests use real Jolt collision and finite stores.
extends TestCase


## The scene has separate usable rooms, shared API clients, and a cargo sensor.
func test_interior_has_clear_centre_passages_and_terminal_mounts() -> void:
	var ship: PlayerShip = _ship()
	await _frames(3)
	check(ship.get_node("NavTerminalMount") is Node3D, "navigation screen has a physical mount")
	check(ship.get_node("ShipTerminalMount") is Node3D, "ship screen has a physical mount")
	check((ship.get_node("NavTerminalMount") as Node3D).basis.z.dot(Vector3.RIGHT) > 0.99, "navigation screen faces into hab")
	check((ship.get_node("ShipTerminalMount") as Node3D).basis.z.dot(Vector3.LEFT) > 0.99, "ship screen faces into hab")
	var volume: Area3D = ship.get_node("CargoVolume") as Area3D
	check_near(float(volume.get_meta("volume_m3")), 50.4, 0.0001, "cargo volume is measured in cubic metres")
	check(_ray(ship, Vector3(0, 0, -6.5), Vector3(0, 0, 5.5)).is_empty(), "cargo, hab and open inner airlock have no solid bounding hull")
	check(not _ray(ship, Vector3.ZERO, Vector3(4, 0, 0)).is_empty(), "side wall remains physically solid")
	check(not _ray(ship, Vector3.ZERO, Vector3(0, -3, 0)).is_empty(), "floor remains physically solid")
	check_near(ship.mass, 10000.0, 0.001, "physical mass includes initial propellant")
	check_near(ship.gravity_scale, 0.0, 0.0, "ship has no local gravity")
	ship.free()


## Opening the cargo door makes exactly the advertised square aperture passable.
func test_cargo_door_opens_aperture_but_frame_blocks_oversize_cargo() -> void:
	var ship: PlayerShip = _ship()
	await _frames(3)
	check(not _ray(ship, Vector3(0, 0, -8), Vector3(0, 0, -6)).is_empty(), "closed cargo door blocks entry")
	ship.api.set_cargo_door(true)
	await _frames(3)
	check(_ray(ship, Vector3(0, 0, -8), Vector3(0, 0, -6)).is_empty(), "open cargo door clears its aperture")
	check(_box_query(ship, Vector3(2.0, 2.0, 0.5), Vector3(0, 0, -7.1)).is_empty(), "two-metre cargo fits")
	check(not _box_query(ship, Vector3(2.4, 2.0, 0.5), Vector3(0, 0, -7.1)).is_empty(), "wide cargo hits the frame")
	check(not _box_query(ship, Vector3(2.0, 2.4, 0.5), Vector3(0, 0, -7.1)).is_empty(), "tall cargo hits the frame")
	ship.free()


## Door interlocks and clearance preserve occupants instead of closing through them.
func test_airlock_interlock_and_blocked_closure() -> void:
	var ship: PlayerShip = _ship()
	await _frames(3)
	ship.api.set_airlock_door("outer", true)
	check(not bool(ship.api.get_telemetry().airlock_outer_open), "outer door cannot open while inner is open")
	ship.api.set_airlock_door("inner", false)
	await _frames(3)
	ship.api.set_airlock_door("outer", true)
	await _frames(3)
	check(bool(ship.api.get_telemetry().airlock_outer_open), "outer opens after inner closes")
	check(_ray(ship, Vector3(0, 0, 5.2), Vector3(0, 0, 6.5)).is_empty(), "opened outer door is physically clear")
	var occupant: RigidBody3D = _box(Vector3(0, 0, 5.9), Vector3.ONE, 100.0)
	occupant.freeze = true
	await _frames(3)
	ship.api.set_airlock_door("outer", false)
	check(bool(ship.api.get_telemetry().airlock_outer_open), "door refuses to close on occupant")
	occupant.free()
	await _frames(3)
	ship.api.set_airlock_door("outer", false)
	await _frames(3)
	check(not bool(ship.api.get_telemetry().airlock_outer_open), "empty airlock door closes")
	check(not _ray(ship, Vector3(0, 0, 5.2), Vector3(0, 0, 6.5)).is_empty(), "closed outer door blocks passage")
	ship.free()


## Cargo obstruction blocks closure while a body deep inside the bay does not.
func test_cargo_closure_checks_door_sweep_only() -> void:
	var ship: PlayerShip = _ship()
	ship.api.set_cargo_door(true)
	await _frames(3)
	var cargo: RigidBody3D = _box(Vector3(0, 0, -7.1), Vector3.ONE, 100.0)
	cargo.freeze = true
	await _frames(3)
	ship.api.set_cargo_door(false)
	check(bool(ship.api.get_telemetry().cargo_door_open), "cargo across threshold prevents closure")
	cargo.position.z = -4.5
	await _frames(3)
	ship.api.set_cargo_door(false)
	await _frames(3)
	check(not bool(ship.api.get_telemetry().cargo_door_open), "secured interior cargo does not obstruct door")
	check((ship.get_node("CargoVolume") as Area3D).get_overlapping_bodies().has(cargo), "cargo sensor sees the body inside")
	cargo.free()
	ship.free()


## Navigation state follows actual ship and reference-body motion through the API.
func test_ship_publishes_motion_and_tracks_reference() -> void:
	var ship: PlayerShip = _ship()
	var target: RigidBody3D = _box(Vector3(0, 0, -30), Vector3.ONE, 100.0)
	ship.linear_velocity = Vector3.RIGHT * 2.0
	target.linear_velocity = Vector3.RIGHT * 1.0
	ship.set_navigation_target(target)
	await _frames(4)
	var telemetry: Dictionary = ship.api.get_telemetry()
	check_near((telemetry.motion.velocity_mps as Vector3).length(), 2.0, 0.001, "API reports physical speed")
	check_near((telemetry.motion.relative_velocity_mps as Vector3).length(), 1.0, 0.001, "API reports relative target speed")
	target.free()
	await _frames(3)
	check(is_finite((ship.api.get_telemetry().motion.velocity_mps as Vector3).length()), "removed target fails soft")
	ship.free()


## Saturated RCS spends propellant according to impulse and releases into coasting.
func test_rcs_force_limit_fuel_cost_and_release() -> void:
	var ship: PlayerShip = _ship()
	ship.linear_velocity = Vector3.RIGHT * 20.0
	ship.api.set_braking(true)
	await _frames(3)
	var before_speed: float = ship.linear_velocity.x
	var before_fuel: float = float(ship.api.get_telemetry().propellant_kg)
	await _frames(12)
	var elapsed: float = 12.0 / float(Engine.physics_ticks_per_second)
	check_near(before_speed - ship.linear_velocity.x, PlayerShip.BRAKE_FORCE_N * elapsed / ship.mass, 0.001, "finite force determines braking acceleration")
	check_near(before_fuel - float(ship.api.get_telemetry().propellant_kg), PlayerShip.BRAKE_FORCE_N * elapsed / PlayerShip.EXHAUST_VELOCITY_MPS, 0.001, "fuel buys delivered linear impulse")
	# RigidBody3D.mass is float32, so at this ship's ~10 t mass the last decimal digit
	# is not representable; loosen from the usual 0.0001 to stay within float32 precision.
	check_near(ship.mass, float(ship.api.get_telemetry().mass_kg), 0.002, "burn updates physical mass")
	ship.api.set_braking(false)
	await _frames(3)
	var released: Vector3 = ship.linear_velocity
	await _frames(12)
	check(ship.linear_velocity.distance_to(released) < 0.0001, "released ship coasts without damping")
	ship.free()


## The final fraction of propellant delivers a partial impulse and then leaves drift.
func test_empty_propellant_and_disabled_rcs_cannot_brake() -> void:
	var ship: PlayerShip = _ship()
	ship.api.consume_propellant(1999.99)
	ship.linear_velocity = Vector3.RIGHT * 20.0
	ship.api.set_braking(true)
	await _frames(6)
	check_near(float(ship.api.get_telemetry().propellant_kg), 0.0, 0.0001, "last tiny propellant supply is consumed")
	check_near(ship.linear_velocity.x, 20.0 - 0.01 * PlayerShip.EXHAUST_VELOCITY_MPS / 8000.0, 0.0001, "partial final tick delivers only affordable impulse")
	var remaining: Vector3 = ship.linear_velocity
	await _frames(12)
	check(ship.linear_velocity.distance_to(remaining) < 0.0001, "empty ship remains stranded in drift")
	ship.free()
	ship = _ship()
	ship.linear_velocity = Vector3.RIGHT * 2.0
	ship.api.set_system_enabled("rcs", false)
	ship.api.set_braking(true)
	await _frames(12)
	check_near(ship.linear_velocity.x, 2.0, 0.0001, "disabled RCS cannot brake")
	check_near(float(ship.api.get_telemetry().propellant_kg), ShipApi.PROPELLANT_CAPACITY_KG, 0.0001, "disabled RCS spends no propellant")
	ship.free()


## Angular braking uses finite torque and fuel; it never snaps spin to zero.
func test_rcs_brakes_spin_with_finite_torque() -> void:
	var ship: PlayerShip = _ship()
	ship.angular_velocity = Vector3.UP * 0.5
	ship.api.set_braking(true)
	await _frames(3)
	var initial_spin: float = ship.angular_velocity.length()
	var initial_fuel: float = float(ship.api.get_telemetry().propellant_kg)
	await _frames(12)
	check(ship.angular_velocity.length() < initial_spin, "RCS counter-torque reduces spin")
	check(ship.angular_velocity.length() > 0.45, "finite torque cannot erase large-ship spin immediately")
	check(float(ship.api.get_telemetry().propellant_kg) < initial_fuel, "attitude jets consume propellant")
	ship.free()


## A real contact damages the system on the hit side using incoming kinetic energy.
func test_incoming_collision_damages_contacted_system() -> void:
	for speed: float in [2.0, 15.0]:
		var ship: PlayerShip = _ship()
		var before: float = _health(ship, "rcs")
		var projectile: RigidBody3D = _box(Vector3(-5.0, 0, 0), Vector3.ONE, 100.0)
		projectile.linear_velocity = Vector3.RIGHT * speed
		await _frames(100)
		check(ship.linear_velocity.x > 0.0, "collision transfers real momentum")
		if speed > 3.0:
			var energy: float = 0.5 * (10000.0 * 100.0 / 10100.0) * speed * speed
			check_near(_health(ship, "rcs"), before - (energy - PlayerShip.DAMAGE_THRESHOLD_J) / PlayerShip.SECTION_DAMAGE_ENERGY_J, 0.0001, "fast incoming contact charges energy once to port RCS section")
		else:
			check_near(_health(ship, "rcs"), before, 0.00001, "gentle contact is below damage threshold")
		check_near(_health(ship, "cargo"), 1.0, 0.00001, "uncontacted cargo system is unchanged")
		projectile.free()
		ship.free()


## Runtime hazard interception applies damage through the same public API.
func test_hazards_damage_ship_and_invalid_energy_is_ignored() -> void:
	var ship: PlayerShip = _ship()
	var before: float = _health(ship, "power")
	for tick: int in range(100):
		ship.receive_hazard_damage("fuel", 500.0)
	check(_health(ship, "power") < before, "fuel plume damages power section")
	before = _health(ship, "rcs")
	ship.receive_hazard_damage("coolant", 50000.0)
	check(_health(ship, "rcs") < before, "coolant plume damages exposed RCS")
	before = _health(ship, "rcs")
	ship.receive_hazard_damage("coolant", NAN)
	ship.receive_hazard_damage("coolant", -100.0)
	check_near(_health(ship, "rcs"), before, 0.0, "nonfinite and negative energy are ignored")
	ship.free()


func _ship() -> PlayerShip:
	var scene: PackedScene = load("res://scenes/player_ship.tscn")
	var ship: PlayerShip = scene.instantiate() as PlayerShip
	(Engine.get_main_loop() as SceneTree).root.add_child(ship)
	return ship


func _box(at: Vector3, size: Vector3, body_mass: float) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.position = at
	body.mass = body_mass
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.continuous_cd = true
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	return body


func _ray(ship: PlayerShip, from: Vector3, to: Vector3) -> Dictionary:
	return ship.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(from), ship.to_global(to), 1))


func _box_query(ship: PlayerShip, size: Vector3, at: Vector3) -> Array[Dictionary]:
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	query.shape = shape
	query.transform = ship.global_transform * Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1
	return ship.get_world_3d().direct_space_state.intersect_shape(query)


func _health(ship: PlayerShip, id: String) -> float:
	return float(ship.api.get_telemetry().systems[id].health)


func _frames(count: int) -> void:
	for index: int in range(count):
		await (Engine.get_main_loop() as SceneTree).physics_frame
