## Station capture, physical constraint, shared controls and persistent berth state.
extends TestCase


## Capture requires the actual cargo port, correct facing, and slow point motion.
func test_capture_envelope_and_safety_interlocks() -> void:
	var f: Dictionary = _fixture()
	var api: ShipApi = f.ship.api
	var ship: PlayerShip = f.ship
	var flight: OrbitalFlight = f.flight
	check(not api.undock(), "cannot release a nonexistent clamp")
	for offset: Vector3 in [Vector3(0, 0, 1), Vector3(0.4, 0, 0), Vector3(0, 0, -0.4)]:
		_place(f, Vector3(0, 0, 0.2) + offset)
		check(not api.dock(), "reject offset %s" % offset)
	_place(f)
	ship.global_basis = Basis(Vector3.UP, deg_to_rad(6))
	ship.global_position = f.station.to_global(StationDock.PORT + Vector3(0, 0, 0.2)) - ship.global_basis * StationDock.SHIP_PORT
	check(not api.dock(), "wrong alignment rejected independently of separation")
	_place(f)
	ship.linear_velocity = Vector3(0.31, 0, 0)
	check(not api.dock(), "excessive lateral speed rejected")
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3(0.0, 0.021, 0.0)
	check(not api.dock(), "excessive spin rejected")
	ship.angular_velocity = Vector3(0.01, 0, 0)
	ship.linear_velocity = Vector3(0, 0.28, 0)
	check(not api.dock(), "port speed includes the angular lever, not just COM speed")
	_place(f)
	check(api.set_cargo_door(true), "open hatch for safety test")
	check(not api.dock(), "capture requires closed cargo hatch")
	api.set_cargo_door(false)
	api.set_airlock_door("inner", false)
	api.set_airlock_door("outer", true)
	check(not api.dock(), "capture requires closed outer airlock")
	api.set_airlock_door("outer", false)
	api.set_throttle(0.1)
	check(not api.dock(), "main burn cannot engage clamp")
	api.flight_command("cutoff")
	api.set_rcs_translation(Vector3.RIGHT)
	check(not api.dock(), "held RCS cannot engage clamp")
	api.set_rcs_translation(Vector3.ZERO)
	var before: Transform3D = ship.global_transform
	check(api.dock(), "slow aligned capture succeeds")
	check_eq(ship.global_transform, before, "capture never snaps the hull pose")
	check(not ship.freeze, "clamp retains live hull physics")
	check(bool(api.get_telemetry().flight.docking.docked), "API publishes captured state immediately")
	check(not api.dock(), "second capture does not replace joint")
	check(not api.set_throttle(0.1), "engine inhibited while docked")
	check(not api.set_rcs_translation(Vector3.RIGHT), "RCS inhibited while docked")
	check(not api.set_braking(true), "brake cannot waste fuel against the clamp")
	check(not api.set_attitude_mode("target"), "turning inhibited while docked")
	check(not api.execute_plan(), "executor inhibited while docked")
	check(not api.approach_dock(), "guidance inhibited while docked")
	check(not api.set_warp(10), "station remains at real time")
	check(api.set_throttle(0) and api.set_rcs_translation(Vector3.ZERO), "stop commands remain available")
	check_eq(flight.session.world.attitude_mode, "manual", "clamp stops attitude motors")
	check_eq(flight.session.world.throttle, 0.0, "clamp stops main drive")
	f.root.free()


