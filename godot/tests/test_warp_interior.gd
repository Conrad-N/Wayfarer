## Coasting warp keeps the interior playable; unrestrained maneuvers use live physics.
extends TestCase


## Sim time accelerates while free drift and collisions remain at ordinary suit speed.
func test_free_drift_and_hull_collision_during_warp() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player")
	var ship: PlayerShip = main.get_node("PlayerShip")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))
	player.linear_velocity = ship.global_basis * Vector3(0, 0, 0.2)
	check(ship.api.set_warp(100.0), "floating pilot requests warp")
	await _frames(2)
	var start: Vector3 = ship.to_local(player.global_position)
	var time_before: float = flight.session.world.time
	await _frames(60)
	var drift: Vector3 = ship.to_local(player.global_position) - start
	check_near(drift.z, 0.2, 0.025, "one second of suit drift is not multiplied by warp")
	check_near(flight.session.world.time - time_before, 100.0, 2.0, "orbit advances one hundred seconds")
	check(not flight.ship_is_local and ship.freeze and not player.freeze, "only hull is frozen during coasting warp")
	player.linear_velocity = ship.global_basis * Vector3(-1, 0, 0)
	await _frames(180)
	check(ship.to_local(player.global_position).x > -1.8, "solid hull stops drifting player")
	check(flight.is_aboard(), "collision retains pilot inside ship")
	check_near(flight.session.world.rate, 100.0, 1e-6, "touching hull does not end coast warp")
	main.free()


## Leaving the chair during a coast does not cancel warp or take control of the suit.
func test_unstrap_and_return_to_real_time_preserve_motion() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player")
	var ship: PlayerShip = main.get_node("PlayerShip")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	var interaction: ShipInteraction = main.get_node("ShipInteraction")
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, PlayerShip.SEAT_POSITION)
	await _frames(3)
	check(interaction.strap_in(), "fasten pilot harness")
	await _frames(4)
	check(ship.api.set_warp(1000.0), "seated coast starts")
	await _frames(4)
	interaction.unstrap()
	await _frames(3)
	check(not interaction.is_seated() and not flight.ship_is_local, "unstrap keeps analytic coast")
	check_near(flight.session.world.rate, 1000.0, 1e-6, "unstrap retains high warp")
	player.linear_velocity = ship.global_basis * Vector3(0, 0, 0.15)
	var relative: Vector3 = player.linear_velocity
	check(ship.api.set_warp(1.0), "return to real time")
	await _frames(2)
	check(flight.ship_is_local and not ship.freeze, "real time restores live hull for unstrapped pilot")
	check((player.linear_velocity - ship.linear_velocity).distance_to(relative) < 0.005, "no velocity kick on leaving warp")
	main.free()


## Powered walking keeps real-time speed, attachment and finite battery cost in warp.
func test_boot_walking_survives_both_handoffs() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player")
	var ship: PlayerShip = main.get_node("PlayerShip")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	var boots: MagneticBoots = player.get_node("MagneticBoots")
	player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.48, 0))
	player.linear_velocity = Vector3.ZERO
	await _frames(3)
	check(boots.try_latch(), "latch to ship deck")
	check(ship.api.set_warp(100.0), "latched boots do not block warp")
	await _frames(4)
	check(boots.is_attached() and not flight.ship_is_local, "deck attachment survives entering warp")
	var start: Vector3 = ship.to_local(player.global_position)
	var charge: float = player.suit.battery_energy_j
	var fuel: float = player.suit.propellant_kg
	(player.get_node("SuitContacts") as SuitContacts).set_physics_process(false)
	boots.set_walk_input(Vector2(0, -1))
	await _frames(60)
	boots.set_walk_input(Vector2.ZERO)
	var distance: float = ship.to_local(player.global_position).distance_to(start)
	check(distance > 0.2 and distance < 2.0, "walking moves at human speed during warp: %.3f m" % distance)
	check(boots.is_attached(), "walking retains magnetic latch")
	check(player.suit.battery_energy_j < charge, "walking spends finite suit battery")
	check_eq(player.suit.propellant_kg, fuel, "walking does not spend jet propellant")
	check(ship.api.set_warp(1.0), "walking pilot requests real time")
	await _frames(5)
	check(boots.is_attached() and flight.ship_is_local, "latch survives return to physical hull")
	main.free()


