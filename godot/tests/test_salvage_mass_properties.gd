## Mass, principal inertia, and off-centre split momentum independent of rendering.
extends TestCase


## A translated box has the known solid-box moments about its own centre.
func test_single_box_and_rotated_box() -> void:
	var part: ShipPart = _part(12.0, Vector3(2.0, 4.0, 6.0), Vector3(7.0, -3.0, 2.0))
	var properties: Dictionary = SalvageMassProperties.from_parts([part])
	check_near(properties["mass_kg"], 12.0, 0.00001, "box mass")
	_check_vector(properties["center"], part.transform.origin, 0.00001, "box centre")
	_check_tensor(properties["tensor"], _diagonal(Vector3(52.0, 40.0, 20.0)), 0.00001, "box inertia")
	var rotation: Basis = Basis(Vector3(1.0, 2.0, -3.0).normalized(), 0.71)
	part.transform.basis = rotation
	properties = SalvageMassProperties.from_parts([part])
	var expected: Basis = rotation * _diagonal(Vector3(52.0, 40.0, 20.0)) * rotation.transposed()
	_check_tensor(properties["tensor"], expected, 0.00003, "rotated box inertia")
	_check_principal(properties, 0.0001)


## Unequal boxes exercise the weighted centre and full parallel-axis tensor.
func test_asymmetrical_assembly_reconstructs_tensor() -> void:
	var first: ShipPart = _part(12.0, Vector3(2.0, 4.0, 6.0), Vector3(-2.0, 1.0, 0.0))
	var second: ShipPart = _part(24.0, Vector3.ONE * 2.0, Vector3(4.0, -2.0, 3.0))
	var properties: Dictionary = SalvageMassProperties.from_parts([first, second])
	check_near(properties["mass_kg"], 36.0, 0.00001, "assembly mass")
	_check_vector(properties["center"], Vector3(2.0, -1.0, 2.0), 0.00001, "weighted centre")
	# Two-body parallel-axis contribution uses reduced mass 8 kg and offset (6,-3,3).
	var expected: Basis = Basis(Vector3(212.0, 144.0, -144.0),
		Vector3(144.0, 416.0, 72.0), Vector3(-144.0, 72.0, 396.0))
	_check_tensor(properties["tensor"], expected, 0.0001, "parallel-axis tensor")
	_check_principal(properties, 0.001)


## Repeated principal moments still produce a proper rotation and positive inertia.
func test_degenerate_and_extreme_mass_ratio_assemblies() -> void:
	var cube: ShipPart = _part(6.0, Vector3.ONE, Vector3.ZERO)
	var properties: Dictionary = SalvageMassProperties.from_parts([cube])
	_check_principal(properties, 0.00001)
	_check_vector(properties["inertia"], Vector3.ONE, 0.00001, "isotropic cube moments")
	var tiny: ShipPart = _part(0.001, Vector3.ONE * 0.02, Vector3(10.0, -8.0, 7.0))
	var heavy: ShipPart = _part(1000000.0, Vector3(1.0, 2.0, 3.0), Vector3(-2.0, 1.0, 3.0))
	properties = SalvageMassProperties.from_parts([tiny, heavy])
	_check_principal(properties, 0.25)
	check_close(properties["mass_kg"], 1000000.001, 1e-12, "mass retains scalar precision")


