## Loss-limited conversion between scalar64 orbital states and small Jolt coordinates.
class_name LocalOrbitFrame
extends RefCounted

const LOCAL_RADIUS_M: float = 10000.0
const EXIT_RADIUS_M: float = 11000.0
const RECENTRE_DISTANCE_M: float = 2000.0
const GODOT_TO_SIM_BODY: Basis = Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))

var reference_position: SimVector = SimVector.new()
var reference_velocity: SimVector = SimVector.new()
var shift: SimVector = SimVector.new()


## Refresh the reference's analytic state without changing any local relative position.
func set_reference(position: SimVector, velocity: SimVector) -> void:
	reference_position = SimVector.new(position.x, position.y, position.z)
	reference_velocity = SimVector.new(velocity.x, velocity.y, velocity.z)


## Subtract large values in double precision before converting to a native vector.
func to_local_position(position: SimVector) -> Vector3:
	return native(SimVector.sub(SimVector.sub(position, reference_position), shift))


## Reconstruct the authoritative position from the nearby frame and floating offset.
func to_orbital_position(position: Vector3) -> SimVector:
	return SimVector.add(reference_position, SimVector.add(shift, scalar(position)))


## Local Jolt velocities are differences from the reference's orbital velocity.
func to_local_velocity(velocity: SimVector) -> Vector3:
	return native(SimVector.sub(velocity, reference_velocity))


## Local impulses become a new absolute orbital velocity on departure.
func to_orbital_velocity(velocity: Vector3) -> SimVector:
	return SimVector.add(reference_velocity, scalar(velocity))


## Rebase independent roots together; parented meshes, screens and cargo follow them.
func recentre(nodes: Array[Node3D], displacement: Vector3) -> void:
	if not displacement.is_finite():
		return
	shift = SimVector.add(shift, scalar(displacement))
	for node: Node3D in nodes:
		if is_instance_valid(node):
			node.global_position -= displacement


## Convert only small differences, forces, or unit directions to engine vectors.
static func native(value: SimVector) -> Vector3:
	return Vector3(value.x, value.y, value.z)


## Lift a local engine vector into separate 64-bit scalar components.
static func scalar(value: Vector3) -> SimVector:
	return SimVector.new(float(value.x), float(value.y), float(value.z))


## Legacy flight uses body +X thrust; the Godot ship points along body -Z.
static func ship_basis(orientation: Dictionary) -> Basis:
	return Basis(Quaternion(float(orientation.x), float(orientation.y), float(orientation.z), float(orientation.w))) * GODOT_TO_SIM_BODY


## Convert the physical hull attitude back to the legacy body's scalar quaternion.
static func orbital_orientation(basis: Basis) -> Dictionary:
	var q: Quaternion = (basis.orthonormalized() * GODOT_TO_SIM_BODY.transposed()).get_rotation_quaternion()
	return {"w": float(q.w), "x": float(q.x), "y": float(q.y), "z": float(q.z)}
