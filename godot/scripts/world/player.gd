## First-person suit controller. Thrust and roll act in the body's own frame;
## mouse look turns the whole capsule, with no preferred up direction.
class_name Player
extends RigidBody3D

@export var input_enabled: bool = true
@export var thrust_force_n: float = 180.0
@export var roll_torque_nm: float = 8.0
@export var mouse_sensitivity: float = 0.0025

var _translation_input: Vector3 = Vector3.ZERO
var _roll_input: float = 0.0
var _pending_look: Vector2 = Vector2.ZERO


func _ready() -> void:
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		set_motion_input(Vector3.ZERO, 0.0)
		return
	set_motion_input(Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("move_forward", "move_back")
	), Input.get_axis("roll_right", "roll_left"))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("ui_cancel"):
		_release_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		queue_mouse_look(motion.screen_relative)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and input_enabled:
		_release_mouse()


func _exit_tree() -> void:
	if input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(_delta: float) -> void:
	apply_central_force(global_basis * _translation_input * thrust_force_n)
	apply_torque(global_basis.z * _roll_input * roll_torque_nm)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_look == Vector2.ZERO:
		return
	# Change the rigid body's orientation only through its safe physics callback.
	# Local yaw followed by local pitch preserves whatever roll the player has.
	var yaw: Basis = Basis(Vector3.UP, -_pending_look.x * mouse_sensitivity)
	var pitch: Basis = Basis(Vector3.RIGHT, -_pending_look.y * mouse_sensitivity)
	var pose: Transform3D = state.transform
	pose.basis = (pose.basis * yaw * pitch).orthonormalized()
	state.transform = pose
	_pending_look = Vector2.ZERO


## Supply local right/up/back thrust and signed roll; diagonals share one thrust budget.
func set_motion_input(translation: Vector3, roll: float) -> void:
	_translation_input = translation.limit_length(1.0) if translation.is_finite() else Vector3.ZERO
	_roll_input = clampf(roll, -1.0, 1.0) if is_finite(roll) else 0.0


## Accumulate mouse pixels until the next physics step, independent of frame rate.
func queue_mouse_look(relative: Vector2) -> void:
	if relative.is_finite():
		_pending_look += relative


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_motion_input(Vector3.ZERO, 0.0)
	_pending_look = Vector2.ZERO
