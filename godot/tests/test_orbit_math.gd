## Legacy Kepler acceptance numbers, conservation, anomaly boundaries, and double-precision regressions.
extends TestCase


## Checks 1–5: closed-orbit telemetry, apsis timing and inclined latitude.
func test_legacy_closed_orbits() -> void:
	var body: Dictionary = SimConstants.cradle()
	var circle: Dictionary = SimConstants.circular_orbit(body, 400e3)
	var state: Dictionary = OrbitMath.propagate(circle, body, 0.0)
	check_near(state.period / 60.0, 92.4, 0.3, "400 km period minutes")
	check_near(state.speed, 7672.0, 5.0, "400 km circular speed")
	for t: float in [0.0, 1000.0, 2772.0, 5544.0, 12345.0]:
		var sample: Dictionary = OrbitMath.propagate(circle, body, t)
		check_near(sample.altitude, 400e3, 1.0, "constant circular altitude")
		check_near(sample.periapsis_altitude, 400e3, 1.0, "circle periapsis")
		check_near(sample.apoapsis_altitude, 400e3, 1.0, "circle apoapsis")
	var ellipse: Dictionary = circle.duplicate()
	ellipse.a = float(body.radius) + 600e3
	ellipse.e = 200e3 / float(ellipse.a)
	var peri: Dictionary = OrbitMath.propagate(ellipse, body, 0.0)
	var apo: Dictionary = OrbitMath.propagate(ellipse, body, float(peri.period) / 2.0)
	check_near(peri.periapsis_altitude, 400e3, 500.0, "ellipse periapsis")
	check_near(peri.apoapsis_altitude, 800e3, 500.0, "ellipse apoapsis")
	check_near(peri.period / 60.0, 96.5, 0.5, "ellipse period")
	check(peri.speed > apo.speed, "periapsis faster than apoapsis")
	check(apo.speed < state.speed and peri.speed > state.speed, "circular speed between apsis speeds")
	check_near(peri.time_to_periapsis, 0.0, 1e-6, "periapsis starts now")
	check_near(apo.time_to_periapsis, float(peri.period) / 2.0, 1e-3, "apoapsis time to periapsis")
	var before_peri: Dictionary = OrbitMath.propagate(ellipse, body, float(peri.period) - 1.0)
	check_near(before_peri.time_to_periapsis, 1.0, 1e-3, "wrap just before periapsis")
	check_near(float(before_peri.time_to_periapsis) + float(before_peri.time_since_periapsis), peri.period, 1e-6, "periapsis times add to period")
	var inclined: Dictionary = SimConstants.circular_orbit(body, 400e3, SimConstants.deg(51.6))
	for step: int in range(4):
		var sample: Dictionary = OrbitMath.propagate(inclined, body, float(state.period) * float(step) / 4.0)
		check_near(rad_to_deg(sample.latitude), [0.0, 51.6, 0.0, -51.6][step], 1e-3, "inclination latitude sweep")
		check_near(sample.speed, state.speed, 1e-9, "inclination preserves speed")


## Check 15: identical explicit inputs produce identical doubles in every telemetry field.
func test_deterministic_propagation_and_kepler_residuals() -> void:
	var elements: Dictionary = SimConstants.circular_orbit(SimConstants.cradle(), 400e3, 0.9)
	elements.e = 0.08
	var a: Dictionary = OrbitMath.propagate(elements, SimConstants.cradle(), 4242.0)
	var b: Dictionary = OrbitMath.propagate(elements, SimConstants.cradle(), 4242.0)
	for key: String in a:
		if a[key] is SimVector:
			check_eq(a[key].x, b[key].x, "deterministic x")
			check_eq(a[key].y, b[key].y, "deterministic y")
			check_eq(a[key].z, b[key].z, "deterministic z")
		else:
			check_eq(a[key], b[key], "deterministic " + key)
	for e: float in [0.0, 0.5, 0.9, 0.999999]:
		for mean_anomaly: float in [-8.0, -PI, -0.01, 0.0, 0.01, PI, 25.0]:
			var eccentric: float = OrbitMath.solve_kepler(mean_anomaly, e)
			check_near(eccentric - e * sin(eccentric), fposmod(mean_anomaly + PI, TAU) - PI, 2e-12, "elliptic Kepler residual")
	for e: float in [1.001, 1.88, 3.0]:
		for mean_anomaly: float in [-100.0, -0.001, 0.0, 0.001, 100.0]:
			var hyper: float = OrbitMath.solve_hyper_kepler(mean_anomaly, e)
			check_near(e * sinh(hyper) - hyper, mean_anomaly, 1e-10, "hyperbolic Kepler residual")
	check(is_nan(OrbitMath.solve_kepler(0.0, 1.0)), "elliptic solver rejects parabolas")
	check(is_nan(OrbitMath.solve_hyper_kepler(0.0, 0.9)), "hyperbolic solver rejects ellipse")


