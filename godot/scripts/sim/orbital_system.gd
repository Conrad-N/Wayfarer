## Analytic tree of celestial bodies, with translated inertial frames and guarded hierarchy traversal.
class_name OrbitalSystem
extends RefCounted

var root_id: String = ""
var valid: bool = false
var _by_id: Dictionary = {}


func _init(bodies: Array[Dictionary] = []) -> void:
	var roots: int = 0
	for entry: Dictionary in bodies:
		var id: String = entry.get("id", "")
		if id.is_empty() or _by_id.has(id):
			return
		_by_id[id] = entry.duplicate(true)
		if entry.get("parent_id") == null:
			root_id = id
			roots += 1
	if roots != 1:
		return
	for id: String in _by_id:
		var seen: Dictionary = {}
		var cursor: String = id
		while not cursor.is_empty():
			if seen.has(cursor) or not _by_id.has(cursor):
				return
			seen[cursor] = true
			var entry: Dictionary = _by_id[cursor]
			var parent: Variant = entry.get("parent_id")
			if parent != null and (not _by_id.has(str(parent)) or not entry.get("elements") is Dictionary or not OrbitMath.valid_elements(entry.elements, _by_id.get(str(parent), {}))):
				return
			cursor = str(parent) if parent != null else ""
	valid = true


## Laplace sphere-of-influence radius in metres.
static func soi_radius(semi_major_axis: float, mu_body: float, mu_parent: float) -> float:
	if not is_finite(semi_major_axis) or not is_finite(mu_body) or not is_finite(mu_parent) or semi_major_axis <= 0.0 or mu_body <= 0.0 or mu_parent <= 0.0:
		return 0.0
	return semi_major_axis * pow(mu_body / mu_parent, 0.4)


## Whether the hierarchy contains this identifier.
func has(id: String) -> bool:
	return valid and _by_id.has(id)


## Independent body definition, or empty for an unknown/invalid hierarchy.
func body(id: String) -> Dictionary:
	return (_by_id[id] as Dictionary).duplicate(true) if has(id) else {}


## The root body defining the outer inertial frame.
func root_body() -> Dictionary:
	return body(root_id)


## All body definitions in supplied order.
func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if valid:
		for id: String in _by_id:
			result.append(body(id))
	return result


## Bodies whose immediate parent is id.
func children(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in all():
		if entry.get("parent_id") == id:
			result.append(entry)
	return result


## Sum each ancestor's conic to obtain a body's state in the root frame.
func body_state_in_root(id: String, t: float) -> Dictionary:
	if not has(id) or not is_finite(t):
		return {}
	var position: SimVector = SimVector.new()
	var velocity: SimVector = SimVector.new()
	var cursor: String = id
	while cursor != root_id:
		var entry: Dictionary = _by_id[cursor]
		var parent_id: String = entry.parent_id
		var local: Dictionary = OrbitMath.propagate(entry.elements, _by_id[parent_id], t)
		if local.is_empty():
			return {}
		position = SimVector.add(position, local.position)
		velocity = SimVector.add(velocity, local.velocity)
		cursor = parent_id
	return {"position": position, "velocity": velocity}


## State of to_id in from_id's translated, nonrotating frame.
func relative_state(from_id: String, to_id: String, t: float) -> Dictionary:
	var from_state: Dictionary = body_state_in_root(from_id, t)
	var to_state: Dictionary = body_state_in_root(to_id, t)
	if from_state.is_empty() or to_state.is_empty():
		return {}
	return {"position": SimVector.sub(to_state.position, from_state.position), "velocity": SimVector.sub(to_state.velocity, from_state.velocity)}
