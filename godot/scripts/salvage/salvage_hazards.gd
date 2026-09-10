## Finite coolant and fuel vents follow their parts through cuts and recoil physically.
## M2 keeps rated wet mass constant; escaping exhaust carries unabsorbed momentum.
class_name SalvageHazards
extends Node3D

const PLUME_RANGE_M: float = 4.0
const COOLANT_FORCE_N: float = 400.0
const COOLANT_DURATION_S: float = 4.0
const FUEL_FORCE_N: float = 1000.0
const FUEL_DURATION_S: float = 6.0

var _wreck: SalvageWreck
var _spent: Dictionary = {}
var _active: Array[Dictionary] = []


## Bind a wreck; rebinding the same wreck cannot refill already spent reservoirs.
func configure(wreck: SalvageWreck) -> void:
	if is_instance_valid(_wreck) and _wreck == wreck:
		return
	_clear_active()
	_spent.clear()
	_wreck = wreck


## Rupture each supported kind on a part once; repeated markers share its reservoir.
func trigger(part_id: String) -> bool:
	if not is_instance_valid(_wreck) or not _wreck.is_inside_tree():
		return false
	var part: ShipPart = _wreck.graph.get_part(part_id)
	if part == null or part.definition == null or _wreck.body_for_part(part_id) == null:
		return false
	var kinds: Array[String] = []
	if _spent.has(part_id):
		kinds.assign(_spent[part_id])
	var started: bool = false
	for hazard: Dictionary in part.definition.hazards:
		var kind: String = str(hazard.get("kind", ""))
		if kind not in ["coolant", "fuel"] or kinds.has(kind):
			continue
		var marker: Variant = hazard.get("transform")
		if not marker is Transform3D or not PartDefinition.is_rigid_transform(marker):
			continue
		var duration: float = COOLANT_DURATION_S if kind == "coolant" else FUEL_DURATION_S
		var force: float = COOLANT_FORCE_N if kind == "coolant" else FUEL_FORCE_N
		_active.append({"part_id": part_id, "kind": kind, "marker": marker,
			"remaining_s": duration, "duration_s": duration, "force_n": force,
			"visual": _make_visual(kind)})
		part.condition -= 0.15 if kind == "coolant" else 0.25
		kinds.append(kind)
		started = true
	if started:
		_spent[part_id] = kinds
		_update_visuals()
	return started


## Count plumes that still have a finite supply remaining.
func active_count() -> int:
	return _active.size()


## Report whether a part is still venting before allowing cargo clamps.
func is_part_active(part_id: String) -> bool:
	for vent: Dictionary in _active:
		if str(vent.part_id) == part_id:
			return true
	return false


## Report whether this part has ruptured any supported reservoir in this session.
func was_triggered(part_id: String) -> bool:
	return _spent.has(part_id)


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if not is_instance_valid(_wreck):
		_clear_active()
		return
	for index: int in range(_active.size() - 1, -1, -1):
		var vent: Dictionary = _active[index]
		var source: WreckBody = _wreck.body_for_part(vent.part_id)
		if source == null or not source.is_inside_tree():
			_remove_active(index)
			continue
		var powered_seconds: float = minf(delta, vent.remaining_s)
		var marker: Transform3D = _wreck.part_pose(vent.part_id) * Transform3D(vent.marker)
		var outward: Vector3 = -marker.basis.z.normalized()
		var force: Vector3 = outward * float(vent.force_n) * powered_seconds / delta
		source.apply_force(-force, marker.origin - source.global_position)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			marker.origin, marker.origin + outward * PLUME_RANGE_M, 1, [source.get_rid()])
		query.hit_from_inside = true
		var hit: Dictionary = source.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is RigidBody3D:
			var target: RigidBody3D = hit.collider as RigidBody3D
			target.apply_force(force, Vector3(hit.position) - target.global_position)
			if target is PlayerShip:
				(target as PlayerShip).receive_hazard_damage(str(vent.kind), float(vent.force_n) * powered_seconds * 20.0)
		vent.remaining_s = maxf(0.0, float(vent.remaining_s) - powered_seconds)
		if float(vent.remaining_s) <= 1e-9:
			_remove_active(index)


func _process(_delta: float) -> void:
	_update_visuals()


func _make_visual(kind: String) -> MeshInstance3D:
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "CoolantPlume" if kind == "coolant" else "FuelPlume"
	visual.top_level = true
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.height = PLUME_RANGE_M
	mesh.bottom_radius = 0.035
	mesh.top_radius = 0.3
	mesh.radial_segments = 8
	mesh.rings = 1
	visual.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.2, 0.85, 1.0, 0.35) if kind == "coolant" else Color(1.0, 0.45, 0.12, 0.35)
	visual.material_override = material
	add_child(visual)
	return visual


func _update_visuals() -> void:
	if not is_instance_valid(_wreck):
		return
	for vent: Dictionary in _active:
		var visual: MeshInstance3D = vent.visual
		if not is_instance_valid(visual) or not visual.is_inside_tree():
			continue
		var source: WreckBody = _wreck.body_for_part(vent.part_id)
		visual.visible = source != null
		if source == null:
			continue
		var marker: Transform3D = _wreck.part_pose(vent.part_id) * Transform3D(vent.marker)
		visual.global_transform = marker * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
			Vector3.FORWARD * PLUME_RANGE_M * 0.5)
		var material: StandardMaterial3D = visual.material_override as StandardMaterial3D
		material.albedo_color.a = 0.35 * minf(1.0, float(vent.remaining_s))


func _remove_active(index: int) -> void:
	var visual: MeshInstance3D = _active[index].visual
	if is_instance_valid(visual):
		visual.visible = false
		visual.queue_free()
	_active.remove_at(index)


func _clear_active() -> void:
	for index: int in range(_active.size() - 1, -1, -1):
		_remove_active(index)
