## Physical starter ship: an open interior, working doors, finite RCS, and damage.
class_name PlayerShip
extends RigidBody3D

const SEAT_POSITION: Vector3 = Vector3(-0.85, 0.0, 1.0)
const CARGO_BOUNDS: AABB = AABB(Vector3(-1.8, -1.4, -7.0), Vector3(3.6, 2.8, 5.0))
const DAMAGE_THRESHOLD_J: float = 2000.0
const SECTION_DAMAGE_ENERGY_J: float = 300000.0
const BRAKE_FORCE_N: float = 10000.0
const BRAKE_TORQUE_NM: float = 6000.0
const EXHAUST_VELOCITY_MPS: float = 2000.0
const THRUSTER_LEVER_ARM_M: float = 2.0

var api: ShipApi = ShipApi.new()
var navigation_target: RigidBody3D
var rotor_momentum_body: Vector3 = Vector3.ZERO
var _doors: Dictionary = {}
var _lights: Array[OmniLight3D] = []


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	continuous_cd = true
	can_sleep = false
	mass = float(api.get_telemetry().mass_kg)
	contact_monitor = true
	max_contacts_reported = 32
	_build_interior()
	api.set_door_validator(_door_is_clear)
	api.command_requested.connect(_on_command)
	body_entered.connect(_on_body_entered)
	_sync_doors()


## Set the local navigation reference; terminals receive motion only through ShipApi.
func set_navigation_target(body: RigidBody3D) -> void:
	navigation_target = body


## Apply an intercepted plume's energy to the exposed ship system.
func receive_hazard_damage(kind: String, energy_j: float) -> void:
	if not is_finite(energy_j) or energy_j <= 0.0:
		return
	api.apply_damage("power" if kind == "fuel" else "rcs", energy_j / SECTION_DAMAGE_ENERGY_J)


## Identify the system behind a local collision-shape index.
func system_at_shape(index: int) -> String:
	if index < 0:
		return "hull"
	var owner_node: Object = shape_owner_get_owner(shape_find_owner(index))
	return str(owner_node.get_meta("system_id", "hull")) if owner_node != null else "hull"


func _physics_process(delta: float) -> void:
	var telemetry: Dictionary = api.get_telemetry()
	mass = float(telemetry.mass_kg)
	if not freeze:
		var inverse: Basis = get_inverse_inertia_tensor()
		if absf(inverse.determinant()) > 1e-30:
			# OrbitalFlight supplies motor torque and this ship's rotor state.
			# Jolt needs the passive body/rotor correction even with motors off.
			var body_inertia: Basis = global_basis.transposed() * inverse.inverse() * global_basis
			apply_torque(global_basis * GyroscopicMotion.torque(global_basis.transposed() * angular_velocity, body_inertia, rotor_momentum_body, delta))
	if bool(telemetry.braking):
		_brake(delta, telemetry)
	var target_position: Vector3 = global_position
	var target_velocity: Vector3 = linear_velocity
	if is_instance_valid(navigation_target):
		target_position = navigation_target.global_position
		target_velocity = navigation_target.linear_velocity
	api.set_motion(global_position, linear_velocity, angular_velocity, target_position, target_velocity)
	for light: OmniLight3D in _lights:
		light.visible = bool(telemetry.power_available)
	for entry: Dictionary in _doors.values():
		(entry.indicator as MeshInstance3D).visible = bool(telemetry.power_available)


func _brake(delta: float, telemetry: Dictionary) -> void:
	var rcs: Dictionary = telemetry.systems.rcs
	if delta <= 0.0 or not bool(rcs.enabled) or float(rcs.health) <= 0.0 or not bool(telemetry.power_available):
		return
	var force: Vector3 = (-linear_velocity * mass / maxf(0.8, delta)).limit_length(BRAKE_FORCE_N)
	var torque: Vector3 = Vector3.ZERO
	var inverse_inertia: Basis = get_inverse_inertia_tensor()
	if absf(inverse_inertia.determinant()) > 1e-20:
		torque = (inverse_inertia.inverse() * (-angular_velocity / maxf(0.8, delta))).limit_length(BRAKE_TORQUE_NM)
	var requested: float = (force.length() + torque.length() / THRUSTER_LEVER_ARM_M) * delta / EXHAUST_VELOCITY_MPS
	if requested <= 0.0:
		return
	var supplied: float = api.consume_propellant(requested)
	apply_central_force(force * supplied / requested)
	apply_torque(torque * supplied / requested)
	mass = float(api.get_telemetry().mass_kg)


