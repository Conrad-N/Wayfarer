## T1: every input action referenced in code must exist in the input map.
## A typo in an action name fails silently at runtime, so this test scans
## every .gd file under res://scripts and res://ui, collects the quoted
## action names from is_action*() and Input.get_action_strength() calls,
## and checks each one against InputMap.
extends TestCase


func test_input_actions_exist_in_map() -> void:
	var action_names: Dictionary = {}
	_collect_action_names("res://scripts", action_names)
	_collect_action_names("res://ui", action_names)
	check(
		action_names.size() >= 10,
		"found at least 10 distinct action names, found %d" % action_names.size()
	)
	for name: String in action_names:
		# Built-in ui_* actions exist in the InputMap from engine start.
		check(InputMap.has_action(name), "action %s exists" % name)


## Recursively lists .gd files under [dir_path], appending paths to [out].
func _list_gd_files(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if f != ".." and not f.begins_with("."):
				_list_gd_files(dir_path + "/" + f, out)
		elif f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()


## Scans every .gd file under [root] for input-action calls and adds the
## quoted action names to [into] (a Dictionary used as a set).
func _collect_action_names(root: String, into: Dictionary) -> void:
	var files: PackedStringArray = []
	_list_gd_files(root, files)
	var is_action_re: RegEx = RegEx.new()
	is_action_re.compile('is_action(?:_just_pressed|_just_released|_pressed)?\\("([a-z_]+)"')
	var strength_re: RegEx = RegEx.new()
	strength_re.compile('get_action_strength\\("([a-z_]+)"')
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in is_action_re.search_all(text):
			into[m.get_string(1)] = true
		for m: RegExMatch in strength_re.search_all(text):
			into[m.get_string(1)] = true
