## Numeric acceptance checks for every targeting instrument and its rejection paths.
extends TestCase


## Legacy checks 12–14: apsis instruments preserve the opposite apsis and budget a Hohmann.
func test_apsis_and_hohmann_legacy_numbers() -> void:
	var body: Dictionary = _body()
	var ellipse: Dictionary = _orbit(600000.0)
	ellipse.e = 200000.0 / ellipse.a
	var fuel: Dictionary = {"dry_mass_kg": 10000.0, "propellant_kg": 5000.0, "isp_seconds": 320.0}
	var circular: Dictionary = OrbitalSolvers.solve_circularize(ellipse, body, 0.0, "apoapsis")
	check(not circular.is_empty(), "Apoapsis circularization solves")
	if circular.is_empty():
		return
	var plan: Dictionary = ManeuverMath.build_plan(ellipse, body, fuel, "Circularize", [circular])
	check_near(plan.after.apoapsis_altitude, 800000.0, 1000.0, "Circularized apoapsis")
	check_near(plan.after.periapsis_altitude, 800000.0, 1000.0, "Circularized periapsis")
	check_near(plan.after.e, 0.0, 0.001, "Circularized eccentricity")
	check(plan.feasible, "Circularization is affordable")
	var raise_peri: Dictionary = OrbitalSolvers.solve_set_apsis(ellipse, body, 0.0, "periapsis", body.radius + 600000.0)
	plan = ManeuverMath.build_plan(ellipse, body, fuel, "Raise periapsis", [raise_peri])
	check_near(plan.after.periapsis_altitude, 600000.0, 1000.0, "Raised periapsis")
	check_near(plan.after.apoapsis_altitude, 800000.0, 1000.0, "Opposite apsis remains fixed")
	var nodes: Array[Dictionary] = OrbitalSolvers.solve_hohmann(_orbit(), body, 0.0, body.radius + 800000.0)
	plan = ManeuverMath.build_plan(_orbit(), body, fuel, "Hohmann", nodes)
	check_eq(nodes.size(), 2, "Hohmann burn count")
	check_near(plan.dv_mag, 217.9, 3.0, "Hohmann delta-v")
	check_near(plan.after.apoapsis_altitude, 800000.0, 1000.0, "Hohmann final apoapsis")
	check_near(plan.after.periapsis_altitude, 800000.0, 1000.0, "Hohmann final periapsis")
	check(plan.feasible, "Hohmann is affordable")


## Lowering transfers and the other apsis branches work without changing the burn radius.
func test_lowering_and_periapsis_circularization() -> void:
	var body: Dictionary = _body()
	var ellipse: Dictionary = _orbit(600000.0)
	ellipse.e = 200000.0 / ellipse.a
	var node: Dictionary = OrbitalSolvers.solve_circularize(ellipse, body, 0.0, "periapsis")
	check(float(node.dv_local.prograde) < 0.0, "Periapsis circularization slows down")
	var after: Dictionary = OrbitMath.propagate(ManeuverMath.apply_burn(ellipse, body, node.time, node.dv_local), body, node.time)
	check_near(after.apoapsis_altitude, 400000.0, 1.0, "Periapsis circularization final radius")
	node = OrbitalSolvers.solve_set_apsis(ellipse, body, 0.0, "apoapsis", body.radius + 1000000.0)
	after = OrbitMath.propagate(ManeuverMath.apply_burn(ellipse, body, node.time, node.dv_local), body, node.time)
	check_near(after.apoapsis_altitude, 1000000.0, 1.0, "Apoapsis raised")
	check_near(after.periapsis_altitude, 400000.0, 1.0, "Periapsis preserved")
	var nodes: Array[Dictionary] = OrbitalSolvers.solve_hohmann(_orbit(800000.0), body, 0.0, body.radius + 400000.0)
	check(float(nodes[0].dv_local.prograde) < 0.0 and float(nodes[1].dv_local.prograde) < 0.0, "Lowering Hohmann uses two retrograde burns")


