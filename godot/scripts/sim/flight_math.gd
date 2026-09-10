## Deterministic attitude control and fixed-step powered motion, using scalar double arithmetic.
class_name FlightMath
extends RefCounted

const G0: float = 9.80665
const IDENTITY_Q: Dictionary = {"w": 1.0, "x": 0.0, "y": 0.0, "z": 0.0}


## Clamp a world/body vector magnitude to a torque or speed limit.
static func clamp_magnitude(value: SimVector, maximum: float) -> SimVector:
	return SimVector.clamp_magnitude(value, maximum)


## Quaternion product, with body-to-world orientation convention.
static func q_mul(a: Dictionary, b: Dictionary) -> Dictionary:
	return {
		"w": float(a.w) * float(b.w) - float(a.x) * float(b.x) - float(a.y) * float(b.y) - float(a.z) * float(b.z),
		"x": float(a.w) * float(b.x) + float(a.x) * float(b.w) + float(a.y) * float(b.z) - float(a.z) * float(b.y),
		"y": float(a.w) * float(b.y) - float(a.x) * float(b.z) + float(a.y) * float(b.w) + float(a.z) * float(b.x),
		"z": float(a.w) * float(b.z) + float(a.x) * float(b.y) - float(a.y) * float(b.x) + float(a.z) * float(b.w),
	}


## Normalize quaternion, substituting identity for a zero or invalid rotation.
static func q_normalize(q: Dictionary) -> Dictionary:
	var magnitude: float = sqrt(pow(float(q.get("w", 0.0)), 2.0) + pow(float(q.get("x", 0.0)), 2.0) + pow(float(q.get("y", 0.0)), 2.0) + pow(float(q.get("z", 0.0)), 2.0))
	if magnitude <= 0.0 or not is_finite(magnitude):
		return IDENTITY_Q.duplicate()
	return {"w": float(q.w) / magnitude, "x": float(q.x) / magnitude, "y": float(q.y) / magnitude, "z": float(q.z) / magnitude}


## Conjugate a unit quaternion to reverse its frame transform.
static func q_conj(q: Dictionary) -> Dictionary:
	return {"w": q.w, "x": -float(q.x), "y": -float(q.y), "z": -float(q.z)}


## Rotate a vector by a unit quaternion.
static func rotate(q: Dictionary, vector: SimVector) -> SimVector:
	var imaginary: SimVector = SimVector.new(q.x, q.y, q.z)
	var twice_cross: SimVector = SimVector.scale(SimVector.cross(imaginary, vector), 2.0)
	return SimVector.add(SimVector.add(vector, SimVector.scale(twice_cross, q.w)), SimVector.cross(imaginary, twice_cross))


## Legacy ship thrust points along body +X; scene adapters map this to their nose axis.
static func thrust_axis_world(q: Dictionary) -> SimVector:
	return rotate(q, SimVector.new(1.0, 0.0, 0.0))


## Semi-implicit Euler rigid-body attitude step with normalized quaternion kinematics.
static func integrate_attitude(q: Dictionary, omega: SimVector, inertia: Dictionary, torque: SimVector, dt: float) -> Dictionary:
	if not _valid_inertia(inertia) or not is_finite(dt) or dt <= 0.0 or not SimVector.is_finite_vector(omega) or not SimVector.is_finite_vector(torque):
		return {"q": q.duplicate(), "omega": SimVector.scale(omega, 1.0)}
	var inertia_omega: SimVector = SimVector.new(float(inertia.ix) * omega.x, float(inertia.iy) * omega.y, float(inertia.iz) * omega.z)
	var gyro: SimVector = SimVector.cross(omega, inertia_omega)
	var derivative: SimVector = SimVector.new((torque.x - gyro.x) / float(inertia.ix), (torque.y - gyro.y) / float(inertia.iy), (torque.z - gyro.z) / float(inertia.iz))
	var omega_new: SimVector = SimVector.add(omega, SimVector.scale(derivative, dt))
	var spin: Dictionary = q_mul(q, {"w": 0.0, "x": omega_new.x, "y": omega_new.y, "z": omega_new.z})
	var q_new: Dictionary = q_normalize({"w": float(q.w) + 0.5 * float(spin.w) * dt, "x": float(q.x) + 0.5 * float(spin.x) * dt, "y": float(q.y) + 0.5 * float(spin.y) * dt, "z": float(q.z) + 0.5 * float(spin.z) * dt})
	return {"q": q_new, "omega": omega_new}


