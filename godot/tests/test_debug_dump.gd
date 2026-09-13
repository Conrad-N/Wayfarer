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
