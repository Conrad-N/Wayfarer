## Pure orbital targeting instruments, ported from the original flight simulator.
## Positions and velocities remain scalar-double SimVectors throughout every solve.
class_name OrbitalSolvers
extends RefCounted

const DEFAULT_INTERCEPT_REVS: int = 4
const INTERCEPT_LEAD: float = 60.0
const DEGENERATE_ANGLE: float = 1.5 * PI / 180.0
const MAX_INTERCEPT_DV: float = 50000.0
const TRANSFER_CLEARANCE: float = 10000.0
const ARC_SAMPLES: int = 64
const CORRECTION_FRACTIONS: Array[float] = [0.5, 0.8, 0.93]
const INTERPLANETARY_LEAD: float = 120.0
const EJECT_VINF: float = 1000.0


## Circularize at the next requested apsis; an unavailable apsis returns no node.
static func solve_circularize(el: Dictionary, body: Dictionary, t_now: float, at: String) -> Dictionary:
	if not _valid_orbit_request(el, body, t_now) or at not in ["apoapsis", "periapsis"]:
		return {}
	var state: Dictionary = OrbitMath.propagate(el, body, t_now)
	var radius: float = state.apoapsis_radius if at == "apoapsis" else state.periapsis_radius
	var delay: float = state.time_to_apoapsis if at == "apoapsis" else state.time_to_periapsis
	if not is_finite(radius) or not is_finite(delay) or radius <= 0.0:
		return {}
	return _node(t_now + delay, sqrt(body.mu / radius) - _vis_viva(body.mu, radius, state.a))


## Move one apsis by burning at the opposite apsis, preserving that burn radius.
static func solve_set_apsis(el: Dictionary, body: Dictionary, t_now: float, which: String, target_radius: float) -> Dictionary:
	if not _valid_orbit_request(el, body, t_now) or which not in ["apoapsis", "periapsis"]:
		return {}
	if not is_finite(target_radius) or target_radius <= float(body.radius):
		return {}
	var state: Dictionary = OrbitMath.propagate(el, body, t_now)
	var at_apo: bool = which == "periapsis"
	var radius: float = state.apoapsis_radius if at_apo else state.periapsis_radius
	var delay: float = state.time_to_apoapsis if at_apo else state.time_to_periapsis
	if not is_finite(radius) or not is_finite(delay) or radius <= 0.0:
		return {}
	if (which == "apoapsis" and target_radius < radius) or (which == "periapsis" and target_radius > radius):
		return {}
	var new_a: float = (radius + target_radius) / 2.0
	return _node(t_now + delay, _vis_viva(body.mu, radius, new_a) - _vis_viva(body.mu, radius, state.a))


## Two-burn Hohmann transfer from a circular orbit to a new circular radius.
static func solve_hohmann(el: Dictionary, body: Dictionary, t_now: float, target_radius: float) -> Array[Dictionary]:
	if not _valid_orbit_request(el, body, t_now) or not is_finite(target_radius) or target_radius <= float(body.radius):
		return []
	if float(el.e) > 0.001:
		return []
	var state: Dictionary = OrbitMath.propagate(el, body, t_now)
	var radius: float = state.radius
	var transfer_a: float = (radius + target_radius) / 2.0
	var arrival: float = t_now + PI * sqrt(pow(transfer_a, 3.0) / body.mu)
	return [_node(t_now, _vis_viva(body.mu, radius, transfer_a) - state.speed),
		_node(arrival, sqrt(body.mu / target_radius) - _vis_viva(body.mu, target_radius, transfer_a))]