## Jolt holds the berth through pushes and origin shifts; release adds no impulse.
func test_physical_hold_release_and_orbital_snapshot() -> void:
	var f: Dictionary = _fixture()
	var ship: PlayerShip = f.ship
	var api: ShipApi = ship.api
	var flight: OrbitalFlight = f.flight
	await _frames(3)
	check(api.dock(), "engage live clamp")
	flight.enabled = true
	var pose: Transform3D = f.station.global_transform.affine_inverse() * ship.global_transform
	var fuel: float = api.get_telemetry().propellant_kg
	ship.apply_central_impulse(Vector3(2000, 300, 1000))
	ship.apply_torque_impulse(Vector3(300, 100, 200))
	await _frames(90)
	var held: Transform3D = f.station.global_transform.affine_inverse() * ship.global_transform
	check(held.origin.distance_to(pose.origin) < 0.03, "constraint resists external shove")
	check(ship.linear_velocity.length() < 0.02, "station absorbs capture and push motion")
	check_near(api.get_telemetry().propellant_kg, fuel, 1e-8, "clamp holds without RCS fuel")
	var roots: Array[Node3D] = [ship, f.player, f.station]
	flight.frame.recentre(roots, Vector3(2300, -300, 200))
	await _frames(30)
	check(ship.global_position.distance_to(f.station.global_transform * pose.origin) < 0.04, "origin shift preserves constraint")
	flight._refresh_local_snapshot()
	var state: Dictionary = flight.session.world.ship_root_state()
	var expected: SimVector = flight.frame.to_orbital_position(ship.to_global(ship.center_of_mass))
	check_near(SimVector.distance(state.position, expected), 0.0, 1e-6, "orbital position follows live docked COM")
	check_near(SimVector.distance(state.velocity, flight.frame.to_orbital_velocity(ship.linear_velocity)), 0.0, 1e-7, "orbital velocity includes station travel")
	api.set_cargo_door(true)
	check(not api.undock(), "open exterior hatch blocks release")
	api.set_cargo_door(false)
	api.set_system_enabled("power", false)
	var velocity: Vector3 = ship.linear_velocity
	var spin: Vector3 = ship.angular_velocity
	var at: Transform3D = ship.global_transform
	check(api.undock(), "mechanical release works with ship power off")
	check_eq(ship.global_transform, at, "release preserves pose")
	check_eq(ship.linear_velocity, velocity, "release grants no departure velocity")
	check_eq(ship.angular_velocity, spin, "release grants no angular impulse")
	api.set_system_enabled("power", true)
	check(api.set_rcs_translation(Vector3.BACK), "real departure RCS restored")
	await _frames(90)
	api.set_rcs_translation(Vector3.ZERO)
	check(ship.linear_velocity.z > 0.1, "released ship departs under its own jets")
	check(float(api.get_telemetry().propellant_kg) < fuel, "departure spends propellant")
	f.root.free()


## The berth survives JSON and cargo COM reconstruction, including unpowered saves.
func test_save_load_restores_station_relative_clamp() -> void:
	var f: Dictionary = _fixture()
	var ship: PlayerShip = f.ship
	ship.center_of_mass = Vector3(0.4, 0.1, -1.2)
	check(ship.api.dock(), "capture loaded hull")
	ship.api.set_cargo_door(true)
	ship.api.set_system_enabled("power", false)
	var pose: Transform3D = f.station.global_transform.affine_inverse() * ship.global_transform
	var saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(f.flight.capture_save()))
	f.root.free()
	var fresh: Dictionary = (load("res://tests/test_orbital_flight.gd") as GDScript).new()._fixture()
	fresh.flight.apply_save(saved)
	fresh.ship.center_of_mass = Vector3(0.4, 0.1, -1.2) # Main rebuilds cargo after flight.
	var station: StationDock = fresh.flight._station
	check(station.is_docked(), "JSON load reconstructs clamp")
	check((station.global_transform.affine_inverse() * fresh.ship.global_transform).origin.distance_to(pose.origin) < 0.0001, "saved hull pose ignores COM reconstruction order")
	check(fresh.ship.api.get_telemetry().cargo_door_open, "load retains an open hatch")
	check(not fresh.ship.api.get_telemetry().power_available, "load retains switched-off power")
	fresh.flight.enabled = true
	await _frames(60)
	check(fresh.ship.global_position.distance_to(station.global_transform * pose.origin) < 0.03, "restored clamp stays stable after cargo mass frame changes")
	check_eq(fresh.ship.api.get_telemetry().flight.warp, 1.0, "load remains at real time")
	fresh.root.free()


## Guidance stages on the clear front, uses finite resources, and leaves capture explicit.
func test_guided_approach_reaches_capture_envelope() -> void:
	var f: Dictionary = _fixture()
	var ship: PlayerShip = f.ship
	var api: ShipApi = ship.api
	_place(f, Vector3(1.5, 0, 14.5))
	check(api.approach_dock(), "front apron admits guidance")
	var fuel: float = api.get_telemetry().propellant_kg
	f.flight.enabled = true
	var ready: bool = false
	for step: int in 4500:
		await _frames(1)
		if bool(f.station.reading(ship).ready):
			ready = true
			break
	check(ready, "guidance reaches the capture envelope: %s" % f.station.reading(ship))
	check(not f.station.is_docked(), "guidance never silently engages the clamp")
	check(float(api.get_telemetry().propellant_kg) < fuel, "approach pays for RCS")
	check(api.dock(), "pilot explicitly captures after guidance")
	check(not f.station.guiding, "capture disengages guidance")
	f.root.free()


