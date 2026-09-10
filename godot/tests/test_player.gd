## Exercises the EVA controller through real headless Jolt physics steps.
## Sampling after startup frames excludes the body registration/force submission delay.
extends TestCase

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const SAMPLE_STEPS: int = 12


## The reusable player is a free, undamped capsule with an attached first-person camera.
func test_scene_has_free_capsule_and_camera() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	check(packed != null, "player scene loads")
	if packed == null:
		return
	var player: Player = packed.instantiate() as Player
	check(player != null, "player scene root uses the rigid-body controller")
	if player == null:
		return
	check_near(player.mass, 100.0, 0.001, "suited player mass in kilograms")
	check_near(player.gravity_scale, 0.0, 0.0, "no gravity")
	check_near(player.linear_damp, 0.0, 0.0, "no translational damping")
	check_near(player.angular_damp, 0.0, 0.0, "no rotational damping")
	check(not player.can_sleep, "player remains responsive while stationary")
	check(not player.lock_rotation, "rotation is free")
	for axis in [PhysicsServer3D.BODY_AXIS_LINEAR_X, PhysicsServer3D.BODY_AXIS_LINEAR_Y,
		PhysicsServer3D.BODY_AXIS_LINEAR_Z, PhysicsServer3D.BODY_AXIS_ANGULAR_X,
		PhysicsServer3D.BODY_AXIS_ANGULAR_Y, PhysicsServer3D.BODY_AXIS_ANGULAR_Z]:
		check(not player.get_axis_lock(axis), "axis %d is unlocked" % axis)
	var collision: CollisionShape3D = _find_type(player, "CollisionShape3D") as CollisionShape3D
	check(collision != null, "has capsule collision")
	if collision != null:
		var capsule: CapsuleShape3D = collision.shape as CapsuleShape3D
		check(capsule != null, "collision uses a capsule")
		if capsule != null:
			check_near(capsule.radius, 0.35, 0.001, "capsule radius")
			check_near(capsule.height, 1.8, 0.001, "capsule height")
	var camera: Camera3D = _find_type(player, "Camera3D") as Camera3D
	check(camera != null, "has first-person camera")
	if camera != null:
		check(camera.current, "player camera is selected")
	player.free()


## All six translation directions accelerate by force divided by mass.
func test_thrust_acceleration_in_all_six_directions() -> void:
	var directions: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP,
		Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	var players: Array[Player] = []
	for i in directions.size():
		var player: Player = _spawn_player(Vector3(float(i) * 10.0, 0.0, 0.0))
		player.set_motion_input(directions[i], 0.0)
		players.append(player)
	await _physics_steps(3)
	var before: Array[Vector3] = []
	for player in players:
		before.append(player.linear_velocity)
	await _physics_steps(SAMPLE_STEPS)
	for i in players.size():
		var player: Player = players[i]
		var expected: Vector3 = directions[i] * player.thrust_force_n / player.mass * _sample_seconds()
		_check_vector(player.linear_velocity - before[i], expected, 0.002, "axis %s acceleration" % directions[i])
		player.free()


## Doubling mass halves acceleration, and diagonal input cannot provide extra force.
func test_mass_and_diagonal_thrust_budget() -> void:
	var light: Player = _spawn_player(Vector3.ZERO)
	var heavy: Player = _spawn_player(Vector3(10.0, 0.0, 0.0))
	var diagonal: Player = _spawn_player(Vector3(20.0, 0.0, 0.0))
	heavy.mass = light.mass * 2.0
	light.set_motion_input(Vector3.FORWARD, 0.0)
	heavy.set_motion_input(Vector3.FORWARD, 0.0)
	diagonal.set_motion_input(Vector3(1.0, 1.0, -1.0), 0.0)
	await _physics_steps(3)
	var initial_light: Vector3 = light.linear_velocity
	var initial_heavy: Vector3 = heavy.linear_velocity
	var initial_diagonal: Vector3 = diagonal.linear_velocity
	await _physics_steps(SAMPLE_STEPS)
	var light_change: Vector3 = light.linear_velocity - initial_light
	var heavy_change: Vector3 = heavy.linear_velocity - initial_heavy
	var diagonal_change: Vector3 = diagonal.linear_velocity - initial_diagonal
	check_close(heavy_change.length(), light_change.length() * 0.5, 0.002, "double mass halves acceleration")
	check_close(diagonal_change.length(), light_change.length(), 0.002, "diagonal force shares the thrust budget")
	_check_vector(diagonal_change.normalized(), Vector3(1.0, 1.0, -1.0).normalized(), 0.002, "diagonal direction")
	light.free()
	heavy.free()
	diagonal.free()


## Releasing controls preserves both translation and rotation in vacuum.
func test_release_coasts_without_damping() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.set_motion_input(Vector3.FORWARD, 1.0)
	await _physics_steps(SAMPLE_STEPS)
	player.set_motion_input(Vector3.ZERO, 0.0)
	await _physics_steps(3)
	var velocity: Vector3 = player.linear_velocity
	var spin: Vector3 = player.angular_velocity
	var initial_position: Vector3 = player.position
	check(velocity.length() > 0.1, "thrust established translation")
	check(spin.length() > 0.01, "roll established rotation")
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, velocity, 0.0001, "linear momentum persists")
	_check_vector(player.angular_velocity, spin, 0.0001, "angular motion persists")
	_check_vector(player.position - initial_position, velocity * _sample_seconds(), 0.002, "coasting position follows velocity")
	player.free()


