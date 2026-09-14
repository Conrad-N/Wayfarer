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


## JSON-safe snapshot: identity, the catalog asset name to re-resolve the shared
## definition on load, the assembly-local transform, and all mutable state.
func to_save() -> Dictionary:
	return {
		"id": id,
		"asset": definition.model_path.get_file().get_basename() if definition != null else "",
		"transform": SaveCodec.transform(transform),
		"condition": condition,
		"intact_factor": intact_factor,
		"scanned": scanned,
	}


## Rebuild a part from to_save() data. The definition comes from PartCatalog's
## cache, so every part built from the same asset shares one PartDefinition
## instance again, exactly as PracticeWreck and the salvage cutters expect.
static func from_save(data: Dictionary) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = str(data.get("id", ""))
	var asset: String = str(data.get("asset", ""))
	part.definition = PartCatalog.definition(asset)
	if part.definition == null:
		push_error("Save data references an unknown part asset: %s" % asset)
	part.transform = SaveCodec.to_transform(data.get("transform"))
	part.condition = float(data.get("condition", 1.0))
	part.intact_factor = float(data.get("intact_factor", 1.0))
	part.scanned = bool(data.get("scanned", false))
	return part