## Lambert's universal-variable solution, including both branches of multiple revolutions.
## An empty dictionary means no finite usable conic connects the requested endpoints.
static func lambert(r1: SimVector, r2: SimVector, tof: float, mu: float, prograde: bool = true, nrev: int = 0, branch: String = "low") -> Dictionary:
	if not SimVector.is_finite_vector(r1) or not SimVector.is_finite_vector(r2):
		return {}
	if not is_finite(tof) or tof <= 0.0 or not is_finite(mu) or mu <= 0.0 or nrev < 0 or nrev > 32 or branch not in ["low", "high"]:
		return {}
	var r1m: float = SimVector.length(r1)
	var r2m: float = SimVector.length(r2)
	if r1m <= 0.0 or r2m <= 0.0:
		return {}
	var cosine: float = clampf(SimVector.dot(r1, r2) / (r1m * r2m), -1.0, 1.0)
	if absf(1.0 - absf(cosine)) < 1e-14:
		return {}
	var cross_z: float = r1.x * r2.y - r1.y * r2.x
	var angle: float = acos(cosine)
	if (prograde and cross_z < 0.0) or (not prograde and cross_z > 0.0):
		angle = TAU - angle
	var factor: float = sin(angle) * sqrt(r1m * r2m / (1.0 - cos(angle)))
	if absf(factor) < 1e-9:
		return {}
	var sqrt_mu: float = sqrt(mu)
	var lo: float = -4.0 * PI * PI
	var hi: float = 4.0 * PI * PI
	if nrev > 0:
		var inner: float = pow(2.0 * nrev * PI, 2.0)
		var outer: float = pow(2.0 * (nrev + 1) * PI, 2.0)
		var span: float = outer - inner
		var lower: float = inner + span * 1e-6
		var upper: float = outer - span * 1e-6
		var ta: float = lower
		var tb: float = upper
		for _iteration: int in range(100):
			var m1: float = ta + (tb - ta) / 3.0
			var m2: float = tb - (tb - ta) / 3.0
			if _finite_tof(m1, r1m, r2m, factor, sqrt_mu) < _finite_tof(m2, r1m, r2m, factor, sqrt_mu):
				tb = m2
			else:
				ta = m1
		var minimum: float = (ta + tb) / 2.0
		if tof < _finite_tof(minimum, r1m, r2m, factor, sqrt_mu):
			return {}
		lo = lower if branch == "low" else minimum
		hi = minimum if branch == "low" else upper
	var tl: float = _tof_at(lo + (hi - lo) * 1e-3, r1m, r2m, factor, sqrt_mu)
	var th: float = _tof_at(hi - (hi - lo) * 1e-3, r1m, r2m, factor, sqrt_mu)
	var decreasing: bool = is_finite(tl) and is_finite(th) and tl > th
	var psi: float = (lo + hi) / 2.0
	var y: float = r1m + r2m
	var converged: bool = false
	for _iteration: int in range(100):
		var c: Dictionary = _stumpff(psi)
		if c.c2 <= 0.0:
			return {}
		y = r1m + r2m + factor * (psi * c.c3 - 1.0) / sqrt(c.c2)
		if factor > 0.0 and y < 0.0:
			lo = psi
			psi = (lo + hi) / 2.0
			continue
		if y < 0.0:
			return {}
		var chi: float = sqrt(y / c.c2)
		var duration: float = (chi * chi * chi * c.c3 + factor * sqrt(y)) / sqrt_mu
		if absf(duration - tof) < 1e-5 * maxf(1.0, tof):
			converged = true
			break
		if decreasing == (duration > tof):
			lo = psi
		else:
			hi = psi
		psi = (lo + hi) / 2.0
	if not converged:
		return {}
	var f: float = 1.0 - y / r1m
	var g: float = factor * sqrt(y / mu)
	var g_dot: float = 1.0 - y / r2m
	if absf(g) < 1e-9:
		return {}
	var v1: SimVector = SimVector.scale(SimVector.sub(r2, SimVector.scale(r1, f)), 1.0 / g)
	var v2: SimVector = SimVector.scale(SimVector.sub(SimVector.scale(r2, g_dot), r1), 1.0 / g)
	if not SimVector.is_finite_vector(v1) or not SimVector.is_finite_vector(v2):
		return {}
	return {"v1": v1, "v2": v2}


## Cheapest departure plus arrival impulse over direct and multi-revolution Lambert arcs.
static func best_transfer(r1: SimVector, r2: SimVector, tof: float, mu: float, v_now: SimVector, v_arr: SimVector, max_revs: int = DEFAULT_INTERCEPT_REVS) -> Dictionary:
	if not SimVector.is_finite_vector(v_now) or not SimVector.is_finite_vector(v_arr):
		return {}
	var best: Dictionary = {}
	var best_dv: float = INF
	for solution: Dictionary in _transfers(r1, r2, tof, mu, max_revs, true):
		var dv: float = SimVector.distance(solution.v1, v_now) + SimVector.distance(v_arr, solution.v2)
		if is_finite(dv) and dv < best_dv:
			best_dv = dv
			best = solution
	return best


