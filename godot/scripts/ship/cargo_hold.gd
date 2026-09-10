## Physical bay acquisition: a clear door passage and slow arrival precede clamping.
class_name CargoHold
extends Node

var ship: PlayerShip
var wreck: SalvageWreck
var hazards: SalvageHazards
var _passages: Dictionary = {}
var _mesh_vertices: Dictionary = {}


## Bind the ship and salvage scene; acquisition runs before new tool forces.
func configure(owner_ship: PlayerShip, source: SalvageWreck, vents: SalvageHazards) -> void:
	_passages.clear()
	_mesh_vertices.clear()
	ship = owner_ship
	wreck = source
	hazards = vents
	process_physics_priority = -90


## Bound actual mesh vertices in the bay frame, including every attached part.
func bounds_in_bay(body: WreckBody) -> AABB:
	var result: AABB
	var first: bool = true
	for child: Node in body.get_children():
		if not child is MeshInstance3D:
			continue
		var visual: MeshInstance3D = child as MeshInstance3D
		if visual.mesh == null:
			continue
		var pose: Transform3D = ship.global_transform.affine_inverse() * visual.global_transform
		for vertex: Vector3 in _vertices(visual.mesh):
			var point: Vector3 = pose * vertex
			result = AABB(point, Vector3.ZERO) if first else result.expand(point)
			first = false
	return result


func _vertices(mesh: Mesh) -> PackedVector3Array:
	if _mesh_vertices.has(mesh):
		return _mesh_vertices[mesh]
	var unique: Dictionary = {}
	for point: Vector3 in mesh.get_faces():
		unique[point] = true
	var points: PackedVector3Array = PackedVector3Array(unique.keys())
	if points.is_empty():
		# Procedural meshes without triangles still get conservative box bounds.
		var bounds: AABB = mesh.get_aabb()
		for index: int in range(8):
			points.append(bounds.get_endpoint(index))
	_mesh_vertices[mesh] = points
	return points


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(wreck):
		return
	for body: WreckBody in wreck.bodies.duplicate():
		if not is_instance_valid(body):
			continue
		var bounds: AABB = bounds_in_bay(body)
		var id: int = body.get_instance_id()
		var end: Vector3 = bounds.end
		var near_door: bool = bounds.position.z < -6.8 and end.z > -9.0 and absf(bounds.get_center().x) < 3.0 and absf(bounds.get_center().y) < 2.5
		var clear: bool = bounds.position.x >= -1.1 and end.x <= 1.1 and bounds.position.y >= -1.1 and end.y <= 1.1
		if end.z < -7.2:
			_passages[id] = false
		if near_door:
			if not bool(ship.api.get_telemetry().cargo_door_open):
				ship.api.set_cargo_message("Cargo door closed")
				if _passages.has(id):
					_passages[id] = false
			elif not clear:
				ship.api.set_cargo_message("Align cargo with the 2.2 × 2.2 m doorway")
				if _passages.has(id):
					_passages[id] = false
			elif _passages.has(id) and end.z >= -7.2:
				_passages[id] = true
		if not bool(_passages.get(id, false)) or not PlayerShip.CARGO_BOUNDS.encloses(bounds):
			continue
		var point_velocity: Vector3 = ship.linear_velocity + ship.angular_velocity.cross(body.global_position - ship.to_global(ship.center_of_mass))
		if (body.linear_velocity - point_velocity).length() > 0.5 or (body.angular_velocity - ship.angular_velocity).length() > 0.35:
			ship.api.set_cargo_message("Inside bay: slow drift below 0.5 m/s and spin below 20 deg/s to secure")
			continue
		var leaking: bool = false
		for part_id: String in body.part_ids:
			leaking = leaking or (is_instance_valid(hazards) and hazards.is_part_active(part_id))
		if leaking:
			ship.api.set_cargo_message("Wait for the active leak to stop before securing cargo")
			continue
		if int(body.get_meta("physical_grip_count", 0)) > 0:
			ship.api.set_cargo_message("Release your grip to secure cargo")
			continue
		_secure(body, bounds)


func _secure(body: WreckBody, bounds: AABB) -> void:
	var ids: PackedStringArray = body.part_ids
	var cargo_id: String = "+".join(ids)
	var volume: float = 0.0
	var value: float = 0.0
	for id: String in ids:
		var part: ShipPart = wreck.graph.get_part(id)
		volume += part.definition.volume_m3
		value += part.salvage_value()
	var old_mass: float = ship.mass
	var old_center: Vector3 = ship.to_global(ship.center_of_mass)
	var new_mass: float = old_mass + body.mass
	var new_center: Vector3 = (old_center * old_mass + body.global_position * body.mass) / new_mass
	var momentum: Vector3 = ship.linear_velocity * old_mass + body.linear_velocity * body.mass
	var ship_inverse: Basis = ship.get_inverse_inertia_tensor()
	var cargo_inverse: Basis = body.get_inverse_inertia_tensor()
	if ship_inverse.determinant() <= 0.0 or cargo_inverse.determinant() <= 0.0:
		return
	var angular_momentum: Vector3 = ship_inverse.inverse() * ship.angular_velocity + cargo_inverse.inverse() * body.angular_velocity
	angular_momentum += (old_center - new_center).cross(ship.linear_velocity * old_mass)
	angular_momentum += (body.global_position - new_center).cross(body.linear_velocity * body.mass)
	if not ship.api.register_cargo(cargo_id, bounds.size, body.mass, volume, {"value_cr": value, "parts": ids}):
		return
	# Represent secured freight once: move its geometry into the ship's compound body.
	for child: Node in body.get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			var copy: Node3D = child.duplicate() as Node3D
			copy.transform = ship.global_transform.affine_inverse() * (child as Node3D).global_transform
			copy.set_meta("system_id", "cargo")
			ship.add_child(copy)
	var local_basis: Basis = ship.global_basis.transposed()
	var ship_tensor: Basis = ship_inverse.inverse()
	var cargo_tensor: Basis = cargo_inverse.inverse()
	var sum_tensor: Basis = Basis(ship_tensor.x + cargo_tensor.x, ship_tensor.y + cargo_tensor.y, ship_tensor.z + cargo_tensor.z)
	var combined: Basis = local_basis * sum_tensor * ship.global_basis
	var offset_ship: Vector3 = local_basis * (old_center - new_center)
	var offset_cargo: Vector3 = local_basis * (body.global_position - new_center)
	var diagonal: Vector3 = Vector3(combined.x.x, combined.y.y, combined.z.z)
	diagonal += _parallel_diagonal(offset_ship, old_mass) + _parallel_diagonal(offset_cargo, body.mass)
	ship.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	ship.center_of_mass = ship.to_local(new_center)
	ship.mass = new_mass
	ship.inertia = diagonal
	ship.linear_velocity = momentum / new_mass
	ship.angular_velocity = ship.global_basis * ((local_basis * angular_momentum) / diagonal)
	_passages.erase(body.get_instance_id())
	wreck.bodies.erase(body)
	body.get_parent().remove_child(body)
	body.queue_free()
	wreck.structure_changed.emit()
	ship.api.set_cargo_message("Secured %s — %.0f kg" % [cargo_id, new_mass - old_mass])


func _parallel_diagonal(offset: Vector3, weight: float) -> Vector3:
	return weight * Vector3(offset.y * offset.y + offset.z * offset.z, offset.x * offset.x + offset.z * offset.z, offset.x * offset.x + offset.y * offset.y)
