## Suit grapple: a single surface anchor, powered reel, and passive elastic tether.
## Equal opposite tension moves lighter bodies more and can spin off-centre debris.
class_name Grapple
extends Node3D

const MAX_LENGTH_M: float = 30.0
const MIN_LENGTH_M: float = 1.0

@export var reel_speed_mps: float = 2.0
@export var spring_n_per_m: float = 200.0
@export var damping_ns_per_m: float = 50.0
@export var max_tension_n: float = 300.0
@export var attach_energy_j: float = 100.0
@export var reel_power_w: float = 1000.0

var cable_length_m: float:
	get:
		return _cable_length_m
var status: String = "READY"

var _body: RigidBody3D
var _stores: SuitResources
var _camera: Camera3D
var _target: PhysicsBody3D
var _local_anchor: Vector3 = Vector3.ZERO
var _cable_length_m: float = 0.0
var _reel_input: float = 0.0
var _attach_requested: bool = false
var _cable: MeshInstance3D


func _ready() -> void:
	_cable = MeshInstance3D.new()
	_cable.name = "TetherVisual"
	_cable.top_level = true
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	_cable.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.8, 0.95)
	_cable.material_override = material
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cable.visible = false
	add_child(_cable)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_body) or not _body.is_inside_tree() or _stores == null:
		return
	if _attach_requested:
		_attach_requested = false
		_cast_from_camera()
	if not is_attached():
		if _target != null:
			DebugLog.event("grapple", "cable lost target")
			_teardown()
			status = "TARGET LOST"
		return
	var anchor: Vector3 = get_anchor_position()
	var distance: float = _body.global_position.distance_to(anchor)
	if distance > MAX_LENGTH_M:
		DebugLog.event("grapple", "cable limit: %.1f m exceeds %.0f m max, detached from %s" % [distance, MAX_LENGTH_M, _target.name])
		_teardown()
		status = "OUT OF RANGE"
		return
	if _line_blocked(anchor):
		DebugLog.event("grapple", "cable blocked: line of sight lost to %s" % _target.name)
		_teardown()
		status = "TETHER BLOCKED"
		return
	status = "TETHER HELD"
	_advance_reel(delta)
	_apply_tension(anchor, distance)


func _process(_delta: float) -> void:
	_cable.visible = is_attached()
	if not _cable.visible:
		return
	var start: Vector3 = _body.global_position
	var offset: Vector3 = get_anchor_position() - start
	var distance: float = offset.length()
	if distance < 0.001:
		_cable.visible = false
		return
	var orientation: Basis = Basis(Quaternion(Vector3.UP, offset / distance))
	_cable.global_transform = Transform3D(orientation * Basis.from_scale(Vector3(1, distance, 1)), start + offset * 0.5)


## Connect this tool to a suit body, its resource stores, and its aiming camera.
func configure(body: RigidBody3D, stores: SuitResources, camera: Camera3D) -> void:
	detach()
	_body = body
	_stores = stores
	_camera = camera


## Queue one aiming ray for the next physics tick, when collision queries are safe.
func request_attach() -> void:
	_attach_requested = true
	DebugLog.event("grapple", "fired")


## Attach to a known surface point; callers performing selection must raycast first.
func attach_to(target: PhysicsBody3D, world_point: Vector3) -> bool:
	if not is_instance_valid(_body) or not _body.is_inside_tree() or _stores == null:
		return false
	if not is_instance_valid(target) or not target.is_inside_tree() or target == _body or not world_point.is_finite():
		return false
	if not (target is RigidBody3D or target is StaticBody3D):
		status = "UNSUPPORTED SURFACE"
		DebugLog.event("grapple", "attach refused: unsupported surface (%s)" % target.name)
		return false
	var distance: float = _body.global_position.distance_to(world_point)
	if distance > MAX_LENGTH_M or distance < 0.001:
		status = "OUT OF RANGE"
		DebugLog.event("grapple", "attach refused: %.1f m out of range" % distance)
		return false
	var cost: float = maxf(attach_energy_j, 0.0)
	if _stores.battery_energy_j < cost:
		status = "INSUFFICIENT BATTERY"
		DebugLog.event("grapple", "attach refused: battery too low, needs %.0f J" % cost)
		return false
	_stores.consume_energy(cost)
	_target = target
	_local_anchor = target.to_local(world_point)
	_cable_length_m = clampf(distance, MIN_LENGTH_M, MAX_LENGTH_M)
	status = "ATTACHED"
	DebugLog.event("grapple", "attached to %s at %.1f m" % [target.name, _cable_length_m])
	return true


