## Shared API and real Jolt integration across orbital travel and local encounters.
extends TestCase


## The ship and every screen see the same authoritative main/RCS/cargo mass.
func test_backend_resources_and_command_validation() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var api: ShipApi = fixture.ship.api
	var world: OrbitalWorld = fixture.session.world
	check(bool(api.get_telemetry().flight.available), "flight backend bound")
	check_near(world.current_mass(), 34100.0, 1e-9, "main fuel, RCS and transported suit counted independently")
	check(not api.set_throttle(NAN), "invalid throttle rejected")
	check(not api.set_warp(1000000.0), "unsupported warp rejected")
	check(not api.set_attitude_mode("teleport"), "unknown attitude rejected")
	check(not api.select_target("missing"), "unknown target rejected")
	check(api.set_cargo_door(true), "cargo door opens")
	check(api.register_cargo("test-plate", Vector3.ONE, 125.0, 1.0), "cargo ledger accepts fitting part")
	api.consume_propellant(10.0)
	flight._sync_mass()
	check_near(world.structural_mass_kg(), 10215.0, 1e-9, "RCS and cargo are inert mass for main drive")
	check_near(world.current_mass(), 34215.0, 1e-9, "all actual masses agree")
	var rcs_before: float = api.get_telemetry().propellant_kg
	check(api.set_throttle(0.5), "manual main engine command accepted")
	check_eq(api.get_telemetry().flight.burn_status, "MAIN THRUST", "manual thrust is not labelled coasting")
	flight._advance_orbit(1.0)
	check(float(api.get_telemetry().main_propellant_kg) < 24000.0, "main burn spends main tank")
	check_eq(api.get_telemetry().propellant_kg, rcs_before, "main burn does not spend RCS tank")
	fixture.root.free()


## Previewing is reversible, and execution rechecks fuel and rejects active-plan replacement.
func test_plan_preview_execute_and_resource_recheck() -> void:
	var fixture: Dictionary = _fixture()
	var api: ShipApi = fixture.ship.api
	var world: OrbitalWorld = fixture.session.world
	check(api.plan_maneuver(world.time + 90.0, 100.0, 0.0, 0.0), "custom node preview accepted")
	check(world.nodes.is_empty() and not world.executor_on, "preview never lights engine")
	check(not world.pending_maneuver.is_empty(), "preview stored")
	world.ship.propellant_kg = 0.01
	check(not api.execute_plan(), "fuel changed since preview blocks execution")
	check(world.nodes.is_empty(), "failed execution commits no nodes")
	world.ship.propellant_kg = 24000.0
	check(api.plan_maneuver(world.time + 90.0, 100.0, 0.0, 0.0), "recalculated node accepted")
	check(api.execute_plan(), "feasible plan commits through API")
	check(world.executor_on and world.nodes.size() == 1, "executor armed on committed node")
	check(not api.plan_maneuver(world.time + 120.0, 50.0, 0.0, 0.0), "active executor cannot be silently replaced")
	check(api.cancel_plan(), "cancel releases executor")
	check(world.nodes.is_empty() and world.pending_maneuver.is_empty() and world.throttle == 0.0, "cancel clears both plans and thrust")
	check(api.flight_command("plan_hohmann", {"altitude_m": 450000.0}), "Hohmann preview builds")
	world.advance(1.0)
	check(api.execute_plan(), "Hohmann preview survives human review delay")
	fixture.root.free()


## Cross-frame targets remain visible but same-body solvers cannot use the wrong gravity.
func test_cross_frame_solver_gates_and_telemetry() -> void:
	var fixture: Dictionary = _fixture()
	var world: OrbitalWorld = fixture.session.world
	var moon: Dictionary = world.system.body("lune")
	world.targets.append({"id": "moon-station", "name": "Moon station", "kind": "station", "body_id": "lune", "elements": SimConstants.circular_orbit(moon, 50000.0)})
	var api: ShipApi = fixture.ship.api
	check(api.select_target("moon-station"), "cross-frame target selectable")
	check(float(api.get_telemetry().flight.target.range_m) > 1e8, "cross-frame range resolves correctly")
	check(not api.plan_intercept(4800.0), "Lambert gated across central bodies")
	check(not api.flight_command("plan_match_velocity"), "velocity match gated across central bodies")
	var state: Dictionary = OrbitMath.propagate(SimConstants.circular_orbit(moon, 100000.0), moon, world.time)
	check(world.replace_state(state.position, state.velocity, "lune"), "test ship moved into the target frame")
	check(api.plan_intercept(4800.0), "same target becomes solvable in shared frame")
	fixture.root.free()


