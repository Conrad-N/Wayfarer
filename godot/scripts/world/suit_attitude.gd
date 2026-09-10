## Three bounded reaction wheels. Motors exchange angular momentum with the suit;
## battery energy pays positive mechanical work and motor losses, never refills.
class_name SuitAttitude
extends RefCounted

const MOMENTUM_LIMIT_NMS: float = 20.0
const ROTOR_INERTIA_KGM2: float = 0.15
const MOTOR_LOSS_J_PER_NMS: float = 30.0

var momentum_body: Vector3 = Vector3.ZERO


## Apply a requested body torque through the motor and return the torque delivered.
## A positive body impulse stores an equal negative impulse in the wheel rotors.
func drive(requested_torque: Vector3, omega_body: Vector3, max_torque_nm: float,
		delta: float, suit: SuitResources) -> Vector3:
	if delta <= 0.0 or not is_finite(delta) or not requested_torque.is_finite() or not omega_body.is_finite():
		return Vector3.ZERO
	var impulse: Vector3 = requested_torque.limit_length(maxf(max_torque_nm, 0.0)) * delta
	var next_momentum: Vector3 = (momentum_body - impulse).clamp(
		Vector3.ONE * -MOMENTUM_LIMIT_NMS, Vector3.ONE * MOMENTUM_LIMIT_NMS)
	impulse = momentum_body - next_momentum
	if impulse.length_squared() < 1e-20:
		return Vector3.ZERO
	var rotor_work: float = maxf((next_momentum.length_squared() - momentum_body.length_squared()) / (2.0 * ROTOR_INERTIA_KGM2), 0.0)
	# Conservative non-regenerative drive: absorb braking work as heat. Include a
	# body-acceleration margin so a motor cannot produce unpaid kinetic energy at rest.
	var body_work: float = absf(impulse.dot(omega_body)) + impulse.length_squared()
	var cost: float = rotor_work + body_work + impulse.length() * MOTOR_LOSS_J_PER_NMS
	var fraction: float = suit.consume_energy(cost) / cost
	impulse *= fraction
	momentum_body -= impulse
	return impulse / delta


## Gyroscopic reaction of body-fixed wheel axes, even with the motors unpowered.
func gyroscopic_torque(omega_body: Vector3) -> Vector3:
	return -omega_body.cross(momentum_body)


## Highest axis utilization, from empty (zero) to saturated (one).
func utilization() -> float:
	return maxf(absf(momentum_body.x), maxf(absf(momentum_body.y), absf(momentum_body.z))) / MOMENTUM_LIMIT_NMS