## Guidance refuses obstructed/backside approaches and obeys pilot cancellation.
func test_guidance_gates_and_cancellation() -> void:
	var f: Dictionary = _fixture()
	var api: ShipApi = f.ship.api
	_place(f, Vector3(2, 0, 5))
	check(not api.approach_dock(), "no diagonal shortcut through ring")
	_place(f, Vector3(0, 0, -1))
	check(not api.approach_dock(), "no approach from station rear")
	_place(f, Vector3(0, 0, 5))
	f.ship.global_basis = Basis(Vector3.UP, deg_to_rad(20))
	f.ship.global_position = f.station.to_global(StationDock.PORT + Vector3(0, 0, 5)) - f.ship.global_basis * StationDock.SHIP_PORT
	check(not api.approach_dock(), "close corridor requires alignment before guidance")
	_place(f, Vector3(0, 0, 15))
	api.select_target("kestrel")
	check(not api.approach_dock(), "select nearby station explicitly")
	api.select_target("lowline")
	f.ship.linear_velocity = Vector3(0, 0, 2.1)
	check(not api.approach_dock(), "match speed first")
	f.ship.linear_velocity = Vector3.ZERO
	api.set_system_enabled("rcs", false)
	check(not api.approach_dock(), "guidance needs usable RCS")
	api.set_system_enabled("rcs", true)
	check(api.flight_command("approach"), "existing station approach uses ring guidance")
	check(f.station.guiding, "shared approach arms berth guide")
	check(api.cancel_plan(), "cutoff cancels docking approach")
	check(not f.station.guiding, "no hidden thrust after cancellation")
	check(api.approach_dock(), "guide can restart")
	api.set_rcs_translation(Vector3.LEFT)
	check(not f.station.guiding, "manual thrust takes over")
	api.set_rcs_translation(Vector3.ZERO)
	api.approach_dock()
	api.set_attitude_mode("manual")
	check(not f.station.guiding, "manual pointing cancels guidance")
	api.approach_dock()
	api.set_system_enabled("power", false)
	f.flight.enabled = true
	f.flight._physics_process(1.0 / 60.0)
	f.flight.enabled = false
	check(not f.station.guiding, "power failure cancels guidance")
	f.root.free()


## Being aligned at long range must not start the half-metre-per-second final crawl.
func test_far_approach_keeps_transit_stage_until_near_ring() -> void:
	var f: Dictionary = _fixture()
	_place(f, Vector3(0, 0, 3000))
	check(f.ship.api.approach_dock(), "aligned long-range approach accepted")
	var target: Vector3 = f.station.guidance_position(f.ship)
	check(not f.station.final_approach, "three kilometres away remains transit, not final crawl")
	check_near(f.station.to_local(target).z, StationDock.PORT.z - StationDock.SHIP_PORT.z + 14.0, 0.001, "transit aims at safe staging distance")
	f.root.free()


## Open space, derelicts and older saves have no implicit station clamp.
func test_docking_requires_station_and_old_saves_remain_free() -> void:
	var f: Dictionary = (load("res://tests/test_orbital_flight.gd") as GDScript).new()._fixture()
	check(not f.ship.api.dock(), "open orbit cannot dock")
	check(not f.ship.api.approach_dock(), "open orbit cannot guide to a ring")
	var saved: Dictionary = f.flight.capture_save()
	saved.erase("docking")
	f.flight.apply_save(saved)
	check(not f.ship.api.get_telemetry().flight.docking.docked, "older undocked save stays free")
	f.flight._enter_encounter("kestrel")
	check(not f.ship.api.dock(), "derelict encounter cannot be mistaken for a station")
	check(not f.ship.api.get_telemetry().flight.docking.available, "derelict has no station docking telemetry")
	f.root.free()


func _fixture() -> Dictionary:
	var f: Dictionary = (load("res://tests/test_orbital_flight.gd") as GDScript).new()._fixture()
	f.flight._enter_encounter("lowline")
	f.station = f.flight._station
	_place(f)
	f.ship.api.select_target("lowline")
	return f


func _place(f: Dictionary, offset: Vector3 = Vector3(0, 0, 0.2)) -> void:
	f.ship.global_basis = Basis.IDENTITY
	f.ship.global_position = f.station.to_global(StationDock.PORT + offset) - StationDock.SHIP_PORT
	f.ship.linear_velocity = Vector3.ZERO
	f.ship.angular_velocity = Vector3.ZERO
	f.player.global_position = f.ship.to_global(Vector3(0, 0, 1))
	f.flight._refresh_local_snapshot()
	f.flight._publish()


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for step: int in count:
		await tree.physics_frame
		await tree.process_frame
