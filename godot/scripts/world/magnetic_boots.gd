## Switchable magnetic soles hold on designated steel surfaces and walk with reaction forces.
class_name MagneticBoots
extends Node

const ENGAGE_ENERGY_J: float = 50.0
const WALK_SPEED_MPS: float = 1.3
const MAX_FORCE_N: float = 1200.0
const MAX_TORQUE_NM: float = 1000.0
const FOOT_HEIGHT_M: float = 0.92
const TURN_TORQUE_NM: float = 250.0
const TURN_ENERGY_J_PER_RAD: float = 500.0

var status: String = "BOOTS OFF | B latch near a steel deck"
var player: Player
var _target: PhysicsBody3D
var _anchor: Vector3
var _normal: Vector3
var _heading: Vector3
var _walking: Vector2 = Vector2.ZERO
var _turn_remaining_rad: float = 0.0
var _height: float = FOOT_HEIGHT_M


## Bind the physical suit. The controller runs before suit actuators.
func configure(owner_player: Player) -> void:
	player = owner_player
	process_physics_priority = -10


## True while the soles retain contact with a suitable surface.
func is_attached() -> bool:
	return is_instance_valid(_target)


## Report the physical supporting body for frame transitions.
func target_body() -> PhysicsBody3D:
	return _target if is_attached() else null


## Set desired lateral/forward walking; diagonal steps share one speed budget.
func set_walk_input(direction: Vector2) -> void:
	_walking = direction.limit_length(1.0) if direction.is_finite() else Vector2.ZERO


## Cancel walking and outstanding turn input when a panel or focus takes control.
func cancel_input() -> void:
	_walking = Vector2.ZERO
	_turn_remaining_rad = 0.0


## Engage only at actual nearby foot contact, with suitable material and low relative speed.
func try_latch() -> bool:
	if not is_instance_valid(player) or is_attached() or bool(player.get_meta("seated", false)):
		return false
	var grip: PhysicalGrip = player.get_node_or_null("PhysicalGrip") as PhysicalGrip
	if grip != null and grip.is_attached():
		status = "BOOTS | Release your hand grip first"
		return false
	var hit: Dictionary = _foot_ray()
	var body: PhysicsBody3D = hit.get("collider") as PhysicsBody3D
	if body == null or not _magnetic_hit(hit):
		status = "BOOTS | Bring your feet close to a steel deck"
		return false
	var normal: Vector3 = hit.normal
	var height: float = (player.global_position - (hit.position as Vector3)).dot(normal)
	if height < 0.88 or height > 1.05:
		status = "BOOTS | Bring your soles into contact with the deck"
		return false
	if normal.dot(player.global_basis.y) < 0.9:
		status = "BOOTS | Align your feet with the deck"
		return false
	var relative: Vector3 = player.linear_velocity - _point_velocity(body, player.global_position)
	if relative.length() > 0.6:
		status = "BOOTS | Slow your approach before latching"
		return false
	if player.suit.battery_energy_j < ENGAGE_ENERGY_J:
		status = "BOOTS | Battery too low to engage"
		return false
	player.suit.consume_energy(ENGAGE_ENERGY_J)
	_target = body
	_anchor = body.to_local(hit.position)
	_normal = body.global_basis.transposed() * normal
	_height = height
	_heading = body.global_basis.transposed() * (-player.global_basis.z).slide(normal).normalized()
	_turn_remaining_rad = 0.0
	player.surface_motion_active = true
	player.set_motion_input(Vector3.ZERO, 0.0)
	status = "BOOTS LATCHED | WASD walk | B release"
	return true


## Mechanical emergency release costs nothing and preserves motion.
func release() -> void:
	_target = null
	_walking = Vector2.ZERO
	_turn_remaining_rad = 0.0
	if is_instance_valid(player):
		player.surface_motion_active = false
	status = "BOOTS OFF | B latch near a steel deck"


