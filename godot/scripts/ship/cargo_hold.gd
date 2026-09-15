## Physical bay acquisition: a clear door passage and slow arrival precede clamping.
class_name CargoHold
extends Node

var ship: PlayerShip
var wreck: SalvageWreck
var hazards: SalvageHazards
var _passages: Dictionary = {}
var _mesh_vertices: Dictionary = {}
## Last refusal reason logged per body (by instance id), so a stalled cargo
## item logs its reason once, not every physics frame it keeps failing.
var _logged_refusal: Dictionary = {}
var _last_refusal_log_s: float = -INF
## One entry per secured cargo item, keyed by its manifest id, kept only so
## to_save() can serialize freight that is no longer represented by any live
## WreckBody. See to_save() for the shape.
var _cargo: Dictionary = {}


## Bind the ship and salvage scene; acquisition runs before new tool forces.
func configure(owner_ship: PlayerShip, source: SalvageWreck, vents: SalvageHazards) -> void:
	_passages.clear()
	_mesh_vertices.clear()
	_cargo.clear()
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
				_refuse(id, "Cargo door closed")
				if _passages.has(id):
					_passages[id] = false
			elif not clear:
				_refuse(id, "Align cargo with the 2.2 × 2.2 m doorway")
				if _passages.has(id):
					_passages[id] = false
			elif _passages.has(id) and end.z >= -7.2:
				_passages[id] = true
		if not bool(_passages.get(id, false)) or not PlayerShip.CARGO_BOUNDS.encloses(bounds):
			continue
		var point_velocity: Vector3 = ship.linear_velocity + ship.angular_velocity.cross(body.global_position - ship.to_global(ship.center_of_mass))
		if (body.linear_velocity - point_velocity).length() > 0.5 or (body.angular_velocity - ship.angular_velocity).length() > 0.35:
			_refuse(id, "Inside bay: slow drift below 0.5 m/s and spin below 20 deg/s to secure")
			continue
		var leaking: bool = false
		for part_id: String in body.part_ids:
			leaking = leaking or (is_instance_valid(hazards) and hazards.is_part_active(part_id))
		if leaking:
			_refuse(id, "Wait for the active leak to stop before securing cargo")
			continue
		if int(body.get_meta("physical_grip_count", 0)) > 0:
			_refuse(id, "Release your grip to secure cargo")
			continue
		_secure(body, bounds)


## Publish a cargo refusal reason and log it once per distinct reason per body,
## so a body stuck against the same obstruction does not spam the trail.
func _refuse(id: int, reason: String) -> void:
	ship.api.set_cargo_message(reason)
	# A body drifting at the doorway edge can flip between two reasons every frame,
	# so a new reason is also held back until a second has passed since the last one.
	var now: float = Time.get_ticks_msec() / 1000.0
	if String(_logged_refusal.get(id, "")) != reason and now - _last_refusal_log_s >= 1.0:
		_logged_refusal[id] = reason
		_last_refusal_log_s = now
		DebugLog.event("cargo", "refused: %s" % reason)


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
		var reason: String = ship.api.last_message
		if String(_logged_refusal.get(body.get_instance_id(), "")) != reason:
			_logged_refusal[body.get_instance_id()] = reason
			DebugLog.event("cargo", "secure refused: %s (%s)" % [reason, cargo_id])
		return
	# Record what to_save() needs while the part data and body pose are still
	# live: each part's own save (definition asset, condition, scan state — the
	# wreck graph entry becomes orphaned the moment the body is freed below) and
	# the ship-local frame its geometry sits in, so apply_save() can regenerate
	# the same shapes without keeping the original nodes around.
	var part_saves: Dictionary = {}
	var part_transforms: Dictionary = {}
	for id: String in ids:
		var part: ShipPart = wreck.graph.get_part(id)
		var body_from_part: Transform3D = body.assembly_from_body.affine_inverse() * part.transform
		part_saves[id] = part.to_save()
		part_transforms[id] = ship.global_transform.affine_inverse() * body.global_transform * body_from_part
	_cargo[cargo_id] = {"parts": ids.duplicate(), "size_m": bounds.size, "mass_kg": body.mass,
		"volume_m3": volume, "value_cr": value, "part_saves": part_saves, "part_transforms": part_transforms}
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
	_logged_refusal.erase(body.get_instance_id())
	wreck.bodies.erase(body)
	body.get_parent().remove_child(body)
	body.queue_free()
	wreck.structure_changed.emit()
	ship.api.set_cargo_message("Secured %s — %.0f kg" % [cargo_id, new_mass - old_mass])
	DebugLog.event("cargo", "secured %s: %.0f kg" % [cargo_id, new_mass - old_mass])


func _parallel_diagonal(offset: Vector3, weight: float) -> Vector3:
	return weight * Vector3(offset.y * offset.y + offset.z * offset.z, offset.x * offset.x + offset.z * offset.z, offset.x * offset.x + offset.y * offset.y)


