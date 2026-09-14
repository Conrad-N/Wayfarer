## One winch cable joining two anchored devices. Tension is computed at the
## velocity level (effective mass along the cable, half the error removed per
## tick) so a 1 kg scrap and a 40 t hull are both stable with the same gains;
## a plain spring-damper cannot do that across such a mass range. Off-centre
## anchors apply real torque, and the motor reels in from the device's own
## battery. Anchors are stored body-local (plus part id/part-local for a
## WreckBody) so floating-origin shifts and frame handoffs cannot move them.
class_name WinchLink
extends Node3D

## Emitted once, with the reason shown on the HUD, right before this link frees itself.
signal detached(reason: String)

const MIN_LENGTH_M: float = 0.3
const MAX_LENGTH_M: float = 30.0
const DETACH_MARGIN_M: float = 1.0
const REEL_SPEED_MPS: float = 0.2
## The tension bias closes stretch at (stretch / 0.5 s), so 0.1 m of stretch is
## needed to follow the reel at full speed; stall a little beyond that.
const REEL_STALL_ERROR_M: float = 0.12
const REEL_EFFICIENCY: float = 0.8
const MAX_TENSION_N: float = 500.0
const DEVICE_BATTERY_J: float = 250000.0

var status: String = "WINCH LINKED"
var cable_length_m: float = 0.0
var device_battery_j: float = DEVICE_BATTERY_J
var tension_n: float = 0.0

var _body_a: PhysicsBody3D
var _local_anchor_a: Vector3 = Vector3.ZERO
var _local_normal_a: Vector3 = Vector3.UP
var _part_id_a: String = ""
var _wreck_a: SalvageWreck
var _part_anchor_a: Vector3 = Vector3.ZERO
var _part_normal_a: Vector3 = Vector3.UP
var _rebuilding_a: bool = false

var _body_b: PhysicsBody3D
var _local_anchor_b: Vector3 = Vector3.ZERO
var _local_normal_b: Vector3 = Vector3.UP
var _part_id_b: String = ""
var _wreck_b: SalvageWreck
var _part_anchor_b: Vector3 = Vector3.ZERO
var _part_normal_b: Vector3 = Vector3.UP
var _rebuilding_b: bool = false

var _device_a: MeshInstance3D
var _device_b: MeshInstance3D
var _cable: MeshInstance3D
var _detached: bool = false


func _ready() -> void:
	process_physics_priority = -20
	_device_a = make_device_mesh()
	_device_b = make_device_mesh()
	_cable = make_cable_mesh()
	add_child(_device_a)
	add_child(_device_b)
	add_child(_cable)


## Attach the first device. Call attach_b and then finish_setup to complete the link.
func attach_a(body: PhysicsBody3D, local_anchor: Vector3, local_normal: Vector3, part_id: String, wreck: SalvageWreck, part_anchor: Vector3, part_normal: Vector3) -> void:
	_body_a = body
	_local_anchor_a = local_anchor
	_local_normal_a = local_normal
	_part_id_a = part_id
	_wreck_a = wreck
	_part_anchor_a = part_anchor
	_part_normal_a = part_normal


## Attach the second device.
func attach_b(body: PhysicsBody3D, local_anchor: Vector3, local_normal: Vector3, part_id: String, wreck: SalvageWreck, part_anchor: Vector3, part_normal: Vector3) -> void:
	_body_b = body
	_local_anchor_b = local_anchor
	_local_normal_b = local_normal
	_part_id_b = part_id
	_wreck_b = wreck
	_part_anchor_b = part_anchor
	_part_normal_b = part_normal


## Finish creation once both devices are attached: fix the starting cable length and hook wreck signals.
func finish_setup() -> void:
	cable_length_m = clampf(anchor_a_position().distance_to(anchor_b_position()), MIN_LENGTH_M, MAX_LENGTH_M)
	if is_instance_valid(_wreck_a) and not _wreck_a.structure_changing.is_connected(_on_structure_changing):
		_wreck_a.structure_changing.connect(_on_structure_changing)
		_wreck_a.structure_changed.connect(_on_structure_changed)
	if is_instance_valid(_wreck_b) and _wreck_b != _wreck_a and not _wreck_b.structure_changing.is_connected(_on_structure_changing):
		_wreck_b.structure_changing.connect(_on_structure_changing)
		_wreck_b.structure_changed.connect(_on_structure_changed)