## Manual throttle and direction commands wake the hull before they can affect a free suit.
func test_unstrapped_maneuvers_drop_to_real_time() -> void:
	for command: String in ["burn", "turn"]:
		var main: Node3D = await _main()
		var player: Player = main.get_node("Player")
		var ship: PlayerShip = main.get_node("PlayerShip")
		var flight: OrbitalFlight = main.get_node("OrbitalFlight")
		check(ship.api.set_warp(1000.0), "start fast coast before " + command)
		await _frames(3)
		player.collision_layer = 0
		player.collision_mask = 0 # Measure freefall before the later physical wall contact.
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
		var initial_basis: Basis = player.global_basis
		var initial_position: Vector3 = ship.to_local(player.global_position)
		var time_before: float = flight.session.world.time
		if command == "burn":
			check(ship.api.set_throttle(1.0), "manual burn accepted")
		else:
			check(ship.api.set_attitude_mode("retrograde"), "manual turn accepted")
		await _frames(40)
		check(flight.ship_is_local and not ship.freeze, "maneuver wakes physical hull")
		check_near(flight.session.world.rate, 1.0, 1e-9, "unstrapped maneuver caps warp at one")
		check(flight.session.world.time - time_before < 0.8, "no accelerated maneuver tick escapes guard")
		check(player.linear_velocity.length() < 0.01, "hull cannot accelerate free suit without contact")
		check(player.global_basis.is_equal_approx(initial_basis), "hull cannot turn free suit without contact")
		if command == "burn":
			check(ship.to_local(player.global_position).distance_to(initial_position) > 0.5, "burn moves hull around floating suit")
			check(ship.api.flight_command("cutoff"), "end burn")
			await _frames(3)
			check(not flight.ship_is_local and flight.session.world.rate > 1.0, "selected warp resumes after burn ends")
		else:
			check(ship.angular_velocity.length() > 0.0001, "turn applies actual hull torque")
		main.free()


## A single large warp step stops at the executor's pointing window without burning early.
func test_event_warp_stops_before_unrestrained_maneuver() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player")
	var ship: PlayerShip = main.get_node("PlayerShip")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	flight.enabled = false
	var world: OrbitalWorld = flight.session.world
	check(ship.api.plan_maneuver(world.time + 150.0, 10.0, 0.0, 0.0), "preview imminent maneuver")
	check(ship.api.execute_plan(), "arm executor")
	check(ship.api.advance_to_next_event(), "unstrapped event warp accepted")
	var boundary: float = world.time + world.interior_coast_seconds()
	var fuel: float = world.ship.propellant_kg
	var pose: Transform3D = player.global_transform
	flight.enabled = true
	flight._physics_process(0.5)
	flight.enabled = false
	check_near(world.time, boundary, 1e-7, "large step stops exactly at pointing boundary")
	check_eq(world.ship.propellant_kg, fuel, "boundary coast spends no main fuel")
	check(player.global_basis.is_equal_approx(pose.basis), "coast does not rotate free player")
	flight.enabled = true
	flight._physics_process(1.0 / 60.0)
	flight.enabled = false
	check(flight.ship_is_local, "next tick starts maneuver in live hull")
	check_near(world.rate, 1.0, 1e-9, "executor cannot accelerate unrestrained maneuver")
	check(world.time - boundary < 0.02, "handoff advances only real-time physics")
	main.free()


## Neither exit may be open when warp starts, and both remain locked until real time.
func test_closed_exit_guards() -> void:
	var main: Node3D = await _main()
	var ship: PlayerShip = main.get_node("PlayerShip")
	check(ship.api.set_cargo_door(true), "open cargo hatch")
	check(not ship.api.set_warp(10.0), "open cargo hatch refuses warp")
	check(ship.api.last_message.contains("CLOSE"), "exit refusal explains remedy")
	check(ship.api.set_cargo_door(false), "close cargo hatch")
	check(ship.api.set_airlock_door("inner", false), "close inner")
	check(ship.api.set_airlock_door("outer", true), "open outer")
	check(not ship.api.set_warp(10.0), "open outer door refuses warp")
	check(not ship.api.advance_to_next_event(), "open outer door also refuses event warp")
	check(ship.api.set_airlock_door("outer", false), "close outer")
	check(ship.api.set_warp(100.0), "closed ship accepts warp")
	await _frames(3)
	var charge: float = ship.api.get_telemetry().battery_energy_j
	check(not ship.api.set_cargo_door(true), "cargo cannot open during accelerated coast")
	check(not ship.api.set_airlock_door("outer", true), "airlock cannot open during accelerated coast")
	check_eq(ship.api.get_telemetry().battery_energy_j, charge, "refused exits cost no energy")
	main.free()


