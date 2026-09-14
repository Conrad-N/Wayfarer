## Game autoload: the save file on disk, and a loaded game waiting for the main
## scene to rebuild before it is applied.
class_name SaveGames
extends Node

const DEFAULT_PATH: String = "user://saves/save.json"
const FORMAT: String = "wayfarer-save"
const VERSION: int = 1

## Tests point this somewhere else.
var save_path: String = DEFAULT_PATH
var _pending: Dictionary = {}


## Whether a readable save exists.
func has_save() -> bool:
	return not read().is_empty()


## Write the game state. The old file is only replaced once the new one is fully
## on disk, so a crash mid-save cannot leave a broken save behind.
func write(state: Dictionary) -> Error:
	var directory: String = save_path.get_base_dir()
	var made: Error = DirAccess.make_dir_recursive_absolute(directory)
	if made != OK and not DirAccess.dir_exists_absolute(directory):
		return made
	var envelope: Dictionary = {"format": FORMAT, "version": VERSION, "saved_at": Time.get_datetime_string_from_system(), "state": state}
	var temporary: String = save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(SaveCodec.stringify(envelope))
	var written: Error = file.get_error()
	file.close()
	if written != OK:
		return written
	return DirAccess.rename_absolute(temporary, save_path)


## Read the saved game state, or an empty dictionary if there is no valid save.
func read() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var envelope: Dictionary = SaveCodec.parse(FileAccess.get_file_as_string(save_path))
	if str(envelope.get("format", "")) != FORMAT or int(envelope.get("version", 0)) != VERSION:
		return {}
	var state: Variant = envelope.get("state")
	return state if state is Dictionary else {}


## Hold a state for the next main scene to apply once it has built itself.
func request_load(state: Dictionary) -> void:
	_pending = state


## Hand over a waiting load exactly once.
func take_pending_load() -> Dictionary:
	var state: Dictionary = _pending
	_pending = {}
	return state
