## A bounded three-axis wheel assembly; motors exchange momentum with the carrier.
## All state is scalar-double data and survives orbital/local scene handoffs.
class_name ShipReactionWheel
extends RefCounted

var capacity_nms: float = 100000.0
var max_torque_nm: float = 5500.0
var rotor_inertia_kgm2: float = 1000.0
var motor_efficiency: float = 0.9
var motor_loss_j_per_nms: float = 2.0
var battery_capacity_j: float = 20000000.0
var battery_energy_j: float = 20000000.0
var enabled: bool = true
var momentum_body: SimVector = SimVector.new()


## Apply a motor command, returning equal-and-opposite carrier torque in N m.
## Positive electrical work drains the supplied battery; deceleration regenerates.
func drive(requested_torque: SimVector, omega_body: SimVector, inertia: Dictionary, delta: float) -> SimVector:
	if not enabled or not _valid(delta, requested_torque, omega_body, inertia) or battery_energy_j <= 0.0:
		return SimVector.new()
	var requested_impulse: SimVector = SimVector.scale(SimVector.clamp_magnitude(requested_torque, max_torque_nm), delta)
	var next: SimVector = SimVector.sub(momentum_body, requested_impulse)
	next = SimVector.new(clampf(next.x, -capacity_nms, capacity_nms), clampf(next.y, -capacity_nms, capacity_nms), clampf(next.z, -capacity_nms, capacity_nms))
	var impulse: SimVector = SimVector.sub(momentum_body, next)
	var cost: float = _electrical_work(impulse, omega_body, inertia)
	if cost > battery_energy_j:
		# Work is convex in impulse. Its positive crossing is unique even when
		# initial rotor deceleration regenerates before a later reversal draws.
		var lo: float = 0.0
		var hi: float = 1.0
		for iteration: int in 48:
			var mid: float = (lo + hi) * 0.5
			if _electrical_work(SimVector.scale(impulse, mid), omega_body, inertia) <= battery_energy_j:
				lo = mid
			else:
				hi = mid
		impulse = SimVector.scale(impulse, lo)
		cost = battery_energy_j
	momentum_body = SimVector.sub(momentum_body, impulse)
	battery_energy_j = clampf(battery_energy_j - cost, 0.0, battery_capacity_j)
	return SimVector.scale(impulse, 1.0 / delta)


## Rotor axes turn with the carrier even when motors and electrical power are off.
func gyroscopic_torque(omega_body: SimVector) -> SimVector:
	if not SimVector.is_finite_vector(omega_body) or not SimVector.is_finite_vector(momentum_body):
		return SimVector.new()
	return SimVector.scale(SimVector.cross(omega_body, momentum_body), -1.0)


## Stable unpowered carrier/rotor precession with conserved kinetic energy.
## Implicit midpoint and its matching Cayley rotation preserve world momentum;
## bounded subdivisions keep the fixed-point solve convergent at full capacity.
func integrate_passive(q: Dictionary, omega_body: SimVector, inertia: Dictionary, delta: float) -> Dictionary:
	if not _valid(delta, SimVector.new(), omega_body, inertia):
		return {"q": q.duplicate(), "omega": SimVector.scale(omega_body, 1.0)}
	var ix: float = inertia.ix
	var iy: float = inertia.iy
	var iz: float = inertia.iz
	var minimum: float = minf(ix, minf(iy, iz))
	var maximum: float = maxf(ix, maxf(iy, iz))
	var frequency: float = (SimVector.length(momentum_body) + maximum * SimVector.length(omega_body)) / minimum
	var subdivisions: int = clampi(ceili(delta * frequency / 0.2), 1, 256)
	var step: float = delta / float(subdivisions)
	var omega: SimVector = SimVector.scale(omega_body, 1.0)
	var orientation: Dictionary = FlightMath.q_normalize(q)
	for subdivision: int in subdivisions:
		var old: SimVector = omega
		var next: SimVector = SimVector.scale(old, 1.0)
		for iteration: int in 12:
			var middle: SimVector = SimVector.scale(SimVector.add(old, next), 0.5)
			var body_h: SimVector = SimVector.new(ix * middle.x, iy * middle.y, iz * middle.z)
			var gyro: SimVector = SimVector.cross(middle, SimVector.add(body_h, momentum_body))
			next = SimVector.sub(old, SimVector.new(step * gyro.x / ix, step * gyro.y / iy, step * gyro.z / iz))
		var middle: SimVector = SimVector.scale(SimVector.add(old, next), 0.5)
		var rotation: Dictionary = FlightMath.q_normalize({"w": 1.0, "x": middle.x * step * 0.5, "y": middle.y * step * 0.5, "z": middle.z * step * 0.5})
		orientation = FlightMath.q_normalize(FlightMath.q_mul(orientation, rotation))
		omega = next
	return {"q": orientation, "omega": omega}


## Copied SI telemetry, suitable for publication through the ship API.
func snapshot() -> Dictionary:
	return {
		"momentum_nms": {"x": momentum_body.x, "y": momentum_body.y, "z": momentum_body.z},
		"capacity_nms": capacity_nms, "max_torque_nm": max_torque_nm,
		"utilization": maxf(absf(momentum_body.x), maxf(absf(momentum_body.y), absf(momentum_body.z))) / capacity_nms,
		"stored_energy_j": SimVector.dot(momentum_body, momentum_body) / (2.0 * rotor_inertia_kgm2),
		"enabled": enabled,
	}


func _electrical_work(impulse: SimVector, omega_body: SimVector, inertia: Dictionary) -> float:
	var next: SimVector = SimVector.sub(momentum_body, impulse)
	var rotor_work: float = (SimVector.dot(next, next) - SimVector.dot(momentum_body, momentum_body)) / (2.0 * rotor_inertia_kgm2)
	var body_work: float = SimVector.dot(impulse, omega_body) + 0.5 * (impulse.x * impulse.x / float(inertia.ix) + impulse.y * impulse.y / float(inertia.iy) + impulse.z * impulse.z / float(inertia.iz))
	var mechanical_work: float = rotor_work + body_work
	return (mechanical_work / motor_efficiency if mechanical_work >= 0.0 else mechanical_work * motor_efficiency) + SimVector.length(impulse) * motor_loss_j_per_nms


func _valid(delta: float, requested: SimVector, omega: SimVector, inertia: Dictionary) -> bool:
	if not is_finite(delta) or delta <= 0.0 or not SimVector.is_finite_vector(requested) or not SimVector.is_finite_vector(omega) or not SimVector.is_finite_vector(momentum_body):
		return false
	for value: float in [capacity_nms, max_torque_nm, rotor_inertia_kgm2, motor_efficiency, battery_capacity_j]:
		if not is_finite(value) or value <= 0.0:
			return false
	if motor_efficiency > 1.0 or not is_finite(motor_loss_j_per_nms) or motor_loss_j_per_nms < 0.0 or not is_finite(battery_energy_j):
		return false
	for axis: String in ["ix", "iy", "iz"]:
		if not is_finite(float(inertia.get(axis, 0.0))) or float(inertia.get(axis, 0.0)) <= 0.0:
			return false
	return true
