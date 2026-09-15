## Timestamped trail of the state changes that matter when play goes wrong:
## power, harness, grips, warp handoffs, suit reserves. Entries print to the
## Godot log while playing and stay in a ring buffer that DebugDump writes out.
class_name DebugLog
extends RefCounted

const CAPACITY: int = 800

static var entries: PackedStringArray = PackedStringArray()
## Called with (source, message) for anomalies so DebugDump can save a snapshot.
static var anomaly_sink: Callable = Callable()


## Record a normal state change.
static func event(source: String, message: String) -> void:
	var line: String = "[%9.2fs] %s: %s" % [Time.get_ticks_msec() / 1000.0, source, message]
	if entries.size() >= CAPACITY:
		entries.remove_at(0)
	entries.append(line)
	if DisplayServer.get_name() != "headless":
		print("EVENT ", line)


## Record something that should not happen in normal play and snapshot the game.
static func anomaly(source: String, message: String) -> void:
	event(source, "ANOMALY " + message)
	if anomaly_sink.is_valid():
		anomaly_sink.call(source + ": " + message)


static func clear() -> void:
	entries.clear()
