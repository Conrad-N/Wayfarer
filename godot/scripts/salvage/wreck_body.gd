## One connected component of a wreck, with compound imported collision and inertia.
class_name WreckBody
extends RigidBody3D

var wreck: SalvageWreck
var part_ids: PackedStringArray = []
var assembly_from_body: Transform3D = Transform3D.IDENTITY
var _labels: Dictionary = {}
var _hazard_labels: Array[Dictionary] = []
var _contact_grace: float = 0.2


## Build one connected body, placing its origin and axes at the principal mass frame.
func configure(owner_wreck: SalvageWreck, ids: PackedStringArray, assembly_world: Transform3D) -> void:
	wreck = owner_wreck
	part_ids = ids.duplicate()
	var parts: Array[ShipPart] = []
	for id: String in ids:
		parts.append(wreck.graph.get_part(id))
	var properties: Dictionary = SalvageMassProperties.from_parts(parts)
	assembly_from_body = Transform3D(properties.basis, properties.center)
	transform = assembly_world * assembly_from_body
	mass = properties.mass_kg
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	inertia = properties.inertia
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 16
	body_entered.connect(_on_body_entered)
	for part: ShipPart in parts:
		_add_part(part)
	for edge_id: String in wreck.graph.edge_ids():
		var edge: Dictionary = wreck.graph.get_edge(edge_id)
		if ids.has(edge.a) and ids.has(edge.b):
			_add_cut_marker(edge_id, edge.a, edge.socket_a)
			_add_cut_marker(edge_id, edge.b, edge.socket_b)


## Recover the current assembly frame from this moving component.
func assembly_pose() -> Transform3D:
	return global_transform * assembly_from_body.affine_inverse()


## Find the part represented by a physics ray's collision shape index.
func part_at_shape(index: int) -> String:
	if index < 0:
		return ""
	var owner_id: int = shape_find_owner(index)
	var shape_node: Object = shape_owner_get_owner(owner_id)
	return str(shape_node.get_meta("part_id", "")) if shape_node != null else ""


func _process(_delta: float) -> void:
	for id: String in _labels:
		var part: ShipPart = wreck.graph.get_part(id)
		var label: Label3D = _labels[id]
		label.visible = part.scanned
		label.text = id
	for entry: Dictionary in _hazard_labels:
		(entry.label as Label3D).visible = wreck.graph.get_part(entry.id).scanned


func _physics_process(delta: float) -> void:
	_contact_grace = maxf(0.0, _contact_grace - delta)


func _add_part(part: ShipPart) -> void:
	var body_from_part: Transform3D = assembly_from_body.affine_inverse() * part.transform
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
		visual.transform = body_from_part * entry.transform
		add_child(visual)
	for entry: Dictionary in geometry.shapes:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = entry.shape
		collision.transform = body_from_part * entry.transform
		collision.set_meta("part_id", part.id)
		add_child(collision)
	var label: Label3D = Label3D.new()
	label.transform = body_from_part
	label.position += body_from_part.basis.y * (part.definition.size_m.y * 0.5 + 0.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.0012
	label.fixed_size = true
	label.outline_size = 4
	label.modulate = Color(0.4, 0.85, 0.95)
	label.visible = false
	add_child(label)
	_labels[part.id] = label
	for hazard: Dictionary in part.definition.hazards:
		var warning: Label3D = Label3D.new()
		warning.transform = body_from_part * hazard.transform
		warning.position -= warning.basis.z * 0.25
		warning.text = str(hazard.kind).to_upper() + " LINE"
		warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		warning.font_size = 32
		warning.pixel_size = 0.0012
		warning.fixed_size = true
		warning.outline_size = 4
		warning.modulate = Color(1, 0.45, 0.1) if hazard.kind == "fuel" else Color(0.1, 0.9, 1.0)
		warning.visible = false
		add_child(warning)
		_hazard_labels.append({"id": part.id, "label": warning})


func _add_cut_marker(edge_id: String, part_id: String, socket: String) -> void:
	var part: ShipPart = wreck.graph.get_part(part_id)
	var unsized: String = socket
	if socket.ends_with("_S") or socket.ends_with("_M") or socket.ends_with("_L"):
		unsized = socket.left(-2)
	var cut: Transform3D = part.definition.cut_points.get(socket, part.definition.cut_points.get(unsized, part.definition.sockets[socket]))
	var area: Area3D = Area3D.new()
	area.name = "Cut_" + edge_id + "_" + part_id
	area.transform = assembly_from_body.affine_inverse() * part.transform * cut
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("edge_id", edge_id)
	area.set_meta("part_id", part_id)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = 0.18
	collision.shape = shape
	area.add_child(collision)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	sphere.radial_segments = 8
	sphere.rings = 4
	visual.mesh = sphere
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.65, 0.12)
	visual.material_override = material
	area.add_child(visual)
	add_child(area)


func _on_body_entered(other: Node) -> void:
	# New fragments initially touch their former neighbours. Do not turn the
	# split itself into impact damage while physics creates contact manifolds.
	if other is WreckBody:
		var fragment: WreckBody = other as WreckBody
		if fragment.wreck == wreck and (_contact_grace > 0.0 or fragment._contact_grace > 0.0):
			return
	var reduced_mass: float = mass
	if other is RigidBody3D and not (other as RigidBody3D).freeze:
		var body: RigidBody3D = other as RigidBody3D
		reduced_mass = mass * body.mass / (mass + body.mass)
	# body_entered runs after the solver has already stopped or bounced the
	# bodies. Jolt retains incoming velocities at each reported contact, including
	# the other body's translation and spin; use those instead of live velocities.
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return
	var speed_squared: float = 0.0
	for index: int in range(state.get_contact_count()):
		if state.get_contact_collider_object(index) != other:
			continue
		var relative: Vector3 = state.get_contact_local_velocity_at_position(index) \
			- state.get_contact_collider_velocity_at_position(index)
		speed_squared = maxf(speed_squared, relative.length_squared())
	# A box may report several contacts for one impact; charge damage once.
	wreck.damage_component(part_ids, 0.5 * reduced_mass * speed_squared)
