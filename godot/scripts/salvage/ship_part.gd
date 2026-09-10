## One salvageable part's state, independent of the rigid body currently carrying it.
class_name ShipPart
extends RefCounted

var id: String = ""
var definition: PartDefinition
var transform: Transform3D = Transform3D.IDENTITY
var condition: float = 1.0:
	set(value):
		condition = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
var intact_factor: float = 1.0:
	set(value):
		intact_factor = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
var scanned: bool = false


## Compute remaining base salvage value; station demand belongs to later sale logic.
func salvage_value() -> float:
	if definition == null or not is_finite(definition.value_cr) or definition.value_cr < 0.0:
		return 0.0
	return definition.value_cr * condition * intact_factor


## Only identified parts with valid physical definitions can enter an assembly.
func is_valid() -> bool:
	return not id.strip_edges().is_empty() and definition != null and definition.is_valid() and PartDefinition.is_rigid_transform(transform)