func _build_interior() -> void:
	var shell: Color = Color(0.32, 0.40, 0.47)
	var trim: Color = Color(0.12, 0.19, 0.24)
	# The shell is six independent slabs, never a convex box across the rooms.
	var deck: CollisionShape3D = _add_box("Floor", Vector3(4.4, 0.3, 13.2), Vector3(0, -1.55, -0.6), "hull", shell, true)
	deck.set_meta("magnetic_surface", true)
	_add_box("Ceiling", Vector3(4.4, 0.3, 13.2), Vector3(0, 1.55, -0.6), "power", shell, true)
	_add_box("PortWall", Vector3(0.3, 2.8, 13.2), Vector3(-2.05, 0, -0.6), "rcs", shell, true)
	_add_box("StarboardWall", Vector3(0.3, 2.8, 13.2), Vector3(2.05, 0, -0.6), "power", shell, true)
	_frame("CargoFrame", -7.1, 2.2, "cargo", trim)
	_frame("HabPartition", -2.0, 2.0, "hull", trim)
	_frame("AirlockInnerFrame", 3.5, 2.0, "airlock", trim)
	_frame("AirlockOuterFrame", 5.9, 2.0, "airlock", trim)
	_door("cargo", -7.1, 2.2, Color(0.8, 0.55, 0.16))
	_door("inner", 3.5, 2.0, Color(0.35, 0.65, 0.75))
	_door("outer", 5.9, 2.0, Color(0.35, 0.65, 0.75))
	var volume: Area3D = _area("CargoVolume", CARGO_BOUNDS.size, CARGO_BOUNDS.get_center())
	volume.set_meta("volume_m3", CARGO_BOUNDS.get_volume())
	_mount("NavTerminalMount", Vector3(-1.89, 0.35, 1.0), PI / 2.0)
	_mount("ShipTerminalMount", Vector3(1.89, 0.35, 1.0), -PI / 2.0)
	_build_pilot_seat()
	_sign("CARGO / 2.2 m CLEARANCE", Vector3(0, 1.32, -7.28), PI)
	_sign("HAB", Vector3(0, 1.3, -2.18), PI)
	_sign("AIRLOCK", Vector3(0, 1.3, 3.32), PI)
	_sign("WAYFARER / EVA", Vector3(0, 1.31, 6.08), 0.0)
	# An inset bunk stays outside the clear centre passage.
	_add_box("Bunk", Vector3(0.7, 0.15, 1.7), Vector3(-1.45, -1.1, 2.25), "hull", Color(0.21, 0.36, 0.40))
	for station: float in [-5.2, 0.0, 4.7]:
		var light: OmniLight3D = OmniLight3D.new()
		light.position = Vector3(0, 1.25, station)
		light.omni_range = 6.0
		light.light_energy = 1.2
		light.light_color = Color(0.65, 0.85, 1.0)
		add_child(light)
		_lights.append(light)


func _build_pilot_seat() -> void:
	# The seat faces the port NAV screen and leaves the centre passage clear.
	var upholstery: Color = Color(0.13, 0.23, 0.27)
	var frame_color: Color = Color(0.45, 0.51, 0.53)
	_add_box("SeatPedestal", Vector3(0.34, 0.35, 0.4), Vector3(-0.85, -1.22, 1.0), "hull", frame_color)
	_add_box("SeatCushion", Vector3(0.68, 0.16, 0.72), Vector3(-0.85, -1.0, 1.0), "hull", upholstery)
	_add_box("SeatBack", Vector3(0.13, 1.25, 0.72), Vector3(-0.4, -0.38, 1.0), "hull", upholstery)
	for side: float in [-1.0, 1.0]:
		_add_box("SeatArm" + str(side), Vector3(0.65, 0.1, 0.08), Vector3(-0.85, -0.55, 1.0 + side * 0.42), "hull", frame_color)
		_add_box("SeatHarness" + str(side), Vector3(0.025, 0.8, 0.065), Vector3(-0.52, -0.17, 1.0 + side * 0.21), "hull", Color(0.93, 0.58, 0.13))
	for child: Node in get_children():
		if child is CollisionShape3D and str(child.name).begins_with("Seat"):
			child.set_meta("pilot_seat", true)
	var area: Area3D = _area("PilotSeat", Vector3(0.9, 1.7, 1.0), SEAT_POSITION)
	area.collision_layer = 4
	area.set_meta("pilot_seat", true)
	_sign("PILOT / F STRAP IN", Vector3(-0.31, 0.56, 1.0), PI / 2.0)


func _frame(label: String, z: float, width: float, system: String, color: Color) -> void:
	var side_width: float = (3.8 - width) * 0.5
	for side: float in [-1.0, 1.0]:
		_add_box(label + str(side), Vector3(side_width, 2.8, 0.2), Vector3(side * (width * 0.5 + side_width * 0.5), 0, z), system, color, true)
		var sill: CollisionShape3D = _add_box(label + "Lintel" + str(side), Vector3(width, 0.3, 0.2), Vector3(0, side * 1.25, z), system, color)

		if side < 0.0:
			sill.set_meta("magnetic_surface", true)


