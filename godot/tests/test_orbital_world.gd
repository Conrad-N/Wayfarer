## Legacy orbital-world parity and authoritative stepping/handoff regressions.
extends TestCase


## Interior coasts stop before any live engine, rotation or commanded attitude change.
func test_interior_coast_requires_stationary_unpowered_hull() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_attitude_mode("manual")
	check(is_inf(world.interior_coast_seconds()), "idle coast has no maneuver boundary")
	world.set_throttle(0.1)
	check_eq(world.interior_coast_seconds(), 0.0, "engine forbids stationary interior")
	world.set_throttle(0.0)
	world.set_manual_torque(SimVector.new(1, 0, 0))
	check_eq(world.interior_coast_seconds(), 0.0, "manual torque requires physical interior")
	world.set_manual_torque(SimVector.new())
	world.angular_vel = SimVector.new(0, 0.01, 0)
	check_eq(world.interior_coast_seconds(), 0.0, "passive spin requires physical interior")
	world.set_attitude_mode("kill")
	check_eq(world.interior_coast_seconds(), 0.0, "braking spin still requires physical interior")
	world.angular_vel = SimVector.new()
	check(is_inf(world.interior_coast_seconds()), "settled kill mode allows coast")
	world.set_attitude_mode("prograde")
	check_eq(world.interior_coast_seconds(), 0.0, "direction tracking requires physical interior")


## Sampling an executor boundary resolves its controls without advancing or spending stores.
func test_interior_coast_stops_at_pointing_window() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_attitude_mode("kill")
	world.attitude_lead_seconds = 120.0
	world.nodes.assign([{"time": 1000.0, "dv_local": {"prograde": 20.0, "normal": 0.0, "radial": 0.0}}])
	world.set_executor(true)
	var fuel: float = world.ship.propellant_kg
	var charge: float = world.reaction_wheel.battery_energy_j
	var duration: float = 20.0 * world.current_mass() / float(world.ship.thrust_n)
	var boundary: float = 1000.0 - duration * 0.5 - 120.0
	world.prepare_interior_controls()
	check_near(world.interior_coast_seconds(), boundary, 1e-9, "reports exact finite-burn pointing window")
	check_eq(world.time, 0.0, "control preparation advances no time")
	check_eq(world.ship.propellant_kg, fuel, "control preparation spends no fuel")
	check_eq(world.reaction_wheel.battery_energy_j, charge, "control preparation spends no wheel energy")
	world.set_rate(1000.0)
	world.advance(boundary / 1000.0)
	check_near(world.time, boundary, 1e-9, "coast lands on boundary")
	world.prepare_interior_controls()
	check_eq(world.interior_coast_seconds(), 0.0, "boundary requests live maneuver physics")
	check_eq(world.attitude_mode, "node", "executor prepares real maneuver attitude")
	check_eq(world.ship.propellant_kg, fuel, "preparing turn does not burn early")


## Legacy 18: finite prograde thrust changes the conic and folds continuously.
func test_powered_burn_raises_orbit_and_spends_fuel() -> void:
	var world: OrbitalWorld = _aligned_world()
	var before: float = world.orbit()["apoapsis_altitude"]
	var fuel: float = world.ship["propellant_kg"]
	world.set_throttle(1.0)
	for step: int in range(60):
		world.advance(0.1)
	var mid: float = world.orbit()["apoapsis_altitude"]
	check(not world.powered_state.is_empty(), "engine uses integrated state")
	world.set_throttle(0.0)
	world.advance(1.0)
	check(world.powered_state.is_empty(), "engine cutoff folds to analytic coast")
	check(float(world.orbit()["apoapsis_altitude"]) > before + 5000.0, "six seconds raises apoapsis")
	check_near(world.orbit()["apoapsis_altitude"], mid, 2000.0, "coast fold is continuous")
	check(float(world.ship["propellant_kg"]) < fuel - 50.0, "main burn consumes actual propellant")


## Legacy 19: identical powered steps are independent of their API tick grouping.
func test_powered_tick_chunk_invariance() -> void:
	var fine: OrbitalWorld = _aligned_world()
	var coarse: OrbitalWorld = _aligned_world()
	fine.set_throttle(1.0)
	coarse.set_throttle(1.0)
	for step: int in range(128):
		fine.advance(OrbitalWorld.DT_PHYS)
	coarse.advance(1.0)
	coarse.advance(1.0)
	_check_same_state(fine, coarse, 1e-9)