## Legacy check 15: a Lambert departure lands within 200 m on each target coordinate.
func test_lambert_arrival_matches_legacy_tolerance() -> void:
	var body: Dictionary = _body()
	var target: Dictionary = _orbit(450000.0, 20.0)
	var start: Dictionary = OrbitMath.propagate(_orbit(), body, 0.0)
	var finish: Dictionary = OrbitMath.propagate(target, body, 4800.0)
	var solution: Dictionary = OrbitalSolvers.lambert(start.position, finish.position, 4800.0, body.mu)
	check(not solution.is_empty(), "Lambert returns a transfer")
	if solution.is_empty():
		return
	var arrived: Dictionary = OrbitMath.propagate(ManeuverMath.state_to_elements(start.position, solution.v1, body, 0.0), body, 4800.0)
	check_near(arrived.position.x, finish.position.x, 200.0, "Arrival x")
	check_near(arrived.position.y, finish.position.y, 200.0, "Arrival y")
	check_near(arrived.position.z, finish.position.z, 200.0, "Arrival z")


## Both multiple-revolution branches arrive, and the scored transfer picks the cheaper arc.
func test_multirevolution_branches_and_best_transfer() -> void:
	var body: Dictionary = _body()
	var el: Dictionary = _orbit(400000.0, 0.0, 0.0)
	var start: Dictionary = OrbitMath.propagate(el, body, 0.0)
	var duration: float = start.period * 1.25
	var finish: Dictionary = OrbitMath.propagate(el, body, duration)
	var branches: Array[Dictionary] = []
	for branch: String in ["low", "high"]:
		var solution: Dictionary = OrbitalSolvers.lambert(start.position, finish.position, duration, body.mu, true, 1, branch)
		check(not solution.is_empty(), "One-revolution %s branch solves" % branch)
		if solution.is_empty():
			continue
		branches.append(solution)
		var arrived: Dictionary = OrbitMath.propagate(ManeuverMath.state_to_elements(start.position, solution.v1, body, 0.0), body, duration)
		check(SimVector.distance(arrived.position, finish.position) < 1000.0, "Multi-revolution arrival stays within numerical tolerance")
	if branches.size() == 2:
		check(SimVector.distance(branches[0].v1, branches[1].v1) > 10.0, "Branches have different departure energies")
	var best: Dictionary = OrbitalSolvers.best_transfer(start.position, finish.position, duration, body.mu, start.velocity, finish.velocity, 2)
	check(not best.is_empty(), "Best transfer exists")
	if not best.is_empty():
		check(SimVector.distance(best.v1, start.velocity) + SimVector.distance(best.v2, finish.velocity) < 1.0, "Multi-revolution search finds the nearly free circular coast")
	check(OrbitalSolvers.lambert(start.position, finish.position, 10.0, body.mu, true, 1).is_empty(), "Too-fast multirevolution request is rejected")
	var retro_time: float = start.period * 0.75
	var retro: Dictionary = OrbitalSolvers.lambert(start.position, finish.position, retro_time, body.mu, false)
	check(not retro.is_empty(), "Retrograde long-way branch solves")
	if not retro.is_empty():
		check(SimVector.cross(start.position, retro.v1).z < 0.0, "Retrograde branch reverses angular momentum")
		var retro_arrival: Dictionary = OrbitMath.propagate(ManeuverMath.state_to_elements(start.position, retro.v1, body, 0.0), body, retro_time)
		check(SimVector.distance(retro_arrival.position, finish.position) < 1000.0, "Retrograde transfer arrives at its requested endpoint")