## Rendezvous with a future target position, optionally adding three live correction nodes.
static func solve_intercept(ship_el: Dictionary, body: Dictionary, t_now: float, target_el: Dictionary, tof: float, max_revs: int = DEFAULT_INTERCEPT_REVS, guided: bool = false) -> Array[Dictionary]:
	if not _valid_orbit_request(ship_el, body, t_now) or not _valid_orbit_request(target_el, body, t_now) or not is_finite(tof) or tof <= 0.0:
		return []
	var burn_time: float = t_now + INTERCEPT_LEAD
	var arrival_time: float = burn_time + tof
	var departure: Dictionary = OrbitMath.propagate(ship_el, body, burn_time)
	var arrival: Dictionary = OrbitMath.propagate(target_el, body, arrival_time)
	var cosine: float = clampf(SimVector.dot(departure.position, arrival.position) / (departure.radius * arrival.radius), -1.0, 1.0)
	var theta: float = acos(cosine)
	var direct: bool = theta >= DEGENERATE_ANGLE and PI - theta >= DEGENERATE_ANGLE
	var best: Dictionary = {}
	var best_dv: float = INF
	for solution: Dictionary in _transfers(departure.position, arrival.position, tof, body.mu, max_revs, direct):
		var dv: float = SimVector.distance(solution.v1, departure.velocity) + SimVector.distance(arrival.velocity, solution.v2)
		if is_finite(dv) and dv < best_dv and _transfer_clears(departure.position, solution.v1, body, burn_time, tof):
			best = solution
			best_dv = dv
	if best.is_empty() or best_dv > MAX_INTERCEPT_DV:
		return []
	var depart_node: Dictionary = {"time": burn_time, "dv_local": FlightMath.world_dv_to_local(SimVector.sub(best.v1, departure.velocity), departure.position, departure.velocity)}
	var match_node: Dictionary = {"time": arrival_time, "dv_local": FlightMath.world_dv_to_local(SimVector.sub(arrival.velocity, best.v2), arrival.position, best.v2)}
	var nodes: Array[Dictionary] = [depart_node]
	if guided:
		for fraction: float in CORRECTION_FRACTIONS:
			nodes.append(_guided_node(burn_time + fraction * tof, target_el, arrival_time, max_revs))
		match_node["retarget"] = {"kind": "match", "target_el": target_el.duplicate(true)}
	nodes.append(match_node)
	return nodes


## Scan 30–360 minutes of flight time for the least expensive physical rendezvous.
static func suggest_intercept_tof(ship_el: Dictionary, body: Dictionary, t_now: float, target_el: Dictionary, max_revs: int = DEFAULT_INTERCEPT_REVS) -> Dictionary:
	var best: Dictionary = {}
	for tof: int in range(1800, 21601, 120):
		var nodes: Array[Dictionary] = solve_intercept(ship_el, body, t_now, target_el, float(tof), max_revs)
		if nodes.is_empty():
			continue
		var dv: float = 0.0
		for node: Dictionary in nodes:
			dv += FlightMath.dv_magnitude(node.dv_local)
		if best.is_empty() or dv < float(best.dv_mag):
			best = {"tof_seconds": float(tof), "dv_mag": dv}
	return best


