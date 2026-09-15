## Development dump of the whole play state to a JSON file (F11, or automatically
## on an anomaly), so a stuck situation can be read afterwards instead of guessed.
class_name DebugDump
extends Node

signal dump_finished(path: String, error: Error)

@export var output_directory: String = "user://debug"
## Automatic anomaly dumps are rate limited so one runaway fault cannot flood the disk.
@export var min_seconds_between_auto_dumps: float = 5.0
## Actions that save a snapshot after every press (F and V: seat and screens).
@export var press_dump_actions: PackedStringArray = ["interact", "unstrap"]
## Wait so the file shows what the press led to; the state at the press is kept too.
@export var press_dump_delay_s: float = 0.5
@export var press_dump_directory: String = "user://debug/presses"

## One-off key actions worth a line in the event trail. Movement is left out: it
## would fill the trail in seconds.
const TRAIL_ACTIONS: PackedStringArray = ["interact", "unstrap", "tablet", "magnetic_boots", "physical_grip",
	"brake", "wheel_brake", "wheel_dump", "freelook", "tool_slot_1", "tool_slot_2", "tool_slot_3", "tool_slot_4",
	"tool_primary", "tool_secondary", "grapple_reel_in", "grapple_reel_out", "ui_cancel", "debug_screenshot", "debug_dump"]
## Held actions also log their release, so the trail shows how long they were held.
const HELD_ACTIONS: PackedStringArray = ["magnetic_boots", "brake", "wheel_brake", "wheel_dump", "freelook",
	"tool_primary", "tool_secondary", "grapple_reel_in", "grapple_reel_out"]

var _sections: Dictionary = {}
var _last_auto_dump_s: float = -INF
var last_path: String = ""


func _ready() -> void:
	DebugLog.anomaly_sink = _on_anomaly
	# The window sees every event before any node can mark it handled.
	get_window().window_input.connect(record_input)


## Log a discrete key action and, for F/V, schedule a snapshot of what it led to.
func record_input(event: InputEvent) -> void:
	if event.is_echo() or event is InputEventMouseMotion:
		return
	for action: String in TRAIL_ACTIONS:
		if not InputMap.has_action(action) or not event.is_action(action):
			continue
		var pressed: bool = event.is_pressed()
		if not pressed and action not in HELD_ACTIONS:
			continue
		var key: String = event.as_text()
		DebugLog.event("input", "%s %s (%s)" % [action, "pressed" if pressed else "released", key])
		if pressed and action in press_dump_actions:
			var at_press: Dictionary = _collect_sections()
			var timer: SceneTreeTimer = get_tree().create_timer(press_dump_delay_s, true, true)
			timer.timeout.connect(_write_press_dump.bind(action, key, at_press))


func _exit_tree() -> void:
	if DebugLog.anomaly_sink.is_valid() and DebugLog.anomaly_sink.get_object() == self:
		DebugLog.anomaly_sink = Callable()


## Register a named section; the provider returns a Dictionary when a dump is written.
func add_section(section: String, provider: Callable) -> void:
	_sections[section] = provider


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_dump") and not event.is_echo():
		get_viewport().set_input_as_handled()
		dump("F11")


## Write every section plus the event trail; returns the file path or "" on failure.
## `extra` adds top-level entries; `into` and `prefix` pick another folder and file name.
func dump(reason: String, extra: Dictionary = {}, into: String = "", prefix: String = "state") -> String:
	var state: Dictionary = {
		"reason": reason,
		"saved_at": Time.get_datetime_string_from_system(),
		"uptime_s": Time.get_ticks_msec() / 1000.0,
	}
	state.merge(_collect_sections())
	state.merge(extra)
	state["events"] = Array(DebugLog.entries)
	var directory: String = ProjectSettings.globalize_path(into if not into.is_empty() else output_directory)
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_finish("", error)
		return ""
	var stem: String = "%s_%s_%d" % [prefix, Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_usec()]
	var path: String = directory.path_join(stem + ".json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_finish(path, FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(_to_json(state), "  "))
	file.close()
	_finish(path, OK)
	return path


## Plain JSON: vectors become [x, y, z], anything else non-JSON becomes its string form.
static func _to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in (value as Dictionary):
				out[str(key)] = _to_json(value[key])
			return out
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(_to_json(item))
			return items
		TYPE_VECTOR3:
			return [(value as Vector3).x, (value as Vector3).y, (value as Vector3).z]
		TYPE_VECTOR2:
			return [(value as Vector2).x, (value as Vector2).y]
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return value if typeof(value) != TYPE_STRING_NAME else str(value)
		_:
			return str(value)


func _collect_sections() -> Dictionary:
	var sections: Dictionary = {}
	for section: String in _sections:
		var provider: Callable = _sections[section]
		sections[section] = provider.call() if provider.is_valid() else {"error": "provider gone"}
	return sections


func _write_press_dump(action: String, key: String, at_press: Dictionary) -> void:
	var name_part: String = key.validate_filename().replace(" ", "")
	dump("%s pressed (%s); sections show %.1f s later, at_press shows the moment of the press" % [action, key, press_dump_delay_s],
		{"at_press": at_press}, press_dump_directory, "press_" + (name_part if not name_part.is_empty() else action))


func _on_anomaly(description: String) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_auto_dump_s < min_seconds_between_auto_dumps:
		return
	_last_auto_dump_s = now
	dump("anomaly: " + description)


func _finish(path: String, error: Error) -> void:
	if error == OK:
		last_path = path
		if DisplayServer.get_name() != "headless":
			print("State dump saved: ", path)
	else:
		printerr("State dump failed: %s (%s)" % [path, error_string(error)])
	dump_finished.emit(path, error)