## Legacy 20: executor decisions happen on the fixed grid regardless of API ticks.
func test_executor_tick_chunk_invariance() -> void:
	var fine: OrbitalWorld = _run_node(OrbitalWorld.DT_PHYS)
	var coarse: OrbitalWorld = _run_node(1.0)
	check(fine.nodes.is_empty() and coarse.nodes.is_empty(), "both executors finish")
	check_near(fine.orbit()["apoapsis_altitude"], coarse.orbit()["apoapsis_altitude"], 1e-3, "apoapsis matches")
	check_near(fine.orbit()["periapsis_altitude"], coarse.orbit()["periapsis_altitude"], 1e-3, "periapsis matches")
	check_near(fine.ship["propellant_kg"], coarse.ship["propellant_kg"], 1e-6, "fuel matches")


## Legacy 21: the real finite burn reaches the impulsive planner's nearby result.
func test_executor_reaches_previewed_orbit() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var node: Dictionary = _node(0.0, 150.0)
	var preview: Dictionary = ManeuverMath.preview_node(world.ship["elements"], world.get_body(), _fuel(world), node)
	world.nodes.append(node)
	world.set_executor(true)
	_fly_current_node(world)
	check(world.nodes.is_empty() and not world.executor_on, "node retires after delivery")
	check_near(world.orbit()["apoapsis_altitude"], preview["after"]["apoapsis_altitude"], 30000.0, "finite burn within 30 km of impulse preview")


## Legacy 22: independently authored nodes execute in order across a coast jump.
func test_executor_flies_multiple_authored_nodes() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.nodes.append(_node(0.0, 60.0))
	world.nodes.append(_node(600.0, 60.0))
	world.set_executor(true)
	_fly_current_node(world)
	check_eq(world.nodes.size(), 1, "first node retires alone")
	world.advance(OrbitalWorld.DT_PHYS)
	check(world.jump_to_next_node(), "next node is reachable by analytic jump")
	_fly_current_node(world)
	check(world.nodes.is_empty() and not world.executor_on, "both nodes retire")
	check(float(world.ship["propellant_kg"]) < 23950.0, "both burns spend fuel")


## Legacy 26: target telemetry remains in the correct root frame across SOIs.
func test_cross_frame_target_telemetry() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.selected_target = 3
	var target: Dictionary = world.selected_target_def()
	check_eq(target["body_id"], "sol", "planet target orbits the root")
	var distance: float = SimVector.distance(world.target_root_state(target)["position"], world.ship_root_state()["position"])
	check(distance > 1e10, "cross-frame target range is physically large")
	world.set_attitude_mode("target")
	var toward: SimVector = world.attitude_target_dir()
	world.set_attitude_mode("anti_target")
	check_near(SimVector.dot(toward, world.attitude_target_dir()), -1.0, 1e-12, "target and anti-target headings oppose")
	check_near(SimVector.length(toward), 1.0, 1e-12, "target bearing normalized")


## Legacy 27: analytic escape is continuous and independent of coast tick size.
func test_soi_escape_and_tick_chunk_invariance() -> void:
	var fine: OrbitalWorld = _escape_world()
	var coarse: OrbitalWorld = _escape_world()
	check_eq(fine.next_soi.get("to_body_id"), "sol", "escape predicted")
	if fine.next_soi.is_empty():
		return
	var total: float = float(fine.next_soi["time"]) + 50000.0
	_advance_total(fine, total, 50.0)
	_advance_total(coarse, total, 20000.0)
	check_eq(fine.central_body_id, "sol", "fine coast escaped")
	check_eq(coarse.central_body_id, "sol", "coarse coast escaped")
	check_near(fine.time, coarse.time, 1e-6, "same simulation time")
	check_near(SimVector.distance(fine.ship_root_state()["position"], coarse.ship_root_state()["position"]), 0.0, 1.0, "root position within one metre")


