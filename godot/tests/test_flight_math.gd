## Powered-flight and attitude acceptance tests plus fuel exhaustion and frame consistency.
extends TestCase


## Check 16: fixed RK4 burn delivers the rocket-equation impulse and exact fuel flow.
func test_finite_burn_rocket_equation() -> void:
	var state: Dictionary = {"r": SimVector.new(1e7), "v": SimVector.new(), "m": 12000.0}
	var engine: Dictionary = {"thrust_n": 50000.0, "isp_seconds": 320.0}
	for _step: int in range(1280):
		state = FlightMath.step_powered(state, {"mu": 0.0}, SimVector.new(1.0), 1.0, engine, 8000.0, 1.0 / 64.0)
	var expected_mass: float = 12000.0 - 50000.0 / (320.0 * FlightMath.G0) * 20.0
	var expected_dv: float = 320.0 * FlightMath.G0 * log(12000.0 / expected_mass)
	check_near(state.m, expected_mass, 0.5, "fixed burn propellant flow")
	check_near(state.v.x, expected_dv, 0.5, "fixed burn rocket-equation impulse")
	check_near(state.v.y, 0.0, 1e-12, "no spurious lateral thrust")
	check_near(state.v.z, 0.0, 1e-12, "no spurious vertical thrust")


## Check 17: a 180-degree slew settles in the expected physical time with bounded torque.
func test_half_turn_slew_settles() -> void:
	var inertia: Dictionary = {"ix": 14000.0, "iy": 107000.0, "iz": 107000.0}
	var q: Dictionary = FlightMath.IDENTITY_Q.duplicate()
	var omega: SimVector = SimVector.new()
	var target: SimVector = SimVector.new(-1.0)
	var settle: float = INF
	var max_seen: float = 0.0
	for step: int in range(1920):
		var torque: SimVector = FlightMath.control_torque_body(q, omega, target, inertia, 5500.0, deg_to_rad(20.0))
		max_seen = maxf(max_seen, SimVector.length(torque))
		var next: Dictionary = FlightMath.integrate_attitude(q, omega, inertia, torque, 1.0 / 64.0)
		q = next.q
		omega = next.omega
		var angle: float = acos(clampf(SimVector.dot(FlightMath.thrust_axis_world(q), target), -1.0, 1.0))
		if angle < deg_to_rad(0.5) and SimVector.length(omega) < deg_to_rad(0.5):
			settle = float(step + 1) / 64.0
			break
	check(settle >= 8.0 and settle <= 26.0, "half-turn settles between 8 and 26 seconds: %.3f" % settle)
	check(max_seen <= 5500.0 + 1e-9, "controller respects available torque")
	check_near(float(q.w) * float(q.w) + float(q.x) * float(q.x) + float(q.y) * float(q.y) + float(q.z) * float(q.z), 1.0, 1e-12, "attitude stays unit length")
	check_eq(SimVector.length(FlightMath.control_torque_body(q, omega, null, inertia, 5500.0, 0.3)), 0.0, "manual mode supplies no automatic torque")


## Local node axes are orthonormal even on eccentric orbits and invert without losing a component.
func test_orbital_frame_and_quaternion_round_trip() -> void:
	var r: SimVector = SimVector.new(7e6, 2e6, 1e6)
	var v: SimVector = SimVector.new(-1000.0, 7800.0, 2000.0)
	var frame: Dictionary = FlightMath.orbital_frame(r, v)
	check_near(SimVector.dot(frame.prograde, frame.normal), 0.0, 1e-14, "prograde perpendicular normal")
	check_near(SimVector.dot(frame.prograde, frame.radial_out), 0.0, 1e-14, "prograde perpendicular radial")
	check_near(SimVector.dot(frame.normal, frame.radial_out), 0.0, 1e-14, "normal perpendicular radial")
	var local: Dictionary = {"prograde": 70.0, "normal": -34.0, "radial": 27.0}
	var world: SimVector = FlightMath.local_dv_to_world(local, r, v)
	var again: Dictionary = FlightMath.world_dv_to_local(world, r, v)
	for axis: String in local:
		check_near(again[axis], local[axis], 1e-12, "delta-v round trip " + axis)
	check_near(SimVector.length(world), FlightMath.dv_magnitude(local), 1e-12, "orthonormal magnitude preserved")
	check_near(SimVector.dot(FlightMath.heading_dir("radial_in", r, v), frame.radial_out), -1.0, 1e-14, "radial hold agrees with node frame")
	var q: Dictionary = FlightMath.q_normalize({"w": 2.0, "x": 0.1, "y": 0.8, "z": -0.2})
	check_near(SimVector.distance(r, FlightMath.rotate(FlightMath.q_conj(q), FlightMath.rotate(q, r))), 0.0, 1e-8, "quaternion inverse rotation")


