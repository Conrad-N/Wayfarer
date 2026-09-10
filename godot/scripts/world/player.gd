## First-person suit controller. Thrust and roll act in the body's own frame;
## mouse look turns the whole capsule, with no preferred up direction.
class_name Player
extends RigidBody3D

@export var input_enabled: bool = true
@export var thrust_force_n: float = 180.0
@export var roll_torque_nm: float = 8.0
@export var mouse_sensitivity: float = 0.0025
@export_range(0.0, 2000.0, 1.0) var brake_force_n: float = 600.0
@export_range(0.0, 200.0, 1.0) var brake_torque_nm: float = 60.0
@export_range(0.1, 5.0, 0.1) var brake_response_seconds: float = 1.0
@export_range(1.0, 10000.0, 1.0) var exhaust_velocity_mps: float = 2000.0
@export_range(0.01, 2.0, 0.01) var thruster_lever_arm_m: float = 0.5

var suit: SuitResources = SuitResources.new()

var _translation_input: Vector3 = Vector3.ZERO
var _roll_input: float = 0.0
var _pending_look: Vector2 = Vector2.ZERO
var _braking: bool = false


func _ready() -> void:
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		set_motion_input(Vector3.ZERO, 0.0)
		set_braking(false)
		return
	set_braking(Input.is_action_pressed("brake"))
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


func _physics_process(delta: float) -> void:
	if _braking:
		_apply_brake(delta)
		return
	_apply_suit_forces(
		global_basis * _translation_input * thrust_force_n,
		global_basis.z * _roll_input * roll_torque_nm, delta
	)


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


## Hold suit RCS braking in the local scene's frame; it takes priority over thrust and roll.
func set_braking(enabled: bool) -> void:
	_braking = enabled


## Report whether the suit is commanded to brake, including while already stationary.
func is_braking() -> bool:
	return _braking


func _apply_brake(delta: float) -> void:
	if delta <= 0.0:
		return
	# Remove 99% of motion in the response time when the jets are not saturated.
	# This step-aware gain cannot demand a velocity reversal, even at low tick rates.
	var response: float = maxf(brake_response_seconds, 0.1)
	var gain: float = (1.0 - exp(-log(100.0) * delta / response)) / delta
	var force: Vector3 = (-linear_velocity * mass * gain).limit_length(maxf(brake_force_n, 0.0))
	# The capsule resists spin differently on each axis. Convert the requested
	# angular deceleration through its current world-space inertia before limiting jets.
	var inverse_inertia: Basis = get_inverse_inertia_tensor()
	var torque: Vector3 = Vector3.ZERO
	if inverse_inertia.determinant() > 0.0:
		torque = inverse_inertia.inverse() * (-angular_velocity * gain)
		torque = torque.limit_length(maxf(brake_torque_nm, 0.0))
	_apply_suit_forces(force, torque, delta)


func _apply_suit_forces(force: Vector3, torque: Vector3, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# Torque comes from opposed jets: their summed force is torque / lever arm.
	var jet_force: float = force.length() + torque.length() / maxf(thruster_lever_arm_m, 0.01)
	var requested: float = jet_force * delta / maxf(exhaust_velocity_mps, 1.0)
	if not is_finite(requested) or requested <= 0.0:
		return
	var spent: float = suit.consume_propellant(requested)
	if spent <= 0.0:
		return
	var fraction: float = spent / requested
	# The last partial tick delivers only the impulse its remaining fuel can buy.
	mass = maxf(mass - spent, 0.001)
	apply_central_force(force * fraction)
	apply_torque(torque * fraction)


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_motion_input(Vector3.ZERO, 0.0)
	set_braking(false)
	_pending_look = Vector2.ZERO
