extends TestCase
## End-to-end checks of PartCatalog against the committed glb kit.
##
## test_part_import.gd proves the raw Blender -> glb -> meta pipeline on one
## part and the whole kit's geometry. This file covers the layer on top: that
## PartCatalog.definition() turns every committed part into a valid, cached
## PartDefinition with sane designer numbers, that geometry stays available
## afterwards, and that unknown parts fail softly instead of crashing.

const PARTS_DIR: String = "res://assets/models/parts"
const KNOWN_KINDS: Array[String] = [
	"hull", "cap", "tank", "engine", "radiator", "truss", "mast", "plating",
]


func _part_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(PARTS_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".glb"):
			names.append(file.get_basename())
		file = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func test_every_committed_part_builds_a_valid_definition() -> void:
	var names: PackedStringArray = _part_names()
	check_eq(names.size(), 17, "catalog sees all seventeen kit parts")
	var total_cut_points: int = 0
	for part_name: String in names:
		var def: PartDefinition = PartCatalog.definition(part_name)
		check(def != null, "%s builds a definition" % part_name)
		if def == null:
			continue
		check(def.is_valid(), "%s definition passes PartDefinition.is_valid" % part_name)
		check(KNOWN_KINDS.has(def.kind), "%s has a known part_kind: %s" % [part_name, def.kind])
		check_eq(def.model_path, "%s/%s.glb" % [PARTS_DIR, part_name], "%s model path" % part_name)
		check(not def.material.is_empty(), "%s material survives" % part_name)
		check(def.mass_kg > 0.0 and def.mass_kg < 1000000.0, "%s mass is sane: %.1f kg" % [part_name, def.mass_kg])
		check(def.value_cr >= 0.0 and is_finite(def.value_cr), "%s value is sane" % part_name)
		check(def.volume_m3 > 0.0, "%s volume survives" % part_name)
		check(def.thickness_mm > 0.0 and def.thickness_mm < 10000.0, "%s thickness is sane" % part_name)
		check(def.size_m.x > 0.0 and def.size_m.y > 0.0 and def.size_m.z > 0.0, "%s size is positive" % part_name)
		check(not def.sockets.is_empty(), "%s keeps its sockets" % part_name)
		total_cut_points += def.cut_points.size()
	check(total_cut_points > 0, "catalog preserves CUT_ markers across the kit")


func test_definitions_are_cached_and_unknown_parts_return_null() -> void:
	var first: PartDefinition = PartCatalog.definition("hull_segment_a")
	var again: PartDefinition = PartCatalog.definition("hull_segment_a")
	check(first != null and again == first, "definitions are cached by name")
	check(PartCatalog.definition("no_such_part_zz") == null, "unknown part returns null")


func test_geometry_is_retained_for_every_part() -> void:
	for part_name: String in _part_names():
		var def: PartDefinition = PartCatalog.definition(part_name)
		if def == null:
			check(false, "%s definition missing" % part_name)
			continue
		var geometry: Dictionary = PartCatalog.geometry(def)
		check(not geometry.is_empty(), "%s geometry is retained" % part_name)
		check((geometry.get("meshes") as Array).size() > 0, "%s geometry has meshes" % part_name)
		check((geometry.get("shapes") as Array).size() > 0, "%s geometry has collision shapes" % part_name)
