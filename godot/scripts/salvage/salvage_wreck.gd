## Owns a ship graph and turns its connected components into drifting rigid bodies.
class_name SalvageWreck
extends Node3D

signal structure_changed()
signal structure_changing()

var graph: ShipGraph = ShipGraph.new()
var bodies: Array[WreckBody] = []
var cut_progress: Dictionary = {}
var _split_pending: bool = false
var _pending_edge: String = ""


func _ready() -> void:
	# Replace bodies at the next physics boundary, before that tick's tool and
	# vent forces. The previous tick's queued forces have then been integrated.
	process_physics_priority = -100


func _physics_process(_delta: float) -> void:
	if _split_pending:
		_sever(_pending_edge)


## Spawn a graph at the supplied world pose and velocity without modifying its data.
func spawn(source: ShipGraph, pose: Transform3D, velocity: Vector3 = Vector3.ZERO, spin: Vector3 = Vector3.ZERO) -> void:
	if not bodies.is_empty() or source == null:
		return
	graph = source
	for ids: PackedStringArray in graph.components():
		var body: WreckBody = _make_body(ids, pose)
		body.linear_velocity = velocity
		body.angular_velocity = spin
	structure_changed.emit()


## Return the current moving owner of a particular part.
func body_for_part(id: String) -> WreckBody:
	for body: WreckBody in bodies:
		if is_instance_valid(body) and body.part_ids.has(id):
			return body
	return null


## Return a part's current world transform, even after multiple cuts and splits.
func part_pose(id: String) -> Transform3D:
	var body: WreckBody = body_for_part(id)
	return body.assembly_pose() * graph.get_part(id).transform if body != null else Transform3D.IDENTITY


## Apply powered cutting time at an existing joint; completion queues a safe split.
func cut(edge_id: String, seconds: float, part_id: String) -> bool:
	if _split_pending or not is_finite(seconds) or seconds <= 0.0:
		return false
	var edge: Dictionary = graph.get_edge(edge_id)
	if edge.is_empty() or (part_id != edge.a and part_id != edge.b):
		return false
	var part: ShipPart = graph.get_part(part_id)
	var material_factor: float = 0.6 if part.definition.material == "aluminium" else 1.0
	var required: float = maxf(0.4, part.definition.thickness_mm * material_factor / 4.0)
	cut_progress[edge_id] = minf(1.0, float(cut_progress.get(edge_id, 0.0)) + seconds / required)
	if float(cut_progress[edge_id]) < 1.0:
		return false
	_split_pending = true
	_pending_edge = edge_id
	return true


## Sum the recoverable value of individually freed parts (debug accounting, not a sale).
func salvaged_value() -> float:
	var value: float = 0.0
	for body: WreckBody in bodies:
		if is_instance_valid(body) and body.part_ids.size() == 1:
			value += graph.get_part(body.part_ids[0]).salvage_value()
	return value


## Apply significant impact damage proportionally across a struck connected body.
func damage_component(ids: PackedStringArray, energy_j: float) -> void:
	if not is_finite(energy_j) or energy_j <= 2000.0:
		return
	var total_mass: float = 0.0
	var valid_ids: PackedStringArray = []
	for id: String in ids:
		if graph.get_part(id) == null or valid_ids.has(id):
			continue
		valid_ids.append(id)
		total_mass += graph.get_part(id).definition.mass_kg
	if total_mass <= 0.0:
		return
	var loss: float = minf(0.5, (energy_j - 2000.0) / (total_mass * 300.0))
	for id: String in valid_ids:
		var part: ShipPart = graph.get_part(id)
		part.condition -= loss


func _make_body(ids: PackedStringArray, pose: Transform3D) -> WreckBody:
	var body: WreckBody = WreckBody.new()
	# This node is organisational only; bodies are configured in world coordinates.
	body.top_level = true
	body.configure(self, ids, pose)
	add_child(body)
	bodies.append(body)
	return body


func _sever(edge_id: String) -> void:
	var edge: Dictionary = graph.get_edge(edge_id)
	if edge.is_empty():
		_split_pending = false
		return
	var old: WreckBody = body_for_part(edge.a)
	if old == null:
		_split_pending = false
		return
	structure_changing.emit()
	var pose: Transform3D = old.assembly_pose()
	var velocity: Vector3 = old.linear_velocity
	var spin: Vector3 = old.angular_velocity
	var centre: Vector3 = old.global_position
	graph.sever_edge(edge_id)
	bodies.erase(old)
	# All replacement collision is enabled together after the old body leaves
	# the physics world; there is no frame with duplicate active collision.
	remove_child(old)
	for component: PackedStringArray in graph.components():
		if not old.part_ids.has(component[0]):
			continue
		var body: WreckBody = _make_body(component, pose)
		body.linear_velocity = SalvageMassProperties.fragment_velocity(velocity, spin, centre, body.global_position)
		body.angular_velocity = spin
	old.queue_free()
	_split_pending = false
	structure_changed.emit()