## Warp guards cover actual EVA, nearby encounters and attitude catch-up.
func test_warp_eva_and_local_guards() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var api: ShipApi = fixture.ship.api
	check(api.set_warp(1000.0), "aboard in open orbit can warp")
	check(api.set_attitude_mode("prograde"), "direction hold available")
	check(api.set_warp(1000.0), "warp request accepted while settling attitude")
	check_eq(fixture.session.world.attitude_mode, "kill", "high warp requests settle rotation")
	api.set_throttle(0.5)
	var before: float = fixture.session.world.time
	flight._advance_orbit(0.5)
	check(float(fixture.session.world.time) - before <= 5.0001, "manual main burn also caps effective warp at ten")
	api.flight_command("cutoff")
	fixture.player.global_position = fixture.ship.to_global(Vector3(0, 0, 8))
	check(not api.set_warp(10.0), "outside suit prevents warp")
	flight.enabled = true
	flight._physics_process(1.0 / 60.0)
	flight.enabled = false
	check(flight.ship_is_local, "EVA switches the ship to physical integration")
	check_eq(flight.reference_id, OrbitalFlight.EVA_REFERENCE_ID, "EVA uses independent coast reference")
	check(not api.advance_to_next_event(), "EVA blocks event warp")
	check(not api.set_warp(10.0), "physical EVA keeps warp at one")
	fixture.player.global_position = fixture.ship.to_global(Vector3(0, 0, 1))
	flight.enabled = true
	flight._physics_process(1.0 / 60.0)
	flight.enabled = false
	check(flight.reference_id.is_empty() and not flight.ship_is_local, "reboarding free-flight ship restores orbital travel")
	check(api.set_warp(10.0), "warp resumes after reboarding")
	fixture.root.free()


## Warp rate membership is judged with is_equal_approx (T5), so a control that
## hands over a slightly-off float is accepted and a genuinely wrong rate is not.
func test_warp_rate_accepts_rounding() -> void:
	var fixture: Dictionary = _fixture()
	var api: ShipApi = fixture.ship.api
	check(api.set_warp(10.0 + 1e-9), "warp rate a hair above ten is accepted")
	check(not api.set_warp(11.0), "unlisted warp rate is still rejected")
	fixture.root.free()


