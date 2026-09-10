## Physical EVA suit: propellant-fed translation/braking, bounded electric reaction
## wheels for body rotation, and a freely moving head within anatomical limits.
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

const HEAD_YAW_LIMIT_RAD: float = PI / 3.0
const HEAD_PITCH_LIMIT_RAD: float = PI * 5.0 / 18.0
const BODY_FOLLOW_THRESHOLD_RAD: float = 0.21

var suit: SuitResources = SuitResources.new()
var attitude: SuitAttitude = SuitAttitude.new()
var head_angles_rad: Vector2 = Vector2.ZERO
var brake_reference: Callable
var surface_motion_active: bool = false
var body_follow_enabled: bool = true
var _body_follow: bool = false
var _gaze_world: Vector3 = Vector3.FORWARD
@onready var grapple: Grapple = $Grapple
var salvage_tools: SalvageTools
var _capture_click_held: bool = false
var _secondary_blocked: bool = false

var _translation_input: Vector3 = Vector3.ZERO
var _roll_input: float = 0.0
var _pending_look: Vector2 = Vector2.ZERO
var _braking: bool = false
var _wheel_braking: bool = false


func _ready() -> void:
	grapple.configure(self, suit, $Camera3D)
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_body_follow = false
		set_motion_input(Vector3.ZERO, 0.0)
		set_braking(false)
		set_wheel_braking(false)
		grapple.cancel_input()
		if is_instance_valid(salvage_tools):
			salvage_tools.cancel_input()
		return
	if not Input.is_action_pressed("tool_primary"):
		_capture_click_held = false
	if not Input.is_action_pressed("tool_secondary"):
		_secondary_blocked = false
	if is_instance_valid(salvage_tools) and salvage_tools.selected != SalvageTools.Tool.GRAPPLE:
		grapple.cancel_input()
		salvage_tools.set_triggers(Input.is_action_pressed("tool_primary") and not _capture_click_held, Input.is_action_pressed("tool_secondary") and not _secondary_blocked)
	else:
		grapple.set_reel_input(Input.get_axis("grapple_reel_out", "grapple_reel_in"))
	set_braking(Input.is_action_pressed("brake"))
	set_wheel_braking(Input.is_action_pressed("wheel_brake"))
	set_motion_input(Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_down", "move_up"),
		Input.get_axis("move_forward", "move_back")
	), Input.get_axis("roll_right", "roll_left"))


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if is_instance_valid(salvage_tools):
		for slot: int in range(4):
			if event.is_action_pressed("tool_slot_%d" % (slot + 1)):
				salvage_tools.select_tool(slot as SalvageTools.Tool)
				_capture_click_held = Input.is_action_pressed("tool_primary")
				_secondary_blocked = Input.is_action_pressed("tool_secondary")
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		_release_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_capture_click_held = true
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _grapple_selected() and event.is_action_pressed("tool_primary"):
			grapple.request_attach()
			get_viewport().set_input_as_handled()
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _grapple_selected() and event.is_action_pressed("tool_secondary"):
			grapple.detach()
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
	if not body_follow_enabled:
		_body_follow = false
	_update_head()
	if freeze:
		_body_follow = false
		return
	# Rotating wheel axes transfers their stored momentum back to the body,
	# including through seats and boots while their suit motors are disabled.
	var omega_body: Vector3 = global_basis.transposed() * angular_velocity
	var inverse_inertia: Basis = get_inverse_inertia_tensor()
	var gyro_torque: Vector3 = global_basis * attitude.gyroscopic_torque(omega_body)
	if inverse_inertia.determinant() > 0.0:
		gyro_torque -= angular_velocity.cross(inverse_inertia.inverse() * angular_velocity)
	apply_torque(gyro_torque)
	if surface_motion_active or bool(get_meta("seated", false)):
		_body_follow = false
		return
	if _braking:
		_body_follow = false
		_apply_brake(delta)
		return
	_apply_suit_forces(global_basis * _translation_input * thrust_force_n, Vector3.ZERO, delta)
	var motor_torque: Vector3 = Vector3.BACK * _roll_input * roll_torque_nm
	if _wheel_braking:
		_body_follow = false
		motor_torque = _wheel_brake_torque(delta, inverse_inertia)
	elif _body_follow:
		var desired_rate: Vector3 = Vector3(head_angles_rad.y, head_angles_rad.x, 0.0) * 2.0
		desired_rate = desired_rate.limit_length(0.8)
		if inverse_inertia.determinant() > 0.0:
			var acceleration: Vector3 = Vector3(desired_rate.x - omega_body.x, desired_rate.y - omega_body.y, 0.0) * 5.0
			motor_torque += global_basis.transposed() * (inverse_inertia.inverse() * (global_basis * acceleration))
		if head_angles_rad.length() < 0.01 and Vector2(omega_body.x, omega_body.y).length() < 0.01:
			_body_follow = false
	var delivered: Vector3 = attitude.drive(motor_torque, omega_body, roll_torque_nm, delta, suit)
	apply_torque(global_basis * delivered)