## Legacy 28: a genuine heliocentric approach enters a child planet's SOI.
func test_soi_capture() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var vesper: Dictionary = world.system.body("vesper")
	var target: Dictionary = world.system.body_state_in_root("vesper", 0.0)
	var outward: SimVector = SimVector.normalized(target["position"])
	var r: SimVector = SimVector.add(target["position"], SimVector.scale(outward, float(vesper["soi_radius"]) * 1.5))
	var v: SimVector = SimVector.sub(target["velocity"], SimVector.scale(outward, 200.0))
	check(world.replace_state(r, v, "sol", 0.0), "approach state accepted")
	check_eq(world.next_soi.get("to_body_id"), "vesper", "capture predicted")
	for step: int in range(20000):
		if world.central_body_id != "sol":
			break
		world.advance(500.0)
	check_eq(world.central_body_id, "vesper", "captured by Vesper")
	check(float(world.orbit()["radius"]) < float(vesper["soi_radius"]) + 1.0, "inside child SOI")


## Legacy 32: the complete transfer planner output flies through both SOIs.
func test_interplanetary_plan_physically_flies() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.selected_target = 3
	var destination: Dictionary = world.system.body("vesper")
	var window: Dictionary = OrbitalSolvers.suggest_interplanetary_window(world.get_body(), destination, world.system, world.time, world.orbit()["radius"])
	check(not window.is_empty(), "interplanetary window exists")
	if window.is_empty():
		return
	world.nodes = OrbitalSolvers.solve_interplanetary_transfer(world.ship["elements"], world.get_body(), world.time, destination, window)
	check_eq(world.nodes.size(), 4, "ejection, injection and two corrections")
	var escaped: bool = false
	var captured: bool = false
	var closest: float = INF
	world.set_executor(true)
	for node_index: int in range(20):
		if world.nodes.is_empty():
			break
		if not world.powered_state.is_empty():
			world.advance(OrbitalWorld.DT_PHYS)
		check(world.jump_to_next_node(), "cross-SOI node jump succeeds")
		_fly_current_node(world, 20.0)
		escaped = escaped or world.central_body_id == "sol"
	check(world.nodes.is_empty(), "all transfer burns finish")
	var end_time: float = world.time + 320.0 * 86400.0
	for coast_step: int in range(60000):
		if world.time >= end_time or captured:
			break
		world.set_rate(1500.0)
		world.advance(60.0)
		escaped = escaped or world.central_body_id == "sol"
		captured = captured or world.central_body_id == "vesper"
		closest = minf(closest, SimVector.distance(world.target_root_state(world.selected_target_def())["position"], world.ship_root_state()["position"]))
	check(escaped, "left Cradle")
	check(captured, "entered Vesper sphere of influence")
	check(closest < float(destination["soi_radius"]), "closest approach is physically inside SOI")
	check(float(world.ship["propellant_kg"]) > 0.0, "fuel remains on arrival")


## Legacy 33: the default drive can escape from the original parking orbit.
func test_sustained_burn_reaches_escape_with_fuel() -> void:
	var world: OrbitalWorld = _aligned_world()
	check(ManeuverMath.dv_budget(world.ship["propellant_kg"], world.structural_mass_kg(), world.ship["isp_seconds"]) > 10000.0, "legacy ship has interplanetary fuel budget")
	world.set_throttle(1.0)
	for step: int in range(3000):
		if float(world.orbit()["e"]) >= 1.0:
			break
		world.advance(0.5)
	check(float(world.orbit()["e"]) >= 1.0, "sustained prograde burn becomes hyperbolic")
	check(float(world.ship["propellant_kg"]) > 0.0, "escape does not exhaust tank")


## Invalid elapsed times and warp commands cannot poison authoritative state.
func test_invalid_clock_and_control_commands() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	for invalid: float in [-1.0, NAN, INF]:
		world.advance(invalid)
		check(not world.set_rate(invalid), "invalid rate rejected")
	check_eq(world.time, 0.0, "invalid deltas did not advance")
	check(not world.set_rate(1000001.0), "warp has finite bound")
	check(not world.set_throttle(NAN), "invalid throttle rejected")
	check(not world.set_manual_torque(SimVector.new(INF, 0.0, 0.0)), "invalid torque rejected")
	check(not world.set_attitude_mode("magic"), "unknown mode rejected")
	world.set_rate(0.0)
	world.advance(10.0)
	check_eq(world.time, 0.0, "zero warp pauses")
	check(world.set_throttle(9.0), "finite throttle accepted")
	check_eq(world.throttle, 1.0, "throttle clamped")
	world.set_executor(false)
	check_eq(world.throttle, 0.0, "executor off cuts engine")