## Search sibling-body transfer windows in their parent frame, favoring an early affordable departure.
static func suggest_interplanetary_window(a_body: Dictionary, b_body: Dictionary, system: OrbitalSystem, t_now: float, r0: float, opts: Dictionary = {}) -> Dictionary:
	if system == null or not is_finite(t_now) or not is_finite(r0) or r0 <= 0.0:
		return {}
	if a_body.get("parent_id") == null or b_body.get("parent_id") == null or a_body.parent_id != b_body.parent_id:
		return {}
	if not a_body.get("elements") is Dictionary or not b_body.get("elements") is Dictionary or a_body.get("id") == b_body.get("id"):
		return {}
	if not system.has(str(a_body.get("id", ""))) or not system.has(str(b_body.get("id", ""))) or r0 <= float(a_body.get("radius", INF)):
		return {}
	var parent: Dictionary = system.body(a_body.parent_id)
	if parent.is_empty() or float(a_body.mu) <= 0.0 or float(b_body.mu) <= 0.0:
		return {}
	var a_state: Dictionary = system.relative_state(parent.id, a_body.id, t_now)
	var b_state: Dictionary = system.relative_state(parent.id, b_body.id, t_now)
	var transfer_a: float = (SimVector.length(a_state.position) + SimVector.length(b_state.position)) / 2.0
	var hohmann_time: float = PI * sqrt(pow(transfer_a, 3.0) / parent.mu)
	var tof_min: float = opts.get("tof_min_s", 0.35 * hohmann_time)
	var tof_max: float = opts.get("tof_max_s", 1.75 * hohmann_time)
	var period_a: float = OrbitMath.propagate(a_body.elements, parent, t_now).period
	var period_b: float = OrbitMath.propagate(b_body.elements, parent, t_now).period
	var difference: float = absf(1.0 / period_a - 1.0 / period_b)
	var synodic: float = 1.0 / difference if difference > 1e-15 else 5.0 * maxf(period_a, period_b)
	var depart_span: float = opts.get("depart_span_s", 1.5 * synodic)
	var r_park: float = opts.get("r_park_b", float(b_body.radius) + 200000.0)
	var margin: float = opts.get("margin_frac", 1.15)
	for value: float in [tof_min, tof_max, depart_span, r_park, margin]:
		if not is_finite(value) or value <= 0.0:
			return {}
	if tof_max < tof_min or margin < 1.0 or r_park <= float(b_body.radius):
		return {}
	var context: Dictionary = {"a": a_body, "b": b_body, "parent": parent, "system": system, "now": t_now, "r0": r0, "r_park": r_park}
	var coarse: Dictionary = _pick_window(_collect_windows(context, 0.0, depart_span, tof_min, tof_max, 48, 40), margin)
	if coarse.is_empty():
		return {}
	var d_step: float = depart_span / 48.0
	var t_step: float = (tof_max - tof_min) / 40.0
	var center: float = coarse.departure_time - t_now
	var fine: Dictionary = _pick_window(_collect_windows(context, maxf(0.0, center - d_step), minf(depart_span, center + d_step), maxf(tof_min, coarse.tof_seconds - t_step), minf(tof_max, coarse.tof_seconds + t_step), 12, 12), margin)
	return coarse if fine.is_empty() else fine


