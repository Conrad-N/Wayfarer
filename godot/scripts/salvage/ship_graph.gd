## Deterministic socket connections between salvage parts, with no scene-tree state.
class_name ShipGraph
extends RefCounted

var _parts: Dictionary[String, ShipPart] = {}
var _edges: Dictionary[String, Dictionary] = {}


## Add one valid, uniquely identified part. Failed additions leave the graph intact.
func add_part(part: ShipPart) -> bool:
	if part == null or not part.is_valid() or _parts.has(part.id):
		return false
	_parts[part.id] = part
	return true


## Join two unused, equally sized sockets; separate mounts may link the same parts.
func connect_parts(edge_id: String, part_a: String, socket_a: String, part_b: String, socket_b: String) -> bool:
	if edge_id.strip_edges().is_empty() or _edges.has(edge_id) or part_a == part_b:
		return false
	var first: ShipPart = get_part(part_a)
	var second: ShipPart = get_part(part_b)
	if first == null or second == null or not first.is_valid() or not second.is_valid():
		return false
	if first.id != part_a or second.id != part_b:
		return false
	if not first.definition.sockets.has(socket_a) or not second.definition.sockets.has(socket_b):
		return false
	if _socket_size(socket_a) != _socket_size(socket_b):
		return false
	for edge: Dictionary in _edges.values():
		if _uses_socket(edge, part_a, socket_a) or _uses_socket(edge, part_b, socket_b):
			return false
	_edges[edge_id] = {"a": part_a, "b": part_b, "socket_a": socket_a, "socket_b": socket_b}
	return true


## Remove an existing connection; cutting an absent or already severed edge is safe.
func sever_edge(id: String) -> bool:
	return _edges.erase(id)


## Return sorted connected components, ordered by their smallest part identifier.
func components() -> Array[PackedStringArray]:
	var result: Array[PackedStringArray] = []
	var neighbors: Dictionary[String, PackedStringArray] = {}
	for id: String in part_ids():
		neighbors[id] = PackedStringArray()
	for edge: Dictionary in _edges.values():
		neighbors[edge["a"]].append(edge["b"])
		neighbors[edge["b"]].append(edge["a"])
	var visited: Dictionary[String, bool] = {}
	for first: String in part_ids():
		if visited.has(first):
			continue
		var component: PackedStringArray = []
		var pending: PackedStringArray = [first]
		visited[first] = true
		while not pending.is_empty():
			var current: String = pending[pending.size() - 1]
			pending.resize(pending.size() - 1)
			component.append(current)
			for neighbor: String in neighbors[current]:
				if not visited.has(neighbor):
					visited[neighbor] = true
					pending.append(neighbor)
		component.sort()
		result.append(component)
	return result


## Look up the live part state; callers may change condition and scan progress.
func get_part(id: String) -> ShipPart:
	return _parts.get(id)


## Return a sorted copy of part IDs so traversal does not depend on insertion order.
func part_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray(_parts.keys())
	result.sort()
	return result


## Return a sorted copy of edge IDs for stable saving, selection, and rebuilding.
func edge_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray(_edges.keys())
	result.sort()
	return result


## Return a connection copy, or an empty dictionary when the edge is absent.
func get_edge(id: String) -> Dictionary:
	var edge: Dictionary = _edges.get(id, {})
	return edge.duplicate()


## JSON-safe snapshot of every part and every surviving connection, with enough
## detail for from_save() to rebuild an identical graph: same components, same
## severed edges, same mass (parts share catalog definitions, not copies).
func to_save() -> Dictionary:
	var parts: Array = []
	for id: String in part_ids():
		parts.append(_parts[id].to_save())
	var edges: Array = []
	for id: String in edge_ids():
		var edge: Dictionary = _edges[id]
		edges.append({"id": id, "a": edge["a"], "b": edge["b"], "socket_a": edge["socket_a"], "socket_b": edge["socket_b"]})
	return {"parts": parts, "edges": edges}


## Rebuild a graph from to_save() data. A part whose asset no longer resolves,
## or an edge that fails validation, is skipped and logged rather than aborting
## the whole load; the rest of the wreck still comes back.
static func from_save(data: Dictionary) -> ShipGraph:
	var graph: ShipGraph = ShipGraph.new()
	for entry: Variant in (data.get("parts", []) as Array):
		if not entry is Dictionary:
			continue
		var part: ShipPart = ShipPart.from_save(entry)
		if not graph.add_part(part):
			push_error("Save data could not restore part: %s" % str((entry as Dictionary).get("id", "")))
	for entry: Variant in (data.get("edges", []) as Array):
		if not entry is Dictionary:
			continue
		var edge: Dictionary = entry
		var edge_id: String = str(edge.get("id", ""))
		if not graph.connect_parts(edge_id, str(edge.get("a", "")), str(edge.get("socket_a", "")), str(edge.get("b", "")), str(edge.get("socket_b", ""))):
			push_error("Save data could not restore edge: %s" % edge_id)
	return graph


func _socket_size(socket: String) -> String:
	var suffix: String = socket.get_slice("_", socket.get_slice_count("_") - 1)
	return suffix if suffix in ["S", "M", "L"] else "M"


func _uses_socket(edge: Dictionary, part: String, socket: String) -> bool:
	return (edge["a"] == part and edge["socket_a"] == socket) or (edge["b"] == part and edge["socket_b"] == socket)