## Local arrival preserves both momenta and physical departure fits a changed orbit.
func test_arrival_departure_state_and_burn_continuity() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var api: ShipApi = fixture.ship.api
	var reference: Dictionary = fixture.session.object_state("kestrel", world.time)
	var position: SimVector = SimVector.add(reference.position, SimVector.new(500.0, 200.0, 100.0))
	var velocity: SimVector = SimVector.add(reference.velocity, SimVector.new(2.0, 0.0, -1.0))
	check(world.replace_state(position, velocity), "arriving orbital state accepted")
	flight._enter_encounter("kestrel")
	check(flight.ship_is_local and not fixture.ship.freeze, "arrival enables physical ship")
	check_near(fixture.ship.linear_velocity.distance_to(Vector3(2, 0, -1)), 0.0, 0.001, "arrival velocity relative to actual target")
	check_near(SimVector.distance(flight.frame.to_orbital_position(fixture.ship.to_global(fixture.ship.center_of_mass)), position), 0.0, 0.001, "arrival position continuous")
	check(not api.set_warp(10.0), "near wreck enforces one-times time")
	await _frames(3)
	var before_velocity: Vector3 = fixture.ship.linear_velocity
	var fuel_before: float = api.get_telemetry().main_propellant_kg
	check(api.set_throttle(0.5), "main engine works inside encounter")
	for step: int in range(12):
		flight._advance_local(1.0 / float(Engine.physics_ticks_per_second))
		await _frames(1)
		fixture.player.global_position = fixture.ship.to_global(Vector3(0, 0, 1))
	flight._refresh_local_snapshot()
	check(fixture.ship.linear_velocity.distance_to(before_velocity) > 0.6, "Jolt receives main-engine force")
	check(float(api.get_telemetry().main_propellant_kg) < fuel_before, "local main burn pays fuel")
	var root_position: SimVector = flight.frame.to_orbital_position(fixture.ship.to_global(fixture.ship.center_of_mass))
	var root_velocity: SimVector = flight.frame.to_orbital_velocity(fixture.ship.linear_velocity)
	flight._leave_local_ship()
	check_near(SimVector.distance(world.current_rv().r, root_position), 0.0, 0.001, "departure carries actual moved position")
	check_near(SimVector.distance(world.current_rv().v, root_velocity), 0.0, 1e-6, "departure carries actual burn velocity")
	check_eq(world.throttle, 0.5, "ongoing burn survives physical handoff")
	var remaining: float = world.ship.propellant_kg
	world.advance(0.1)
	check(not world.powered_state.is_empty() and float(world.ship.propellant_kg) < remaining, "orbital integrator continues the same burn")
	fixture.root.free()


## RCS buys only its delivered physical impulse from its separate finite tank.
func test_local_rcs_resource_and_cutoff() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var api: ShipApi = fixture.ship.api
	var reference: Dictionary = fixture.session.object_state("kestrel", world.time)
	world.replace_state(SimVector.add(reference.position, SimVector.new(100.0, 0.0, 0.0)), reference.velocity)
	flight._enter_encounter("kestrel")
	await _frames(3)
	var main_before: float = api.get_telemetry().main_propellant_kg
	var rcs_before: float = api.get_telemetry().propellant_kg
	check(api.set_rcs_translation(Vector3.RIGHT), "RCS command reaches driver")
	for step: int in range(6):
		flight._advance_local(1.0 / float(Engine.physics_ticks_per_second))
		await _frames(1)
	check(fixture.ship.linear_velocity.length() > 0.02, "RCS pushes the physical ship")
	check_near(rcs_before - float(api.get_telemetry().propellant_kg), 1000.0 / PlayerShip.EXHAUST_VELOCITY_MPS, 0.001, "RCS fuel matches six 60 Hz impulses")
	check_eq(api.get_telemetry().main_propellant_kg, main_before, "RCS preserves main tank")
	check(api.flight_command("cutoff"), "cutoff accepted")
	var rcs_after: float = api.get_telemetry().propellant_kg
	flight._advance_local(1.0 / 60.0)
	await _frames(1)
	check_eq(api.get_telemetry().propellant_kg, rcs_after, "cutoff clears held RCS translation")
	api.select_target("lowline")
	check(not api.flight_command("approach"), "approach refuses a different selected target")
	api.select_target("kestrel")
	check(api.flight_command("approach"), "nearby selected target can be approached")
	api.select_target("lowline")
	check(not flight._approaching, "target selection releases previous approach")
	fixture.root.free()


## Refreshing a local snapshot uses the current reference epoch, avoiding a false 128 m offset.
func test_local_telemetry_uses_same_epoch_as_reference() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var reference: Dictionary = fixture.session.object_state("kestrel", world.time)
	world.replace_state(SimVector.add(reference.position, SimVector.new(50.0, 0.0, 0.0)), reference.velocity)
	flight._enter_encounter("kestrel")
	flight._advance_local(1.0 / 60.0)
	flight._publish()
	check_near(fixture.ship.api.get_telemetry().flight.target.range_m, 50.0, 0.002, "near target range is not polluted by orbital travel during tick")
	check_near(fixture.ship.api.get_telemetry().flight.target.relative_speed_mps, 0.0, 0.002, "co-moving ship retains zero relative velocity")
	fixture.root.free()