func _physics_process(delta: float) -> void:
	if not is_attached():
		if is_instance_valid(player):
			player.surface_motion_active = false
		return
	var look: Vector2 = player.take_surface_look()
	if player.is_freelooking() or player.is_braking() or player.is_wheel_braking() or player.is_wheel_dumping():
		_turn_remaining_rad = 0.0
	else:
		_turn_remaining_rad += look.x
	var normal: Vector3 = (_target.global_basis * _normal).normalized()
	var anchor: Vector3 = _target.to_global(_anchor)
	var offset: Vector3 = player.global_position - anchor
	var hit: Dictionary = _foot_ray()
	if hit.get("collider") != _target or not _magnetic_hit(hit) or offset.dot(normal) > 1.25 or offset.dot(normal) < 0.7:
		release()
		status = "BOOTS RELEASED | Lost deck contact"
		return
	var relative: Vector3 = player.linear_velocity - _point_velocity(_target, player.global_position)
	var forward: Vector3 = (-player.global_basis.z).slide(normal).normalized()
	var right: Vector3 = forward.cross(normal)
	var walking: Vector3 = (right * _walking.x + forward * _walking.y) * WALK_SPEED_MPS
	var powered: bool = walking.length_squared() > 0.0001
	var turn_step: float = _turn_remaining_rad
	powered = powered or absf(turn_step) > 0.000001
	var fraction: float = 1.0
	if powered:
		# Powered steps have a conservative rated draw above the maximum mechanical output.
		var request: float = delta * 1800.0 * _walking.length() + TURN_ENERGY_J_PER_RAD * absf(turn_step)
		fraction = player.suit.consume_energy(request) / request
		_anchor += _target.global_basis.transposed() * walking * delta * fraction
		_heading = Basis(_normal, turn_step * fraction) * _heading
		_turn_remaining_rad -= turn_step * fraction
	anchor = _target.to_global(_anchor)
	var error: Vector3 = anchor + normal * _height - player.global_position
	if error.slide(normal).length() > 0.45:
		release()
		status = "BOOTS RELEASED | Step obstructed or holding force exceeded"
		return
	var force: Vector3 = error * 16000.0 - relative * 1800.0
	var target_omega: Vector3 = (_target as RigidBody3D).angular_velocity if _target is RigidBody3D else Vector3.ZERO
	var heading: Vector3 = (_target.global_basis * _heading).slide(normal).normalized()
	var wanted: Basis = Basis(heading.cross(normal), normal, -heading).orthonormalized()
	var difference: Quaternion = (wanted * player.global_basis.transposed()).get_rotation_quaternion()
	if difference.w < 0.0:
		difference = -difference
	var torque: Vector3 = difference.get_axis() * difference.get_angle() * 900.0 - (player.angular_velocity - target_omega) * 180.0
	# Foot pivots have finite motor torque. A large requested turn must not
	# instantly overload adhesion before the body has had time to rotate.
	var yaw_torque: float = torque.dot(normal)
	torque += normal * (clampf(yaw_torque, -TURN_TORQUE_NM, TURN_TORQUE_NM) - yaw_torque)
	# Apply forces at one shared point, including the balancing ankle moment.
	var point: Vector3 = player.global_position - normal * _height
	torque -= (point - player.to_global(player.center_of_mass)).cross(force)
	if force.length() > MAX_FORCE_N or torque.length() > MAX_TORQUE_NM:
		release()
		status = "BOOTS RELEASED | Holding force exceeded"
		return
	player.apply_force(force, point - player.global_position)
	player.apply_torque(torque)
	if _target is RigidBody3D and not (_target as RigidBody3D).freeze:
		var rigid: RigidBody3D = _target as RigidBody3D
		rigid.apply_force(-force, point - rigid.global_position)
		rigid.apply_torque(-torque)
	status = "BOOTS WALKING" if powered and fraction > 0.0 else "BOOTS LATCHED | Passive hold | B release"


func _foot_ray() -> Dictionary:
	var origin: Vector3 = player.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin - player.global_basis.y * 1.2, 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _magnetic_hit(hit: Dictionary) -> bool:
	var body: PhysicsBody3D = hit.get("collider") as PhysicsBody3D
	if body == null:
		return false
	var index: int = int(hit.get("shape", -1))
	if index >= 0:
		var owner: Object = body.shape_owner_get_owner(body.shape_find_owner(index))
		if owner != null and owner.has_meta("magnetic_surface"):
			return bool(owner.get_meta("magnetic_surface"))
	return body.is_in_group("magnetic_surface")


func _point_velocity(body: PhysicsBody3D, point: Vector3) -> Vector3:
	if body is RigidBody3D:
		var rigid: RigidBody3D = body as RigidBody3D
		return rigid.linear_velocity + rigid.angular_velocity.cross(point - rigid.to_global(rigid.center_of_mass))
	return Vector3.ZERO


func _exit_tree() -> void:
	release()
