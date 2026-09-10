## A nearby handhold joins two live rigid bodies; Jolt exchanges their momentum.
## The held part retains its identity across salvage splits. No pose is teleported.
class_name PhysicalGrip
extends Node3D

signal attachment_changed()

@export var max_reach_m: float = 2.0
@export var max_catch_speed_mps: float = 3.0
@export var max_grip_force_n: float = 2500.0
@export var max_grip_torque_nm: float = 350.0

var status: String = "HANDS FREE"
var held_part_id: String = ""
var _player: RigidBody3D
var _camera: Camera3D
var _target: RigidBody3D
var _joint: Generic6DOFJoint3D
var _wreck: SalvageWreck
var _target_anchor: Vector3 = Vector3.ZERO
var _player_anchor: Vector3 = Vector3.ZERO
var _part_anchor: Vector3 = Vector3.ZERO
var _last_velocity: Vector3 = Vector3.ZERO
var _last_spin: Vector3 = Vector3.ZERO
var _settle_seconds: float = 0.0
var _rebuilding: bool = false


## Connect this component to a suit and an optional aiming camera.
func configure(player: RigidBody3D, camera: Camera3D = null) -> void:
	release()
	_player = player
	_camera = camera
	process_physics_priority = -20


## Attempt a handhold on the first solid surface within arm's reach of the camera.
func try_grab() -> bool:
	if not is_instance_valid(_player) or not is_instance_valid(_camera) or _player.freeze:
		return false
	var origin: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin,
		origin - _camera.global_basis.z * maxf(max_reach_m, 0.0), 1, [_player.get_rid()])
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is RigidBody3D:
		status = "NO HANDHOLD IN REACH"
		return false
	var body: RigidBody3D = hit.collider as RigidBody3D
	var id: String = (body as WreckBody).part_at_shape(int(hit.shape)) if body is WreckBody else ""
	return grab_body(body, hit.position, id)


## Hold a reachable rigid surface at the current relative pose, preserving live motion.
func grab_body(body: RigidBody3D, world_point: Vector3, part_id: String = "") -> bool:
	if not is_instance_valid(_player) or not is_instance_valid(body) or body == _player \
			or not _player.is_inside_tree() or not body.is_inside_tree() or _player.freeze \
			or not world_point.is_finite():
		return false
	var origin: Vector3 = _camera.global_position if is_instance_valid(_camera) else _player.global_position
	if origin.distance_to(world_point) > maxf(max_reach_m, 0.0):
		status = "HANDHOLD OUT OF REACH"
		return false
	if body is WreckBody and (part_id.is_empty() or not (body as WreckBody).part_ids.has(part_id)):
		status = "NO SOLID PART SELECTED"
		return false
	var relative: Vector3 = _point_velocity(body, world_point) - _point_velocity(_player, world_point)
	var reduced_mass: float = _player.mass if body.freeze else _player.mass * body.mass / (_player.mass + body.mass)
	var inverse_sum: Basis = _player.get_inverse_inertia_tensor()
	if not body.freeze:
		inverse_sum = _sum(inverse_sum, body.get_inverse_inertia_tensor())
	var angular_catch: float = 0.0
	if absf(inverse_sum.determinant()) > 1e-20:
		angular_catch = (inverse_sum.inverse() * (body.angular_velocity - _player.angular_velocity)).length() / 0.15
	if relative.length() > maxf(max_catch_speed_mps, 0.0) \
			or relative.length() * reduced_mass / 0.15 > maxf(max_grip_force_n, 0.0) \
			or angular_catch > maxf(max_grip_torque_nm, 0.0):
		status = "MOVING TOO FAST TO CATCH"
		return false
	release()
	_target = body
	held_part_id = part_id
	_target_anchor = body.to_local(world_point)
	_player_anchor = _player.to_local(world_point)
	if body is WreckBody:
		_wreck = (body as WreckBody).wreck
		_part_anchor = _wreck.part_pose(part_id).affine_inverse() * world_point
		_wreck.structure_changing.connect(_before_structure_change)
		_wreck.structure_changed.connect(_after_structure_change)
	_make_joint(world_point)
	status = "HOLDING " + (held_part_id if not held_part_id.is_empty() else body.name)
	attachment_changed.emit()
	return true


## Release without changing either object's position, velocity, or spin.
func release() -> void:
	_remove_joint()
	if is_instance_valid(_wreck):
		if _wreck.structure_changing.is_connected(_before_structure_change):
			_wreck.structure_changing.disconnect(_before_structure_change)
		if _wreck.structure_changed.is_connected(_after_structure_change):
			_wreck.structure_changed.disconnect(_after_structure_change)
	_wreck = null
	_target = null
	held_part_id = ""
	_rebuilding = false
	status = "HANDS FREE"
	attachment_changed.emit()


## Report whether the grip currently has a live physical carrier.
func is_attached() -> bool:
	return is_instance_valid(_target) and (_rebuilding or is_instance_valid(_joint))


## Return the live carrier, including a replacement fragment after cutting.
func target_body() -> RigidBody3D:
	return _target if is_instance_valid(_target) else null


