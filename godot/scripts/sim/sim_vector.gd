## Scalar double-precision vector for inertial simulation; never narrowed to engine vectors.
class_name SimVector
extends RefCounted

var x: float
var y: float
var z: float


func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> void:
	x = px
	y = py
	z = pz


## Add vectors without mutating either input.
static func add(a: SimVector, b: SimVector) -> SimVector:
	return SimVector.new(a.x + b.x, a.y + b.y, a.z + b.z)


## Subtract b from a.
static func sub(a: SimVector, b: SimVector) -> SimVector:
	return SimVector.new(a.x - b.x, a.y - b.y, a.z - b.z)


## Scale a vector by a scalar.
static func scale(a: SimVector, factor: float) -> SimVector:
	return SimVector.new(a.x * factor, a.y * factor, a.z * factor)


## Scalar dot product.
static func dot(a: SimVector, b: SimVector) -> float:
	return a.x * b.x + a.y * b.y + a.z * b.z


## Right-handed cross product.
static func cross(a: SimVector, b: SimVector) -> SimVector:
	return SimVector.new(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)


## Euclidean length, scaled to avoid overflow in intermediate squares.
static func length(a: SimVector) -> float:
	var largest: float = maxf(absf(a.x), maxf(absf(a.y), absf(a.z)))
	if largest == 0.0 or not is_finite(largest):
		return largest
	return largest * sqrt(pow(a.x / largest, 2.0) + pow(a.y / largest, 2.0) + pow(a.z / largest, 2.0))


## Unit vector, or zero for a zero/invalid input.
static func normalized(a: SimVector) -> SimVector:
	var magnitude: float = length(a)
	return scale(a, 1.0 / magnitude) if magnitude > 0.0 and is_finite(magnitude) else SimVector.new()


## Distance between points.
static func distance(a: SimVector, b: SimVector) -> float:
	return length(sub(a, b))


## Copy a vector with its length limited to a nonnegative finite maximum.
static func clamp_magnitude(a: SimVector, maximum: float) -> SimVector:
	if not is_finite_vector(a) or not is_finite(maximum) or maximum < 0.0:
		return SimVector.new()
	var magnitude: float = length(a)
	return scale(a, maximum / magnitude) if magnitude > maximum else scale(a, 1.0)


## Whether all components are finite and the vector exists.
static func is_finite_vector(a: SimVector) -> bool:
	return a != null and is_finite(a.x) and is_finite(a.y) and is_finite(a.z)
