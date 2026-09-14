## Suit-carried winch kits: place two anchored devices within reach and let a
## powered cable reel them together. Owns placement/removal and the list of
## live WinchLink nodes; the physics and visuals of a single link live there.
class_name SuitWinch
extends RefCounted

const MAX_REACH_M: float = 2.0
const MAX_CABLE_M: float = 30.0
const MAX_KITS: int = 4
const AIM_TOLERANCE_M: float = 0.35

var status: String = "WINCH | Left: place device on first object (4 kits)"
var kits_available: int = MAX_KITS

var _player: Player
var _camera: Camera3D
var _links_parent: Node3D
var _links: Array[WinchLink] = []

var _pending_body: PhysicsBody3D
var _pending_local_anchor: Vector3 = Vector3.ZERO
var _pending_local_normal: Vector3 = Vector3.UP
var _pending_part_id: String = ""
var _pending_wreck: SalvageWreck
var _pending_part_anchor: Vector3 = Vector3.ZERO
var _pending_part_normal: Vector3 = Vector3.UP
var _pending_device: MeshInstance3D
var _pending_cable: MeshInstance3D


## Share the suit, its aiming camera, and the stable world node links attach under.
func configure(player: Player, camera: Camera3D, links_parent: Node3D) -> void:
	_player = player
	_camera = camera
	_links_parent = links_parent


## Refresh the status readout; call every physics tick regardless of input.
func update(_delta: float) -> void:
	if _pending_body != null:
		if not is_instance_valid(_pending_body):
			_clear_pending(true)
		else:
			_update_pending_visuals()
			_update_pending_status()
			return
	var aimed: WinchLink = _aimed_link()
	if aimed != null:
		status = "WINCH %d | %s" % [_links.find(aimed) + 1, aimed.status]
	else:
		status = "WINCH | Left: place device on first object (%d kits)" % kits_available


## Left click: place the first device, or the second to complete a link.
func place() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_camera):
		return
	if _pending_body != null:
		_place_second()
	else:
		_place_first()


## Right click: pick a pending device back up, or remove the winch aimed at.
func remove() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_camera):
		return
	if _pending_body != null:
		_cancel_pending()
		return
	var aimed: WinchLink = _aimed_link()
	if aimed == null:
		status = "WINCH | No device aimed within reach"
		return
	aimed.detach_now("WINCH REMOVED")


func _place_first() -> void:
	if kits_available <= 0:
		status = "WINCH | No kits remaining"
		return
	var hit: Dictionary = _ray()
	if hit.is_empty():
		status = "WINCH | No surface within 2 m"
		return
	var body: PhysicsBody3D = hit.collider as PhysicsBody3D
	if body == null or body == _player or not (body is RigidBody3D or body is StaticBody3D):
		status = "WINCH | Unsupported surface"
		return
	var point: Vector3 = hit.position
	_pending_body = body
	_pending_local_anchor = body.to_local(point)
	_pending_local_normal = body.global_basis.inverse() * (hit.normal as Vector3)
	_pending_part_id = ""
	_pending_wreck = null
	_pending_part_anchor = Vector3.ZERO
	_pending_part_normal = Vector3.UP
	if body is WreckBody:
		var wreck_body: WreckBody = body as WreckBody
		_pending_part_id = wreck_body.part_at_shape(int(hit.shape))
		_pending_wreck = wreck_body.wreck
		if not _pending_part_id.is_empty():
			var pose: Transform3D = _pending_wreck.part_pose(_pending_part_id)
			_pending_part_anchor = pose.affine_inverse() * point
			_pending_part_normal = pose.basis.inverse() * (hit.normal as Vector3)
	kits_available -= 1
	# Until the second device is placed, show the first one with slack cable back to the suit.
	_pending_device = WinchLink.make_device_mesh()
	_pending_cable = WinchLink.make_cable_mesh()
	_links_parent.add_child(_pending_device)
	_links_parent.add_child(_pending_cable)
	_update_pending_visuals()
	DebugLog.event("winch", "placed device A on %s" % body.name)


func _place_second() -> void:
	if not is_instance_valid(_pending_body):
		_clear_pending(true)
		return
	var hit: Dictionary = _ray()
	if hit.is_empty():
		return
	var body: PhysicsBody3D = hit.collider as PhysicsBody3D
	if body == null or not (body is RigidBody3D or body is StaticBody3D):
		return
	if body == _pending_body:
		status = "PICK A DIFFERENT OBJECT"
		return
	var point: Vector3 = hit.position
	var distance: float = _pending_body.to_global(_pending_local_anchor).distance_to(point)
	if distance > MAX_CABLE_M:
		status = "CABLE TOO SHORT: 30 m"
		return
	_create_link(body, point, hit.normal as Vector3, int(hit.shape))


