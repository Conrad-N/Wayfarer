## The F11 state dump and the event trail behind it write readable JSON.
extends TestCase


func test_dump_writes_sections_events_and_anomaly_snapshots() -> void:
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	var dump: DebugDump = DebugDump.new()
	dump.output_directory = "user://debug_test"
	root.add_child(dump)
	dump.add_section("probe", func() -> Dictionary: return {"answer": 42, "where": Vector3(1, 2, 3)})
	DebugLog.clear()
	DebugLog.event("test", "hello")
	var path: String = dump.dump("unit test")
	check(path != "" and FileAccess.file_exists(path), "dump writes a file")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary and str(parsed.get("reason", "")) == "unit test", "dump is valid JSON carrying the reason")
	check(parsed is Dictionary and int(parsed.get("probe", {}).get("answer", 0)) == 42, "registered sections are written")
	var events: Array = parsed.get("events", []) if parsed is Dictionary else []
	check(not events.is_empty() and str(events.back()).ends_with("test: hello"), "event trail is included")
	DebugLog.anomaly("test", "boom")
	check(dump.last_path != path and FileAccess.file_exists(dump.last_path), "an anomaly saves a snapshot on its own")
	check(str(DebugLog.entries[-1]).contains("ANOMALY boom"), "the anomaly itself is in the trail")
	var before: String = dump.last_path
	DebugLog.anomaly("test", "again")
	check_eq(dump.last_path, before, "anomaly snapshots are rate limited")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(before)
	root.remove_child(dump)
	dump.free()
	check(not DebugLog.anomaly_sink.is_valid(), "removing the dump node unhooks the anomaly sink")
	DebugLog.clear()


## Every F or V press saves a file shortly after, holding the state at the press too (Conrad, 2026-09-15).
func test_f_and_v_presses_save_before_and_after_snapshots() -> void:
	var dump: DebugDump = _press_dump()
	var calls: Array[int] = [0]
	dump.add_section("probe", func() -> Dictionary:
		calls[0] += 1
		return {"call": calls[0]})
	check(dump.get_window().window_input.is_connected(dump.record_input), "the dump listens to every window input")
	DebugLog.clear()
	dump.record_input(_action("interact", true))
	check(Array(DebugLog.entries).any(func(line: String) -> bool: return line.contains("input: interact pressed")), "the F press is in the trail")
	check_eq(dump.last_path, "", "the file waits so it can show what the press led to")
	var first: String = await _next_dump(dump, "")
	check(first.begins_with(ProjectSettings.globalize_path("user://debug_test/presses")), "press snapshots go to their own folder")
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(first)) as Dictionary
	check(str(parsed.get("reason", "")).contains("interact pressed"), "the file says which key made it")
	check(int(parsed.get("at_press", {}).get("probe", {}).get("call", 0)) < int(parsed.get("probe", {}).get("call", 0)), "it holds the state at the press and the state after")
	dump.record_input(_action("unstrap", true))
	var second: String = await _next_dump(dump, first)
	check(second != first and str((JSON.parse_string(FileAccess.get_file_as_string(second)) as Dictionary).get("reason", "")).contains("unstrap pressed"), "V saves its own file")
	DirAccess.remove_absolute(first)
	DirAccess.remove_absolute(second)
	dump.free()
	DebugLog.clear()


## The trail keeps one-off keys and releases of held keys, but not movement, repeats or other releases.
func test_input_trail_skips_movement_repeats_and_tap_releases() -> void:
	var dump: DebugDump = _press_dump()
	DebugLog.clear()
	dump.record_input(_action("tablet", true))
	dump.record_input(_action("tablet", false))
	check_eq(DebugLog.entries.size(), 1, "Tab logs its press only")
	dump.record_input(_action("brake", true))
	dump.record_input(_action("brake", false))
	check_eq(DebugLog.entries.size(), 3, "a held brake logs press and release")
	dump.record_input(_action("move_forward", true))
	var repeat: InputEventKey = InputEventKey.new()
	repeat.physical_keycode = KEY_F
	repeat.pressed = true
	repeat.echo = true
	dump.record_input(repeat)
	dump.record_input(InputEventMouseMotion.new())
	check_eq(DebugLog.entries.size(), 3, "movement, key repeat and mouse motion are left out")
	for index: int in 20:
		await (Engine.get_main_loop() as SceneTree).physics_frame
	check_eq(dump.last_path, "", "only F and V save snapshot files")
	dump.free()
	DebugLog.clear()


func _press_dump() -> DebugDump:
	var dump: DebugDump = DebugDump.new()
	dump.output_directory = "user://debug_test"
	dump.press_dump_directory = "user://debug_test/presses"
	dump.press_dump_delay_s = 0.1
	(Engine.get_main_loop() as SceneTree).root.add_child(dump)
	return dump


func _action(action: String, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _next_dump(dump: DebugDump, previous: String) -> String:
	for index: int in 120:
		await (Engine.get_main_loop() as SceneTree).physics_frame
		if dump.last_path != previous and dump.last_path != "":
			return dump.last_path
	return dump.last_path
