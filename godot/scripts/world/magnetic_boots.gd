## Switchable magnetic soles hold on designated steel surfaces and walk with reaction forces.
class_name MagneticBoots
extends Node

const ENGAGE_ENERGY_J: float = 50.0
const WALK_SPEED_MPS: float = 1.3
const MAX_FORCE_N: float = 3000.0
const MAX_TORQUE_NM: float = 2000.0
const FOOT_HEIGHT_M: float = 0.92
const MAX_STEP_HEIGHT_M: float = 0.30
const STEP_LIFT_SPEED_MPS: float = 0.8

var status: String = "BOOTS OFF | B arm"
var player: Player
var _target: PhysicsBody3D
var _anchor: Vector3
var _normal: Vector3
var _heading: Vector3
var _walking: Vector2 = Vector2.ZERO
var _height: float = FOOT_HEIGHT_M
var _armed: bool = false
var _approach_held: bool = false
var _approaching: bool = false


## Bind the physical suit. The controller runs before suit actuators.
func configure(owner_player: Player) -> void:
	player = owner_player
	process_physics_priority = -10


## True while the soles retain contact with a suitable surface.
func is_attached() -> bool:
	return is_instance_valid(_target)


## True while waiting to engage at safe physical sole contact.
func is_armed() -> bool:
	return _armed


## Hold a paid suit approach while armed; releasing leaves contact detection armed.
func set_approach_held(held: bool) -> void:
	_approach_held = held and _armed and not is_attached()
	if not _approach_held:
		_approaching = false
		if is_instance_valid(player):
			player.set_boot_approach(false)


## True while hold-B has an eligible surface and controls the ordinary suit actuators.
func is_approaching() -> bool:
	return _approaching


## Arm contact detection, or cancel/release if already enabled.
func toggle() -> void:
	if _armed or is_attached():
		release()
		return
	if not is_instance_valid(player) or bool(player.get_meta("seated", false)):
		return
	var grip: PhysicalGrip = player.get_node_or_null("PhysicalGrip") as PhysicalGrip
	if grip != null and grip.is_attached():
		status = "BOOTS OFF | Release your hand grip first"
		return
	_armed = true
	try_latch()


## Report the physical supporting body for frame transitions.
func target_body() -> PhysicsBody3D:
	return _target if is_attached() else null


## Set desired lateral/forward walking; diagonal steps share one speed budget.
func set_walk_input(direction: Vector2) -> void:
	_walking = direction.limit_length(1.0) if direction.is_finite() else Vector2.ZERO


## Cancel walking and held approach when a panel or focus takes control.
func cancel_input() -> void:
	set_approach_held(false)
	_walking = Vector2.ZERO


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
		_waiting("Bring your soles to a steel surface")
		return false
	var normal: Vector3 = hit.normal
	var height: float = (player.global_position - (hit.position as Vector3)).dot(normal)
	if height < 0.88 or height > 1.05:
		_waiting("Bring your soles into contact with a steel surface")
		return false
	if normal.dot(player.global_basis.y) < 0.9:
		_waiting("Align your soles with the steel surface")
		return false
	# A slanted sole ray can put the spring anchor far beside the suit. Reject
	# that catch before paying, reserving force for damping and later disturbances.
	var catch_error: Vector3 = (hit.position as Vector3) + normal * height - player.global_position
	if catch_error.length() * 16000.0 > MAX_FORCE_N * 0.5:
		_waiting("Align your soles with the steel surface | Hold B to approach")
		return false
	if _approach_held:
		var carrier_omega: Vector3 = (body as RigidBody3D).angular_velocity if body is RigidBody3D else Vector3.ZERO
		if normal.dot(player.global_basis.y) < 0.997 or (player.angular_velocity - carrier_omega).length() > 0.25:
			return false
	var relative: Vector3 = player.linear_velocity - _point_velocity(body, player.global_position)
	if relative.length() > 0.6:
		_waiting("Slow your approach before latching")
		return false
	if player.suit.battery_energy_j < ENGAGE_ENERGY_J:
		_waiting("Battery too low to engage")
		return false
	player.suit.consume_energy(ENGAGE_ENERGY_J)
	set_approach_held(false)
	_armed = false
	_target = body
	_anchor = body.to_local(hit.position)
	_normal = body.global_basis.transposed() * normal
	_height = height
	_heading = body.global_basis.transposed() * (-player.global_basis.z).slide(normal).normalized()
	player.surface_motion_active = true
	player.set_motion_input(Vector3.ZERO, 0.0)
	status = "BOOTS LATCHED | WASD walk | B release"
	return true


