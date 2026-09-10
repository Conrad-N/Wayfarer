## Local rigid-body mass and principal inertia, using each part's solid box envelope.
## The same approximation before and after cutting conserves split momentum.
class_name SalvageMassProperties
extends RefCounted


## Combine valid parts in assembly coordinates; an empty result has zero mass.
## Part transforms must be rigid rotations/translations, with no scale or shear.
static func from_parts(parts: Array[ShipPart]) -> Dictionary:
	var valid: Array[ShipPart] = []
	var mass_kg: float = 0.0
	var weighted_center: Vector3 = Vector3.ZERO
	for part: ShipPart in parts:
		if not _valid_part(part):
			continue
		valid.append(part)
		mass_kg += part.definition.mass_kg
		weighted_center += part.transform.origin * part.definition.mass_kg
	if mass_kg <= 0.0 or not is_finite(mass_kg) or not weighted_center.is_finite():
		return _empty()
	var center: Vector3 = weighted_center / mass_kg
	var tensor: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for part: ShipPart in valid:
		var mass: float = part.definition.mass_kg
		var size: Vector3 = part.definition.size_m
		var box_inertia: Vector3 = mass / 12.0 * Vector3(
			size.y * size.y + size.z * size.z,
			size.x * size.x + size.z * size.z,
			size.x * size.x + size.y * size.y)
		var rotation: Basis = part.transform.basis.orthonormalized()
		var rotated: Basis = rotation * _diagonal(box_inertia) * rotation.transposed()
		var offset: Vector3 = part.transform.origin - center
		var shift: Basis = Basis(
			Vector3(offset.y * offset.y + offset.z * offset.z, -offset.x * offset.y, -offset.x * offset.z),
			Vector3(-offset.y * offset.x, offset.x * offset.x + offset.z * offset.z, -offset.y * offset.z),
			Vector3(-offset.z * offset.x, -offset.z * offset.y, offset.x * offset.x + offset.y * offset.y))
		for axis: int in range(3):
			tensor[axis] += rotated[axis] + shift[axis] * mass
	if not tensor.is_finite():
		return _empty()
	var principal: Dictionary = _principal_axes(tensor)
	var inertia: Vector3 = principal["inertia"]
	if not inertia.is_finite() or inertia.x <= 0.0 or inertia.y <= 0.0 or inertia.z <= 0.0:
		return _empty()
	return {"mass_kg": mass_kg, "center": center, "basis": principal["basis"],
		"inertia": inertia, "tensor": tensor}


## Inherit the parent's velocity at the fragment's new centre of mass.
static func fragment_velocity(parent_linear: Vector3, angular: Vector3,
		parent_center: Vector3, fragment_center: Vector3) -> Vector3:
	if not parent_linear.is_finite() or not angular.is_finite() \
			or not parent_center.is_finite() or not fragment_center.is_finite():
		return Vector3.ZERO
	var velocity: Vector3 = parent_linear + angular.cross(fragment_center - parent_center)
	return velocity if velocity.is_finite() else Vector3.ZERO


static func _valid_part(part: ShipPart) -> bool:
	if part == null or part.definition == null:
		return false
	var mass: float = part.definition.mass_kg
	var size: Vector3 = part.definition.size_m
	var transform: Transform3D = part.transform
	if not is_finite(mass) or mass <= 0.0 or not size.is_finite() \
			or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or not transform.is_finite():
		return false
	var rotation: Basis = transform.basis
	return absf(rotation.determinant() - 1.0) < 0.0001 \
		and (rotation.transposed() * rotation).is_equal_approx(Basis.IDENTITY)


static func _empty() -> Dictionary:
	return {"mass_kg": 0.0, "center": Vector3.ZERO, "basis": Basis.IDENTITY,
		"inertia": Vector3.ZERO, "tensor": Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)}


static func _diagonal(values: Vector3) -> Basis:
	return Basis(Vector3(values.x, 0.0, 0.0), Vector3(0.0, values.y, 0.0),
		Vector3(0.0, 0.0, values.z))


static func _principal_axes(tensor: Basis) -> Dictionary:
	# Jacobi rotations diagonalize this symmetric matrix. Keep the iteration math
	# in float64 arrays rather than accumulating rotations in float32 Vector3s.
	var matrix: Array[float] = []
	var axes: Array[float] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	for row: int in range(3):
		for column: int in range(3):
			matrix.append((float(tensor[column][row]) + float(tensor[row][column])) * 0.5)
	for iteration: int in range(32):
		var p: int = 0
		var q: int = 1
		if absf(matrix[2]) > absf(matrix[p * 3 + q]):
			q = 2
		if absf(matrix[5]) > absf(matrix[p * 3 + q]):
			p = 1
			q = 2
		var off_diagonal: float = matrix[p * 3 + q]
		var scale: float = maxf(absf(matrix[0]), maxf(absf(matrix[4]), absf(matrix[8])))
		if absf(off_diagonal) <= maxf(scale * 1e-12, 1e-30):
			break
		var angle: float = 0.5 * atan2(2.0 * off_diagonal,
			matrix[q * 3 + q] - matrix[p * 3 + p])
		var cosine: float = cos(angle)
		var sine: float = sin(angle)
		var pp: float = matrix[p * 3 + p]
		var qq: float = matrix[q * 3 + q]
		matrix[p * 3 + p] = cosine * cosine * pp - 2.0 * sine * cosine * off_diagonal + sine * sine * qq
		matrix[q * 3 + q] = sine * sine * pp + 2.0 * sine * cosine * off_diagonal + cosine * cosine * qq
		matrix[p * 3 + q] = 0.0
		matrix[q * 3 + p] = 0.0
		for row: int in range(3):
			if row != p and row != q:
				var rp: float = matrix[row * 3 + p]
				var rq: float = matrix[row * 3 + q]
				matrix[row * 3 + p] = cosine * rp - sine * rq
				matrix[p * 3 + row] = matrix[row * 3 + p]
				matrix[row * 3 + q] = sine * rp + cosine * rq
				matrix[q * 3 + row] = matrix[row * 3 + q]
			var axis_p: float = axes[row * 3 + p]
			var axis_q: float = axes[row * 3 + q]
			axes[row * 3 + p] = cosine * axis_p - sine * axis_q
			axes[row * 3 + q] = sine * axis_p + cosine * axis_q
	var basis: Basis = Basis(Vector3(axes[0], axes[3], axes[6]),
		Vector3(axes[1], axes[4], axes[7]), Vector3(axes[2], axes[5], axes[8])).orthonormalized()
	return {"basis": basis, "inertia": Vector3(matrix[0], matrix[4], matrix[8])}