## Invalid inputs cannot introduce non-finite bodies into the physics scene.
func test_invalid_parts_fail_soft() -> void:
	var properties: Dictionary = SalvageMassProperties.from_parts([])
	check_eq(properties["mass_kg"], 0.0, "empty assembly has zero mass")
	check_eq(properties["inertia"], Vector3.ZERO, "empty assembly has no inertia")
	var missing: ShipPart = ShipPart.new()
	var negative: ShipPart = _part(-1.0, Vector3.ONE, Vector3.ZERO)
	var infinite: ShipPart = _part(INF, Vector3.ONE, Vector3.ZERO)
	var flat: ShipPart = _part(1.0, Vector3(0.0, 1.0, 1.0), Vector3.ZERO)
	var invalid_position: ShipPart = _part(1.0, Vector3.ONE, Vector3(NAN, 0.0, 0.0))
	var scaled: ShipPart = _part(1.0, Vector3.ONE, Vector3.ZERO)
	scaled.transform.basis = Basis.IDENTITY.scaled(Vector3(2.0, 1.0, 1.0))
	var reflected: ShipPart = _part(1.0, Vector3.ONE, Vector3.ZERO)
	reflected.transform.basis = Basis.IDENTITY.scaled(Vector3(-1.0, 1.0, 1.0))
	var good: ShipPart = _part(7.0, Vector3.ONE, Vector3.ZERO)
	properties = SalvageMassProperties.from_parts([null, missing, negative, infinite, flat,
		invalid_position, scaled, reflected, good])
	check_eq(properties["mass_kg"], 7.0, "only physically valid entries contribute")
	_check_principal(properties, 0.00001)
	var overflow: ShipPart = _part(1e100, Vector3.ONE, Vector3.ONE)
	properties = SalvageMassProperties.from_parts([overflow])
	check_eq(properties["mass_kg"], 0.0, "overflow cannot produce an unusable rigid body")
	check_eq(SalvageMassProperties.fragment_velocity(Vector3(INF, 0.0, 0.0),
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO, "non-finite velocity rejected")


## A severed rotating assembly preserves linear and angular momentum and energy.
func test_rotating_offcenter_split_conserves_momentum() -> void:
	var parts: Array[ShipPart] = [
		_part(20.0, Vector3(1.0, 2.0, 3.0), Vector3(-3.0, 2.0, 1.0)),
		_part(70.0, Vector3(2.0, 1.0, 1.0), Vector3(2.0, -1.0, 3.0)),
		_part(130.0, Vector3(3.0, 2.0, 2.0), Vector3(4.0, 1.0, -2.0))]
	parts[0].transform.basis = Basis(Vector3(2.0, -1.0, 3.0).normalized(), 0.37)
	parts[2].transform.basis = Basis(Vector3(1.0, 4.0, 2.0).normalized(), -0.62)
	var parent: Dictionary = SalvageMassProperties.from_parts(parts)
	var world_basis: Basis = Basis(Vector3(1.0, 2.0, 3.0).normalized(), 1.1)
	var world_origin: Vector3 = Vector3(100.0, -40.0, 80.0)
	var parent_center: Vector3 = world_origin + world_basis * Vector3(parent["center"])
	var parent_tensor: Basis = world_basis * Basis(parent["tensor"]) * world_basis.transposed()
	var velocity: Vector3 = Vector3(2.0, -3.0, 0.7)
	var angular: Vector3 = Vector3(0.2, -0.7, 0.4)
	var expected_linear: Vector3 = velocity * float(parent["mass_kg"])
	var expected_angular: Vector3 = parent_tensor * angular
	var expected_energy: float = 0.5 * (float(parent["mass_kg"]) * velocity.length_squared()
		+ angular.dot(parent_tensor * angular))
	# Repeat with both a two-fragment cut and a complete disassembly.
	var groups: Array[Array] = [[parts.slice(0, 1), parts.slice(1, 3)],
		[parts.slice(0, 1), parts.slice(1, 2), parts.slice(2, 3)]]
	for group: Array in groups:
		var actual_linear: Vector3 = Vector3.ZERO
		var actual_angular: Vector3 = Vector3.ZERO
		var actual_energy: float = 0.0
		for fragment_parts: Array[ShipPart] in group:
			var fragment: Dictionary = SalvageMassProperties.from_parts(fragment_parts)
			var center: Vector3 = world_origin + world_basis * Vector3(fragment["center"])
			var fragment_linear: Vector3 = SalvageMassProperties.fragment_velocity(
				velocity, angular, parent_center, center)
			var mass: float = fragment["mass_kg"]
			var tensor: Basis = world_basis * Basis(fragment["tensor"]) * world_basis.transposed()
			actual_linear += fragment_linear * mass
			actual_angular += tensor * angular + (center - parent_center).cross(fragment_linear * mass)
			actual_energy += 0.5 * (mass * fragment_linear.length_squared() + angular.dot(tensor * angular))
		_check_vector(actual_linear, expected_linear, 0.002, "split linear momentum")
		_check_vector(actual_angular, expected_angular, 0.01, "split spin plus orbital angular momentum")
		check_close(actual_energy, expected_energy, 0.00001, "no artificial energy at split")


## The inherited tangential velocity has the right sign and vanishes without spin.
func test_fragment_velocity_direction() -> void:
	_check_vector(SalvageMassProperties.fragment_velocity(Vector3(1.0, 2.0, 3.0),
		Vector3(0.0, 0.0, 2.0), Vector3(10.0, 0.0, 0.0), Vector3(13.0, 0.0, 0.0)),
		Vector3(1.0, 8.0, 3.0), 0.00001, "positive z spin gives positive y tangential motion")
	_check_vector(SalvageMassProperties.fragment_velocity(Vector3(1.0, 2.0, 3.0),
		Vector3.ZERO, Vector3(10.0, 0.0, 0.0), Vector3(13.0, 0.0, 0.0)),
		Vector3(1.0, 2.0, 3.0), 0.00001, "no spin inherits only translation")


func _part(mass: float, size: Vector3, center: Vector3) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.definition = PartDefinition.new()
	part.definition.mass_kg = mass
	part.definition.size_m = size
	part.transform.origin = center
	return part


func _diagonal(values: Vector3) -> Basis:
	return Basis(Vector3(values.x, 0.0, 0.0), Vector3(0.0, values.y, 0.0), Vector3(0.0, 0.0, values.z))


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.is_finite() and actual.distance_to(expected) <= tolerance,
		"%s: expected %s, got %s" % [message, expected, actual])


func _check_tensor(actual: Basis, expected: Basis, tolerance: float, message: String) -> void:
	for axis: int in range(3):
		_check_vector(actual[axis], expected[axis], tolerance, "%s column %d" % [message, axis])


func _check_principal(properties: Dictionary, tolerance: float) -> void:
	var basis: Basis = properties["basis"]
	var inertia: Vector3 = properties["inertia"]
	check(inertia.is_finite() and inertia.x > 0.0 and inertia.y > 0.0 and inertia.z > 0.0,
		"principal moments are finite and positive")
	check_near(basis.determinant(), 1.0, 0.00001, "principal basis is right handed")
	_check_tensor(basis.transposed() * basis, Basis.IDENTITY, 0.00001, "principal axes orthonormal")
	_check_tensor(basis * _diagonal(inertia) * basis.transposed(), properties["tensor"],
		tolerance, "principal moments reconstruct full inertia")
