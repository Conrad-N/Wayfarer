## Input ownership for hand grips and magnetic boots, independent of the selected cutting tool.
class_name SuitContacts
extends Node

const APPROACH_HOLD_SECONDS: float = 0.35

var player: Player
var grip: PhysicalGrip
var boots: MagneticBoots
var _grab_requested: bool = false
var _boots_requested: bool = false
var _boot_held: bool = false
var _hold_seconds: float = 0.0
var _hold_eligible: bool = false
var _approach_started: bool = false


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
	elif event.is_action("magnetic_boots"):
		set_boot_input(event.is_pressed())
		get_viewport().set_input_as_handled()


## Supply boot-button edges; a tap toggles and a sustained unlatched press approaches.
func set_boot_input(pressed: bool) -> void:
	if pressed == _boot_held:
		return
	_boot_held = pressed
	_hold_seconds = 0.0
	_approach_started = false
	_hold_eligible = pressed and not boots.is_attached()
	if pressed:
		_boots_requested = true
	else:
		boots.set_approach_held(false)


func _physics_process(delta: float) -> void:
	var active: bool = player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not active:
		set_boot_input(false)
		_grab_requested = false
		_boots_requested = false
		boots.cancel_input()
		return
	if _grab_requested:
		if grip.is_attached():
			grip.release()
		elif not boots.is_attached() and not bool(player.get_meta("seated", false)):
			grip.try_grab()
	if _boot_held and not Input.is_action_pressed("magnetic_boots"):
		set_boot_input(false)
	_advance_boot_hold(delta)
	_grab_requested = false
	boots.set_walk_input(Vector2.ZERO if Input.is_action_pressed("brake") else Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward")))


func _advance_boot_hold(delta: float) -> void:
	if _boots_requested:
		boots.toggle()
		_boots_requested = false
	if not _boot_held or not _hold_eligible:
		boots.set_approach_held(false)
		return
	_hold_seconds += maxf(delta, 0.0)
	if _hold_seconds < APPROACH_HOLD_SECONDS:
		return
	if not _approach_started:
		_approach_started = true
		# Holding an already-armed press may rearm after its initial cancel tap.
		# A press that releases a latch never immediately catches it again.
		if not boots.is_attached() and not boots.is_armed():
			boots.toggle()
	boots.set_approach_held(boots.is_armed() and not boots.is_attached())
