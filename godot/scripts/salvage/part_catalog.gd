## Reads generated part geometry, imported convex collision, and designer metadata.
class_name PartCatalog
extends RefCounted

static var _definitions: Dictionary = {}
static var _geometry: Dictionary = {}


## Load a kit definition once, retaining no scene nodes in the catalog.
static func definition(part_name: String) -> PartDefinition:
	if _definitions.has(part_name):
		return _definitions[part_name] as PartDefinition
	var path: String = "res://assets/models/parts/%s.glb" % part_name
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	var source: Node3D = packed.instantiate() as Node3D
	var data: Dictionary = {"meshes": [], "shapes": [], "sockets": {}, "cuts": {}, "hazards": [], "extras": {}}
	_collect(source, Transform3D.IDENTITY, data)
	source.free()
	var extras: Dictionary = data.extras
	if extras.is_empty() or data.meshes.is_empty() or data.shapes.is_empty():
		push_error("Part has no imported geometry/collision/metadata: " + path)
		return null
	var result: PartDefinition = PartDefinition.new()
	result.kind = str(extras.get("part_kind", ""))
	result.model_path = path
	result.mass_kg = float(extras.get("mass_kg", 0.0))
	result.value_cr = float(extras.get("value_cr", 0.0))
	result.volume_m3 = float(extras.get("volume_m3", 0.0))
	result.thickness_mm = float(extras.get("thickness_mm", 0.0))
	result.material = str(extras.get("material", ""))
	result.sockets = data.sockets
	result.cut_points = data.cuts
	result.hazards.assign(data.hazards)
	var bounds: AABB
	var first: bool = true
	for entry: Dictionary in data.meshes:
		var mesh: Mesh = entry.mesh
		var pose: Transform3D = entry.transform
		var box: AABB = pose * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	result.size_m = bounds.size
	if not result.is_valid():
		push_error("Invalid part definition: " + path)
		return null
	_definitions[part_name] = result
	_geometry[path] = data
	return result


## Return shared immutable mesh/shape resources and their model-local transforms.
static func geometry(part: PartDefinition) -> Dictionary:
	if not _geometry.has(part.model_path):
		definition(part.model_path.get_file().get_basename())
	return _geometry.get(part.model_path, {})


static func _collect(node: Node, parent_pose: Transform3D, data: Dictionary) -> void:
	var pose: Transform3D = parent_pose
	if node is Node3D:
		pose = parent_pose * (node as Node3D).transform
	if node is MeshInstance3D:
		var visual: MeshInstance3D = node as MeshInstance3D
		data.meshes.append({"mesh": visual.mesh, "transform": pose})
		if node.has_meta("extras"):
			data.extras = node.get_meta("extras")
	elif node is CollisionShape3D:
		data.shapes.append({"shape": (node as CollisionShape3D).shape, "transform": pose})
	var label: String = str(node.name)
	if label.begins_with("SOCKET_"):
		data.sockets[label.trim_prefix("SOCKET_")] = pose
	elif label.begins_with("CUT_"):
		data.cuts[label.trim_prefix("CUT_")] = pose
	elif label.begins_with("HAZARD_"):
		data.hazards.append({"kind": label.split("_")[1], "transform": pose})
	for child: Node in node.get_children():
		_collect(child, pose, data)