## Return device A's current world anchor point, following its carrying body.
func anchor_a_position() -> Vector3:
	return _body_a.to_global(_local_anchor_a) if is_instance_valid(_body_a) else Vector3.ZERO


## Return device B's current world anchor point, following its carrying body.
func anchor_b_position() -> Vector3:
	return _body_b.to_global(_local_anchor_b) if is_instance_valid(_body_b) else Vector3.ZERO


## Free this link immediately, reporting reason as its final status and signal payload.
func detach_now(reason: String) -> void:
	if _detached:
		return
	_detached = true
	status = reason
	detached.emit(reason)
	queue_free()


func _exit_tree() -> void:
	_disconnect_wreck(_wreck_a)
	_disconnect_wreck(_wreck_b)


func _disconnect_wreck(wreck: SalvageWreck) -> void:
	if not is_instance_valid(wreck):
		return
	if wreck.structure_changing.is_connected(_on_structure_changing):
		wreck.structure_changing.disconnect(_on_structure_changing)
	if wreck.structure_changed.is_connected(_on_structure_changed):
		wreck.structure_changed.disconnect(_on_structure_changed)


func _physics_process(delta: float) -> void:
	if _detached or _rebuilding_a or _rebuilding_b:
		return
	if not _body_valid(_body_a) or not _body_valid(_body_b):
		detach_now("WINCH DETACHED")
		return
	var point_a: Vector3 = anchor_a_position()
	var point_b: Vector3 = anchor_b_position()
	var distance: float = point_a.distance_to(point_b)
	if distance > MAX_LENGTH_M + DETACH_MARGIN_M:
		detach_now("WINCH DETACHED")
		return
	if distance < 0.0001 or delta <= 0.0:
		return
	var normal: Vector3 = (point_b - point_a) / distance
	tension_n = _apply_tension(point_a, point_b, distance, normal, delta)
	_advance_reel(distance, delta)
	status = "%.1f m | %.0f N | device battery %.0f%%" % [distance, tension_n, device_battery_j / DEVICE_BATTERY_J * 100.0]


func _process(_delta: float) -> void:
	if _detached or not _body_valid(_body_a) or not _body_valid(_body_b):
		return
	place_device(_device_a, _body_a, _local_anchor_a, _local_normal_a)
	place_device(_device_b, _body_b, _local_anchor_b, _local_normal_b)
	place_cable(_cable, anchor_a_position(), anchor_b_position())


func _apply_tension(point_a: Vector3, point_b: Vector3, distance: float, normal: Vector3, delta: float) -> float:
	if distance < cable_length_m:
		return 0.0
	var inverse_mass: float = _inv_mass(_body_a) + _inv_mass(_body_b) \
		+ _inertia_term(_body_a, point_a, normal) + _inertia_term(_body_b, point_b, normal)
	if inverse_mass <= 1e-9:
		return 0.0
	var effective_mass: float = 1.0 / inverse_mass
	var separation_speed: float = (_point_velocity(_body_b, point_b) - _point_velocity(_body_a, point_a)).dot(normal)
	var bias: float = (distance - cable_length_m) / 0.5
	var tension: float = clampf(effective_mass * 0.5 * (separation_speed + bias) / delta, 0.0, MAX_TENSION_N)
	if tension <= 0.0:
		return 0.0
	var force: Vector3 = normal * tension
	_apply_force(_body_a, force, point_a)
	_apply_force(_body_b, -force, point_b)
	return tension


func _advance_reel(distance: float, delta: float) -> void:
	if cable_length_m <= MIN_LENGTH_M or device_battery_j <= 0.0:
		return
	if distance - cable_length_m > REEL_STALL_ERROR_M:
		return
	var requested_length: float = maxf(cable_length_m - REEL_SPEED_MPS * delta, MIN_LENGTH_M)
	var travel: float = cable_length_m - requested_length
	if travel <= 0.0:
		return
	var cost: float = tension_n * travel / REEL_EFFICIENCY
	var fraction: float = 1.0
	if cost > 0.0:
		var available: float = minf(cost, device_battery_j)
		device_battery_j -= available
		fraction = available / cost
	cable_length_m -= travel * fraction