func _door(id: String, z: float, width: float, color: Color) -> void:
	var shape: CollisionShape3D = _add_box(id.capitalize() + "Door", Vector3(width, 2.2, 0.16), Vector3(0, 0, z), "cargo" if id == "cargo" else "airlock", color, true)
	var area: Area3D = _area(id.capitalize() + "DoorClearance", Vector3(width, 2.2, 0.45), Vector3(0, 0, z))
	var indicator: MeshInstance3D = MeshInstance3D.new()
	var lamp: SphereMesh = SphereMesh.new()
	lamp.radius = 0.07
	lamp.height = 0.14
	lamp.radial_segments = 8
	lamp.rings = 4
	indicator.mesh = lamp
	indicator.position = Vector3(width * 0.5 + 0.25, 0.8, z - 0.13)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator.material_override = material
	add_child(indicator)
	_doors[id] = {"shape": shape, "visual": shape.get_meta("visual"), "area": area, "indicator": indicator}


func _area(label: String, size: Vector3, at: Vector3) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = label
	area.position = at
	area.collision_layer = 0
	area.collision_mask = 1
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	area.add_child(collision)
	add_child(area)
	return area


func _add_box(label: String, size: Vector3, at: Vector3, system: String, color: Color, kit: bool = false) -> CollisionShape3D:
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = label + "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	collision.set_meta("system_id", system)
	add_child(collision)
	var visual: Node3D = Node3D.new()
	visual.name = label + "Visual"
	visual.position = at
	add_child(visual)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	if kit:
		var definition: PartDefinition = PartCatalog.definition("plating_panel_a")
		var geometry: Dictionary = PartCatalog.geometry(definition)
		var bounds: AABB
		var first: bool = true
		for entry: Dictionary in geometry.meshes:
			var entry_bounds: AABB = (entry.transform as Transform3D) * (entry.mesh as Mesh).get_aabb()
			bounds = entry_bounds if first else bounds.merge(entry_bounds)
			first = false
		var normalize: Transform3D = Transform3D(Basis.from_scale(size / bounds.size), Vector3.ZERO)
		normalize.origin = -(normalize.basis * bounds.get_center())
		for entry: Dictionary in geometry.meshes:
			var mesh: MeshInstance3D = MeshInstance3D.new()
			mesh.mesh = entry.mesh
			mesh.transform = normalize * (entry.transform as Transform3D)
			mesh.material_override = material
			visual.add_child(mesh)
	else:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = material
		visual.add_child(mesh)
	collision.set_meta("visual", visual)
	return collision


func _mount(label: String, at: Vector3, yaw: float) -> void:
	var mount: Node3D = Node3D.new()
	mount.name = label
	mount.position = at
	mount.rotation.y = yaw
	add_child(mount)


func _sign(message: String, at: Vector3, yaw: float) -> void:
	var sign: Label3D = Label3D.new()
	sign.text = message
	sign.font_size = 48
	sign.pixel_size = 0.0012
	sign.position = at
	sign.rotation.y = yaw
	sign.modulate = Color(0.65, 0.9, 1.0)
	add_child(sign)


func _door_is_clear(door: String, opening: bool) -> bool:
	if opening or not _doors.has(door) or not is_inside_tree():
		return true
	var area: Area3D = _doors[door].area
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = (area.get_child(0) as CollisionShape3D).shape
	query.transform = area.global_transform
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _on_command(_command: String, _arguments: Dictionary) -> void:
	_sync_doors()


func _sync_doors() -> void:
	var telemetry: Dictionary = api.get_telemetry()
	var states: Dictionary = {"cargo": telemetry.cargo_door_open, "inner": telemetry.airlock_inner_open, "outer": telemetry.airlock_outer_open}
	for id: String in _doors:
		var entry: Dictionary = _doors[id]
		(entry.shape as CollisionShape3D).set_deferred("disabled", states[id])
		(entry.visual as Node3D).visible = not bool(states[id])
		var material: StandardMaterial3D = (entry.indicator as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = Color(0.2, 1.0, 0.5) if bool(states[id]) else Color(1.0, 0.5, 0.12)


func _on_body_entered(other: Node) -> void:
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return
	var reduced_mass: float = mass
	if other is RigidBody3D and not (other as RigidBody3D).freeze:
		var other_mass: float = (other as RigidBody3D).mass
		reduced_mass = mass * other_mass / (mass + other_mass)
	var maximum_energy: float = 0.0
	var impacted_system: String = "hull"
	for index: int in range(state.get_contact_count()):
		if state.get_contact_collider_object(index) != other:
			continue
		var relative: Vector3 = state.get_contact_local_velocity_at_position(index) - state.get_contact_collider_velocity_at_position(index)
		var energy: float = 0.5 * reduced_mass * relative.length_squared()
		if energy > maximum_energy:
			maximum_energy = energy
			impacted_system = system_at_shape(state.get_contact_local_shape(index))
	api.apply_damage(impacted_system, maxf(maximum_energy - DAMAGE_THRESHOLD_J, 0.0) / SECTION_DAMAGE_ENERGY_J)
