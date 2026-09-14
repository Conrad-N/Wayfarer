## Cutter, suit winch, and stationary scanner on the EVA suit. Grapple selection
## is handled by Player directly; the physical hand grip (G) works with any tool.
class_name SalvageTools
extends Node3D

enum Tool { GRAPPLE, CUTTER, WINCH, SCANNER }

var selected: Tool = Tool.GRAPPLE
var status: String = "Grapple ready"
var heat: float = 0.0
var scan_progress: float = 0.0
var target_readout: String = ""
var _overheated: bool = false
var _primary: bool = false
var _secondary: bool = false
var _winch_request: int = 0
var _player: Player
var _camera: Camera3D
var _wreck: SalvageWreck
var _hazards: SalvageHazards
var _winch: SuitWinch
var _scan_basis: Basis = Basis.IDENTITY
var _beam: MeshInstance3D
var _beam_end: Vector3
var _beam_visible: bool = false


## Share the player's finite tool battery and the current salvage scene. Winch
## links attach under links_parent (a stable world node) so they outlive tool
## switches and do not move with the suit; defaults to this node if omitted.
func configure(player: Player, wreck: SalvageWreck, hazards: SalvageHazards, links_parent: Node3D = null) -> void:
	_player = player
	_camera = player.get_node("Camera3D") as Camera3D
	_wreck = wreck
	_hazards = hazards
	_scan_basis = _camera.global_basis
	_winch = SuitWinch.new()
	_winch.configure(_player, _camera, links_parent if links_parent != null else self)


## Switch tools without carrying a held trigger or reel command into the next tool.
func select_tool(tool: Tool) -> void:
	selected = tool
	cancel_input()
	if is_instance_valid(_player):
		_player.grapple.cancel_input()
	var winch_status: String = _winch.status if is_instance_valid(_winch) else "WINCH | Left: place device on first object"
	status = ["Grapple ready", "Aim at a gold cut point", winch_status, "Hold still to scan"][selected]


## Supply held tool controls; the winch uses a press edge to place or remove a device.
func set_triggers(primary: bool, secondary: bool) -> void:
	if selected == Tool.WINCH:
		if secondary and not _secondary:
			_winch_request = -1
		elif primary and not _primary:
			_winch_request = 1
	_primary = primary
	_secondary = secondary


## Release controls on Escape, focus loss, or a tool switch.
func cancel_input() -> void:
	_primary = false
	_secondary = false
	_winch_request = 0
	scan_progress = 0.0
	_beam_visible = false


func _ready() -> void:
	_beam = MeshInstance3D.new()
	_beam.top_level = true
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = 1.0
	mesh.radial_segments = 6
	_beam.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.6, 0.1)
	_beam.material_override = material
	_beam.visible = false
	add_child(_beam)


func _physics_process(delta: float) -> void:
	if is_instance_valid(_winch):
		# Refresh status before acting on a press edge, so a placement or removal
		# outcome this tick (an error or a new link) is what the HUD shows next,
		# not immediately overwritten by the steady-state text.
		_winch.update(delta)
		if _winch_request != 0:
			if _winch_request > 0:
				_winch.place()
			else:
				_winch.remove()
			_winch_request = 0
	if not is_instance_valid(_player) or not is_instance_valid(_wreck):
		return
	_inspect_target()
	_beam_visible = false
	if not (selected == Tool.CUTTER and _primary and not _overheated):
		heat = maxf(0.0, heat - delta * 0.18)
	if _overheated and heat <= 0.25:
		_overheated = false
	match selected:
		Tool.CUTTER:
			_cutter(delta)
		Tool.WINCH:
			status = _winch.status
		Tool.SCANNER:
			_scanner(delta)
	if selected == Tool.CUTTER and _primary and not _overheated and not _beam_visible:
		heat = maxf(0.0, heat - delta * 0.18)
	_scan_basis = _camera.global_basis


func _process(_delta: float) -> void:
	_beam.visible = _beam_visible
	if not _beam_visible or not is_instance_valid(_player):
		return
	var start: Vector3 = _camera.global_position - _camera.global_basis.y * 0.18
	var offset: Vector3 = _beam_end - start
	if offset.length() < 0.01:
		_beam.visible = false
		return
	var basis: Basis = Basis(Quaternion(Vector3.UP, offset.normalized())) * Basis.from_scale(Vector3(1, offset.length(), 1))
	_beam.global_transform = Transform3D(basis, start + offset * 0.5)


