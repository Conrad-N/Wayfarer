## Exercises suit braking through real Jolt steps, including force limits and release.
extends TestCase

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const SAMPLE_STEPS: int = 12


## Normal drift and tumbling settle in about a second, regardless of suit orientation.
func test_brake_converges_on_rotated_body() -> void:
	var orientation: Basis = Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, 0.9)
	var player: Player = _spawn_player(Vector3.ZERO, orientation)
	player.linear_velocity = Vector3(1.0, -2.0, 3.0).normalized() * 2.0
	player.angular_velocity = Vector3(-2.0, 3.0, 1.0).normalized() * 0.5
	await _physics_steps(3)
	player.set_braking(true)
	check(player.is_braking(), "brake reports held state")
	await _physics_steps(Engine.physics_ticks_per_second + 3)
	check(player.linear_velocity.length() < 0.04, "normal drift loses at least 98% of speed in about one second")
	check(player.angular_velocity.length() < 0.01, "tumbling loses at least 98% of spin in about one second")
	player.free()


## Counter-thrust slows motion over several frames without instantly stopping or reversing.
func test_brake_is_gradual_without_overshoot() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	var direction: Vector3 = Vector3(1.0, -1.0, 1.0).normalized()
	player.linear_velocity = direction * 1.0
	player.angular_velocity = Vector3.UP * 0.3
	await _physics_steps(3)
	player.set_braking(true)
	await _physics_steps(6)
	check(player.linear_velocity.length() > 0.1, "braking does not erase linear velocity immediately")
	check(player.angular_velocity.length() > 0.03, "braking does not erase spin immediately")
	var previous_speed: float = player.linear_velocity.length()
	var previous_spin: float = player.angular_velocity.length()
	var decreases: bool = true
	var no_reverse: bool = true
	for sample in 10:
		await _physics_steps(6)
		decreases = decreases and player.linear_velocity.length() <= previous_speed + 0.00001
		decreases = decreases and player.angular_velocity.length() <= previous_spin + 0.00001
		no_reverse = no_reverse and player.linear_velocity.dot(direction) >= -0.00001
		no_reverse = no_reverse and player.angular_velocity.y >= -0.00001
		previous_speed = player.linear_velocity.length()
		previous_spin = player.angular_velocity.length()
	check(decreases, "linear and angular speed decrease throughout braking")
	check(no_reverse, "counter-thrust never reverses drift or spin")
	player.free()


## Fast drift uses the finite suit force; twice the mass takes twice as long to slow.
func test_brake_force_budget_and_mass_response() -> void:
	var light: Player = _spawn_player(Vector3.ZERO)
	var heavy: Player = _spawn_player(Vector3(20.0, 0.0, 0.0))
	heavy.mass = light.mass * 2.0
	var direction: Vector3 = Vector3(1.0, 2.0, -3.0).normalized()
	for player: Player in [light, heavy]:
		player.linear_velocity = direction * 20.0
		player.set_braking(true)
	await _physics_steps(3)
	var light_before: Vector3 = light.linear_velocity
	var heavy_before: Vector3 = heavy.linear_velocity
	await _physics_steps(SAMPLE_STEPS)
	var light_change: Vector3 = light_before - light.linear_velocity
	var heavy_change: Vector3 = heavy_before - heavy.linear_velocity
	var expected: float = light.brake_force_n / light.mass * _sample_seconds()
	_check_vector(light_change, direction * expected, 0.002, "diagonal brake shares one force budget")
	_check_vector(heavy_change, light_change * 0.5, 0.002, "double mass halves braking acceleration")
	check(light.linear_velocity.length() > 15.0, "high speed cannot stop within a fraction of a second")
	light.free()
	heavy.free()