## A capped update preserves its backlog, and sub-grid ticks retain their phase.
func test_fixed_step_backlog_and_manual_torque() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_manual_torque(SimVector.new(100.0, 0.0, 0.0))
	world.advance(0.001)
	check_eq(world.time, 0.0, "fractional physical step retained")
	world.advance(100.0)
	check_near(world.time, 64.0, 1e-12, "bounded fixed work per update")
	check_near(world.pending_sim_time(), 36.001, 1e-9, "backlog preserved")
	world.advance(0.0)
	check_near(world.time + world.pending_sim_time(), 100.001, 1e-9, "catch-up preserves every accepted second")
	check(SimVector.length(world.angular_vel) > 0.0, "manual torque turns initially stationary ship")


## A huge coast tick cannot sail across an entire maneuver window without burning.
func test_high_warp_stops_at_burn_approach() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.nodes.append(_node(1000.0, 150.0))
	world.set_executor(true)
	world.set_rate(1000000.0)
	world.advance(1.0)
	check_eq(world.rate, 10.0, "high warp lowered at approach")
	check(world.time < 1100.0, "event bounds remaining wall-clock warp")
	check(world.nodes.size() == 1, "burn has not been skipped")
	check(world.time > 900.0, "coast reaches the burn approach efficiently")
	_fly_current_node(world)
	check(world.nodes.is_empty(), "approached node subsequently flies")


## Physics handoff reproduces a live local r/v and preserves root-frame continuity.
func test_state_replacement_mass_and_snapshot_isolation() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var original: Dictionary = world.current_rv()
	var changed_velocity: SimVector = SimVector.add(original["v"], SimVector.new(0.1, -0.2, 0.3))
	check(world.replace_state(original["r"], changed_velocity), "local state accepted")
	check_near(SimVector.distance(world.current_rv()["r"], original["r"]), 0.0, 1e-5, "handoff position preserved")
	check_near(SimVector.distance(world.current_rv()["v"], changed_velocity), 0.0, 1e-7, "handoff velocity preserved")
	var root_before: Dictionary = world.ship_root_state()
	check(world.transition_to("sol", world.time), "frame transition accepted")
	check_near(SimVector.distance(world.ship_root_state()["position"], root_before["position"]), 0.0, 0.001, "translated root position preserved")
	check_near(SimVector.distance(world.ship_root_state()["velocity"], root_before["velocity"]), 0.0, 1e-7, "translated root velocity preserved")
	check(world.sync_mass(250.0, 700.0, 8000.0), "mass synchronization accepted")
	check_eq(world.current_mass(), 8950.0, "dry, fuel and cargo counted once")
	check(not world.sync_mass(-1.0, 0.0), "negative fuel rejected")
	check(not world.replace_state(SimVector.new(), changed_velocity), "zero orbital radius rejected")
	var snapshot: Dictionary = world.current_rv()
	(snapshot["r"] as SimVector).x = 0.0
	check(absf((world.current_rv()["r"] as SimVector).x) > 1.0, "read state does not alias truth")


## Local physics receives exactly the drive impulse charged to propellant.
func test_local_controls_impulse_fuel_and_fractional_clock() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.sync_mass(1.0, 0.0, 8000.0)
	world.set_throttle(1.0)
	var rv: Dictionary = world.current_rv()
	var total_impulse: float = 0.0
	for step: int in range(60):
		var result: Dictionary = world.advance_local(1.0 / 60.0, rv["r"], rv["v"], FlightMath.IDENTITY_Q, SimVector.new())
		total_impulse += SimVector.length(result["force_world"]) / 60.0
	check_near(world.time, 1.0, 1e-12, "local clock advances full physics elapsed time")
	check_near(total_impulse, 900.0 * 9.80665, 1e-6, "one kilogram produces its exact exhaust impulse")
	check_eq(world.ship["propellant_kg"], 0.0, "local drive runs out of fuel")
	check_eq(world.throttle, 0.0, "local flameout cuts throttle")
	check_near(SimVector.distance(world.current_rv()["r"], rv["r"]), 0.0, 1e-12, "Jolt remains sole owner of local translation")


