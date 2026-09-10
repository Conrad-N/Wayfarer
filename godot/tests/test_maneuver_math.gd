## Legacy state/conic and maneuver acceptance checks, fuel accounting and difficult orbit orientations.
extends TestCase

const FUEL: Dictionary = {"dry_mass_kg": 8000.0, "propellant_kg": 4000.0, "isp_seconds": 320.0}


## Check 6 and retrograde regressions: RV to elements reproduces orientation and motion.
func test_round_trip_conic_orientations() -> void:
	var body: Dictionary = SimConstants.cradle()
	for inclination: float in [0.0, SimConstants.deg(51.6), PI / 2.0, PI]:
		for e: float in [0.0, 0.03, 0.7]:
			var elements: Dictionary = SimConstants.circular_orbit(body, 400e3, inclination)
			elements.e = e
			elements.argp = 0.7
			elements.raan = 0.3
			var before: Dictionary = OrbitMath.propagate(elements, body, 1234.0)
			var converted: Dictionary = ManeuverMath.state_to_elements(before.position, before.velocity, body, 1234.0)
			var after: Dictionary = OrbitMath.propagate(converted, body, 1234.0)
			check(not after.is_empty(), "round trip representable")
			if not after.is_empty():
				check_near(SimVector.distance(before.position, after.position), 0.0, 1.0, "position round trip")
				check_near(SimVector.distance(before.velocity, after.velocity), 0.0, 1e-2, "velocity round trip")
	check(ManeuverMath.state_to_elements(SimVector.new(), SimVector.new(), body, 0.0).is_empty(), "zero state rejected")
	check(ManeuverMath.state_to_elements(SimVector.new(1e7), SimVector.new(1.0), body, 0.0).is_empty(), "radial state rejected")


## Check 24: hyperbolic state conversion and energy conservation, inbound and outbound.
func test_hyperbolic_round_trip_and_energy() -> void:
	var body: Dictionary = SimConstants.cradle()
	var r: SimVector = SimVector.new(float(body.radius) + 400e3, 0.0, 0.0)
	var v: SimVector = SimVector.new(0.0, 1.2 * sqrt(2.0 * float(body.mu) / r.x), 0.0)
	var elements: Dictionary = ManeuverMath.state_to_elements(r, v, body, 0.0)
	check(float(elements.e) > 1.0, "escape velocity produces hyperbola")
	var initial: Dictionary = OrbitMath.propagate(elements, body, 0.0)
	check(is_inf(initial.apoapsis_radius) and is_inf(initial.period), "open orbit has no apoapsis or period")
	check_near(SimVector.distance(r, initial.position), 0.0, 1e-3, "hyperbolic initial position")
	check_near(SimVector.distance(v, initial.velocity), 0.0, 1e-6, "hyperbolic initial velocity")
	var energy: float = SimVector.dot(v, v) / 2.0 - float(body.mu) / SimVector.length(r)
	for time: float in [-20000.0, -5000.0, 5000.0, 20000.0]:
		var sample: Dictionary = OrbitMath.propagate(elements, body, time)
		check_near(SimVector.dot(sample.velocity, sample.velocity) / 2.0 - float(body.mu) / SimVector.length(sample.position), energy, 1e-3, "hyperbolic energy conserved")
		var again: Dictionary = OrbitMath.propagate(ManeuverMath.state_to_elements(sample.position, sample.velocity, body, time), body, time)
		check_near(SimVector.distance(sample.position, again.position), 0.0, 1e-3, "hyperbolic inbound/outbound RV round trip")
		check_near(SimVector.distance(sample.velocity, again.velocity), 0.0, 1e-6, "hyperbolic velocity round trip")


## Checks 7–9: local burn direction, rocket equation, and insufficient tanks.
func test_legacy_burn_previews() -> void:
	var body: Dictionary = SimConstants.cradle()
	var elements: Dictionary = SimConstants.circular_orbit(body, 400e3, SimConstants.deg(51.6))
	var preview: Dictionary = ManeuverMath.preview_node(elements, body, FUEL, {"time": 0.0, "dv_local": {"prograde": 109.4, "normal": 0.0, "radial": 0.0}})
	check_near(preview.dv_mag, 109.4, 0.1, "prograde magnitude")
	check_near(preview.after.apoapsis_altitude, 800e3, 1000.0, "prograde raises apoapsis")
	check_near(preview.after.periapsis_altitude, 400e3, 1000.0, "prograde keeps periapsis")
	check_near(preview.propellant_kg, 411.0, 5.0, "rocket equation propellant")
	check(preview.feasible, "affordable burn feasible")
	elements = SimConstants.circular_orbit(body, 400e3)
	preview = ManeuverMath.preview_node(elements, body, FUEL, {"time": 0.0, "dv_local": {"normal": 500.0}})
	check_near(preview.dv_mag, 500.0, 0.1, "normal magnitude")
	check_near(preview.after.i, atan2(500.0, float(preview.before.speed)), deg_to_rad(0.05), "normal changes inclination")
	preview = ManeuverMath.preview_node(elements, body, FUEL, {"time": 0.0, "dv_local": {"prograde": 5000.0}})
	check(not preview.feasible and not String(preview.note).is_empty(), "unaffordable burn explains failure")
	preview = ManeuverMath.preview_node(elements, body, FUEL, {"time": 0.0, "dv_local": {}})
	check(not preview.feasible, "zero burn not actionable")


## Chained burns use decreasing mass, reject reordered/invalid input, and account for cargo in burnout mass.
func test_plan_mass_and_validation() -> void:
	var body: Dictionary = SimConstants.cradle()
	var elements: Dictionary = SimConstants.circular_orbit(body, 400e3)
	var nodes: Array[Dictionary] = [{"time": 0.0, "dv_local": {"prograde": 60.0}}, {"time": 600.0, "dv_local": {"prograde": 60.0}}]
	var plan: Dictionary = ManeuverMath.build_plan(elements, body, FUEL, "two burns", nodes)
	check(plan.feasible, "two burn plan feasible")
	check(float(plan.burns[1].propellant_kg) < float(plan.burns[0].propellant_kg), "second burn starts lighter")
	check_near(plan.propellant_kg, ManeuverMath.propellant_for_dv(12000.0, 120.0, 320.0), 1e-9, "threaded mass equals combined rocket equation")
	check_near(float(plan.dv_budget_before) - float(plan.dv_budget_after), 120.0, 1e-9, "budget consumed by total delta-v")
	nodes.reverse()
	check(not ManeuverMath.build_plan(elements, body, FUEL, "bad order", nodes).feasible, "unsorted nodes rejected")
	check(not ManeuverMath.preview_node(elements, body, FUEL, {"time": NAN}).feasible, "invalid time rejected")
	check_eq(ManeuverMath.dv_budget(-1.0, 8000.0, 320.0), 0.0, "negative fuel rejected")
	check(ManeuverMath.dv_budget(4000.0, 9000.0, 320.0) < ManeuverMath.dv_budget(4000.0, 8000.0, 320.0), "cargo reduces delta-v budget")