## A limited torque cannot erase extreme spin, even around the capsule's easy axis.
func test_brake_torque_budget() -> void:
	var orientation: Basis = Basis(Vector3.RIGHT, 0.6) * Basis(Vector3.BACK, 0.8)
	var player: Player = _spawn_player(Vector3.ZERO, orientation)
	var axis: Vector3 = orientation * Vector3.UP
	player.angular_velocity = axis * 10.0
	player.brake_torque_nm = 0.5
	player.set_braking(true)
	await _physics_steps(3)
	var before: Vector3 = player.angular_velocity
	var inverse_inertia: Basis = player.get_inverse_inertia_tensor()
	await _physics_steps(SAMPLE_STEPS)
	var expected_change: Vector3 = inverse_inertia * axis * player.brake_torque_nm * _sample_seconds()
	_check_vector(before - player.angular_velocity, expected_change, 0.002, "angular deceleration respects available torque and capsule inertia")
	check(player.angular_velocity.length() > 9.0, "small torque cannot instantly stop rapid spin")
	player.free()


## Releasing the brake leaves the remaining velocity alone in vacuum.
func test_releasing_brake_restores_coasting() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.linear_velocity = Vector3(1.0, -0.5, -1.0)
	player.angular_velocity = Vector3.UP * 0.4
	player.set_braking(true)
	await _physics_steps(SAMPLE_STEPS)
	player.set_braking(false)
	check(not player.is_braking(), "brake reports released state")
	await _physics_steps(3)
	var velocity: Vector3 = player.linear_velocity
	var spin: Vector3 = player.angular_velocity
	check(velocity.length() > 0.1, "release occurs while still drifting")
	check(spin.length() > 0.01, "release occurs while still rotating")
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, velocity, 0.0001, "remaining linear velocity coasts")
	_check_vector(player.angular_velocity, spin, 0.0001, "remaining angular velocity coasts")
	player.free()


## Holding brake overrides thrust and roll; releasing it resumes controls still held.
func test_brake_overrides_thrust_and_roll_until_release() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.set_motion_input(Vector3.FORWARD, 1.0)
	player.set_braking(true)
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, Vector3.ZERO, 0.00001, "brake holds against translation input")
	_check_vector(player.angular_velocity, Vector3.ZERO, 0.00001, "brake holds against roll input")
	player.set_braking(false)
	await _physics_steps(SAMPLE_STEPS)
	check(player.linear_velocity.length() > 0.1, "held thrust resumes after releasing brake")
	check(player.angular_velocity.length() > 0.01, "held roll resumes after releasing brake")
	player.free()


## A stationary suit remains stationary while braking, and mouse aim remains available.
func test_stationary_brake_allows_mouse_look() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.set_braking(true)
	await _physics_steps(3)
	player.set_freelooking(true)
	player.queue_mouse_look(Vector2(0.0, -PI / player.mouse_sensitivity))
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, Vector3.ZERO, 0.00001, "braking at rest creates no drift")
	_check_vector(player.angular_velocity, Vector3.ZERO, 0.00001, "braking at rest creates no spin")
	_check_vector(player.basis.y, Vector3.UP, 0.0001, "head aiming does not bypass brake with body teleport")
	check_near(player.head_angles_rad.y, Player.HEAD_PITCH_LIMIT_RAD, 0.0001, "head look remains available within limits")
	player.free()


## The documented physical Alt key remains bound to the hold-to-brake action.
func test_brake_uses_physical_alt_key() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_ALT
	event.pressed = true
	check(InputMap.event_is_action(event, "brake"), "physical Alt activates brake")
	event.physical_keycode = KEY_X
	check(not InputMap.event_is_action(event, "brake"), "X does not activate RCS brake")
	check(InputMap.event_is_action(event, "wheel_brake"), "physical X activates rotation-only wheel brake")


func _spawn_player(at: Vector3, orientation: Basis = Basis.IDENTITY) -> Player:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	player.position = at
	player.basis = orientation
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(player)
	return player


func _physics_steps(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for step in count:
		await tree.physics_frame


func _sample_seconds() -> float:
	return float(SAMPLE_STEPS) / float(Engine.physics_ticks_per_second)


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s, got %s" % [message, expected, actual])
