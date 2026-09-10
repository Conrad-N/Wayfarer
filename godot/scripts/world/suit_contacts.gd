## Input ownership for hand grips and magnetic boots, independent of the selected cutting tool.
class_name SuitContacts
extends Node

var player: Player
var grip: PhysicalGrip
var boots: MagneticBoots
var _grab_requested: bool = false
var _boots_requested: bool = false


## Bind the suit's two mutually exclusive surface attachment modes.
func configure(owner_player: Player, hand_grip: PhysicalGrip, soles: MagneticBoots) -> void:
	player = owner_player
	grip = hand_grip
	boots = soles
	process_physics_priority = -15


func _unhandled_input(event: InputEvent) -> void:
	if not player.input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or event.is_echo():
		return
	if event.is_action_pressed("physical_grip"):
		_grab_requested = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("magnetic_boots"):
		_boots_requested = true
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	player.body_follow_enabled = not grip.is_attached() or Input.is_action_pressed("steer_held")
	var active: bool = player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not active:
		_grab_requested = false
		_boots_requested = false
		boots.cancel_input()
		return
	if _grab_requested:
		if grip.is_attached():
			grip.release()
		elif not boots.is_attached() and not bool(player.get_meta("seated", false)):
			grip.try_grab()
	if _boots_requested:
		if boots.is_attached():
			boots.release()
		else:
			boots.try_latch()
	_grab_requested = false
	_boots_requested = false
	boots.set_walk_input(Vector2.ZERO if Input.is_action_pressed("brake") else Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward")))