func _update_head() -> void:
	var requested_look: bool = _pending_look != Vector2.ZERO
	if _body_follow and not freeze and not _braking and not _wheel_braking:
		var direction: Vector3 = global_basis.transposed() * _gaze_world
		head_angles_rad = Vector2(atan2(-direction.x, -direction.z), asin(clampf(direction.y, -1.0, 1.0)))
	if _pending_look != Vector2.ZERO:
		head_angles_rad -= _pending_look * mouse_sensitivity
		_pending_look = Vector2.ZERO
	head_angles_rad.x = clampf(head_angles_rad.x, -HEAD_YAW_LIMIT_RAD, HEAD_YAW_LIMIT_RAD)
	head_angles_rad.y = clampf(head_angles_rad.y, -HEAD_PITCH_LIMIT_RAD, HEAD_PITCH_LIMIT_RAD)
	var camera: Camera3D = $Camera3D
	camera.basis = Basis(Vector3.UP, head_angles_rad.x) * Basis(Vector3.RIGHT, head_angles_rad.y)
	_gaze_world = -camera.global_basis.z
	if requested_look and body_follow_enabled and head_angles_rad.length() > BODY_FOLLOW_THRESHOLD_RAD and not freeze and not _braking and not _wheel_braking:
		_body_follow = true


## Supply local right/up/back thrust and signed roll; diagonals share one thrust budget.
func set_motion_input(translation: Vector3, roll: float) -> void:
	_translation_input = translation.limit_length(1.0) if translation.is_finite() else Vector3.ZERO
	_roll_input = clampf(roll, -1.0, 1.0) if is_finite(roll) else 0.0


## Accumulate free head-look pixels; larger offsets request powered body follow.
func queue_mouse_look(relative: Vector2) -> void:
	if relative.is_finite():
		_pending_look += relative


## Hold suit RCS braking in the local scene's frame; it takes priority over thrust and roll.
func set_braking(enabled: bool) -> void:
	_braking = enabled


## Report whether the suit is commanded to brake, including while already stationary.
func is_braking() -> bool:
	return _braking


## Hold rotation-only wheel braking; translation remains available and no jets fire for rotation.
func set_wheel_braking(enabled: bool) -> void:
	_wheel_braking = enabled


## Report the commanded wheel brake state, including at rest or saturation.
func is_wheel_braking() -> bool:
	return _wheel_braking


func _wheel_brake_torque(delta: float, inverse_inertia: Basis) -> Vector3:
	if delta <= 0.0 or not is_finite(delta):
		return Vector3.ZERO
	var omega: Vector3 = angular_velocity
	var world_inertia: Basis = inverse_inertia.inverse() if inverse_inertia.determinant() > 0.0 else Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	if brake_reference.is_valid():
		var reference: Dictionary = brake_reference.call()
		omega = reference.get("angular_velocity", omega)
		world_inertia = reference.get("inertia", world_inertia)
	var gain: float = (1.0 - exp(-log(100.0) * delta / maxf(brake_response_seconds, 0.1))) / delta
	# The motor's equal opposing impulse remains in the rotors. A held load can
	# demand more torque or storage than the suit has; saturation leaves it spinning.
	return global_basis.transposed() * (world_inertia * (-omega * gain))