## Guided intercepts add live trims and a match; nominal arcs clear the planet.
func test_intercept_guidance_clearance_and_match_velocity() -> void:
	var body: Dictionary = _body()
	var el: Dictionary = _orbit(400000.0, 0.0, 0.0)
	var target: Dictionary = _orbit(450000.0, 20.0, 0.0)
	var suggestion: Dictionary = OrbitalSolvers.suggest_intercept_tof(el, body, 0.0, target, 2)
	check(not suggestion.is_empty(), "Time-of-flight scan finds an affordable intercept")
	if suggestion.is_empty():
		return
	check(float(suggestion.tof_seconds) >= 1800.0 and float(suggestion.tof_seconds) <= 21600.0, "Suggested flight time lies inside scan bounds")
	var plain: Array[Dictionary] = OrbitalSolvers.solve_intercept(el, body, 0.0, target, suggestion.tof_seconds, 2)
	var guided: Array[Dictionary] = OrbitalSolvers.solve_intercept(el, body, 0.0, target, suggestion.tof_seconds, 2, true)
	check_eq(plain.size(), 2, "Unguided transfer has two nodes")
	check_eq(guided.size(), 5, "Guided transfer has departure, three trims and match")
	if guided.size() != 5:
		return
	check_near(guided[0].time, 60.0, 0.0, "Departure preserves review and slew lead")
	for index: int in range(1, 4):
		check_eq(guided[index].retarget.kind, "transfer", "Midcourse node resolves a transfer live")
		check_near(FlightMath.dv_magnitude(guided[index].dv_local), 0.0, 0.0, "Nominal trim delta-v is zero")
		check(float(guided[index].time) > float(guided[index - 1].time), "Nodes remain chronological")
	check_eq(guided[4].retarget.kind, "match", "Arrival matches live target velocity")
	var transfer: Dictionary = ManeuverMath.apply_burn(el, body, plain[0].time, plain[0].dv_local)
	for index: int in range(65):
		var state: Dictionary = OrbitMath.propagate(transfer, body, float(plain[0].time) + float(suggestion.tof_seconds) * index / 64.0)
		check(float(state.radius) >= float(body.radius) + 10000.0, "Planned arc clears the surface")
	var ship_now: Dictionary = OrbitMath.propagate(el, body, 321.0)
	var target_now: Dictionary = OrbitMath.propagate(target, body, 321.0)
	var match_node: Dictionary = OrbitalSolvers.solve_match_velocity(el, body, 321.0, target)
	var impulse: SimVector = FlightMath.local_dv_to_world(match_node.dv_local, ship_now.position, ship_now.velocity)
	check(SimVector.distance(SimVector.add(ship_now.velocity, impulse), target_now.velocity) < 1e-8, "Velocity match exactly cancels relative velocity")


