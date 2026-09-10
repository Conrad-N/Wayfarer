## Hand-authored eight-part salvage exercise assembled by mating imported sockets.
class_name PracticeWreck
extends RefCounted


## Build a small tug with a shield plate, exposed radiator, and volatile fuel tank.
static func make_graph() -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	var hull: ShipPart = _part("Spine", "hull_segment_b")
	if hull == null:
		return graph
	graph.add_part(hull)
	_attach(graph, "Spine", "aft_M", "Drive", "hull_segment_b", "fore_M")
	_attach(graph, "Spine", "fore_M", "Nose", "cap_nose_a", "aft_M")
	_attach(graph, "Drive", "aft_M", "Engine", "engine_chemical_a", "fore_M")
	_attach(graph, "Spine", "starboard_M", "Fuel", "tank_fuel_a", "mount_M")
	_attach(graph, "Drive", "port_M", "Radiator", "radiator_panel_a", "mount_M")
	_attach(graph, "Spine", "instrument_S", "Antenna", "sensor_mast_a", "aft_S")
	_attach(graph, "Drive", "bottom_M", "Shield", "plating_panel_a", "mount_M")
	return graph


static func _part(id: String, asset: String) -> ShipPart:
	var definition: PartDefinition = PartCatalog.definition(asset)
	if definition == null:
		push_error("Missing practice wreck part: " + asset)
		return null
	var part: ShipPart = ShipPart.new()
	part.id = id
	part.definition = definition
	return part


static func _attach(graph: ShipGraph, parent_id: String, parent_socket: String, id: String, asset: String, socket: String) -> void:
	var part: ShipPart = _part(id, asset)
	var parent: ShipPart = graph.get_part(parent_id)
	if part == null or parent == null or not parent.definition.sockets.has(parent_socket) or not part.definition.sockets.has(socket):
		push_error("Practice wreck socket missing: " + id)
		return
	var mount: Transform3D = parent.transform * parent.definition.sockets[parent_socket]
	# A narrow gap exposes the joint; opposing socket forward axes face each other.
	mount.origin -= mount.basis.z * 0.12
	part.transform = mount * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * (part.definition.sockets[socket] as Transform3D).affine_inverse()
	graph.add_part(part)
	graph.connect_parts("Joint_" + id, parent_id, parent_socket, id, socket)