## Phase-plane point-at controller, including a deterministic axis for a 180-degree flip.
static func control_torque_body(q: Dictionary, omega: SimVector, target_dir_world: SimVector, inertia: Dictionary, max_torque: float, rate_cap: float) -> SimVector:
	if target_dir_world == null or not _valid_inertia(inertia) or max_torque <= 0.0 or rate_cap <= 0.0:
		return SimVector.new()
	var axis: SimVector = thrust_axis_world(q)
	var target: SimVector = SimVector.normalized(target_dir_world)
	if SimVector.length(target) == 0.0:
		return SimVector.new()
	var angle: float = acos(clampf(SimVector.dot(axis, target), -1.0, 1.0))
	var error: SimVector = SimVector.cross(axis, target)
	var error_length: float = SimVector.length(error)
	var error_axis: SimVector = SimVector.new()
	if error_length > 1e-9:
		error_axis = SimVector.scale(error, 1.0 / error_length)
	elif angle > 1e-6:
		error_axis = SimVector.normalized(SimVector.cross(axis, SimVector.new(1.0, 0.0, 0.0) if absf(axis.x) < 0.9 else SimVector.new(0.0, 1.0, 0.0)))
	var omega_magnitude: float = minf(rate_cap, sqrt(2.0 * max_torque / float(inertia.iy) * angle * 0.85))
	var desired: SimVector = SimVector.scale(error_axis, omega_magnitude)
	var torque_world: SimVector = clamp_magnitude(SimVector.scale(SimVector.sub(desired, rotate(q, omega)), float(inertia.iy) * 4.0), max_torque)
	return rotate(q_conj(q), torque_world)


## Orthonormal orbital basis: velocity, orbit normal, and outward transverse radial.
static func orbital_frame(r: SimVector, v: SimVector) -> Dictionary:
	var prograde: SimVector = SimVector.normalized(v)
	var normal: SimVector = SimVector.normalized(SimVector.cross(r, v))
	return {"prograde": prograde, "normal": normal, "radial_out": SimVector.normalized(SimVector.cross(prograde, normal))}


## Direction for an orbital attitude hold mode.
static func heading_dir(mode: String, r: SimVector, v: SimVector) -> SimVector:
	var frame: Dictionary = orbital_frame(r, v)
	match mode:
		"retrograde": return SimVector.scale(frame.prograde, -1.0)
		"normal": return frame.normal
		"antinormal": return SimVector.scale(frame.normal, -1.0)
		"radial_out": return frame.radial_out
		"radial_in": return SimVector.scale(frame.radial_out, -1.0)
	return frame.prograde


## Magnitude of a three-component local maneuver delta-v.
static func dv_magnitude(dv: Dictionary) -> float:
	return SimVector.length(SimVector.new(dv.get("prograde", 0.0), dv.get("normal", 0.0), dv.get("radial", 0.0)))


## Convert orthonormal local delta-v to the inertial frame.
static func local_dv_to_world(dv: Dictionary, r: SimVector, v: SimVector) -> SimVector:
	var frame: Dictionary = orbital_frame(r, v)
	return SimVector.add(SimVector.add(SimVector.scale(frame.prograde, dv.get("prograde", 0.0)), SimVector.scale(frame.normal, dv.get("normal", 0.0))), SimVector.scale(frame.radial_out, dv.get("radial", 0.0)))


## Unit inertial burn direction.
static func node_world_dir(dv: Dictionary, r: SimVector, v: SimVector) -> SimVector:
	return SimVector.normalized(local_dv_to_world(dv, r, v))


## Decompose inertial delta-v into the same orthonormal planner basis.
static func world_dv_to_local(dv_world: SimVector, r: SimVector, v: SimVector) -> Dictionary:
	var frame: Dictionary = orbital_frame(r, v)
	return {"prograde": SimVector.dot(dv_world, frame.prograde), "normal": SimVector.dot(dv_world, frame.normal), "radial": SimVector.dot(dv_world, frame.radial_out)}