## Fuel exhaustion truncates the burn within a step; throttle and malformed inputs cannot create impulse.
func test_depletion_and_input_guards() -> void:
	var engine: Dictionary = {"thrust_n": 50000.0, "isp_seconds": 320.0}
	var state: Dictionary = {"r": SimVector.new(), "v": SimVector.new(), "m": 8000.01}
	var after: Dictionary = FlightMath.step_powered(state, {"mu": 0.0}, SimVector.new(1.0), 1.0, engine, 8000.0, 1.0)
	check_near(after.m, 8000.0, 1e-12, "mass stops at dry mass")
	check_near(after.v.x, 320.0 * FlightMath.G0 * log(8000.01 / 8000.0), 1e-8, "last fuel cannot power entire timestep")
	var coast: Dictionary = FlightMath.step_powered(after, {"mu": 0.0}, SimVector.new(1.0), 1.0, engine, 8000.0, 1.0)
	check_eq(coast.v.x, after.v.x, "empty tank coasts")
	state.m = 12000.0
	var clamped: Dictionary = FlightMath.step_powered(state, {"mu": 0.0}, SimVector.new(1.0), 10.0, engine, 8000.0, 0.01)
	var normal: Dictionary = FlightMath.step_powered(state, {"mu": 0.0}, SimVector.new(1.0), 1.0, engine, 8000.0, 0.01)
	check_eq(clamped.v.x, normal.v.x, "throttle clamps at full power")
	check_eq(FlightMath.step_powered(state, {"mu": 0.0}, SimVector.new(1.0), NAN, engine, 8000.0, 1.0).m, state.m, "invalid throttle rejected")
	check_eq(FlightMath.step_powered(state, {"mu": 0.0}, SimVector.new(1.0), 1.0, engine, 8000.0, -1.0).m, state.m, "negative timestep rejected")
	check_eq(FlightMath.step_powered(state, {"mu": NAN}, SimVector.new(1.0), 1.0, engine, 8000.0, 1.0).m, state.m, "invalid gravity rejected")
	check_eq(FlightMath.step_powered(state, {"mu": 0.0}, null, 1.0, engine, 8000.0, 1.0).m, state.m, "missing direction cannot burn")


## RK4 with no thrust follows the same Kepler trajectory over many fixed steps.
func test_rk4_gravity_tracks_analytic_coast() -> void:
	var body: Dictionary = SimConstants.cradle()
	var elements: Dictionary = SimConstants.circular_orbit(body, 400e3, 0.9)
	var initial: Dictionary = OrbitMath.propagate(elements, body, 0.0)
	var state: Dictionary = {"r": initial.position, "v": initial.velocity, "m": 12000.0}
	for _step: int in range(640):
		state = FlightMath.step_powered(state, body, SimVector.new(), 0.0, {"thrust_n": 50000.0, "isp_seconds": 320.0}, 8000.0, 1.0 / 64.0)
	var analytic: Dictionary = OrbitMath.propagate(elements, body, 10.0)
	check_near(SimVector.distance(state.r, analytic.position), 0.0, 1e-5, "RK4 coast position")
	check_near(SimVector.distance(state.v, analytic.velocity), 0.0, 1e-8, "RK4 coast velocity")
	check_eq(state.m, 12000.0, "coast uses no propellant")