## Legacy checks 29–30: the full cross-planet plan builds and its window stays bounded.
func test_interplanetary_window_and_four_node_plan() -> void:
	var system: OrbitalSystem = SimConstants.default_system()
	var a_body: Dictionary = system.body("cradle")
	var b_body: Dictionary = system.body("vesper")
	var radius: float = a_body.radius + 400000.0
	var window: Dictionary = OrbitalSolvers.suggest_interplanetary_window(a_body, b_body, system, 0.0, radius)
	check(not window.is_empty(), "Cradle-to-Vesper window solves from inside Cradle's SOI")
	if window.is_empty():
		return
	var parent: Dictionary = system.body(a_body.parent_id)
	var r_a: float = SimVector.length(system.relative_state(parent.id, a_body.id, 0.0).position)
	var r_b: float = SimVector.length(system.relative_state(parent.id, b_body.id, 0.0).position)
	var hohmann_time: float = PI * sqrt(pow((r_a + r_b) / 2.0, 3.0) / parent.mu)
	check(float(window.tof_seconds) <= 1.75 * hohmann_time + 1.0, "Transfer duration obeys Hohmann-derived cap")
	check(float(window.departure_time) <= 2400.0 * 86400.0, "Departure is within 2400 days")
	check(float(window.dv_eject) > 0.0 and float(window.dv_capture) > 0.0, "Both parking-orbit burn costs are positive")
	check(float(window.dv_total) < 12200.0, "Full estimated ejection and capture cost fits legacy budget")
	var parking: Dictionary = SimConstants.circular_orbit(a_body, 400000.0, deg_to_rad(51.6))
	var nodes: Array[Dictionary] = OrbitalSolvers.solve_interplanetary_transfer(parking, a_body, 0.0, b_body, window)
	check_eq(nodes.size(), 4, "Ejection, injection and two trim nodes")
	if nodes.size() != 4:
		return
	var fuel: Dictionary = {"dry_mass_kg": 8000.0, "propellant_kg": 24000.0, "isp_seconds": 900.0}
	var plan: Dictionary = ManeuverMath.build_plan(parking, a_body, fuel, "Vesper transfer", nodes)
	check(plan.feasible, "Cross-SOI plan is feasible")
	check(float(plan.dv_mag) < ManeuverMath.dv_budget(fuel.propellant_kg, fuel.dry_mass_kg, fuel.isp_seconds), "Ejection is within ship fuel budget")
	check(float(nodes[0].time) >= 120.0 and float(nodes[0].time) <= 2400.0 * 86400.0, "Ejection preserves slew lead and departure bound")
	for index: int in range(1, 4):
		check(float(nodes[index].time) > float(nodes[index - 1].time), "Interplanetary nodes chronological")
		check_eq(nodes[index].retarget.kind, "transfer", "Parent-frame burn resolves live")
		check_near(nodes[index].retarget.arrival_time, window.arrival_time, 0.0, "All guided legs share the window arrival")


## Legacy check 31: a wider affordable margin selects an earlier departure.
func test_interplanetary_window_prefers_soonest() -> void:
	var system: OrbitalSystem = SimConstants.default_system()
	var a_body: Dictionary = system.body("cradle")
	var b_body: Dictionary = system.body("vesper")
	var radius: float = a_body.radius + 400000.0
	var wide: Dictionary = OrbitalSolvers.suggest_interplanetary_window(a_body, b_body, system, 0.0, radius, {"margin_frac": 5.0, "depart_span_s": 4.0 * 365.0 * 86400.0})
	var tight: Dictionary = OrbitalSolvers.suggest_interplanetary_window(a_body, b_body, system, 0.0, radius, {"margin_frac": 1.01, "depart_span_s": 4.0 * 365.0 * 86400.0})
	check(not wide.is_empty() and not tight.is_empty(), "Both affordability margins solve")
	if not wide.is_empty() and not tight.is_empty():
		check(float(wide.departure_time) <= float(tight.departure_time) + 1.0, "Wide margin departs no later than tight margin")