func _ray(range_m: float, mask: int = 1, areas: bool = false) -> Dictionary:
	var start: Vector3 = _camera.global_position
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, start - _camera.global_basis.z * range_m, mask, [_player.get_rid()])
	query.collide_with_areas = areas
	query.collide_with_bodies = not areas
	return get_world_3d().direct_space_state.intersect_ray(query)


func _inspect_target() -> void:
	target_readout = ""
	var hit: Dictionary = _ray(20.0)
	var body: WreckBody = hit.get("collider") as WreckBody
	if body == null:
		return
	var part: ShipPart = _wreck.graph.get_part(body.part_at_shape(int(hit.shape)))
	if part == null:
		return
	if not part.scanned:
		target_readout = "UNSCANNED PART | Use 4 to reveal mass, condition, value, and hazards"
		return
	target_readout = "%s / %s | %.0f kg | %.0f%% | %.0f cr" % [part.id, part.definition.kind, part.definition.mass_kg, part.condition * 100.0, part.salvage_value()]
	for hazard: Dictionary in part.definition.hazards:
		target_readout += " | " + str(hazard.kind).to_upper()
	if _hazards.was_triggered(part.id):
		target_readout += " (RUPTURED)"


func _cutter(delta: float) -> void:
	if _overheated:
		status = "CUTTER cooling | %.0f%% heat" % (heat * 100.0)
		return
	if not _primary:
		status = "CUTTER | Hold left click on a gold joint | %.0f%% heat" % (heat * 100.0)
		return
	var hit: Dictionary = _ray(8.0, 2, true)
	if hit.is_empty():
		status = "CUTTER | No joint within 8 m"
		return
	var marker: Area3D = hit.collider as Area3D
	if marker == null or not marker.has_meta("edge_id"):
		return
	var part_id: String = str(marker.get_meta("part_id"))
	var solid: Dictionary = _ray(_camera.global_position.distance_to(marker.global_position))
	if not solid.is_empty():
		var body: WreckBody = solid.collider as WreckBody
		if body == null or body.part_at_shape(int(solid.shape)) != part_id:
			status = "CUTTER | Joint blocked by material"
			return
	var powered_time: float = minf(delta, maxf(0.0, 1.0 - heat) / 0.24)
	var seconds: float = _player.suit.consume_energy(powered_time * 1200.0) / 1200.0
	if seconds <= 0.0:
		status = "CUTTER | Battery empty"
		return
	_beam_end = marker.global_position
	_beam_visible = true
	heat = minf(1.0, heat + seconds * 0.24)
	var edge: String = str(marker.get_meta("edge_id"))
	_hazards.trigger(part_id)
	_wreck.cut(edge, seconds, part_id)
	status = "CUTTER | %s %.0f%% | %.0f%% heat" % [edge.trim_prefix("Joint_"), float(_wreck.cut_progress.get(edge, 0.0)) * 100.0, heat * 100.0]
	if heat >= 1.0:
		_overheated = true


func _scanner(delta: float) -> void:
	if not _primary:
		scan_progress = 0.0
		status = "SCANNER | Hold left click and stay still | 20 m"
		return
	var angle: float = _scan_basis.get_rotation_quaternion().angle_to(_camera.global_basis.get_rotation_quaternion())
	if _player.linear_velocity.length() > 0.2 or _player.angular_velocity.length() > 0.1 or angle > 0.01:
		scan_progress = 0.0
		status = "SCANNER | Hold Alt to settle; keep aim still"
		return
	if scan_progress >= 1.0:
		return
	var seconds: float = _player.suit.consume_energy(delta * 150.0) / 150.0
	if seconds <= 0.0:
		status = "SCANNER | Battery empty"
		return
	scan_progress = minf(1.0, scan_progress + seconds / 2.0)
	status = "SCANNER | %.0f%%" % (scan_progress * 100.0)
	if scan_progress < 1.0:
		return
	var count: int = 0
	for id: String in _wreck.graph.part_ids():
		if _wreck.body_for_part(id) == null:
			continue
		if _camera.global_position.distance_to(_wreck.part_pose(id).origin) <= 20.0:
			_wreck.graph.get_part(id).scanned = true
			count += 1
	status = "SCANNER | Revealed %d parts; cyan coolant / orange fuel" % count
