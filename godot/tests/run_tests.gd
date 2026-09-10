## Headless test runner. Run from the repo root with:
##   godot --headless --path godot -s tests/run_tests.gd
## Discovers every tests/test_*.gd, instantiates it, calls every test_* method,
## prints a summary, exits 0 on success and 1 on any failure.
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var total_checks: int = 0
	var all_failures: PackedStringArray = []
	var files: PackedStringArray = _find_test_files("res://tests")
	files.sort()
	for path in files:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			all_failures.append("%s: failed to load" % path)
			continue
		var inst: Object = script.new()
		if not inst is TestCase:
			all_failures.append("%s: does not extend TestCase" % path)
			continue
		var tc: TestCase = inst as TestCase
		var names: Array[String] = []
		for m in tc.get_method_list():
			var n: String = m["name"]
			if n.begins_with("test_"):
				names.append(n)
		names.sort()
		for n in names:
			tc.set_current("%s::%s" % [path.get_file(), n])
			var before: int = tc.failures.size()
			var checks_before: int = tc.checks
			await tc.call(n)
			if tc.checks == checks_before:
				tc.check(false, "test completed without any checks")
			var status: String = "PASS" if tc.failures.size() == before else "FAIL"
			print("%s  %s::%s" % [status, path.get_file(), n])
		total_checks += tc.checks
		all_failures.append_array(tc.failures)
	print("")
	print("%d checks, %d failures" % [total_checks, all_failures.size()])
	for f in all_failures:
		printerr("  " + f)
	quit(1 if all_failures.size() > 0 else 0)


func _find_test_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out