func _create_link(body_b: PhysicsBody3D, point_b: Vector3, normal_b: Vector3, shape_b: int) -> void:
	var link: WinchLink = WinchLink.new()
	link.name = "WinchLink"
	_links_parent.add_child(link)
	link.attach_a(_pending_body, _pending_local_anchor, _pending_local_normal, _pending_part_id, _pending_wreck, _pending_part_anchor, _pending_part_normal)
	var part_id_b: String = ""
	var wreck_b: SalvageWreck = null
	var part_anchor_b: Vector3 = Vector3.ZERO
	var part_normal_b: Vector3 = Vector3.UP
	if body_b is WreckBody:
		var wreck_body: WreckBody = body_b as WreckBody
		part_id_b = wreck_body.part_at_shape(shape_b)
		wreck_b = wreck_body.wreck
		if not part_id_b.is_empty():
			var pose: Transform3D = wreck_b.part_pose(part_id_b)
			part_anchor_b = pose.affine_inverse() * point_b
			part_normal_b = pose.basis.inverse() * normal_b
	link.attach_b(body_b, body_b.to_local(point_b), body_b.global_basis.inverse() * normal_b, part_id_b, wreck_b, part_anchor_b, part_normal_b)
	link.finish_setup()
	link.detached.connect(_on_link_detached.bind(link))
	_links.append(link)
	var placed_on: String = _pending_body.name
	DebugLog.event("winch", "linked %s to %s" % [placed_on, body_b.name])
	_clear_pending(false)
	status = "WINCH LINKED"


func _cancel_pending() -> void:
	DebugLog.event("winch", "picked device A back up")
	_clear_pending(true)
	status = "WINCH | Left: place device on first object (%d kits)" % kits_available


func _clear_pending(return_kit: bool) -> void:
	if return_kit:
		kits_available = mini(kits_available + 1, MAX_KITS)
	_pending_body = null
	_pending_part_id = ""
	_pending_wreck = null
	for mesh: MeshInstance3D in [_pending_device, _pending_cable]:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_pending_device = null
	_pending_cable = null


func _update_pending_visuals() -> void:
	if not is_instance_valid(_pending_device) or not is_instance_valid(_pending_cable) or not is_instance_valid(_pending_body):
		return
	WinchLink.place_device(_pending_device, _pending_body, _pending_local_anchor, _pending_local_normal)
	WinchLink.place_cable(_pending_cable, _pending_body.to_global(_pending_local_anchor), _player.global_position)


func _update_pending_status() -> void:
	var device_name: String = _pending_body.name
	var hit: Dictionary = _ray()
	if hit.is_empty():
		status = "WINCH | Device on %s | place second device within reach" % device_name
		return
	var body: Object = hit.get("collider")
	if body == _pending_body:
		status = "PICK A DIFFERENT OBJECT"
		return
	var distance: float = _pending_body.to_global(_pending_local_anchor).distance_to(hit.position as Vector3)
	if distance > MAX_CABLE_M:
		status = "CABLE TOO SHORT: 30 m"
		return
	status = "WINCH | Device on %s | place second device within reach | cable %.1f / %d m" % [device_name, distance, int(MAX_CABLE_M)]


func _on_link_detached(reason: String, link: WinchLink) -> void:
	_links.erase(link)
	kits_available = mini(kits_available + 1, MAX_KITS)
	DebugLog.event("winch", reason)
	status = reason


func _aimed_link() -> WinchLink:
	if not is_instance_valid(_camera):
		return null
	var origin: Vector3 = _camera.global_position
	var direction: Vector3 = -_camera.global_basis.z
	var best: WinchLink = null
	var best_distance: float = AIM_TOLERANCE_M
	for link: WinchLink in _links:
		for point: Vector3 in [link.anchor_a_position(), link.anchor_b_position()]:
			var to_point: Vector3 = point - origin
			var along: float = to_point.dot(direction)
			if along < 0.0 or along > MAX_REACH_M:
				continue
			var perpendicular: float = (to_point - direction * along).length()
			if perpendicular < best_distance:
				best_distance = perpendicular
				best = link
	return best


func _ray() -> Dictionary:
	var origin: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin - _camera.global_basis.z * MAX_REACH_M, 1, [_player.get_rid()])
	return _player.get_world_3d().direct_space_state.intersect_ray(query)