## The reviewed default transfer really flies into a live salvage encounter and matches velocity.
func test_guided_transfer_arrives_through_live_jolt() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var api: ShipApi = fixture.ship.api
	fixture.player.freeze = false
	fixture.player.collision_layer = 1
	fixture.player.collision_mask = 1
	var terminal: WorldScreen = preload("res://ui/world_screen.tscn").instantiate() as WorldScreen
	terminal.configure(api, "NAV")
	fixture.ship.get_node("NavTerminalMount").add_child(terminal)
	var interaction: ShipInteraction = ShipInteraction.new()
	fixture.root.add_child(interaction)
	interaction.configure(fixture.player, fixture.ship)
	fixture.player.global_transform = fixture.ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)
	await _frames(3)
	check(interaction.strap_in(), "pilot straps into physical seat")
	check(interaction.open_terminal(terminal), "pilot uses real NAV terminal from seat")
	check(interaction.is_seated() and not fixture.player.freeze, "seat carries a live finite-mass suit")
	check(api.plan_intercept(9600.0), "160-minute guided transfer previews")
	check(api.execute_plan(), "reviewed transfer commits")
	check_eq(world.nodes.size(), 5, "departure, three trims and arrival match queued")
	api.set_warp(1000.0)
	for step: int in range(2000):
		if flight.ship_is_local or world.time > 9800.0:
			break
		flight.enabled = true
		flight._physics_process(0.5)
		flight.enabled = false
		interaction._physics_process(0.5)
	check(flight.ship_is_local and flight.reference_id == "kestrel", "analytic transfer enters the actual wreck scene")
	check(not fixture.wreck.bodies.is_empty(), "salvage bodies exist on arrival")
	check(world.executor_on and world.nodes.size() == 1, "arrival burn continues across local handoff")
	if not flight.ship_is_local:
		fixture.root.free()
		return
	# Eight-times faster test wall-clock, with the production 1/60 s Jolt step unchanged.
	var old_hz: int = Engine.physics_ticks_per_second
	var old_scale: float = Engine.time_scale
	Engine.physics_ticks_per_second = 480
	Engine.time_scale = 8.0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	flight.enabled = true
	var end_time: float = world.time + 300.0
	while not world.nodes.is_empty() and world.time < end_time:
		await tree.process_frame
	flight.enabled = false
	Engine.physics_ticks_per_second = old_hz
	Engine.time_scale = old_scale
	flight._refresh_local_snapshot()
	flight._publish()
	var arrival: Dictionary = api.get_telemetry().flight.target
	check(world.nodes.is_empty() and not world.executor_on, "real local controller completes final match")
	check(flight.ship_is_local, "ship remains inside the salvage encounter")
	check(float(arrival.range_m) < 1000.0, "arrival within one kilometre of real wreck")
	check(float(arrival.relative_speed_mps) < 5.0, "arrival relative speed suitable for local handling")
	check(float(api.get_telemetry().main_propellant_kg) > 0.0, "arrival retains main fuel")
	check(float(api.get_telemetry().main_propellant_kg) < 24000.0, "journey paid actual engine propellant")
	check_near(api.get_telemetry().propellant_kg, ShipApi.PROPELLANT_CAPACITY_KG, 0.001, "main-drive journey preserves RCS reserve")
	interaction.close_screen()
	interaction.unstrap()
	check(not fixture.player.get_collision_exceptions().has(fixture.ship), "releasing handhold restores suit/hull collisions")
	check(not fixture.player.freeze, "released suit returns to physical flight")
	fixture.root.free()