## Return the moving hand contact in world coordinates.
func anchor_position() -> Vector3:
	return _target.to_global(_target_anchor) if is_instance_valid(_target) else Vector3.ZERO


## Supply combined centre-of-mass motion and inertia for the suit's finite RCS brake.
func brake_state() -> Dictionary:
	if not is_attached() or _target.freeze:
		return {}
	var total: float = _player.mass + _target.mass
	var player_center: Vector3 = _center(_player)
	var target_center: Vector3 = _center(_target)
	var center: Vector3 = (player_center * _player.mass + target_center * _target.mass) / total
	var tensor: Basis = _sum(_inertia(_player), _inertia(_target))
	tensor = _sum(tensor, _parallel_axis(_player.mass, player_center - center))
	tensor = _sum(tensor, _parallel_axis(_target.mass, target_center - center))
	return {"velocity": (_player.linear_velocity * _player.mass + _target.linear_velocity * _target.mass) / total,
		"angular_velocity": _player.angular_velocity, "mass": total, "inertia": tensor,
		"force_offset": player_center - center}


func _physics_process(delta: float) -> void:
	if _rebuilding:
		return
	if not is_attached():
		if is_instance_valid(_joint):
			release()
		return
	if not is_instance_valid(_player) or _player.freeze or _target.is_queued_for_deletion():
		release()
		return
	_settle_seconds = maxf(0.0, _settle_seconds - delta)
	# Godot does not expose solved joint impulses. Monitor the suit's measured
	# acceleration as a conservative overload estimate, including its own jets.
	var force: float = _player.mass * (_player.linear_velocity - _last_velocity).length() / maxf(delta, 0.001)
	var torque: float = (_inertia(_player) * ((_player.angular_velocity - _last_spin) / maxf(delta, 0.001))).length()
	_last_velocity = _player.linear_velocity
	_last_spin = _player.angular_velocity
	var error: float = anchor_position().distance_to(_player.to_global(_player_anchor))
	if error > 0.3 or (_settle_seconds <= 0.0 and (force > max_grip_force_n or torque > max_grip_torque_nm)):
		release()
		status = "GRIP LOST: LOAD TOO HIGH"


func _exit_tree() -> void:
	release()


func _make_joint(point: Vector3) -> void:
	_joint = Generic6DOFJoint3D.new()
	_joint.name = "PhysicalHandhold"
	_joint.exclude_nodes_from_collision = false
	add_child(_joint)
	_joint.global_position = point
	# All six zero-width limits form a fixed constraint at the existing pose.
	# Keeping contacts enabled prevents a carried object passing through the suit.
	for axis: String in ["x", "y", "z"]:
		_joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		_joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		_joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	_joint.node_a = _joint.get_path_to(_player)
	_joint.node_b = _joint.get_path_to(_target)
	_player.sleeping = false
	_target.sleeping = false
	_target.set_meta("physical_grip_count", int(_target.get_meta("physical_grip_count", 0)) + 1)
	_last_velocity = _player.linear_velocity
	_last_spin = _player.angular_velocity
	_settle_seconds = 0.2


func _remove_joint() -> void:
	if is_instance_valid(_joint):
		if is_instance_valid(_target):
			_target.set_meta("physical_grip_count", maxi(0, int(_target.get_meta("physical_grip_count", 0)) - 1))
		_joint.node_a = NodePath()
		_joint.node_b = NodePath()
		_joint.free()
	_joint = null


func _before_structure_change() -> void:
	_rebuilding = true
	_remove_joint()


func _after_structure_change() -> void:
	# Cargo clamps and unrelated refreshes also emit changed without replacing us.
	if not _rebuilding:
		return
	if not is_instance_valid(_wreck) or held_part_id.is_empty():
		release()
		return
	_target = _wreck.body_for_part(held_part_id)
	if not is_instance_valid(_target):
		release()
		return
	var point: Vector3 = _wreck.part_pose(held_part_id) * _part_anchor
	_target_anchor = _target.to_local(point)
	_make_joint(point)
	_rebuilding = false
	attachment_changed.emit()


static func _center(body: RigidBody3D) -> Vector3:
	return body.to_global(body.center_of_mass)


static func _point_velocity(body: RigidBody3D, point: Vector3) -> Vector3:
	return body.linear_velocity + body.angular_velocity.cross(point - _center(body))


static func _inertia(body: RigidBody3D) -> Basis:
	var inverse: Basis = body.get_inverse_inertia_tensor()
	return inverse.inverse() if inverse.determinant() > 0.0 else Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)


static func _parallel_axis(mass_kg: float, offset: Vector3) -> Basis:
	return Basis(Vector3(offset.y * offset.y + offset.z * offset.z, -offset.x * offset.y, -offset.x * offset.z) * mass_kg,
		Vector3(-offset.y * offset.x, offset.x * offset.x + offset.z * offset.z, -offset.y * offset.z) * mass_kg,
		Vector3(-offset.z * offset.x, -offset.z * offset.y, offset.x * offset.x + offset.y * offset.y) * mass_kg)


static func _sum(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)