## Build ejection, parent-frame injection and two live trims across an SOI boundary.
static func solve_interplanetary_transfer(ship_el: Dictionary, a_body: Dictionary, t_now: float, b_body: Dictionary, window: Dictionary, opts: Dictionary = {}) -> Array[Dictionary]:
	if not _valid_orbit_request(ship_el, a_body, t_now) or a_body.get("parent_id") == null or not is_finite(float(a_body.get("soi_radius", NAN))) or not b_body.get("elements") is Dictionary:
		return []
	if a_body.get("parent_id") != b_body.get("parent_id") or a_body.get("id") == b_body.get("id"):
		return []
	for key: String in ["departure_time", "arrival_time", "v_inf_out"]:
		if not window.has(key):
			return []
	if not is_finite(float(window.departure_time)) or not is_finite(float(window.arrival_time)) or not SimVector.is_finite_vector(window.v_inf_out):
		return []
	var max_revs: int = clampi(int(opts.get("max_revs", 0)), 0, 32)
	var excess: float = maxf(1.0, SimVector.length(window.v_inf_out))
	var period: float = OrbitMath.propagate(ship_el, a_body, window.departure_time).period
	var eject_time: float = window.departure_time
	if is_finite(period) and period > 0.0:
		var best_dot: float = -INF
		for k: int in range(64):
			var time: float = window.departure_time + float(k) * period / 64.0
			var velocity: SimVector = OrbitMath.propagate(ship_el, a_body, time).velocity
			var speed: float = SimVector.length(velocity)
			var alignment: float = SimVector.dot(velocity, window.v_inf_out) / (speed * excess) if speed > 0.0 else -INF
			if alignment > best_dot:
				best_dot = alignment
				eject_time = time
	if eject_time < t_now + INTERPLANETARY_LEAD:
		eject_time = maxf(eject_time + (period if is_finite(period) else 0.0), t_now + INTERPLANETARY_LEAD)
	var eject_state: Dictionary = OrbitMath.propagate(ship_el, a_body, eject_time)
	var radius: float = SimVector.length(eject_state.position)
	var speed: float = SimVector.length(eject_state.velocity)
	if speed <= 0.0 or radius <= 0.0:
		return []
	var dv: float = sqrt(EJECT_VINF * EJECT_VINF + 2.0 * a_body.mu / radius) - speed
	var velocity_post: SimVector = SimVector.scale(eject_state.velocity, 1.0 + dv / speed)
	var post_el: Dictionary = ManeuverMath.state_to_elements(eject_state.position, velocity_post, a_body, eject_time)
	var escape: Variant = OrbitMath.next_escape_time(post_el, a_body, eject_time, a_body.soi_radius)
	var escape_time: float = eject_time + 0.05 * (window.arrival_time - eject_time) if escape == null else float(escape)
	var arrival_time: float = window.arrival_time
	if not is_finite(escape_time) or arrival_time <= escape_time:
		return []
	var injection_time: float = escape_time + 0.01 * (arrival_time - escape_time)
	return [_node(eject_time, dv), _guided_node(injection_time, b_body.elements, arrival_time, max_revs),
		_guided_node(injection_time + 0.45 * (arrival_time - injection_time), b_body.elements, arrival_time, max_revs),
		_guided_node(injection_time + 0.8 * (arrival_time - injection_time), b_body.elements, arrival_time, max_revs)]


## Cancel a target's current relative velocity with one local-frame impulse.
static func solve_match_velocity(ship_el: Dictionary, body: Dictionary, t_now: float, target_el: Dictionary) -> Dictionary:
	if not _valid_orbit_request(ship_el, body, t_now) or not _valid_orbit_request(target_el, body, t_now):
		return {}
	var state: Dictionary = OrbitMath.propagate(ship_el, body, t_now)
	var target: Dictionary = OrbitMath.propagate(target_el, body, t_now)
	return {"time": t_now, "dv_local": FlightMath.world_dv_to_local(SimVector.sub(target.velocity, state.velocity), state.position, state.velocity)}


static func _node(time: float, prograde: float) -> Dictionary:
	return {"time": time, "dv_local": {"prograde": prograde, "normal": 0.0, "radial": 0.0}}


static func _guided_node(time: float, target_el: Dictionary, arrival_time: float, max_revs: int) -> Dictionary:
	var node: Dictionary = _node(time, 0.0)
	node["retarget"] = {"kind": "transfer", "target_el": target_el.duplicate(true), "arrival_time": arrival_time, "max_revs": max_revs}
	return node


static func _valid_orbit_request(el: Dictionary, body: Dictionary, time: float) -> bool:
	return is_finite(time) and is_finite(float(body.get("radius", NAN))) and float(body.get("radius", -1.0)) >= 0.0 and OrbitMath.valid_elements(el, body)


static func _vis_viva(mu: float, radius: float, semi_major: float) -> float:
	return sqrt(maxf(0.0, mu * (2.0 / radius - 1.0 / semi_major)))


static func _stumpff(psi: float) -> Dictionary:
	if psi > 1e-6:
		var root: float = sqrt(psi)
		return {"c2": (1.0 - cos(root)) / psi, "c3": (root - sin(root)) / pow(root, 3.0)}
	if psi < -1e-6:
		var root: float = sqrt(-psi)
		return {"c2": (1.0 - cosh(root)) / psi, "c3": (sinh(root) - root) / pow(root, 3.0)}
	return {"c2": 0.5, "c3": 1.0 / 6.0}


static func _tof_at(psi: float, r1m: float, r2m: float, factor: float, sqrt_mu: float) -> float:
	var c: Dictionary = _stumpff(psi)
	if c.c2 <= 0.0:
		return NAN
	var y: float = r1m + r2m + factor * (psi * c.c3 - 1.0) / sqrt(c.c2)
	if y < 0.0:
		return NAN
	var chi: float = sqrt(y / c.c2)
	return (chi * chi * chi * c.c3 + factor * sqrt(y)) / sqrt_mu


