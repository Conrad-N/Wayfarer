## T1: every input action referenced in code must exist in the input map.
## A typo in an action name fails silently at runtime, so this test scans
## every .gd file under res://scripts and res://ui, collects the quoted
## action names from is_action*() and Input.get_action_strength() calls,
## and checks each one against InputMap.
##
## T2: the freelook action is bound to Shift and the middle mouse button
## (2026-09-14 rebinding away from Z), and both bindings actually match.
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
	# player.gd builds these names from a template, so the regex scan misses them.
	for slot: int in range(1, 5):
		var slot_action: String = "tool_slot_%d" % slot
		check(InputMap.has_action(slot_action), "action %s exists" % slot_action)


## Free look is bound to exactly Shift plus middle mouse (2026-09-14), so either
## key recentres the view on release and the retired Z binding is fully gone.
func test_freelook_bound_to_shift_and_middle_mouse() -> void:
	var events: Array[InputEvent] = InputMap.action_get_events("freelook")
	check_eq(events.size(), 2, "freelook has exactly two bindings")
	var has_shift: bool = false
	var has_middle_mouse: bool = false
	for event: InputEvent in events:
		if event is InputEventKey:
			var key: InputEventKey = event as InputEventKey
			check(key.physical_keycode != KEY_Z, "old Z binding still present on freelook")
			if key.physical_keycode == KEY_SHIFT:
				has_shift = true
		elif event is InputEventMouseButton:
			if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
				has_middle_mouse = true
	check(has_shift, "freelook is bound to Shift")
	check(has_middle_mouse, "freelook is bound to the middle mouse button")
	# Synthesised presses must match the action the same way player.gd reads it
	# (event.is_action), which also proves the mouse-button binding works.
	var shift_press: InputEventKey = InputEventKey.new()
	shift_press.physical_keycode = KEY_SHIFT
	shift_press.pressed = true
	check(shift_press.is_action("freelook"), "a Shift press matches the freelook action")
	var middle_press: InputEventMouseButton = InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	middle_press.pressed = true
	check(middle_press.is_action("freelook"), "a middle-mouse press matches the freelook action")
	var z_press: InputEventKey = InputEventKey.new()
	z_press.physical_keycode = KEY_Z
	z_press.pressed = true
	check(not z_press.is_action("freelook"), "a Z press no longer matches the freelook action")


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