## Failed power or reaction wheel cannot steer in either layer, while existing spin persists.
func test_attitude_requires_working_power_and_reaction_wheel() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var api: ShipApi = fixture.ship.api
	world.set_manual_torque(SimVector.new(5000.0, 0.0, 0.0))
	api.set_system_enabled("power", false)
	flight._advance_orbit(1.0)
	check_near(SimVector.length(world.angular_vel), 0.0, 1e-12, "unpowered orbital wheel cannot spin ship up")
	world.angular_vel = SimVector.new(0.01, 0.0, 0.0)
	flight._advance_orbit(1.0)
	check_near(world.angular_vel.x, 0.01, 1e-12, "unpowered ship retains existing principal-axis spin")
	api.set_system_enabled("power", true)
	api.set_system_enabled("reaction_wheel", false)
	world.angular_vel = SimVector.new()
	flight._advance_orbit(1.0)
	check_near(SimVector.length(world.angular_vel), 0.0, 1e-12, "disabled reaction wheel cannot steer orbital ship")
	api.set_system_enabled("reaction_wheel", true)
	var target: Dictionary = fixture.session.object_state("kestrel", world.time)
	world.replace_state(SimVector.add(target.position, SimVector.new(100, 0, 0)), target.velocity)
	flight._enter_encounter("kestrel")
	await _frames(3)
	flight._advance_local(1.0 / 120.0)
	await _frames(2)
	var spin: Vector3 = fixture.ship.angular_velocity
	check(spin.length() > 0.0, "powered local wheel supplies physical torque")
	api.set_system_enabled("power", false)
	flight._advance_local(1.0 / 120.0)
	await _frames(2)
	check_near(fixture.ship.angular_velocity.distance_to(spin), 0.0, 0.0001, "power loss also gates held fractional control torque")
	api.set_system_enabled("power", true)
	api.apply_damage("reaction_wheel", 1.0)
	spin = fixture.ship.angular_velocity
	flight._advance_local(1.0 / 60.0)
	await _frames(2)
	check_near(fixture.ship.angular_velocity.distance_to(spin), 0.0, 0.0001, "destroyed reaction wheel cannot steer physical ship")
	fixture.root.free()


## Warp only changes how many frames a sim-time interval is split into before
## each one calls _advance_solar; the energy collected over the same interval
## (~half the default 400 km orbit, well under the empty battery's 20 MJ cap)
## must not depend on that chunking, whether warp is 10 or 1000.
func test_solar_charging_matches_across_warp_rates() -> void:
	var gained: Dictionary = {}
	for rate: float in [10.0, 1000.0]:
		var fixture: Dictionary = _fixture()
		var flight: OrbitalFlight = fixture.flight
		var world: OrbitalWorld = fixture.session.world
		var api: ShipApi = fixture.ship.api
		api.consume_energy(ShipApi.BATTERY_CAPACITY_J)
		var half: float = float(world.orbit().period) * 0.5
		world.set_rate(rate)
		var remaining: float = half
		while remaining > 1e-6:
			var real_dt: float = minf(1.0, remaining / rate)
			var before: float = world.time
			world.advance(real_dt)
			flight._advance_solar(before)
			remaining -= (world.time - before)
		gained[rate] = float(api.get_telemetry().battery_energy_j)
		fixture.root.free()
	print("solar warp independence: warp10=%.1f J warp1000=%.1f J diff=%.3f%%" % [gained[10.0], gained[1000.0], 100.0 * absf(gained[1000.0] - gained[10.0]) / gained[10.0]])
	check(gained[10.0] > 0.0 and gained[10.0] < ShipApi.BATTERY_CAPACITY_J, "half orbit charges without hitting the 20 MJ cap")
	check_close(gained[1000.0], gained[10.0], 0.02, "warp 10 and warp 1000 collect the same energy within 2%")


