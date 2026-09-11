## Every shipped scene must load headless, instantiate, and free cleanly,
## with no autoload scaffolding. Recurses res://scenes and res://ui, loads
## each .tscn, checks it is a PackedScene, instantiates it, and frees it.
extends TestCase


func test_every_scene_loads_instantiates_and_frees() -> void:
	var scene_paths: Array[String] = []
	_collect("res://scenes", scene_paths)
	_collect("res://ui", scene_paths)
	print("scene load test: found %d scene files" % scene_paths.size())
	check(scene_paths.size() >= 5, "at least five scene files found (%d)" % scene_paths.size())
	for path: String in scene_paths:
		var packed: PackedScene = load(path)
		check(packed is PackedScene, "scene loads as PackedScene: %s" % path)
		if packed == null:
			continue
		var instance: Node = packed.instantiate()
		check(instance != null, "scene instantiates without scaffolding: %s" % path)
		if instance != null:
			instance.free()


func _collect(base_path: String, into: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(base_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			_collect(base_path + "/" + name, into)
		elif name.ends_with(".tscn"):
			into.append(base_path + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
