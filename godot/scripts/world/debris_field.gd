## Repeatable M1 collision playground: eleven box props and the generated hull.
## Everything starts at rest so the player can see the motion each bump creates.
class_name DebrisField
extends Node3D

const HULL_PATH: String = "res://assets/models/parts/hull_segment_a.glb"
const STEEL: Color = Color(0.36, 0.43, 0.49)
const BLUE: Color = Color(0.20, 0.38, 0.51)


func _ready() -> void:
	# Equal-sized crates make mass, rather than shape, the visible comparison.
	_place_box("LightCrate", Vector3.ONE * 0.8, 20.0, Vector3(0, 0, 3), BLUE)
	_place_box("SuitMassCrate", Vector3.ONE * 0.8, 100.0, Vector3(-3, 0, 3), BLUE)
	_place_box("HeavyCrate", Vector3.ONE * 0.8, 1000.0, Vector3(3, 0, 3), BLUE)
	_place_box("ThinPanel", Vector3(2, 0.18, 1.4), 35.0, Vector3(-6, 2, -2), STEEL, Vector3(0, 0.35, 0.2))
	_place_box("LongBeam", Vector3(0.3, 0.3, 3), 60.0, Vector3(-8, -1, -6), STEEL, Vector3(0.2, 0.5, 0.3))
	_place_box("CargoBlock", Vector3(1.4, 1.2, 1.3), 250.0, Vector3(-3, -3, -5), BLUE)
	_place_box("Ballast", Vector3(1.8, 0.8, 1.8), 1800.0, Vector3(2, -3, -6), STEEL)
	_place_box("UpperCrate", Vector3.ONE * 1.2, 180.0, Vector3(0, 3, -3), BLUE)
	_place_box("RearPod", Vector3(1.6, 1, 1.2), 400.0, Vector3(-5, 1, 10), BLUE)
	_place_box("RearPlate", Vector3(2.4, 0.2, 1.5), 80.0, Vector3(5, -2, 10), STEEL, Vector3(0.21, 0.3, 0.18))
	_place_box("SmallBrick", Vector3(0.6, 0.9, 0.7), 50.0, Vector3(-7, -4, 4), STEEL)
	var hull: RigidBody3D = create_hull()
	if hull != null:
		hull.position = Vector3(6, 1, -7)
		_add_mass_label(hull, 2.4)
		add_child(hull)


## Create a detached, freely drifting box with matching visual and collision size.
static func create_box(size: Vector3, mass_kg: float, colour: Color) -> RigidBody3D:
	if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0 or not is_finite(mass_kg) or mass_kg <= 0.0:
		push_error("Debris boxes need positive finite dimensions and mass.")
		return null
	var body: RigidBody3D = _create_body(mass_kg)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "Mesh"
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(colour)
	body.add_child(mesh)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


## Wrap the existing hull model in a dynamic convex body, using its imported mass.
static func create_hull() -> RigidBody3D:
	var packed: PackedScene = load(HULL_PATH)
	if packed == null:
		push_error("Cannot load the M1 hull model.")
		return null
	var model: Node3D = packed.instantiate() as Node3D
	var mesh: MeshInstance3D = _find_mesh(model)
	if mesh == null or mesh.mesh == null:
		push_error("The M1 hull model has no mesh.")
		model.free()
		return null
	var extras: Dictionary = mesh.get_meta("extras", {})
	var mass_kg: float = float(extras.get("mass_kg", 0.0))
	if not is_finite(mass_kg) or mass_kg <= 0.0:
		push_error("The M1 hull model needs positive mass_kg metadata.")
		model.free()
		return null
	var shape: ConvexPolygonShape3D = mesh.mesh.create_convex_shape()
	if shape == null:
		push_error("Cannot create convex collision for the M1 hull.")
		model.free()
		return null
	var body: RigidBody3D = _create_body(mass_kg)
	body.name = "HullSegment"
	body.add_child(model)
	mesh.material_override = _material(STEEL)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	# Include every imported transform without needing the model in the scene tree.
	var mesh_pose: Transform3D = Transform3D.IDENTITY
	var ancestor: Node3D = mesh
	while ancestor != body:
		mesh_pose = ancestor.transform * mesh_pose
		ancestor = ancestor.get_parent() as Node3D
	collision.transform = mesh_pose
	body.add_child(collision)
	return body


func _place_box(label: String, size: Vector3, mass_kg: float, at: Vector3, colour: Color, angles: Vector3 = Vector3.ZERO) -> void:
	var body: RigidBody3D = create_box(size, mass_kg, colour)
	if body == null:
		return
	body.name = label
	body.position = at
	body.rotation = angles
	_add_mass_label(body, size.y * 0.5 + 0.3)
	add_child(body)


static func _create_body(mass_kg: float) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = mass_kg
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	body.continuous_cd = true
	var surface: PhysicsMaterial = PhysicsMaterial.new()
	surface.friction = 0.2
	surface.bounce = 0.0
	body.physics_material_override = surface
	return body


static func _material(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	return material


static func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var mesh: MeshInstance3D = _find_mesh(child)
		if mesh != null:
			return mesh
	return null


static func _add_mass_label(body: RigidBody3D, height: float) -> void:
	var label: Label3D = Label3D.new()
	label.name = "MassLabel"
	label.text = "%.0f kg" % body.mass
	label.position.y = height
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.006
	label.modulate = Color(0.8, 0.9, 1.0)
	body.add_child(label)