## Cargo affects mass and rocket budget independently of occupied volume.
func test_cargo_manifest_mass_and_volume() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var empty_budget: float = ManeuverMath.dv_budget(world.ship["propellant_kg"], world.structural_mass_kg(), world.ship["isp_seconds"])
	world.ship["cargo"] = [{"id": "plate", "mass_kg": 300.0, "volume_m3": 0.12, "qty": 4}]
	check_eq(world.cargo_mass_kg(), 1200.0, "cargo mass sums quantities")
	check_near(world.cargo_volume_m3(), 0.48, 1e-12, "cargo volume sums quantities")
	check_eq(world.structural_mass_kg(), 9200.0, "cargo is inert burnout mass")
	check(ManeuverMath.dv_budget(world.ship["propellant_kg"], world.structural_mass_kg(), world.ship["isp_seconds"]) < empty_budget, "cargo reduces flight budget")


## Local executor burns and retires nodes while accepting, never integrating, Jolt poses.
func test_local_executor_completes_and_preserves_supplied_attitude() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.ship["elements"] = SimConstants.circular_orbit(world.get_body(), 400000.0)
	var rv: Dictionary = world.current_rv()
	var q: Dictionary = {"w": sqrt(0.5), "x": 0.0, "y": 0.0, "z": sqrt(0.5)}
	world.nodes.append(_node(0.0, 1.0))
	world.set_executor(true)
	var impulse: float = 0.0
	for step: int in range(120):
		var result: Dictionary = world.advance_local(1.0 / 60.0, rv["r"], rv["v"], q, SimVector.new())
		impulse += SimVector.length(result["force_world"]) / 60.0
		if world.nodes.is_empty():
			break
	check(world.nodes.is_empty() and not world.executor_on, "local executor retires completed burn")
	check(impulse >= 31990.0 and impulse < 36000.0, "local executor delivers the requested impulse within one control quantum")
	check(float(world.ship["propellant_kg"]) < 24000.0, "local executor burns the same main tank")
	check_near(world.orientation["z"], q["z"], 1e-12, "Jolt owns local orientation")
	check_near(SimVector.distance(world.current_rv()["v"], rv["v"]), 0.0, 0.0, "world does not double-integrate local velocity")


## Closed-loop matching resolves from the live orbit and skips unaffordable corrections.
func test_retarget_resolution_and_unaffordable_trim() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var match_node: Dictionary = _node(0.0, 1.0)
	match_node["retarget"] = {"kind": "match", "target_el": world.current_elements()}
	world.nodes.append(match_node)
	world.set_executor(true)
	world.advance(0.0)
	check(not match_node.has("retarget"), "live match resolves once")
	check_near(FlightMath.dv_magnitude(match_node["dv_local"]), 0.0, 1e-9, "co-moving target needs zero correction")
	check(world.nodes.is_empty(), "zero correction is skipped")
	world = OrbitalWorld.new()
	world.sync_mass(0.01, 0.0)
	var opposite: Dictionary = world.current_elements()
	opposite["i"] = float(opposite["i"]) + PI
	var unaffordable: Dictionary = _node(0.0, 1.0)
	unaffordable["retarget"] = {"kind": "match", "target_el": opposite}
	world.nodes.append(unaffordable)
	world.set_executor(true)
	world.advance(0.0)
	check_eq(FlightMath.dv_magnitude(unaffordable["dv_local"]), 0.0, "unaffordable trim safely skipped")
	check_eq(world.ship["propellant_kg"], 0.01, "unaffordable correction preserves fuel")


## A heliocentric retarget remains unresolved until its preceding SOI handoff.
func test_retarget_waits_for_correct_frame() -> void:
	var world: OrbitalWorld = _escape_world()
	if world.next_soi.is_empty():
		check(false, "escape event exists")
		return
	var next: Dictionary = _node(float(world.next_soi["time"]) + 500.0, 0.0)
	next["retarget"] = {"kind": "match", "target_el": world.system.body("vesper")["elements"]}
	world.nodes.append(next)
	world.set_executor(true)
	world.advance(0.0)
	check(next.has("retarget"), "cross-frame trim deferred")
	check(world.jump_to_next_node(), "jump crosses prior SOI")
	check_eq(world.central_body_id, "sol", "trim is now in parent frame")
	world.advance(0.0)
	check(not next.has("retarget"), "trim resolves only in correct frame")


