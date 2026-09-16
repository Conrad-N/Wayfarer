## A station berth with a physical capture constraint and measured docking guidance.
## The cargo-end collar accepts any roll; it is a service clamp, not a pressure seal.
class_name StationDock
extends StaticBody3D

const PORT: Vector3 = Vector3(0, 0, 14)
const SHIP_PORT: Vector3 = Vector3(0, 0, -7.4)
const MAX_GAP_M: float = 0.5
const MAX_LATERAL_M: float = 0.3
const MAX_SPEED_MPS: float = 0.3
const MAX_ANGLE_RAD: float = PI / 36.0
const MAX_SPIN_RAD_S: float = 0.02
var guiding: bool = false
var final_approach: bool = false
var _joint: Generic6DOFJoint3D


func _ready() -> void:
	for side: float in [-1.0, 1.0]:
		_box(Vector3(8, 8, 24), Vector3(side * 12.0, 0, 0), Color(0.25, 0.5, 0.55))
		_box(Vector3(24, 1, 1), Vector3(0, side * 5, 12), Color(0.18, 0.28, 0.32))
	# An open, octagonal collar clears the hull at the permitted capture angles.
	for index: int in 8:
		var angle: float = TAU * float(index) / 8.0
		_box(Vector3(3.2, 0.4, 0.6), PORT + Vector3(sin(angle), cos(angle), 0) * 4.0, Color(0.9, 0.63, 0.19), -angle)
	var sign: Label3D = Label3D.new()
	sign.text = "LOWLINE YARD\nBERTH 01 / CARGO END FIRST"
	sign.position = Vector3(0, 6.3, 14)
	sign.pixel_size = 0.012
	add_child(sign)


## True only while a real six-axis station constraint exists.
func is_docked() -> bool:
	return is_instance_valid(_joint)


## Live port separation, point speed and pointing error, expressed in SI units.
func reading(ship: PlayerShip) -> Dictionary:
	var point: Vector3 = ship.to_global(SHIP_PORT)
	var offset: Vector3 = to_local(point) - PORT
	var velocity: Vector3 = ship.linear_velocity + ship.angular_velocity.cross(point - ship.to_global(ship.center_of_mass))
	var angle: float = acos(clampf(ship.global_basis.z.dot(global_basis.z), -1.0, 1.0))
	var lateral: float = Vector2(offset.x, offset.y).length()
	var speed: float = velocity.length()
	var spin: float = ship.angular_velocity.length()
	var reason: String = "READY TO DOCK"
	if not offset.is_finite() or not velocity.is_finite() or not is_finite(angle) or not is_finite(spin):
		reason = "DOCKING TELEMETRY UNAVAILABLE"
	elif offset.z < 0.0 or offset.z > MAX_GAP_M or lateral > MAX_LATERAL_M:
		reason = "MOVE CARGO COLLAR INTO THE RING"
	elif angle > MAX_ANGLE_RAD:
		reason = "ALIGN CARGO END WITH THE RING"
	elif speed > MAX_SPEED_MPS or spin > MAX_SPIN_RAD_S:
		reason = "SLOW TRANSLATION AND ROTATION"
	elif ship.api.get_telemetry().cargo_door_open or ship.api.get_telemetry().airlock_outer_open:
		reason = "CLOSE EXTERIOR HATCHES BEFORE DOCKING"
	return {"available": true, "docked": is_docked(), "guiding": guiding,
		"ready": reason == "READY TO DOCK", "status": "DOCKED / LOWLINE YARD" if is_docked() else reason,
		"gap_m": offset.z, "lateral_m": lateral, "offset_m": offset,
		"speed_mps": speed, "angle_rad": angle, "spin_rad_s": spin}


## Capture only inside the slow, aligned envelope; preserve the current hull pose.
func capture(ship: PlayerShip) -> bool:
	if is_docked() or not bool(reading(ship).ready):
		return false
	_engage(ship)
	return true


func _engage(ship: PlayerShip) -> void:
	guiding = false
	_joint = Generic6DOFJoint3D.new()
	_joint.name = "DockingClamp"
	_joint.exclude_nodes_from_collision = false
	add_child(_joint)
	_joint.global_position = ship.to_global(SHIP_PORT)
	for axis: String in ["x", "y", "z"]:
		_joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		_joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	_joint.node_a = _joint.get_path_to(self)
	_joint.node_b = _joint.get_path_to(ship)
	ship.sleeping = false


## Mechanical release never changes hull pose or imparts a departure impulse.
func release() -> void:
	guiding = false
	if is_instance_valid(_joint):
		_joint.node_a = NodePath()
		_joint.node_b = NodePath()
		_joint.free()
	_joint = null


## Admit guidance from the clear front apron, or from an already aligned corridor.
func start_guidance(ship: PlayerShip) -> bool:
	var data: Dictionary = reading(ship)
	var point: Vector3 = data.offset_m
	if not point.is_finite() or is_docked() or point.z < 0.0:
		return false
	if point.z < 14.0 and (float(data.lateral_m) > MAX_LATERAL_M or float(data.angle_rad) > MAX_ANGLE_RAD or float(data.spin_rad_s) > MAX_SPIN_RAD_S):
		return false
	guiding = true
	final_approach = point.z < 14.0
	return true


## Desired COM position for finite RCS guidance: align outside, then creep inward.
func guidance_position(ship: PlayerShip) -> Vector3:
	var data: Dictionary = reading(ship)
	if not final_approach and absf(float(data.gap_m) - 14.0) < 1.0 and float(data.lateral_m) < 0.2 and float(data.angle_rad) < deg_to_rad(2.0) \
			and float(data.spin_rad_s) < 0.01 and ship.linear_velocity.length() < 0.15:
		final_approach = true
	var gap: float = 0.2 if final_approach else 14.0
	return to_global(PORT + Vector3(0, 0, gap)) - ship.global_basis * SHIP_PORT + ship.global_basis * ship.center_of_mass


## Store a station-relative hull pose, independent of floating origin and cargo COM.
func capture_save(ship: PlayerShip) -> Dictionary:
	return {"pose": SaveCodec.transform(global_transform.affine_inverse() * ship.global_transform)} if is_docked() else {}


## Restore a saved clamp even without ship power or with hatches since opened.
func restore(ship: PlayerShip, data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var pose: Transform3D = SaveCodec.to_transform(data.get("pose"))
	if not pose.is_finite() or absf(pose.basis.determinant() - 1.0) > 0.001:
		return false
	var old_pose: Transform3D = ship.global_transform
	ship.global_transform = global_transform * pose
	var port: Vector3 = to_local(ship.to_global(SHIP_PORT)) - PORT
	if port.length() > 1.0 or ship.global_basis.z.dot(global_basis.z) < cos(MAX_ANGLE_RAD):
		ship.global_transform = old_pose
		return false
	# A saved latch is already engaged; open doors do not require a fresh capture.
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	_engage(ship)
	return true


func _box(size_m: Vector3, at: Vector3, color: Color, turn: float = 0.0) -> void:
	var assembly: Node3D = Node3D.new()
	add_child(assembly)
	assembly.position = at
	assembly.rotation.z = turn
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size_m
	mesh.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	assembly.add_child(mesh)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size_m
	collider.shape = shape
	# Physics shapes must be direct children of their collision body.
	add_child(collider)
	collider.transform = assembly.transform
