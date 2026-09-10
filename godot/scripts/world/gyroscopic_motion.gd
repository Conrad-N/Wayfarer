## Stable passive rotation of a rigid carrier and its body-fixed reaction wheels.
class_name GyroscopicMotion
extends RefCounted

## Integrate body and rotor precession with an implicit midpoint solve. Its torque
## does no rotational work; explicit gyro torque gains energy at high wheel speeds.
static func torque(omega_body: Vector3, inertia_body: Basis, momentum_body: Vector3, delta: float) -> Vector3:
	if delta <= 0.0 or not is_finite(delta) or inertia_body.determinant() <= 0.0:
		return Vector3.ZERO
	var inverse: Basis = inertia_body.inverse()
	var rate: Vector3 = omega_body
	# Bound the nonlinear solve's angular step for high rotor speed or rapid tumble.
	var frequency: float = omega_body.length() + (inverse * momentum_body).length()
	var steps: int = clampi(ceili(delta * frequency / 0.25), 1, 128)
	var dt: float = delta / float(steps)
	for step: int in steps:
		var next: Vector3 = rate
		for iteration: int in 8:
			var middle: Vector3 = (rate + next) * 0.5
			var total: Vector3 = inertia_body * middle + momentum_body
			var residual: Vector3 = next - rate + dt * (inverse * middle.cross(total))
			if residual.length_squared() < 1e-18:
				break
			var jacobian: Basis = Basis.IDENTITY
			for axis: int in 3:
				var direction: Vector3 = Basis.IDENTITY[axis]
				jacobian[axis] = direction + 0.5 * dt * (inverse * (direction.cross(total) + middle.cross(inertia_body * direction)))
			next -= jacobian.inverse() * residual
		rate = next
	return inertia_body * (rate - omega_body) / delta

