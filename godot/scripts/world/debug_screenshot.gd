## Development capture of the rendered game viewport, including its HUD.
class_name DebugScreenshot
extends Node

signal capture_started()
signal capture_finished(path: String, error: Error)

@export var output_directory: String = "res://build/screens"

var _busy: bool = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_screenshot") and not event.is_echo():
		get_viewport().set_input_as_handled()
		capture()


## Save a completed frame; repeated requests during capture are ignored.
## Headless or unwritable runs report an error without waiting or stopping play.
func capture() -> void:
	if _busy:
		return
	if DisplayServer.get_name() == "headless":
		capture_finished.emit("", ERR_UNAVAILABLE)
		return
	_busy = true
	capture_started.emit()
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	if frame == null or frame.is_empty():
		_finish("", ERR_UNAVAILABLE)
		return
	var directory: String = ProjectSettings.globalize_path(output_directory)
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_finish(directory, error)
		return
	# Windows-safe timestamp plus a per-process tick value; check existing files
	# as well so restarting the game never replaces a previous capture.
	var stem: String = "wayfarer_%s_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_usec()
	]
	var path: String = directory.path_join(stem + ".png")
	var suffix: int = 1
	while FileAccess.file_exists(path):
		path = directory.path_join("%s_%d.png" % [stem, suffix])
		suffix += 1
	_finish(path, frame.save_png(path))


func _finish(path: String, error: Error) -> void:
	_busy = false
	if error == OK:
		print("Screenshot saved: ", path)
	else:
		printerr("Screenshot failed: %s (%s)" % [path, error_string(error)])
	capture_finished.emit(path, error)
