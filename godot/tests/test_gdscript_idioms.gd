extends TestCase
## Guard against Godot 3 idioms returning to the codebase.
##
## AGENTS.md pins the project to the Godot 4 API ("Godot 3 patterns are wrong
## here and will not compile"). Most banned names fail loudly at parse time,
## but a few (the old coroutine yield, linear2db, connect("s", self, "m"))
## can survive as plain identifiers or wrong-arity calls. This scans every .gd
## under res://scripts, res://ui and res://tests for them. Comments and string
## literal bodies (either quote style) are blanked out before matching, so
## this file can carry the patterns themselves safely.

const SCAN_ROOTS: Array[String] = ["res://scripts", "res://ui", "res://tests"]


## Each entry is a human label, a RegEx, and whether a leading '@' exempts it
## (at-export is Godot 4; bare export is Godot 3).
func _patterns() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var defs: Array = [
		["yield( (Godot 3 coroutine)", "\\byield\\s*\\(", false],
		[".instance() (use .instantiate())", "\\.instance\\s*\\(\\s*\\)", false],
		["KinematicBody (use CharacterBody/RigidBody3D)", "\\bKinematicBody", false],
		["RigidBody bare (use RigidBody3D)", "\\bRigidBody\\b", false],
		["CollisionShape bare (use CollisionShape3D)", "\\bCollisionShape\\b", false],
		["SpatialMaterial (Godot 3 shader material)", "\\bSpatialMaterial\\b", false],
		["bare export var (use @export var)", "\\bexport var\\b", true],
		["bare onready var (use @onready var)", "\\bonready var\\b", true],
		["bare export() (use @export)", "\\bexport\\s*\\(", true],
		["Godot 3 math helpers", "\\brad2deg\\s*\\(|\\bdeg2rad\\s*\\(|\\blinear2db\\s*\\(|\\bdb2linear\\s*\\(", false],
		["connect(\"s\", self, \"m\") (Godot 3 form)", "\\bconnect\\s*\\(\\s*\"[^\"]*\"\\s*,\\s*self\\s*,", false],
	]
	for def: Array in defs:
		var pattern: String = str(def[1])
		var regex: RegEx = RegEx.create_from_string(pattern)
		check(regex != null and regex.is_valid(), "pattern compiles: " + pattern)
		entries.append({"label": str(def[0]), "regex": regex, "allow_at": bool(def[2])})
	return entries


func test_no_godot3_idioms_in_scripts() -> void:
	var files: PackedStringArray = PackedStringArray()
	for root: String in SCAN_ROOTS:
		_collect_gd(root, files)
	check(files.size() >= 90, "the scan covers every script in the project (%d files)" % files.size())
	var offenders: PackedStringArray = PackedStringArray()
	var patterns: Array[Dictionary] = _patterns()
	for path: String in files:
		_scan_file(path, patterns, offenders)
	check_eq(offenders.size(), 0, "Godot 3 idioms found:\n" + "\n".join(offenders))


func _collect_gd(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		var full: String = dir_path.path_join(entry_name)
		if dir.current_is_dir():
			_collect_gd(full, out)
		elif entry_name.ends_with(".gd"):
			out.append(full)
		entry_name = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, patterns: Array[Dictionary], offenders: PackedStringArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		offenders.append(path + ": unreadable")
		return
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	for index: int in lines.size():
		var line: String = _scrub(lines[index])
		for entry: Dictionary in patterns:
			var regex: RegEx = entry.regex
			for match_result: RegExMatch in regex.search_all(line):
				var start: int = match_result.get_start()
				if bool(entry.allow_at) and start > 0 and line[start - 1] == "@":
					continue
				offenders.append("%s:%d: %s" % [path, index + 1, str(entry.label)])
				break


## Prepare one line for matching: stop at an unquoted '#' comment, and blank
## string literal bodies to spaces while keeping the quote characters. The
## quotes stay so connect("sig", self, "m") is still recognizable; everything
## written inside a string (including this file's own pattern definitions) is
## replaced and cannot self-trigger a match. Backslash escapes are consumed
## in pairs so \\" does not look like a closing quote.
func _scrub(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var char: String = line[index]
		if quote != "":
			if char == "\\" and index + 1 < line.length():
				out += "  "
				index += 2
				continue
			if char == quote:
				quote = ""
				out += char
			else:
				out += " "
			index += 1
			continue
		if char == "\"" or char == "'":
			quote = char
			out += char
		elif char == "#":
			return out
		else:
			out += char
		index += 1
	return out