## The energy collected over an interval should equal the wings' unshadowed
## face-on output times the time actually spent unshadowed, checked on the
## same sub-step grid _advance_solar uses internally.
func test_solar_charging_matches_power_times_sunlit_time() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var api: ShipApi = fixture.ship.api
	api.consume_energy(ShipApi.BATTERY_CAPACITY_J)
	var half: float = float(world.orbit().period) * 0.5
	var body: Dictionary = world.get_body()
	var span: SimVector = SolarArray.span_axis(world.orientation)
	var sun_dir: SimVector = SolarArray.sun_bearing(world.system, world.ship_root_state().position, world.time).direction
	var unshadowed_power_w: float = float(SolarArray.PANEL_COUNT) * SolarArray.PANEL_AREA_M2 * SolarArray.CELL_EFFICIENCY * SolarArray.IRRADIANCE_AT_AU_WM2 * SolarArray.tracking_factor(sun_dir, span)
	var before: float = world.time
	var samples: int = clampi(ceili(half / OrbitalFlight.SOLAR_SAMPLE_S), 1, OrbitalFlight.SOLAR_MAX_SAMPLES)
	var step: float = half / float(samples)
	var sunlit_seconds: float = 0.0
	for index: int in samples:
		var at_time: float = before + step * (float(index) + 0.5)
		if not SolarArray.shadowed(world.orbit_at(at_time).position, sun_dir, body):
			sunlit_seconds += step
	world.set_rate(1000.0)
	world.advance(half / 1000.0)
	flight._advance_solar(before)
	check_close(float(api.get_telemetry().battery_energy_j), unshadowed_power_w * sunlit_seconds, 0.001, "gain matches face-on output times sunlit seconds")
	check(sunlit_seconds > half * 0.5 and sunlit_seconds < half * 0.75, "roughly 61% of the default orbit is sunlit")
	fixture.root.free()


## Charging must work with the battery flat and ship power off, and power must
## return once the battery holds any charge; a full sunlit orbit (~61% of the
## ~92-minute default orbit) exceeds the 20 MJ cap.
func test_flat_battery_recovers_and_restores_power() -> void:
	var fixture: Dictionary = _fixture()
	var flight: OrbitalFlight = fixture.flight
	var world: OrbitalWorld = fixture.session.world
	var api: ShipApi = fixture.ship.api
	api.consume_energy(ShipApi.BATTERY_CAPACITY_J)
	check_eq(api.get_telemetry().battery_energy_j, 0.0, "battery drained for the test")
	check(not bool(api.get_telemetry().power_available), "a flat battery cuts power even with every switch on")
	var period: float = float(world.orbit().period)
	world.set_rate(1000.0)
	var before: float = world.time
	world.advance(period / 1000.0)
	flight._advance_solar(before)
	var telemetry: Dictionary = api.get_telemetry()
	check(float(telemetry.battery_energy_j) > 0.0, "sunlight recharges a flat, unpowered battery")
	check(bool(telemetry.power_available), "ship power returns once the battery holds charge")
	check_near(float(telemetry.battery_energy_j), ShipApi.BATTERY_CAPACITY_J, 1.0, "a full sunlit orbit gains more than the 20 MJ cap")
	fixture.root.free()


func _fixture() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var holder: Node3D = Node3D.new()
	tree.root.add_child(holder)
	var session: OrbitalSession = OrbitalSession.new()
	holder.add_child(session)
	var ship: PlayerShip = (load("res://scenes/player_ship.tscn") as PackedScene).instantiate() as PlayerShip
	holder.add_child(ship)
	var player: Player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	player.input_enabled = false
	player.freeze = true
	player.set_meta("seated", true) # Isolated orbital fixtures model a restrained pilot.
	player.collision_layer = 0
	player.collision_mask = 0
	holder.add_child(player)
	player.position = Vector3(0, 0, 1)
	var wreck: SalvageWreck = SalvageWreck.new()
	holder.add_child(wreck)
	var hazards: SalvageHazards = SalvageHazards.new()
	holder.add_child(hazards)
	hazards.configure(wreck)
	var tools: SalvageTools = SalvageTools.new()
	player.add_child(tools)
	tools.configure(player, wreck, hazards)
	player.salvage_tools = tools
	var flight: OrbitalFlight = OrbitalFlight.new()
	flight.enabled = false
	holder.add_child(flight)
	flight.configure(session, ship, player, wreck, hazards)
	return {"root": holder, "flight": flight, "session": session, "ship": ship, "player": player, "wreck": wreck, "hazards": hazards}


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for step: int in range(count):
		await tree.physics_frame
		await tree.process_frame
