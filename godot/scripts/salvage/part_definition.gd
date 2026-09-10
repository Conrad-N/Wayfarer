## Designer-editable part properties and attachment markers in part-local metres.
class_name PartDefinition
extends Resource

@export var kind: String = ""
@export var model_path: String = ""
@export var mass_kg: float = 1.0
@export var value_cr: float = 0.0
@export var volume_m3: float = 1.0
@export var thickness_mm: float = 1.0
@export var material: String = "steel"
@export var size_m: Vector3 = Vector3.ONE
@export var sockets: Dictionary = {}
@export var cut_points: Dictionary = {}
@export var hazards: Array[Dictionary] = []


## Reject unusable physical properties and malformed marker data before spawning.
func is_valid() -> bool:
	if kind.strip_edges().is_empty() or material.strip_edges().is_empty():
		return false
	if not is_finite(mass_kg) or mass_kg <= 0.0:
		return false
	if not is_finite(value_cr) or value_cr < 0.0:
		return false
	if not is_finite(volume_m3) or volume_m3 < 0.0:
		return false
	if not is_finite(thickness_mm) or thickness_mm <= 0.0:
		return false
	if not size_m.is_finite() or size_m.x <= 0.0 or size_m.y <= 0.0 or size_m.z <= 0.0:
		return false
	if not _markers_valid(sockets) or not _markers_valid(cut_points):
		return false
	for hazard: Dictionary in hazards:
		if not hazard.get("kind") is String or not hazard.get("transform") is Transform3D:
			return false
		if hazard["kind"] not in ["fuel", "coolant", "pressure", "power"]:
			return false
		if not is_rigid_transform(hazard["transform"]):
			return false
	return true


## Physical assembly transforms permit finite translation and rotation, never scale.
static func is_rigid_transform(value: Transform3D) -> bool:
	if not value.is_finite() or not is_equal_approx(value.basis.determinant(), 1.0):
		return false
	return value.basis.is_equal_approx(value.basis.orthonormalized())


func _markers_valid(markers: Dictionary) -> bool:
	for key: Variant in markers:
		if not key is String or String(key).strip_edges().is_empty():
			return false
		if not markers[key] is Transform3D or not is_rigid_transform(markers[key]):
			return false
	return true