## Escape crossings are outbound, strictly future, and independent of integration cadence.
func test_escape_boundary_solutions() -> void:
	var body: Dictionary = SimConstants.cradle()
	var elements: Dictionary = SimConstants.circular_orbit(body, 400e3)
	check(OrbitMath.next_escape_time(elements, body, 0.0, body.soi_radius) == null, "parking orbit never escapes")
	var peri: float = float(body.radius) + 400e3
	var apo: float = 2.0 * float(body.soi_radius)
	elements.a = (peri + apo) / 2.0
	elements.e = (apo - peri) / (apo + peri)
	var crossing: Variant = OrbitMath.next_escape_time(elements, body, 0.0, body.soi_radius)
	check(crossing is float, "high ellipse has escape")
	if crossing == null:
		return
	var sample: Dictionary = OrbitMath.propagate(elements, body, crossing)
	check_near(sample.radius, body.soi_radius, 1e-3, "analytic ellipse crossing radius")
	check(SimVector.dot(sample.position, sample.velocity) > 0.0, "crossing outbound")
	var next: Variant = OrbitMath.next_escape_time(elements, body, crossing, body.soi_radius)
	check_near(float(next) - float(crossing), sample.period, 1e-3, "next crossing excludes current boundary")
	elements.a = -1e7
	elements.e = 1.8
	crossing = OrbitMath.next_escape_time(elements, body, 0.0, body.soi_radius)
	check(crossing != null, "hyperbola escapes")
	if crossing != null:
		sample = OrbitMath.propagate(elements, body, crossing)
		check_near(sample.radius, body.soi_radius, 1e-3, "analytic hyperbolic crossing radius")
		check(OrbitMath.next_escape_time(elements, body, float(crossing) + 1.0, body.soi_radius) == null, "hyperbola crosses once")
	check(OrbitMath.propagate({}, body, 0.0).is_empty(), "invalid orbit fails soft")
	check(OrbitMath.propagate(elements, body, NAN).is_empty(), "invalid time fails soft")


## Scalar storage retains centimetres at an AU and vector operations remain orthonormal.
func test_sim_vector_double_precision() -> void:
	var origin: SimVector = SimVector.new(SimConstants.AU, -SimConstants.AU, 0.0)
	var moved: SimVector = SimVector.add(origin, SimVector.new(0.01, 0.02, 0.03))
	var delta: SimVector = SimVector.sub(moved, origin)
	check_near(delta.x, 0.01, 2e-5, "AU centimetre x")
	check_near(delta.y, 0.02, 2e-5, "AU centimetre y")
	check_near(delta.z, 0.03, 1e-15, "double z")
	check_near(SimVector.length(SimVector.new(1e200, 1e200, 0.0)) / 1e200, sqrt(2.0), 1e-15, "length avoids overflow")
	check_eq(SimVector.length(SimVector.normalized(SimVector.new())), 0.0, "zero normalization")
	check_near(SimVector.length(SimVector.clamp_magnitude(SimVector.new(3.0, 4.0, 0.0), 2.0)), 2.0, 1e-14, "magnitude clamp")
	check(not SimVector.is_finite_vector(SimVector.new(NAN)), "reject nonfinite components")