## JSON-safe snapshot of every secured cargo item plus the ship-frame mass state
## clamping produced (centre of mass and inertia). Ship mass itself needs no
## separate storage: PlayerShip recomputes it from ShipApi's telemetry every
## physics tick, so it self-heals once the manifest is restored. Each item
## carries its own parts' full ShipPart save, because the wreck graph's entry
## for a secured part is orphaned — no WreckBody claims it — the moment it is
## aboard, so nothing else keeps that state once the source wreck is gone.
func to_save() -> Dictionary:
	var items: Array = []
	for cargo_id: String in _cargo:
		var entry: Dictionary = _cargo[cargo_id]
		var parts: Array = []
		for id: String in (entry.parts as PackedStringArray):
			parts.append(id)
		var part_transforms: Dictionary = {}
		for id: String in (entry.part_transforms as Dictionary).keys():
			part_transforms[id] = SaveCodec.transform(entry.part_transforms[id])
		items.append({
			"cargo_id": cargo_id, "parts": parts, "size_m": SaveCodec.vector3(entry.size_m),
			"mass_kg": entry.mass_kg, "volume_m3": entry.volume_m3, "value_cr": entry.value_cr,
			"part_transforms": part_transforms, "part_saves": (entry.part_saves as Dictionary).duplicate(true),
		})
	var center: Vector3 = ship.center_of_mass if is_instance_valid(ship) else Vector3.ZERO
	var inertia_diagonal: Vector3 = ship.inertia if is_instance_valid(ship) else Vector3.ZERO
	return {"items": items, "center_of_mass": SaveCodec.vector3(center), "inertia": SaveCodec.vector3(inertia_diagonal)}


## Rebuild every secured cargo item from to_save() data: regrow the ship's compound
## visual/collision geometry at its saved ship-local placement, then restore the
## resulting mass frame. The manifest itself comes back through ShipApi.apply_save,
## which must run first; re-registering here would re-run the loading checks (door
## open, power on) that a ship loaded with its door shut would fail.
func apply_save(data: Dictionary) -> void:
	if not is_instance_valid(ship):
		return
	_cargo.clear()
	for entry: Variant in (data.get("items", []) as Array):
		if not entry is Dictionary:
			continue
		var item: Dictionary = entry
		var cargo_id: String = str(item.get("cargo_id", ""))
		var ids: PackedStringArray = PackedStringArray(item.get("parts", []) as Array)
		var size_m: Vector3 = SaveCodec.to_vector3(item.get("size_m"))
		var mass_kg: float = float(item.get("mass_kg", 0.0))
		var volume_m3: float = float(item.get("volume_m3", 0.0))
		var value_cr: float = float(item.get("value_cr", 0.0))
		var part_saves: Dictionary = item.get("part_saves", {}) as Dictionary
		var part_transforms: Dictionary = item.get("part_transforms", {}) as Dictionary
		var stored_transforms: Dictionary = {}
		for id: String in ids:
			var part: ShipPart = ShipPart.from_save(part_saves.get(id, {}) as Dictionary)
			var ship_local: Transform3D = SaveCodec.to_transform(part_transforms.get(id))
			stored_transforms[id] = ship_local
			_add_cargo_geometry(part, ship_local)
		_cargo[cargo_id] = {"parts": ids, "size_m": size_m, "mass_kg": mass_kg, "volume_m3": volume_m3,
			"value_cr": value_cr, "part_saves": part_saves.duplicate(true), "part_transforms": stored_transforms}
	ship.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	ship.center_of_mass = SaveCodec.to_vector3(data.get("center_of_mass"))
	ship.inertia = SaveCodec.to_vector3(data.get("inertia"))


## Regrow one secured part's visual and collision geometry directly under the
## ship at its saved ship-local placement, mirroring how WreckBody lays out
## the same part's meshes/shapes relative to its own body in _add_part().
func _add_cargo_geometry(part: ShipPart, ship_local: Transform3D) -> void:
	if part.definition == null:
		return
	var geometry: Dictionary = PartCatalog.geometry(part.definition) if part.definition.model_path != "" else {}
	if geometry.is_empty():
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = part.definition.size_m
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = part.definition.size_m
		geometry = {"meshes": [{"mesh": mesh, "transform": Transform3D.IDENTITY}], "shapes": [{"shape": shape, "transform": Transform3D.IDENTITY}]}
	for entry: Dictionary in geometry.meshes:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.mesh = entry.mesh
		visual.transform = ship_local * (entry.transform as Transform3D)
		visual.set_meta("system_id", "cargo")
		ship.add_child(visual)
	for entry: Dictionary in geometry.shapes:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = entry.shape
		collision.transform = ship_local * (entry.transform as Transform3D)
		collision.set_meta("system_id", "cargo")
		collision.set_meta("part_id", part.id)
		ship.add_child(collision)