## Warp falls to a safe rate near SOI boundaries and never jumps a live burn.
func test_soi_warp_limit_and_live_burn_jump_rejection() -> void:
	var world: OrbitalWorld = _escape_world()
	check(world.jump_to_next_soi(), "SOI approach jump available")
	var before: float = world.time
	world.set_rate(1000000.0)
	world.advance(1.0)
	check_eq(world.rate, 10.0, "SOI approach clamps high warp")
	check_near(world.time - before, 10.0, 1e-8, "only safe-rate seconds elapsed")
	check(world.warp_auto_limited, "SOI limit visible in telemetry")
	world.nodes.append(_node(world.time + 100.0, 1.0))
	world.set_throttle(1.0)
	check(not world.jump_to_next_node(), "live throttle blocks node jump")
	check(not world.jump_to_next_soi(), "live throttle blocks SOI jump")


## Fractional calls preserve the same attitude grid as whole-second calls.
func test_fractional_attitude_tick_chunk_invariance() -> void:
	var fine: OrbitalWorld = OrbitalWorld.new()
	var coarse: OrbitalWorld = OrbitalWorld.new()
	fine.set_manual_torque(SimVector.new(100.0, 0.0, 0.0))
	coarse.set_manual_torque(SimVector.new(100.0, 0.0, 0.0))
	for step: int in range(1000):
		fine.advance(0.01)
	for step: int in range(10):
		coarse.advance(1.0)
	_check_same_state(fine, coarse, 1e-9)


## Updating cargo and fuel during a live burn changes its mass without a teleport.
func test_powered_mass_sync_and_starvation_disengage() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_throttle(1.0)
	world.advance(OrbitalWorld.DT_PHYS)
	var before: Dictionary = world.current_rv()
	check(world.sync_mass(0.01, 1200.0), "in-flight mass synchronization accepted")
	check_near(world.current_mass(), 9200.01, 1e-9, "live integrated mass synchronized")
	check_near(SimVector.distance(before["r"], world.current_rv()["r"]), 0.0, 0.0, "mass update preserves position")
	world.nodes.append(_node(world.time, 10000.0))
	world.set_executor(true)
	world.orientation = {"w": sqrt(0.5), "x": 0.0, "y": -sqrt(0.5), "z": 0.0}
	# Direct manual firing isolates fuel starvation from the slew controller.
	world.set_executor(false)
	world.set_throttle(1.0)
	world.advance(OrbitalWorld.DT_PHYS)
	check_eq(world.ship["propellant_kg"], 0.0, "final fraction of fuel consumed")
	check_eq(world.throttle, 0.0, "starved engine shuts off")
	check(world.powered_state.is_empty(), "starvation folds back to coast")


## A loaded hull (measured 34 t starter ship inertia) half-turns without filling
## a wheel. Full-rate slews drained the whole battery over a five-burn intercept.
func test_loaded_hull_half_turn_is_affordable() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.ship.inertia = {"ix": 140164.0, "iy": 636479.0, "iz": 606638.0}
	world.set_attitude_mode("prograde")
	for step: int in range(800):
		world.advance(0.25)
	check(world.pointing_error(world.attitude_target_dir()) < deg_to_rad(0.5), "heavy hull settles on prograde")
	var before: float = world.reaction_wheel.battery_energy_j
	world.set_attitude_mode("retrograde")
	var peak_momentum: float = 0.0
	var aligned_at: float = INF
	var start: float = world.time
	for step: int in range(800):
		world.advance(0.25)
		peak_momentum = maxf(peak_momentum, SimVector.length(world.reaction_wheel.momentum_body))
		if aligned_at == INF and world.pointing_error(world.attitude_target_dir()) < deg_to_rad(2.0):
			aligned_at = world.time - start
	check(aligned_at <= 120.0, "half-turn aligns within the executor lead (%.1f s)" % aligned_at)
	check(peak_momentum <= OrbitalWorld.SLEW_WHEEL_FRACTION * world.reaction_wheel.capacity_nms * 1.25, "slew keeps wheel momentum near its share (%.0f N*m*s)" % peak_momentum)
	check(before - world.reaction_wheel.battery_energy_j < 400000.0, "half-turn costs under 0.4 MJ (%.0f J)" % (before - world.reaction_wheel.battery_energy_j))