## One RK4 step of gravity plus thrust with fuel-limited duration and mass depletion.
## Caller owns the fixed timestep accumulator. A tank exhausted midstep cannot supply free thrust.
static func step_powered(state: Dictionary, body: Dictionary, thrust_dir_world: SimVector, throttle: float, engine: Dictionary, dry_mass_kg: float, dt: float) -> Dictionary:
	var mass: float = state.get("m", NAN)
	var mu: float = body.get("mu", NAN)
	if not is_finite(dt) or dt <= 0.0 or not is_finite(throttle) or not is_finite(dry_mass_kg) or dry_mass_kg <= 0.0 or not is_finite(mass) or mass < dry_mass_kg or not is_finite(mu) or mu < 0.0 or not state.get("r") is SimVector or not state.get("v") is SimVector:
		return state.duplicate()
	if not SimVector.is_finite_vector(state.r) or not SimVector.is_finite_vector(state.v):
		return state.duplicate()
	var thrust_n: float = engine.get("thrust_n", 0.0)
	var isp: float = engine.get("isp_seconds", 0.0)
	var burning: bool = throttle > 0.0 and mass > dry_mass_kg and thrust_n > 0.0 and isp > 0.0 and is_finite(thrust_n) and is_finite(isp) and SimVector.is_finite_vector(thrust_dir_world)
	var force: float = thrust_n * clampf(throttle, 0.0, 1.0) if burning else 0.0
	var mdot: float = force / (isp * G0) if burning else 0.0
	var burn_dt: float = minf(dt, (mass - dry_mass_kg) / mdot) if mdot > 0.0 else dt
	var thrust: SimVector = SimVector.scale(SimVector.normalized(thrust_dir_world), force / mass) if burning else SimVector.new()
	var result: Dictionary = _rk4(state, mu, thrust, burn_dt)
	result.m = maxf(dry_mass_kg, mass - mdot * burn_dt)
	if burn_dt < dt:
		result = _rk4(result, mu, SimVector.new(), dt - burn_dt)
	return result


static func _rk4(state: Dictionary, mu: float, thrust: SimVector, dt: float) -> Dictionary:
	var r: SimVector = state.r
	var v: SimVector = state.v
	var k1v: SimVector = _acceleration(r, mu, thrust)
	var k1r: SimVector = v
	var k2v: SimVector = _acceleration(SimVector.add(r, SimVector.scale(k1r, dt / 2.0)), mu, thrust)
	var k2r: SimVector = SimVector.add(v, SimVector.scale(k1v, dt / 2.0))
	var k3v: SimVector = _acceleration(SimVector.add(r, SimVector.scale(k2r, dt / 2.0)), mu, thrust)
	var k3r: SimVector = SimVector.add(v, SimVector.scale(k2v, dt / 2.0))
	var k4v: SimVector = _acceleration(SimVector.add(r, SimVector.scale(k3r, dt)), mu, thrust)
	var k4r: SimVector = SimVector.add(v, SimVector.scale(k3v, dt))
	return {
		"r": SimVector.add(r, SimVector.scale(SimVector.add(SimVector.add(k1r, SimVector.scale(k2r, 2.0)), SimVector.add(SimVector.scale(k3r, 2.0), k4r)), dt / 6.0)),
		"v": SimVector.add(v, SimVector.scale(SimVector.add(SimVector.add(k1v, SimVector.scale(k2v, 2.0)), SimVector.add(SimVector.scale(k3v, 2.0), k4v)), dt / 6.0)),
		"m": state.m,
	}


static func _acceleration(r: SimVector, mu: float, thrust: SimVector) -> SimVector:
	var radius: float = SimVector.length(r)
	return SimVector.add(SimVector.scale(r, -mu / (radius * radius * radius)), thrust) if radius > 0.0 and mu > 0.0 else SimVector.scale(thrust, 1.0)


static func _valid_inertia(inertia: Dictionary) -> bool:
	for axis: String in ["ix", "iy", "iz"]:
		if float(inertia.get(axis, 0.0)) <= 0.0 or not is_finite(float(inertia.get(axis, 0.0))):
			return false
	return true