## Mechanical emergency release costs nothing and preserves motion.
func release() -> void:
	set_approach_held(false)
	_armed = false
	_target = null
	_walking = Vector2.ZERO
	if is_instance_valid(player):
		player.surface_motion_active = false
	status = "BOOTS OFF | B arm"


func _physics_process(delta: float) -> void:
	if is_instance_valid(player):
		player.set_boot_approach(false)
	_approaching = false
	if _armed and is_instance_valid(player):
		var grip: PhysicalGrip = player.get_node_or_null("PhysicalGrip") as PhysicalGrip
		if bool(player.get_meta("seated", false)) or (grip != null and grip.is_attached()):
			release()
		else:
			try_latch()
	if not is_attached():
		if _approach_held and _armed:
			_update_approach()
		if is_instance_valid(player):
			player.surface_motion_active = false
		return
	player.take_surface_look()
	var normal: Vector3 = (_target.global_basis * _normal).normalized()
	var anchor: Vector3 = _target.to_global(_anchor)
	var offset: Vector3 = player.global_position - anchor
	var hit: Dictionary = _support_ray(player.global_position, normal)
	if hit.get("collider") != _target or not _magnetic_hit(hit) or offset.dot(normal) > 1.3 or offset.dot(normal) < 0.55:
		release()
		status = "BOOTS RELEASED | Lost surface contact | B rearm"
		return
	var relative: Vector3 = player.linear_velocity - _point_velocity(_target, player.global_position)
	var forward: Vector3 = (-(player.get_node("Camera3D") as Camera3D).global_basis.z).slide(normal).normalized()
	var right: Vector3 = forward.cross(normal)
	var walking: Vector3 = (right * _walking.x + forward * _walking.y) * WALK_SPEED_MPS
	var powered: bool = walking.length_squared() > 0.0001
	var fraction: float = 1.0
	if powered:
		fraction = player.suit.consume_energy(delta * 5000.0 * _walking.length()) / (delta * 5000.0 * _walking.length())
		var surface: Vector3 = hit.position
		var support_height: float = surface.dot(normal)
		var desired_height: float = support_height
		var blocked: bool = false
		# Sample the soles' footprint and a leading step before driving into a riser.
		var direction: Vector3 = walking.normalized()
		for sample: Vector3 in [Vector3.ZERO, direction * 0.1, direction * 0.2, direction * 0.3, direction * 0.4, direction * 0.5, direction * 0.60, direction * -0.1, direction * -0.2, direction * -0.34, right * 0.32, right * -0.32]:
			var support: Dictionary = _support_ray(surface + sample + normal * 1.0, normal)
			if support.get("collider") != _target or not _magnetic_hit(support) or (support.normal as Vector3).dot(normal) < 0.95:
				if sample == direction * 0.60:
					blocked = true
				continue
			var candidate_height: float = (support.position as Vector3).dot(normal)
			if candidate_height - support_height > MAX_STEP_HEIGHT_M + 0.002:
				blocked = true
			else:
				desired_height = maxf(desired_height, candidate_height)
		# Chest-height obstructions never become climbing steps.
		var wall_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position, player.global_position + direction * 0.55, 1, [player.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(wall_query).is_empty():
			blocked = true
		var rise: float = desired_height + _height - player.global_position.dot(normal)
		if rise > 0.025 and not _clear_step(normal * rise):
			blocked = true
			desired_height = anchor.dot(normal)
		var elevation: float = move_toward(anchor.dot(normal), desired_height, STEP_LIFT_SPEED_MPS * delta * fraction * _walking.length())
		anchor += normal * (elevation - anchor.dot(normal))
		var clearance: float = player.global_position.dot(normal) - _height - desired_height
		if not blocked and clearance > -0.045:
			anchor += walking * delta * fraction
		# A wall can oppose the motor indefinitely without an ever-receding anchor.
		var lead: Vector3 = (anchor - player.global_position).slide(normal)
		anchor -= lead - lead.limit_length(0.12)
		_anchor = _target.to_local(anchor)
	anchor = _target.to_global(_anchor)
	var error: Vector3 = anchor + normal * _height - player.global_position
	if error.slide(normal).length() > 0.45:
		release()
		status = "BOOTS RELEASED | Step obstructed or holding force exceeded | B rearm"
		return
	var force: Vector3 = error * 16000.0 - relative * 1800.0
	var target_omega: Vector3 = (_target as RigidBody3D).angular_velocity if _target is RigidBody3D else Vector3.ZERO
	var heading: Vector3 = (_target.global_basis * _heading).slide(normal).normalized()
	var wanted: Basis = Basis(heading.cross(normal), normal, -heading).orthonormalized()
	var difference: Quaternion = (wanted * player.global_basis.transposed()).get_rotation_quaternion()
	if difference.w < 0.0:
		difference = -difference
	var torque: Vector3 = difference.get_axis() * difference.get_angle() * 900.0 - (player.angular_velocity - target_omega) * 180.0
	# Apply forces at one shared point, including the balancing ankle moment.
	var point: Vector3 = player.global_position - normal * _height
	torque -= (point - player.to_global(player.center_of_mass)).cross(force)
	if force.length() > MAX_FORCE_N or torque.length() > MAX_TORQUE_NM:
		release()
		status = "BOOTS RELEASED | Holding force exceeded | B rearm"
		return
	player.apply_force(force, point - player.global_position)
	player.apply_torque(torque)
	if _target is RigidBody3D and not (_target as RigidBody3D).freeze:
		var rigid: RigidBody3D = _target as RigidBody3D
		rigid.apply_force(-force, point - rigid.global_position)
		rigid.apply_torque(-torque)
	status = "BOOTS WALKING" if powered and fraction > 0.0 else "BOOTS LATCHED | Passive hold | B release"


func _update_approach() -> void:
	if player.is_braking() or player.is_wheel_braking() or player.is_wheel_dumping() or player.freeze:
		set_approach_held(false)
		return
	var hit: Dictionary = _nearest_approach_surface()
	if hit.is_empty():
		status = "BOOTS ARMED | No clear steel surface within 3 m | Release B to wait"
		return
	var target: PhysicsBody3D = hit.collider
	var normal: Vector3 = hit.normal
	var goal: Vector3 = (hit.position as Vector3) + normal * 0.95
	var relative: Vector3 = player.linear_velocity - _point_velocity(target, player.global_position)
	var target_omega: Vector3 = (target as RigidBody3D).angular_velocity if target is RigidBody3D else Vector3.ZERO
	var omega: Vector3 = player.global_basis.transposed() * (player.angular_velocity - target_omega)
	var axis: Vector3 = player.global_basis.y.cross(normal)
	var angle: float = acos(clampf(player.global_basis.y.dot(normal), -1.0, 1.0))
	if axis.length_squared() < 0.000001:
		axis = player.global_basis.x
	var error: Vector3 = player.global_basis.transposed() * axis.normalized() * angle
	var inverse: Basis = player.global_basis.transposed() * player.get_inverse_inertia_tensor() * player.global_basis
	if inverse.determinant() <= 0.0:
		return
	var desired_omega: Vector3 = Vector3.ZERO
	for component: int in 3:
		var acceleration: float = maxf(inverse[component][component] * player.roll_torque_nm, 0.0)
		desired_omega[component] = signf(error[component]) * minf(absf(error[component]) * 3.0, sqrt(1.4 * acceleration * absf(error[component])))
	var torque: Vector3 = inverse.inverse() * (desired_omega - omega) * 6.0
	var desired_velocity: Vector3 = Vector3.ZERO
	var path_clear: bool = true
	var clearance: float = (player.global_position - (hit.position as Vector3)).dot(normal)
	if angle >= 0.08 and clearance < 0.94:
		# A sideways suit lying on the deck needs room to rotate its full capsule.
		# Back away using ordinary jets first; do not lever its head into the floor.
		var retreat: Vector3 = normal * (0.98 - clearance)
		path_clear = _clear_step(retreat)
		if path_clear:
			desired_velocity = (retreat * 1.2).limit_length(0.25)
		torque = inverse.inverse() * -omega * 6.0
	elif angle < 0.08 and omega.length() < 0.25:
		var travel: Vector3 = goal - player.global_position
		path_clear = _clear_step(travel)
		if path_clear:
			desired_velocity = (travel * 1.2).limit_length(0.25)
	var force: Vector3 = ((desired_velocity - relative) * player.mass * 3.0).limit_length(player.thrust_force_n)
	player.set_boot_approach(true, force, torque)
	_approaching = true
	status = "BOOTS APPROACH | Release B to stop | Uses suit fuel and charge" if path_clear else "BOOTS APPROACH | Path blocked | Release B to stop"


func _nearest_approach_surface() -> Dictionary:
	var nearest: Dictionary = {}
	var distance: float = 3.0001
	var directions: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	# Exact box-face candidates cover narrow steel parts that angular ray sampling
	# could miss. The confirming ray still rejects an intervening obstruction.
	var vicinity: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 3.0
	vicinity.shape = sphere
	vicinity.transform.origin = player.global_position
	vicinity.collision_mask = 1
	vicinity.exclude = [player.get_rid()]
	for candidate: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(vicinity, 128):
		var body: PhysicsBody3D = candidate.get("collider") as PhysicsBody3D
		if body == null:
			continue
		var shape_index: int = int(candidate.get("shape", -1))
		if shape_index < 0:
			continue
		var owner: CollisionShape3D = body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as CollisionShape3D
		if owner == null or not owner.shape is BoxShape3D:
			continue
		var half_size: Vector3 = (owner.shape as BoxShape3D).size * 0.5
		var local: Vector3 = owner.to_local(player.global_position)
		var closest: Vector3 = local.clamp(-half_size, half_size)
		var difference: Vector3 = owner.to_global(closest) - player.global_position
		if difference.length_squared() > 0.000001:
			directions.append(difference.normalized())
	# Uniform rays find nearby surfaces on every side, independent of camera aim.
	for sample: int in 96:
		var y: float = 1.0 - 2.0 * (float(sample) + 0.5) / 96.0
		var radius: float = sqrt(1.0 - y * y)
		var angle: float = float(sample) * 2.399963229728653
		directions.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for direction: Vector3 in directions:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position, player.global_position + direction * 3.0, 1, [player.get_rid()])
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or not _magnetic_hit(hit):
			continue
		var candidate: float = player.global_position.distance_to(hit.position)
		if candidate < distance:
			distance = candidate
			nearest = hit
	return nearest


func _clear_step(lift: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = player.global_transform
	query.motion = lift
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var fractions: PackedFloat32Array = player.get_world_3d().direct_space_state.cast_motion(query)
	return fractions[0] >= 0.999


func _support_ray(origin: Vector3, normal: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin - normal * 1.65, 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _foot_ray() -> Dictionary:
	var origin: Vector3 = player.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin - player.global_basis.y * 1.2, 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _waiting(reason: String) -> void:
	status = "BOOTS ARMED | " + reason + " | B cancel" if _armed else "BOOTS | " + reason


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