func _aligned_world() -> OrbitalWorld:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_attitude_mode("prograde")
	for step: int in range(80):
		world.advance(0.5)
	return world


func _node(at_time: float, prograde: float) -> Dictionary:
	return {"id": "node-%s" % at_time, "time": at_time, "dv_local": {"prograde": prograde, "normal": 0.0, "radial": 0.0}}


func _fuel(world: OrbitalWorld) -> Dictionary:
	return {"dry_mass_kg": world.structural_mass_kg(), "propellant_kg": world.ship["propellant_kg"], "isp_seconds": world.ship["isp_seconds"]}


func _run_node(chunk: float) -> OrbitalWorld:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.nodes.append(_node(0.0, 150.0))
	world.set_executor(true)
	for step: int in range(int(600.0 / chunk)):
		if world.nodes.is_empty():
			break
		world.advance(chunk)
	return world


func _fly_current_node(world: OrbitalWorld, delta: float = 0.1) -> void:
	var count: int = world.nodes.size()
	for step: int in range(30000):
		if world.nodes.size() < count or not world.executor_on:
			return
		world.advance(delta)


func _check_same_state(a: OrbitalWorld, b: OrbitalWorld, tolerance: float) -> void:
	check_near(a.time, b.time, tolerance, "clock matches")
	check_near(SimVector.distance(a.current_rv()["r"], b.current_rv()["r"]), 0.0, tolerance, "position matches")
	check_near(SimVector.distance(a.current_rv()["v"], b.current_rv()["v"]), 0.0, tolerance, "velocity matches")
	check_near(a.ship["propellant_kg"], b.ship["propellant_kg"], tolerance, "fuel matches")
	check_eq(a.orientation, b.orientation, "orientation matches")


func _escape_world() -> OrbitalWorld:
	var world: OrbitalWorld = OrbitalWorld.new()
	var periapsis: float = float(world.get_body()["radius"]) + 400000.0
	var apoapsis: float = 2.0 * float(world.get_body()["soi_radius"])
	world.ship["elements"] = {"a": (periapsis + apoapsis) * 0.5, "e": (apoapsis - periapsis) / (apoapsis + periapsis), "i": deg_to_rad(51.6), "raan": 0.0, "argp": 0.0, "mean_anomaly_at_epoch": 0.0, "epoch": 0.0}
	world.recompute_next_soi()
	return world


func _advance_total(world: OrbitalWorld, total: float, chunk: float) -> void:
	var elapsed: float = 0.0
	while elapsed < total:
		var delta: float = minf(chunk, total - elapsed)
		world.advance(delta)
		elapsed += delta


## A nearby target and the measured local hull must be sampled at the same epoch.
func test_local_target_heading_does_not_advance_past_station() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var rv: Dictionary = world.current_rv()
	world.targets[0].elements = ManeuverMath.state_to_elements(SimVector.add(rv.r, SimVector.new(20, 0, 0)), rv.v, world.get_body(), world.time)
	world.selected_target = 0
	world.set_attitude_mode("target")
	var result: Dictionary = world.advance_local(0.05, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new())
	check_near(SimVector.length(result.torque_body), 0.0, 0.01, "aligned close target does not slew as only its clock advances")
	check_near(world.time, 0.05, 1e-12, "held heading still advances every accepted control fragment")
	world = OrbitalWorld.new()
	rv = world.current_rv()
	world.set_attitude_mode("target")
	result = world.advance_local(0.05, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new(), SimVector.new(0, 1, 0))
	check(SimVector.length(result.torque_body) > 0.0, "local berth heading commands real motor torque")
	check(SimVector.length(world.reaction_wheel.momentum_body) > 0.0, "berth alignment stores reaction momentum")
	var time_before: float = world.time
	world.advance_local(0.05, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new(), SimVector.new(NAN, 0, 0))
	check_eq(world.time, time_before, "invalid local heading fails without changing time")