## Translation follows a rotated suit, rather than the world's original forward axis.
func test_thrust_uses_body_axes() -> void:
	var orientation: Basis = Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, PI * 0.5)
	var player: Player = _spawn_player(Vector3.ZERO, orientation)
	player.set_motion_input(Vector3.UP, 0.0)
	await _physics_steps(3)
	var before: Vector3 = player.linear_velocity
	await _physics_steps(SAMPLE_STEPS)
	var expected: Vector3 = orientation * Vector3.UP * player.thrust_force_n / player.mass * _sample_seconds()
	_check_vector(player.linear_velocity - before, expected, 0.002, "thrust follows body up after yaw and roll")
	player.free()


## Opposite roll commands produce opposite spin around the suit's viewing axis.
func test_roll_torque_sign_and_body_axis() -> void:
	var orientation: Basis = Basis(Vector3.UP, PI * 0.5)
	var left: Player = _spawn_player(Vector3.ZERO, orientation)
	var right: Player = _spawn_player(Vector3(10.0, 0.0, 0.0), orientation)
	left.set_motion_input(Vector3.ZERO, 1.0)
	right.set_motion_input(Vector3.ZERO, -1.0)
	await _physics_steps(SAMPLE_STEPS)
	var roll_axis: Vector3 = orientation * Vector3.BACK
	check(left.angular_velocity.dot(roll_axis) > 0.01, "positive roll spins around local back")
	check(right.angular_velocity.dot(roll_axis) < -0.01, "negative roll spins in the opposite direction")
	_check_vector(left.angular_velocity, -right.angular_velocity, 0.002, "equal opposite roll torques")
	check_near(left.angular_velocity.cross(roll_axis).length(), 0.0, 0.002, "roll has no off-axis spin")
	left.free()
	right.free()


## Small head movement is free and cannot rotate the physical suit.
func test_mouse_head_look_is_bounded_and_consumed_once() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	await _physics_steps(3)
	player.set_freelooking(true)
	player.queue_mouse_look(Vector2(0.1 / player.mouse_sensitivity, -0.05 / player.mouse_sensitivity))
	await _physics_steps(3)
	_check_basis(player.basis, Basis.IDENTITY, "head motion does not teleport the body")
	var camera: Camera3D = player.get_node("Camera3D") as Camera3D
	_check_basis(camera.basis, Basis(Vector3.UP, -0.1) * Basis(Vector3.RIGHT, 0.05), "camera moves within helmet")
	check_eq(player.suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "small head movement costs no motor energy")
	await _physics_steps(3)
	check_near(player.head_angles_rad.x, -0.1, 1e-5, "mouse delta consumed once")
	player.suit.battery_energy_j = 0.0
	player.queue_mouse_look(Vector2(1e6, -1e6))
	await _physics_steps(3)
	check_near(player.head_angles_rad.x, -Player.HEAD_YAW_LIMIT_RAD, 1e-5, "yaw limited without power")
	check_near(player.head_angles_rad.y, Player.HEAD_PITCH_LIMIT_RAD, 1e-5, "pitch limited without power")
	_check_basis(player.basis, Basis.IDENTITY, "unpowered head cannot rotate suit")
	player.free()


## Large mouse movement requests motor torque in the rolled suit's axes.
func test_mouse_body_follow_uses_power_and_local_axes() -> void:
	var orientation: Basis = Basis(Vector3.BACK, PI * 0.5)
	var player: Player = _spawn_player(Vector3.ZERO, orientation)
	await _physics_steps(3)
	player.queue_mouse_look(Vector2(0.5 / player.mouse_sensitivity, 0.0))
	await _physics_steps(3)
	check(player.basis.z.distance_to(orientation.z) < 0.03, "mouse cannot instantly turn rigid body")
	await _physics_steps(SAMPLE_STEPS)
	check(player.angular_velocity.dot(orientation.y) < -0.01, "body-follow yaw uses rolled local up")
	check(player.suit.battery_energy_j < SuitResources.BATTERY_CAPACITY_J, "body-follow costs electricity")
	check_eq(player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG, "body-follow uses no propellant")
	await _physics_steps(Engine.physics_ticks_per_second * 5)
	check(player.basis.z.distance_to((orientation * Basis(Vector3.UP, -0.5)).z) < 0.03, "body reaches the requested mouse heading")
	check(player.angular_velocity.length() < 0.03, "wheel counter-torque settles body follow")
	player.free()


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
	for i in count:
		await tree.physics_frame


func _sample_seconds() -> float:
	return float(SAMPLE_STEPS) / float(Engine.physics_ticks_per_second)


func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find_type(child, type_name)
		if found != null:
			return found
	return null


func _check_vector(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
	check(actual.distance_to(expected) <= tolerance, "%s expected %s, got %s" % [message, expected, actual])


func _check_basis(actual: Basis, expected: Basis, message: String) -> void:
	_check_vector(actual.x, expected.x, 0.0001, message + " (right)")
	_check_vector(actual.y, expected.y, 0.0001, message + " (up)")
	_check_vector(actual.z, expected.z, 0.0001, message + " (back)")