static func _finite_tof(psi: float, r1m: float, r2m: float, factor: float, sqrt_mu: float) -> float:
	var value: float = _tof_at(psi, r1m, r2m, factor, sqrt_mu)
	return value if is_finite(value) else INF


static func _transfers(r1: SimVector, r2: SimVector, tof: float, mu: float, max_revs: int, direct: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if direct:
		var solution: Dictionary = lambert(r1, r2, tof, mu)
		if not solution.is_empty():
			result.append(solution)
	for n: int in range(1, clampi(max_revs, 0, 32) + 1):
		for branch: String in ["low", "high"]:
			var solution: Dictionary = lambert(r1, r2, tof, mu, true, n, branch)
			if not solution.is_empty():
				result.append(solution)
	return result


static func _transfer_clears(r1: SimVector, v1: SimVector, body: Dictionary, burn_time: float, tof: float) -> bool:
	var safe_radius: float = body.radius + TRANSFER_CLEARANCE
	var el: Dictionary = ManeuverMath.state_to_elements(r1, v1, body, burn_time)
	if el.is_empty():
		return false
	if el.e < 1.0 and el.a * (1.0 - el.e) >= safe_radius:
		return true
	for k: int in range(ARC_SAMPLES + 1):
		var position: SimVector = OrbitMath.propagate(el, body, burn_time + tof * k / ARC_SAMPLES).position
		if not SimVector.is_finite_vector(position) or SimVector.length(position) < safe_radius:
			return false
	return true


static func _window_at(context: Dictionary, offset: float, tof: float) -> Dictionary:
	if offset < 0.0 or tof <= 0.0:
		return {}
	var departure: float = context.now + offset
	var arrival: float = departure + tof
	var system: OrbitalSystem = context.system
	var a_state: Dictionary = system.relative_state(context.parent.id, context.a.id, departure)
	var b_state: Dictionary = system.relative_state(context.parent.id, context.b.id, arrival)
	var solution: Dictionary = lambert(a_state.position, b_state.position, tof, context.parent.mu)
	if solution.is_empty():
		return {}
	var v_out: SimVector = SimVector.sub(solution.v1, a_state.velocity)
	var v_in: SimVector = SimVector.sub(solution.v2, b_state.velocity)
	var dv_eject: float = sqrt(pow(SimVector.length(v_out), 2.0) + 2.0 * context.a.mu / context.r0) - sqrt(context.a.mu / context.r0)
	var dv_capture: float = sqrt(pow(SimVector.length(v_in), 2.0) + 2.0 * context.b.mu / context.r_park) - sqrt(context.b.mu / context.r_park)
	if not is_finite(dv_eject + dv_capture):
		return {}
	return {"departure_time": departure, "arrival_time": arrival, "tof_seconds": tof,
		"v_inf_out": v_out, "v_inf_in": v_in, "v_dep_helio": solution.v1,
		"dv_eject": dv_eject, "dv_capture": dv_capture, "dv_total": dv_eject + dv_capture}


static func _collect_windows(context: Dictionary, d0: float, d1: float, t0: float, t1: float, n_depart: int, n_tof: int) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for i: int in range(n_depart + 1):
		for j: int in range(n_tof + 1):
			var cell: Dictionary = _window_at(context, d0 + float(i) * (d1 - d0) / n_depart, t0 + float(j) * (t1 - t0) / n_tof)
			if not cell.is_empty():
				cells.append(cell)
	return cells


static func _pick_window(cells: Array[Dictionary], margin: float) -> Dictionary:
	var minimum: float = INF
	for cell: Dictionary in cells:
		minimum = minf(minimum, cell.dv_total)
	var best: Dictionary = {}
	for cell: Dictionary in cells:
		if cell.dv_total > margin * minimum:
			continue
		if best.is_empty() or cell.departure_time < best.departure_time or (cell.departure_time == best.departure_time and cell.dv_total < best.dv_total):
			best = cell
	return best