## Arrival carries a drifting unseated suit into the encounter's frame without an impact.
func test_unseated_arrival_preserves_relative_drift() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player")
	var ship: PlayerShip = main.get_node("PlayerShip")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	check(ship.api.set_warp(100.0), "start unseated coast")
	await _frames(3)
	flight.enabled = false
	var world: OrbitalWorld = flight.session.world
	var reference: Dictionary = flight.session.object_state("kestrel", world.time)
	var drift: Vector3 = Vector3(0.2, 0.1, -0.15)
	player.linear_velocity = drift
	var local_pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	world.replace_state(SimVector.add(reference.position, SimVector.new(9000, 0, 0)), SimVector.add(reference.velocity, SimVector.new(-1500, 0, 0)))
	flight._enter_encounter("kestrel")
	check_near(world.rate, 1.0, 1e-9, "arrival immediately drops to real time")
	check((player.linear_velocity - ship.linear_velocity).distance_to(drift) < 0.001, "arrival preserves free relative drift at 1500 m/s")
	check((ship.global_transform.affine_inverse() * player.global_transform).is_equal_approx(local_pose), "arrival preserves interior pose")
	check(not ship.api.set_warp(10.0), "real encounter refuses warp")
	main.free()


## A physical interior still detects station arrival while the pilot is unstrapped.
func test_physical_interior_detects_nearby_station() -> void:
	var main: Node3D = await _main()
	var ship: PlayerShip = main.get_node("PlayerShip")
	var player: Player = main.get_node("Player")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	check(flight.ship_is_local and flight.reference_id == OrbitalFlight.EVA_REFERENCE_ID, "start in physical free-flight interior")
	var state: Dictionary = flight.session.world.ship_root_state()
	check(flight.session.store_object("lowline", SimVector.add(state.position, SimVector.new(500, 0, 0)), state.velocity, "cradle"), "place station inside encounter range")
	flight.session.objects.lowline.kind = "station"
	flight.session.objects.lowline.name = "Lowline Yard"
	var drift: Vector3 = player.linear_velocity - ship.linear_velocity
	await _frames(2)
	check(flight.ship_is_local and flight.reference_id == "lowline", "physical interior enters actual nearby station")
	check((player.linear_velocity - ship.linear_velocity).distance_to(drift) < 0.01, "changing coast reference preserves interior drift")
	check(not ship.api.set_warp(10.0), "nearby station keeps warp unavailable")
	main.free()


## Interior handholds and tethers survive entering and leaving the coasting room.
func test_ship_handhold_and_grapple_survive_warp() -> void:
	for held: bool in [true, false]:
		var main: Node3D = await _main()
		var player: Player = main.get_node("Player")
		var ship: PlayerShip = main.get_node("PlayerShip")
		var flight: OrbitalFlight = main.get_node("OrbitalFlight")
		var grip: PhysicalGrip = player.get_node("PhysicalGrip")
		player.global_transform = ship.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.6, 0, 0))
		await _frames(3)
		var point: Vector3 = ship.to_global(Vector3(1.9, 0, 0))
		check(grip.grab_body(ship, point) if held else player.grapple.attach_to(ship, point), "attach to interior hull")
		check(ship.api.set_warp(10.0), "interior attachment permits warp")
		await _frames(5)
		check(not flight.ship_is_local, "attached suit enters coasting room")
		check(grip.is_attached() if held else player.grapple.is_attached(), "attachment survives entry")
		check(ship.api.set_warp(1.0), "attached suit returns to real time")
		await _frames(5)
		check(flight.ship_is_local, "attached suit returns to physical hull")
		check(grip.is_attached() if held else player.grapple.is_attached(), "attachment survives exit")
		main.free()


## Saving a free drifting pilot during warp reloads their pose and motion at real time.
func test_save_load_free_coasting_interior() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player")
	var ship: PlayerShip = main.get_node("PlayerShip")
	check(ship.api.set_warp(100.0), "start coast for save")
	await _frames(3)
	player.linear_velocity = ship.global_basis * Vector3(0, 0, 0.1)
	var velocity: Vector3 = player.linear_velocity
	var pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	var state: Dictionary = SaveCodec.parse(SaveCodec.stringify(main.call("capture_game")))
	var saved_time: float = (main.get_node("OrbitalFlight") as OrbitalFlight).session.world.time
	main.free()
	var game: SaveGames = (Engine.get_main_loop() as SceneTree).root.get_node("Game")
	game.request_load(state)
	main = await _main()
	player = main.get_node("Player")
	ship = main.get_node("PlayerShip")
	var flight: OrbitalFlight = main.get_node("OrbitalFlight")
	check_near(flight.session.world.rate, 1.0, 1e-9, "load resumes at real time")
	check(flight.session.world.time - saved_time < 0.5, "load does not advance a stale warp tick: %.3f s" % (flight.session.world.time - saved_time))
	check((player.linear_velocity - ship.linear_velocity).distance_to(velocity) < 0.001, "load retains free relative drift")
	check(ship.to_local(player.global_position).distance_to(pose.origin) < 0.02, "load retains interior location")
	check(not (main.get_node("ShipInteraction") as ShipInteraction).is_seated(), "load keeps pilot unstrapped")
	main.free()


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