## Release the tether without changing either body's momentum or spending power.
func detach() -> void:
	if is_attached():
		DebugLog.event("grapple", "detached from %s" % _target.name)
	_teardown()


func _teardown() -> void:
	_target = null
	_cable_length_m = 0.0
	_attach_requested = false
	status = "READY"
	if is_instance_valid(_cable):
		_cable.visible = false


## Set signed reel input: positive winds in, negative pays out, zero holds length.
func set_reel_input(direction: float) -> void:
	_reel_input = clampf(direction, -1.0, 1.0) if is_finite(direction) else 0.0


## Stop motor input and discard pending shots on focus loss; keep the physical tether.
func cancel_input() -> void:
	_reel_input = 0.0
	_attach_requested = false


## Return whether both ends of the tether still exist in the scene.
func is_attached() -> bool:
	return is_instance_valid(_target) and _target.is_inside_tree() and is_instance_valid(_body) and _body.is_inside_tree()


## Return the surface anchor in the current world frame, following target rotation.
func get_anchor_position() -> Vector3:
	return _target.to_global(_local_anchor) if is_attached() else Vector3.ZERO


func _cast_from_camera() -> void:
	if not is_instance_valid(_camera):
		return
	var start: Vector3 = _camera.global_position
	var end: Vector3 = start - _camera.global_basis.z * MAX_LENGTH_M
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end, _body.collision_mask, [_body.get_rid()])
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		status = "NO SURFACE WITHIN 30 m"
		DebugLog.event("grapple", "attach refused: no surface within 30 m")
		return
	var target: PhysicsBody3D = hit.get("collider") as PhysicsBody3D
	var point: Vector3 = hit.get("position", Vector3.ZERO)
	attach_to(target, point)


func _line_blocked(anchor: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_body.global_position, anchor, _body.collision_mask, [_body.get_rid(), _target.get_rid()]
	)
	query.hit_from_inside = true
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _advance_reel(delta: float) -> void:
	if _reel_input == 0.0 or reel_speed_mps <= 0.0 or delta <= 0.0:
		return
	var requested_length: float = clampf(_cable_length_m - _reel_input * reel_speed_mps * delta, MIN_LENGTH_M, MAX_LENGTH_M)
	var travel: float = absf(requested_length - _cable_length_m)
	if travel <= 0.0:
		status = "REEL LIMIT"
		return
	var cost: float = travel / reel_speed_mps * maxf(reel_power_w, 0.0)
	var fraction: float = 1.0
	if cost > 0.0:
		fraction = _stores.consume_energy(cost) / cost
	_cable_length_m = lerpf(_cable_length_m, requested_length, fraction)
	status = "REEL IN" if _reel_input > 0.0 else "REEL OUT"
	if fraction < 1.0:
		status = "BATTERY EMPTY: TETHER HELD"


func _apply_tension(anchor: Vector3, distance: float) -> void:
	var extension: float = distance - _cable_length_m
	if extension <= 0.0 or distance < 0.001:
		return # A slack tether cannot push its ends apart.
	var direction: Vector3 = (anchor - _body.global_position) / distance
	var anchor_velocity: Vector3 = Vector3.ZERO
	var target_body: RigidBody3D = _target as RigidBody3D
	if target_body != null and not target_body.freeze:
		var centre: Vector3 = target_body.to_global(target_body.center_of_mass)
		anchor_velocity = target_body.linear_velocity + target_body.angular_velocity.cross(anchor - centre)
	var separation_speed: float = (anchor_velocity - _body.linear_velocity).dot(direction)
	var tension: float = clampf(extension * spring_n_per_m + separation_speed * damping_ns_per_m, 0.0, maxf(max_tension_n, 0.0))
	var force: Vector3 = direction * tension
	_body.apply_central_force(force)
	if target_body != null and not target_body.freeze:
		target_body.apply_force(-force, anchor - target_body.global_position)
