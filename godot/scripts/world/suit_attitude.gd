## Three bounded reaction wheels. Motors exchange angular momentum with the suit;
## Motors pay mechanical work and losses, recovering energy when rotors slow.
class_name SuitAttitude
extends RefCounted

const MOMENTUM_LIMIT_NMS: float = 100.0
const ROTOR_INERTIA_KGM2: float = 0.0239
const MOTOR_LOSS_J_PER_NMS: float = 30.0
const REGEN_EFFICIENCY: float = 0.8

var momentum_body: Vector3 = Vector3.ZERO


## Apply a requested body torque through the motor and return the torque delivered.
## A positive body impulse stores an equal negative impulse in the wheel rotors.
func drive(requested_torque: Vector3, omega_body: Vector3, max_torque_nm: float,
		delta: float, suit: SuitResources, inverse_inertia_body: Basis = Basis.IDENTITY) -> Vector3:
	if delta <= 0.0 or not is_finite(delta) or not requested_torque.is_finite() or not omega_body.is_finite():
		return Vector3.ZERO
	var impulse: Vector3 = requested_torque.limit_length(maxf(max_torque_nm, 0.0)) * delta
	if suit.battery_energy_j <= 0.0:
		# A flat battery can still brake: slowing a rotor that holds the opposite
		# momentum generates. Keep only the spin-opposing part of the command; the
		# energy check below allows no more than the rotor returns.
		impulse = spin_opposing(impulse, omega_body)
	var next_momentum: Vector3 = (momentum_body - impulse).clamp(
		Vector3.ONE * -MOMENTUM_LIMIT_NMS, Vector3.ONE * MOMENTUM_LIMIT_NMS)
	impulse = momentum_body - next_momentum
	if impulse.length_squared() < 1e-20:
		return Vector3.ZERO
	var cost: float = _energy_cost(impulse, omega_body, inverse_inertia_body)
	if cost > suit.battery_energy_j:
		# Work is quadratic in delivered impulse. Solve the affordable fraction;
		# scaling a full-tick energy bill linearly can mint energy during regen.
		var low: float = 0.0
		var high: float = 1.0
		for iteration: int in 40:
			var middle: float = (low + high) * 0.5
			if _energy_cost(impulse * middle, omega_body, inverse_inertia_body) <= suit.battery_energy_j:
				low = middle
			else:
				high = middle
		impulse *= low
		cost = suit.battery_energy_j
	if cost >= 0.0:
		suit.consume_energy(cost)
	else:
		suit.charge_energy(-cost)
	momentum_body -= impulse
	return impulse / delta


## The part of a body impulse that directly opposes the body's current spin.
static func spin_opposing(impulse: Vector3, omega_body: Vector3) -> Vector3:
	var speed: float = omega_body.length()
	if speed <= 0.0:
		return Vector3.ZERO
	var along: float = impulse.dot(omega_body) / speed
	return omega_body * (along / speed) if along < 0.0 else Vector3.ZERO


func _energy_cost(impulse: Vector3, omega_body: Vector3, inverse_inertia_body: Basis) -> float:
	var next: Vector3 = momentum_body - impulse
	var rotor_work: float = (next.length_squared() - momentum_body.length_squared()) / (2.0 * ROTOR_INERTIA_KGM2)
	# Conservatively pay positive body work and the free-body acceleration energy.
	# A constrained body moves less; this overestimate becomes heat, never extra charge.
	var body_work: float = maxf(impulse.dot(omega_body), 0.0) + 0.5 * impulse.dot(inverse_inertia_body * impulse)
	var mechanical_work: float = rotor_work + body_work
	return (mechanical_work if mechanical_work >= 0.0 else mechanical_work * REGEN_EFFICIENCY) + impulse.length() * MOTOR_LOSS_J_PER_NMS


## Gyroscopic reaction of body-fixed wheel axes, even with the motors unpowered.
func gyroscopic_torque(omega_body: Vector3) -> Vector3:
	return -omega_body.cross(momentum_body)


## Highest axis utilization, from empty (zero) to saturated (one).
func utilization() -> float:
	return maxf(absf(momentum_body.x), maxf(absf(momentum_body.y), absf(momentum_body.z))) / MOMENTUM_LIMIT_NMS


## Rotor momentum is the only mutable state; the constants above are fixed ratings.
func to_save() -> Dictionary:
	return {"momentum_body": SaveCodec.vector3(momentum_body)}


## Restore saved rotor momentum, clamped back inside the wheel's own limit.
func apply_save(data: Dictionary) -> void:
	var loaded: Vector3 = SaveCodec.to_vector3(data.get("momentum_body"), Vector3.ZERO)
	momentum_body = loaded.clamp(Vector3.ONE * -MOMENTUM_LIMIT_NMS, Vector3.ONE * MOMENTUM_LIMIT_NMS)