## Invalid inputs, singular geometry and unavailable apsides fail without nonfinite plans.
func test_invalid_and_degenerate_requests_fail_softly() -> void:
	var body: Dictionary = _body()
	var el: Dictionary = _orbit()
	var zero: SimVector = SimVector.new()
	var r1: SimVector = SimVector.new(7000000.0, 0.0, 0.0)
	var r2: SimVector = SimVector.new(0.0, 7000000.0, 0.0)
	check(OrbitalSolvers.lambert(zero, r2, 1000.0, body.mu).is_empty(), "Zero-radius endpoint rejected")
	check(OrbitalSolvers.lambert(r1, r1, 1000.0, body.mu).is_empty(), "Coincident endpoint direction rejected")
	check(OrbitalSolvers.lambert(r1, SimVector.scale(r1, -1.0), 1000.0, body.mu).is_empty(), "Antipodal ambiguity rejected")
	for invalid: float in [-1.0, 0.0, NAN, INF]:
		check(OrbitalSolvers.lambert(r1, r2, invalid, body.mu).is_empty(), "Invalid transfer time rejected")
		check(OrbitalSolvers.lambert(r1, r2, 1000.0, invalid).is_empty(), "Invalid gravity rejected")
	check(OrbitalSolvers.lambert(r1, r2, 1000.0, body.mu, true, -1).is_empty(), "Negative revolutions rejected")
	check(OrbitalSolvers.lambert(r1, r2, 1000.0, body.mu, true, 1, "other").is_empty(), "Unknown Lambert branch rejected")
	check(OrbitalSolvers.solve_circularize(el, body, 0.0, "other").is_empty(), "Unknown apsis rejected")
	check(OrbitalSolvers.solve_circularize({}, body, 0.0, "apoapsis").is_empty(), "Missing elements rejected")
	check(OrbitalSolvers.solve_set_apsis(el, body, 0.0, "apoapsis", body.radius - 1.0).is_empty(), "Underground target rejected")
	check(OrbitalSolvers.solve_set_apsis(el, body, 0.0, "periapsis", body.radius + 800000.0).is_empty(), "Periapsis above fixed apoapsis rejected")
	var eccentric: Dictionary = el.duplicate(true)
	eccentric.e = 0.2
	check(OrbitalSolvers.solve_hohmann(eccentric, body, 0.0, body.radius + 800000.0).is_empty(), "Hohmann requires a circular starting orbit")
	check(OrbitalSolvers.solve_intercept(el, body, 0.0, el, -1.0).is_empty(), "Negative intercept duration rejected")
	var hyperbolic: Dictionary = el.duplicate(true)
	hyperbolic.a = -10000000.0
	hyperbolic.e = 2.0
	check(OrbitalSolvers.solve_circularize(hyperbolic, body, 0.0, "apoapsis").is_empty(), "Hyperbola has no apoapsis to circularize")
	var system: OrbitalSystem = SimConstants.default_system()
	var a_body: Dictionary = system.body("cradle")
	var b_body: Dictionary = system.body("vesper")
	check(OrbitalSolvers.suggest_interplanetary_window(a_body, a_body, system, 0.0, body.radius + 400000.0).is_empty(), "Same-body transfer rejected")
	check(OrbitalSolvers.suggest_interplanetary_window(system.root_body(), b_body, system, 0.0, body.radius + 400000.0).is_empty(), "Non-sibling transfer rejected")
	check(OrbitalSolvers.suggest_interplanetary_window(a_body, b_body, system, 0.0, body.radius + 400000.0, {"margin_frac": 0.5}).is_empty(), "Impossible window margin rejected")
	check(OrbitalSolvers.solve_interplanetary_transfer(el, a_body, 0.0, b_body, {}).is_empty(), "Missing transfer window rejected")
	check(OrbitalSolvers.suggest_interplanetary_window(a_body, b_body, system, 0.0, a_body.radius - 1.0).is_empty(), "Underground departure parking orbit rejected")
	check(OrbitalSolvers.suggest_interplanetary_window(a_body, b_body, system, 0.0, a_body.radius + 400000.0, {"r_park_b": b_body.radius - 1.0}).is_empty(), "Underground capture parking orbit rejected")
	var unrelated: Dictionary = b_body.duplicate(true)
	unrelated.parent_id = "other"
	check(OrbitalSolvers.solve_interplanetary_transfer(el, a_body, 0.0, unrelated, {"departure_time": 1000.0, "arrival_time": 10000000.0, "v_inf_out": r1}).is_empty(), "Cross-parent injection target rejected")


static func _body() -> Dictionary:
	return {"mu": 3.986004418e14, "radius": 6371000.0, "rotation_period": null}


static func _orbit(altitude: float = 400000.0, phase_degrees: float = 0.0, inclination_degrees: float = 51.6) -> Dictionary:
	return {"a": 6371000.0 + altitude, "e": 0.0, "i": deg_to_rad(inclination_degrees), "raan": 0.0, "argp": 0.0, "mean_anomaly_at_epoch": deg_to_rad(phase_degrees), "epoch": 0.0}