## Takes Variant, not PhysicsBody3D: a fully freed (not just queued) body loses
## its class info, and binding it to a typed parameter throws before
## is_instance_valid() can even run. This is the one safe way to probe it.
func _body_valid(body: Variant) -> bool:
	if not is_instance_valid(body):
		return false
	var node: Node = body as Node
	return node.is_inside_tree() and not node.is_queued_for_deletion()


func _inv_mass(body: PhysicsBody3D) -> float:
	if body is RigidBody3D and not (body as RigidBody3D).freeze:
		return 1.0 / maxf((body as RigidBody3D).mass, 0.0001)
	return 0.0


func _inertia_term(body: PhysicsBody3D, anchor: Vector3, normal: Vector3) -> float:
	if body is RigidBody3D and not (body as RigidBody3D).freeze:
		var rigid: RigidBody3D = body as RigidBody3D
		var r: Vector3 = anchor - rigid.to_global(rigid.center_of_mass)
		var cross: Vector3 = r.cross(normal)
		return cross.dot(rigid.get_inverse_inertia_tensor() * cross)
	return 0.0


func _point_velocity(body: PhysicsBody3D, anchor: Vector3) -> Vector3:
	if body is RigidBody3D and not (body as RigidBody3D).freeze:
		var rigid: RigidBody3D = body as RigidBody3D
		var r: Vector3 = anchor - rigid.to_global(rigid.center_of_mass)
		return rigid.linear_velocity + rigid.angular_velocity.cross(r)
	return Vector3.ZERO


func _apply_force(body: PhysicsBody3D, force: Vector3, anchor: Vector3) -> void:
	if body is RigidBody3D and not (body as RigidBody3D).freeze:
		(body as RigidBody3D).apply_force(force, anchor - body.global_position)


func _on_structure_changing() -> void:
	if not _part_id_a.is_empty():
		_rebuilding_a = true
	if not _part_id_b.is_empty():
		_rebuilding_b = true


func _on_structure_changed() -> void:
	if _rebuilding_a:
		_rebuild_side_a()
	if _rebuilding_b:
		_rebuild_side_b()


func _rebuild_side_a() -> void:
	_rebuilding_a = false
	var body: WreckBody = _wreck_a.body_for_part(_part_id_a) if is_instance_valid(_wreck_a) else null
	if not is_instance_valid(body):
		detach_now("WINCH DETACHED")
		return
	var pose: Transform3D = _wreck_a.part_pose(_part_id_a)
	_body_a = body
	_local_anchor_a = body.to_local(pose * _part_anchor_a)
	_local_normal_a = body.global_basis.inverse() * (pose.basis * _part_normal_a).normalized()


func _rebuild_side_b() -> void:
	_rebuilding_b = false
	var body: WreckBody = _wreck_b.body_for_part(_part_id_b) if is_instance_valid(_wreck_b) else null
	if not is_instance_valid(body):
		detach_now("WINCH DETACHED")
		return
	var pose: Transform3D = _wreck_b.part_pose(_part_id_b)
	_body_b = body
	_local_anchor_b = body.to_local(pose * _part_anchor_b)
	_local_normal_b = body.global_basis.inverse() * (pose.basis * _part_normal_b).normalized()


## Sit a device mesh on its body's surface point, facing out along the stored normal.
static func place_device(mesh_instance: MeshInstance3D, body: PhysicsBody3D, local_anchor: Vector3, local_normal: Vector3) -> void:
	var origin: Vector3 = body.to_global(local_anchor)
	var normal: Vector3 = body.global_basis * local_normal
	normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	mesh_instance.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), origin + normal * 0.03)


## Stretch a cable mesh between two world points; hide it when they coincide.
static func place_cable(cable: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var offset: Vector3 = end - start
	var length: float = offset.length()
	if length < 0.001:
		cable.visible = false
		return
	cable.visible = true
	var basis: Basis = Basis(Quaternion(Vector3.UP, offset / length)) * Basis.from_scale(Vector3(1, length, 1))
	cable.global_transform = Transform3D(basis, start + offset * 0.5)


## Build the small amber device box; visual only, no collision.
static func make_device_mesh() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.top_level = true
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.14, 0.06, 0.14)
	mesh_instance.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.85, 0.55, 0.1)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


## Build the thin yellow cable cylinder, one metre tall before scaling.
static func make_cable_mesh() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.top_level = true
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.01
	mesh.bottom_radius = 0.01
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh_instance.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.95, 0.85, 0.15)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance
