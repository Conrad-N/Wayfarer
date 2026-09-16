## Physical EVA suit: propellant-fed translation/braking, bounded electric reaction
## wheels for body rotation, modifier-held EVA head look, and free walking aim.
class_name Player
extends RigidBody3D

@export var input_enabled: bool = true
@export var thrust_force_n: float = 180.0
@export var roll_torque_nm: float = 50.0
@export var mouse_sensitivity: float = 0.0025
@export_range(0.0, 2000.0, 1.0) var brake_force_n: float = 600.0
@export_range(0.0, 200.0, 1.0) var brake_torque_nm: float = 60.0
@export_range(0.1, 5.0, 0.1) var brake_response_seconds: float = 1.0
@export_range(1.0, 10000.0, 1.0) var exhaust_velocity_mps: float = 2000.0
@export_range(0.01, 2.0, 0.01) var thruster_lever_arm_m: float = 0.5

## Esc was pressed with no screen open.
signal pause_requested

const HEAD_YAW_LIMIT_RAD: float = PI / 3.0
const HEAD_PITCH_LIMIT_RAD: float = PI * 5.0 / 18.0
const SURFACE_PITCH_LIMIT_RAD: float = PI * 17.0 / 36.0

var suit: SuitResources = SuitResources.new()
var attitude: SuitAttitude = SuitAttitude.new()
var head_angles_rad: Vector2 = Vector2.ZERO
var brake_reference: Callable
var surface_motion_active: bool = false:
	set(active):
		if surface_motion_active == active:
			return
		surface_motion_active = active
		_cancel_body_look()
		_pending_look = Vector2.ZERO
		_surface_look = Vector2.ZERO
		if active:
			_view_handoff_to_head()
		else:
			_begin_view_handoff()
var body_follow_enabled: bool = true
var _body_follow: bool = false
var _look_remaining: Vector2 = Vector2.ZERO
var _look_previous_basis: Basis = Basis.IDENTITY
var _surface_look: Vector2 = Vector2.ZERO
var _freelooking: bool = false
var _view_handoff: bool = false
var _view_offset: Basis = Basis.IDENTITY
var _view_previous_basis: Basis = Basis.IDENTITY
@onready var grapple: Grapple = $Grapple
var salvage_tools: SalvageTools
var _capture_click_held: bool = false
var _secondary_blocked: bool = false

var _boot_approach_active: bool = false
var _boot_approach_force: Vector3 = Vector3.ZERO
var _boot_approach_torque: Vector3 = Vector3.ZERO
var _translation_input: Vector3 = Vector3.ZERO
var _roll_input: float = 0.0
var _pending_look: Vector2 = Vector2.ZERO
var _braking: bool = false
var _wheel_braking: bool = false
var _wheel_dumping: bool = false
var _view_handoff_started_s: float = 0.0


