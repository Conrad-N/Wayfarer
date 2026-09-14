## JSON-safe encodings for the engine and sim value types a save file holds.
## JSON numbers come back as floats, so every decoder casts explicitly.
class_name SaveCodec
extends RefCounted


## Encode a vector as [x, y, z].
static func vector3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


## Decode [x, y, z]; anything else gives the fallback.
static func to_vector3(data: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if data is Array and (data as Array).size() == 3:
		return Vector3(float(data[0]), float(data[1]), float(data[2]))
	return fallback


## Encode a basis as its three columns, nine numbers.
static func basis(value: Basis) -> Array:
	return [value.x.x, value.x.y, value.x.z, value.y.x, value.y.y, value.y.z, value.z.x, value.z.y, value.z.z]


## Decode nine numbers written by basis().
static func to_basis(data: Variant, fallback: Basis = Basis.IDENTITY) -> Basis:
	if not (data is Array and (data as Array).size() == 9):
		return fallback
	var n: Array = data
	return Basis(Vector3(float(n[0]), float(n[1]), float(n[2])), Vector3(float(n[3]), float(n[4]), float(n[5])), Vector3(float(n[6]), float(n[7]), float(n[8])))


## Encode a transform as twelve numbers: basis columns then origin.
static func transform(value: Transform3D) -> Array:
	return basis(value.basis) + vector3(value.origin)


## Decode twelve numbers written by transform().
static func to_transform(data: Variant, fallback: Transform3D = Transform3D.IDENTITY) -> Transform3D:
	if not (data is Array and (data as Array).size() == 12):
		return fallback
	var n: Array = data
	return Transform3D(to_basis(n.slice(0, 9)), to_vector3(n.slice(9, 12)))


## Encode a double-precision sim vector as [x, y, z].
static func sim_vector(value: SimVector) -> Array:
	return [value.x, value.y, value.z]


## Decode [x, y, z] into a new SimVector.
static func to_sim_vector(data: Variant) -> SimVector:
	if data is Array and (data as Array).size() == 3:
		return SimVector.new(float(data[0]), float(data[1]), float(data[2]))
	return SimVector.new()


## Deep-copy a plain value so it can go into JSON. Vectors, bases, transforms and
## SimVectors become tagged dictionaries; nested arrays and dictionaries are walked.
## Use this only for data whose shape is not known in advance (sim records).
static func plain(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			result[str(key)] = plain(value[key])
		return result
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(plain(item))
		return items
	if value is Vector3:
		return {"__type": "Vector3", "v": vector3(value)}
	if value is Basis:
		return {"__type": "Basis", "v": basis(value)}
	if value is Transform3D:
		return {"__type": "Transform3D", "v": transform(value)}
	if value is SimVector:
		return {"__type": "SimVector", "v": sim_vector(value)}
	if value is Object:
		push_error("SaveCodec.plain cannot store an object: %s" % value)
		return null
	return value


## Undo plain(). Integers are not restored: JSON only has floats, so callers cast.
static func unplain(value: Variant) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value
		match str(dictionary.get("__type", "")):
			"Vector3":
				return to_vector3(dictionary.v)
			"Basis":
				return to_basis(dictionary.v)
			"Transform3D":
				return to_transform(dictionary.v)
			"SimVector":
				return to_sim_vector(dictionary.v)
		var result: Dictionary = {}
		for key: Variant in dictionary.keys():
			result[key] = unplain(dictionary[key])
		return result
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(unplain(item))
		return items
	return value


## Full-precision JSON text; orbital positions need every digit.
static func stringify(data: Dictionary) -> String:
	return JSON.stringify(data, "\t", false, true)


## Parse JSON text into a dictionary, or an empty one if it is not valid.
static func parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