func _apply_brake(delta: float) -> void:
	if delta <= 0.0:
		return
	# Remove 99% of motion in the response time when the jets are not saturated.
	# This step-aware gain cannot demand a velocity reversal, even at low tick rates.
	var response: float = maxf(brake_response_seconds, 0.1)
	var gain: float = (1.0 - exp(-log(100.0) * delta / response)) / delta
	var velocity: Vector3 = linear_velocity
	var omega: Vector3 = angular_velocity
	var effective_mass: float = mass
	var inverse_inertia: Basis = get_inverse_inertia_tensor()
	var world_inertia: Basis = inverse_inertia.inverse() if inverse_inertia.determinant() > 0.0 else Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var offset: Vector3 = Vector3.ZERO
	if brake_reference.is_valid():
		var reference: Dictionary = brake_reference.call()
		velocity = reference.get("velocity", velocity)
		omega = reference.get("angular_velocity", omega)
		effective_mass = reference.get("mass", effective_mass)
		world_inertia = reference.get("inertia", world_inertia)
		offset = reference.get("force_offset", offset)
	var force: Vector3 = (-velocity * effective_mass * gain).limit_length(maxf(brake_force_n, 0.0))
	# Reserve enough opposed-jet torque to cancel the moment of translation around
	# the coupled centre of mass. A distant grip cannot create an unlimited lever.
	var force_moment: Vector3 = offset.cross(force)
	if force_moment.length() > brake_torque_nm * 0.5 and force_moment.length() > 0.0:
		force *= maxf(brake_torque_nm, 0.0) * 0.5 / force_moment.length()
		force_moment = offset.cross(force)
	var torque: Vector3 = (world_inertia * (-omega * gain)).limit_length(maxf(brake_torque_nm - force_moment.length(), 0.0)) - force_moment
	# Desaturation drives the wheels toward zero while opposed RCS cancels their
	# body reaction. Scale wheel command to the jet budget and fuel available first.
	var omega_body: Vector3 = global_basis.transposed() * angular_velocity
	var unload: Vector3 = (attitude.momentum_body / delta).limit_length(maxf(roll_torque_nm, 0.0))
	var jet_room: float = maxf(brake_torque_nm - torque.length(), 0.0)
	unload = unload.limit_length(jet_room)
	var fuel_request: float = (force.length() + (torque.length() + unload.length()) / maxf(thruster_lever_arm_m, 0.01)) * delta / maxf(exhaust_velocity_mps, 1.0)
	var fuel_fraction: float = minf(suit.propellant_kg / fuel_request, 1.0) if fuel_request > 0.0 else 0.0
	var delivered: Vector3 = attitude.drive(unload * fuel_fraction, omega_body, roll_torque_nm, delta, suit)
	var wheel_torque_world: Vector3 = global_basis * delivered
	# Reserve fuel for exactly cancelling wheel unloading before ordinary braking.
	var cancel_fuel: float = wheel_torque_world.length() * delta / (maxf(thruster_lever_arm_m, 0.01) * maxf(exhaust_velocity_mps, 1.0))
	var spent: float = suit.consume_propellant(cancel_fuel)
	mass = maxf(mass - spent, 0.001)
	# Equal motor and jet torques cancel; the expelled gas carries the removed
	# rotor momentum. Do not submit cancelling floats as separate engine forces.
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
	set_wheel_braking(false)
	_pending_look = Vector2.ZERO
	_body_follow = false
	if is_instance_valid(grapple):
		grapple.cancel_input()
	if is_instance_valid(salvage_tools):
		salvage_tools.cancel_input()


func _grapple_selected() -> bool:
	return not is_instance_valid(salvage_tools) or salvage_tools.selected == SalvageTools.Tool.GRAPPLE
