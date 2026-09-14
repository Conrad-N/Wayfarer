## Esc menu: pauses the whole game and offers resume, save, load and quit.
## The menu only asks; Main decides whether a save or load can happen.
class_name PauseMenu
extends CanvasLayer

signal save_requested
signal load_requested
signal closed

## Replaced by tests so pressing Quit does not end the test run.
var quit_action: Callable = _quit_game
var _status: Label
var _save_button: Button
var _load_button: Button
var _resume_button: Button
var _quit_button: Button


func _init() -> void:
	name = "PauseMenu"
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	_resume_button = _button(column, "Resume", close)
	_save_button = _button(column, "Save", func() -> void: save_requested.emit())
	_load_button = _button(column, "Load", func() -> void: load_requested.emit())
	_quit_button = _button(column, "Quit", func() -> void: quit_action.call())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


## Show the menu and freeze the game underneath it.
func open() -> void:
	if visible:
		return
	visible = true
	_status.text = ""
	get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume_button.grab_focus()


## Hide the menu and let the game run again.
func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	closed.emit()


## Whether the menu is showing.
func is_open() -> bool:
	return visible


## Tell the player what just happened (saved, nothing to load, and so on).
func show_message(text: String) -> void:
	_status.text = text


## Grey out Save or Load when they cannot work right now.
func set_available(can_save: bool, can_load: bool) -> void:
	_save_button.disabled = not can_save
	_load_button.disabled = not can_load


## The current message, for tests.
func message() -> String:
	return _status.text


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _exit_tree() -> void:
	if visible and is_inside_tree():
		get_tree().paused = false