func _ready() -> void:
	grapple.configure(self, suit, $Camera3D)
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if not input_enabled:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		centre_head()
		set_freelooking(false)
		set_motion_input(Vector3.ZERO, 0.0)
		set_braking(false)
		set_wheel_braking(false)
		set_wheel_dumping(false)
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
	set_freelooking(Input.is_action_pressed("freelook"))
	set_braking(Input.is_action_pressed("brake"))
	set_wheel_braking(Input.is_action_pressed("wheel_brake"))
	set_wheel_dumping(Input.is_action_pressed("wheel_dump"))
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
	if event.is_action("freelook"):
		set_freelooking(event.is_pressed() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_release_mouse()
		pause_requested.emit()
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
		_cancel_body_look()
	_update_head()
	_update_body_look()
	if freeze:
		_body_follow = false
		return
	# Rotating wheel axes transfers their stored momentum back to the body,
	# including through seats and boots while their suit motors are disabled.
	var omega_body: Vector3 = global_basis.transposed() * angular_velocity
	var inverse_inertia: Basis = get_inverse_inertia_tensor()
	if inverse_inertia.determinant() > 0.0:
		var inverse_body: Basis = global_basis.transposed() * inverse_inertia * global_basis
		apply_torque(global_basis * GyroscopicMotion.torque(omega_body, inverse_body.inverse(), attitude.momentum_body, delta))
	if _wheel_dumping:
		_body_follow = false
		# Only the suit receives this motor reaction. Joints/contact carry it to
		# anything held, whose own attitude controller may respond independently.
		if delta > 0.0:
			var dump_torque: Vector3 = attitude.drive(attitude.momentum_body / delta, omega_body, roll_torque_nm, delta, suit, global_basis.transposed() * inverse_inertia * global_basis)
			apply_torque(global_basis * dump_torque)
		return
	if surface_motion_active or bool(get_meta("seated", false)):
		_body_follow = false
		return
	if _braking:
		_body_follow = false
		_apply_brake(delta)
		return
	if _boot_approach_active and not _wheel_braking:
		_boot_approach_active = false
		_cancel_body_look()
		_apply_thrust(_boot_approach_force.limit_length(thrust_force_n), delta)
		var approach_delivered: Vector3 = attitude.drive(_boot_approach_torque, omega_body, roll_torque_nm, delta, suit, global_basis.transposed() * inverse_inertia * global_basis)
		apply_torque(global_basis * approach_delivered)
		return
	_apply_thrust(global_basis * _translation_input * thrust_force_n, delta)
	var motor_torque: Vector3 = Vector3.BACK * _roll_input * roll_torque_nm
	if _wheel_braking:
		_body_follow = false
		motor_torque = _wheel_brake_torque(delta, inverse_inertia)
	elif _body_follow:
		motor_torque += _body_look_torque(omega_body, inverse_inertia)
	elif _view_handoff:
		motor_torque += _view_handoff_torque(omega_body, inverse_inertia)
	var delivered: Vector3 = attitude.drive(motor_torque, omega_body, roll_torque_nm, delta, suit, global_basis.transposed() * inverse_inertia * global_basis)
	apply_torque(global_basis * delivered)


func _update_head() -> void:
	var camera: Camera3D = $Camera3D
	if has_automatic_freelook():
		# Strapping in poses the head itself; boots convert the view when they latch.
		_view_handoff = false
		head_angles_rad -= _pending_look * mouse_sensitivity
		head_angles_rad.x = wrapf(head_angles_rad.x, -PI, PI)
		head_angles_rad.y = clampf(head_angles_rad.y, -SURFACE_PITCH_LIMIT_RAD, SURFACE_PITCH_LIMIT_RAD)
	elif _view_handoff:
		_track_view_handoff()
		head_angles_rad = Vector2.ZERO
		_pending_look = Vector2.ZERO
		camera.basis = _view_offset
		return
	elif _freelooking:
		head_angles_rad -= _pending_look * mouse_sensitivity
		head_angles_rad.x = clampf(head_angles_rad.x, -HEAD_YAW_LIMIT_RAD, HEAD_YAW_LIMIT_RAD)
		head_angles_rad.y = clampf(head_angles_rad.y, -HEAD_PITCH_LIMIT_RAD, HEAD_PITCH_LIMIT_RAD)
	else:
		head_angles_rad = Vector2.ZERO
	_pending_look = Vector2.ZERO
	camera.basis = Basis(Vector3.UP, head_angles_rad.x) * Basis(Vector3.RIGHT, head_angles_rad.y)


func _update_body_look() -> void:
	if not _body_follow:
		return
	# Measure actual rotation instead of assuming a motor command succeeded. The
	# unwrapped remainder retains a complete fast swipe, even beyond half a turn.
	var rotation_step: Quaternion = (_look_previous_basis.transposed() * global_basis).get_rotation_quaternion()
	if rotation_step.w < 0.0:
		rotation_step = -rotation_step
	# atan2 retains tiny physical turns that acos(w) and get_axis lose near zero.
	var imaginary: Vector3 = Vector3(rotation_step.x, rotation_step.y, rotation_step.z)
	var sine_half: float = imaginary.length()
	var turned: Vector3 = imaginary * (2.0 * atan2(sine_half, rotation_step.w) / sine_half) if sine_half > 1e-10 else imaginary * 2.0
	_look_remaining -= Vector2(turned.y, turned.x)
	_look_previous_basis = global_basis


func _body_look_torque(omega_body: Vector3, inverse_inertia: Basis) -> Vector3:
	if inverse_inertia.determinant() <= 0.0:
		return Vector3.ZERO
	var inverse_body: Basis = _steering_inverse_inertia(inverse_inertia)
	var error: Vector3 = Vector3(_look_remaining.y, _look_remaining.x, 0.0)
	var desired_rate: Vector3 = Vector3.ZERO
	for axis: int in 2:
		var acceleration: float = maxf(inverse_body[axis][axis] * roll_torque_nm, 0.0)
		# Begin slowing while there is still room to stop with the same finite
		# motor torque. There is no fixed turning-speed limit or anatomical clamp.
		desired_rate[axis] = signf(error[axis]) * minf(absf(error[axis]) * 4.0, sqrt(1.6 * acceleration * absf(error[axis])))
	var correction: Vector3 = Vector3(desired_rate.x - omega_body.x, desired_rate.y - omega_body.y, 0.0) * 8.0
	if _look_remaining.length() < 0.0002 and Vector2(omega_body.x, omega_body.y).length() < 0.0003:
		_cancel_body_look()
		return Vector3.ZERO
	return inverse_body.inverse() * correction


## Body-frame inverse inertia for steering. A held load turns with the suit; plan
## the stop with the pair's inertia or it overshoots.
func _steering_inverse_inertia(inverse_inertia: Basis) -> Basis:
	var world_inverse: Basis = inverse_inertia
	if brake_reference.is_valid():
		var reference: Dictionary = brake_reference.call()
		if reference.has("inertia") and (reference.inertia as Basis).determinant() > 0.0:
			world_inverse = (reference.inertia as Basis).inverse()
	return global_basis.transposed() * world_inverse * global_basis


func _cancel_body_look() -> void:
	_body_follow = false
	_look_remaining = Vector2.ZERO


## Leaving free camera aim keeps the view where it points; the suit then turns to face it.
func _begin_view_handoff() -> void:
	head_angles_rad = Vector2.ZERO
	var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
	if not is_instance_valid(camera) or camera.basis.is_equal_approx(Basis.IDENTITY):
		return
	_view_offset = camera.basis.orthonormalized()
	_view_previous_basis = global_basis
	_view_handoff = true
	_view_handoff_started_s = Time.get_ticks_msec() / 1000.0
	DebugLog.event("player", "view turn begun: %.0f deg off heading" % rad_to_deg(_view_offset.get_rotation_quaternion().get_angle()))


## Latching again mid-turn carries the unfinished view over as free head aim.
func _view_handoff_to_head() -> void:
	if not _view_handoff:
		return
	var forward: Vector3 = -_view_offset.z
	head_angles_rad = Vector2(atan2(-forward.x, -forward.z), asin(clampf(forward.y, -1.0, 1.0)))
	_view_handoff = false
	_view_offset = Basis.IDENTITY
	DebugLog.event("player", "view turn interrupted: %.1fs elapsed, kept as head aim" % (Time.get_ticks_msec() / 1000.0 - _view_handoff_started_s))


## Hold the view still in space while the suit turns underneath it. A held roll
## key rolls the view with the suit instead.
func _track_view_handoff() -> void:
	var step: Quaternion = (_view_previous_basis.transposed() * global_basis).get_rotation_quaternion()
	_view_previous_basis = global_basis
	if _roll_input != 0.0:
		step.z = 0.0
		step = step.normalized()
	_view_offset = (Basis(step).transposed() * _view_offset).orthonormalized()


## Turn the suit toward the held view with the same finite wheels as mouse steering.
func _view_handoff_torque(omega_body: Vector3, inverse_inertia: Basis) -> Vector3:
	if inverse_inertia.determinant() <= 0.0:
		return Vector3.ZERO
	var turn: Quaternion = _view_offset.get_rotation_quaternion()
	if turn.w < 0.0:
		turn = -turn
	var imaginary: Vector3 = Vector3(turn.x, turn.y, turn.z)
	var sine_half: float = imaginary.length()
	var error: Vector3 = imaginary * (2.0 * atan2(sine_half, turn.w) / sine_half) if sine_half > 1e-10 else imaginary * 2.0
	if _roll_input != 0.0:
		error.z = 0.0
	if error.length() < 0.0005 and omega_body.length() < 0.001:
		_view_handoff = false
		_view_offset = Basis.IDENTITY
		($Camera3D as Camera3D).basis = Basis.IDENTITY
		DebugLog.event("player", "view turn finished: %.1fs elapsed" % (Time.get_ticks_msec() / 1000.0 - _view_handoff_started_s))
		return Vector3.ZERO
	var inverse_body: Basis = _steering_inverse_inertia(inverse_inertia)
	var desired_rate: Vector3 = Vector3.ZERO
	for axis: int in 3:
		var acceleration: float = maxf(inverse_body[axis][axis] * roll_torque_nm, 0.0)
		desired_rate[axis] = signf(error[axis]) * minf(absf(error[axis]) * 4.0, sqrt(1.6 * acceleration * absf(error[axis])))
	var correction: Vector3 = (desired_rate - omega_body) * 8.0
	if _roll_input != 0.0:
		correction.z = 0.0
	return inverse_body.inverse() * correction


## Supply boot approach requests through the normal finite suit actuators once per tick.
func set_boot_approach(active: bool, force_world: Vector3 = Vector3.ZERO, torque_body: Vector3 = Vector3.ZERO) -> void:
	_boot_approach_active = active
	_boot_approach_force = force_world if force_world.is_finite() else Vector3.ZERO
	_boot_approach_torque = torque_body if torque_body.is_finite() else Vector3.ZERO
	if active:
		_cancel_body_look()


## Centre the view after an explicit seated-pose transition, clearing pending steering.
func centre_head() -> void:
	head_angles_rad = Vector2.ZERO
	_pending_look = Vector2.ZERO
	_surface_look = Vector2.ZERO
	_cancel_body_look()
	var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
	if is_instance_valid(camera):
		camera.basis = _view_offset if _view_handoff else Basis.IDENTITY


## Hold EVA head-only aiming; walking and seating already permit free camera aim.
func set_freelooking(enabled: bool) -> void:
	if _freelooking == enabled:
		return
	_freelooking = enabled
	if not has_automatic_freelook():
		centre_head()


## Report always-on free camera aiming supplied by boots or the pilot seat.
func has_automatic_freelook() -> bool:
	return surface_motion_active or bool(get_meta("seated", false))


## Report whether the EVA head-look modifier is held.
func is_freelooking() -> bool:
	return _freelooking


## Consume separate surface steering; free camera aim does not populate this queue.
func take_surface_look() -> Vector2:
	var result: Vector2 = _surface_look
	_surface_look = Vector2.ZERO
	return result


## Supply local right/up/back thrust and signed roll; diagonals share one thrust budget.
func set_motion_input(translation: Vector3, roll: float) -> void:
	_translation_input = translation.limit_length(1.0) if translation.is_finite() else Vector3.ZERO
	_roll_input = clampf(roll, -1.0, 1.0) if is_finite(roll) else 0.0


## Route mouse pixels at event time to free head aim or a complete powered body turn.
func queue_mouse_look(relative: Vector2) -> void:
	if not relative.is_finite():
		return
	if has_automatic_freelook():
		_pending_look += relative
	elif _view_handoff:
		# The view keeps leading; the suit's turn simply gets a new goal.
		_view_offset = _view_offset * Basis(Vector3.UP, -relative.x * mouse_sensitivity) * Basis(Vector3.RIGHT, -relative.y * mouse_sensitivity)
	elif _freelooking:
		_pending_look += relative
	elif not freeze and not bool(get_meta("seated", false)) and body_follow_enabled and not _braking and not _wheel_braking and not _wheel_dumping:
		if not _body_follow:
			_look_previous_basis = global_basis
			_look_remaining = Vector2.ZERO
		_body_follow = true
		_look_remaining -= relative * mouse_sensitivity


## Hold suit RCS braking in the local scene's frame; it takes priority over thrust and roll.
func set_braking(enabled: bool) -> void:
	if enabled != _braking:
		if enabled:
			DebugLog.event("player", "jet brake engaged: killing %.2f m/s" % linear_velocity.length())
		else:
			DebugLog.event("player", "jet brake ended: %.2f m/s remaining" % linear_velocity.length())
	_braking = enabled


## Report whether the suit is commanded to brake, including while already stationary.
func is_braking() -> bool:
	return _braking


## Hold rotation-only wheel braking; translation remains available and no jets fire for rotation.
func set_wheel_braking(enabled: bool) -> void:
	if enabled != _wheel_braking:
		if enabled:
			DebugLog.event("player", "wheel brake engaged: %.2f rad/s spin" % angular_velocity.length())
		else:
			DebugLog.event("player", "wheel brake finished: %.2f rad/s spin" % angular_velocity.length())
	_wheel_braking = enabled


## Report the commanded wheel brake state, including at rest or saturation.
func is_wheel_braking() -> bool:
	return _wheel_braking


## Hold rotor unloading: its real reaction spins the suit and any physical support.
func set_wheel_dumping(enabled: bool) -> void:
	var before: bool = is_wheel_dumping()
	_wheel_dumping = enabled
	_log_wheel_dump_transition(before)


## Log held unloading starting or finishing once, despite per-frame input polling.
func _log_wheel_dump_transition(before: bool) -> void:
	var after: bool = is_wheel_dumping()
	if after == before:
		return
	if after:
		DebugLog.event("player", "wheel dump engaged: %.1f N m s stored" % attitude.momentum_body.length())
	else:
		DebugLog.event("player", "wheel dump finished: %.1f N m s remaining" % attitude.momentum_body.length())


## Report held unloading, including in a seat or latched boots.
func is_wheel_dumping() -> bool:
	return _wheel_dumping


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
	var delivered: Vector3 = attitude.drive(unload * fuel_fraction, omega_body, roll_torque_nm, delta, suit, global_basis.transposed() * inverse_inertia * global_basis)
	var wheel_torque_world: Vector3 = global_basis * delivered
	# Reserve fuel for exactly cancelling wheel unloading before ordinary braking.
	var cancel_fuel: float = wheel_torque_world.length() * delta / (maxf(thruster_lever_arm_m, 0.01) * maxf(exhaust_velocity_mps, 1.0))
	var spent: float = suit.consume_propellant(cancel_fuel)
	mass = maxf(mass - spent, 0.001)
	# Equal motor and jet torques cancel; the expelled gas carries the removed
	# rotor momentum. Do not submit cancelling floats as separate engine forces.
	_apply_suit_forces(force, torque, delta)


func _apply_thrust(force: Vector3, delta: float) -> void:
	var offset: Vector3 = Vector3.ZERO
	if brake_reference.is_valid():
		offset = (brake_reference.call() as Dictionary).get("force_offset", offset)
	# Jets push at the suit's own centre, which turns a held load about the pair's
	# shared centre of mass. Opposed jets cancel that moment; past their torque
	# rating the push is reduced, so sideways thrust with a big load is weaker.
	var moment: Vector3 = offset.cross(force)
	var budget: float = maxf(brake_torque_nm, 0.0)
	if moment.length() > budget:
		force *= budget / moment.length()
		moment = offset.cross(force)
	_apply_suit_forces(force, -moment, delta)


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


## Take the mouse back after a menu, without the click or key that closed it firing a tool.
func resume_control() -> void:
	_capture_click_held = true
	_secondary_blocked = true
	if input_enabled and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	set_boot_approach(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_motion_input(Vector3.ZERO, 0.0)
	set_braking(false)
	set_wheel_braking(false)
	set_wheel_dumping(false)
	set_freelooking(false)
	centre_head()
	if is_instance_valid(grapple):
		grapple.cancel_input()
	if is_instance_valid(salvage_tools):
		salvage_tools.cancel_input()


func _grapple_selected() -> bool:
	return not is_instance_valid(salvage_tools) or salvage_tools.selected == SalvageTools.Tool.GRAPPLE
