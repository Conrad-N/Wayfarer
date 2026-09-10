## Real Jolt impacts trigger suit feedback; propulsion and settled contact do not.
extends TestCase


## An actual collision flashes once and fades even while the suit touches the wall.
func test_wall_bump_flashes_then_settles() -> void:
	var player: Player = _spawn_player(Vector3(-0.8, 0.0, 0.0))
	var wall: StaticBody3D = _spawn_wall(Vector3.ZERO)
	var impacts: SuitImpacts = _observe(player)
	await _steps(3)
	check_eq(impacts.flash_strength(), 0.0, "separated stationary suit has no bump")
	player.linear_velocity = Vector3.RIGHT
	var peak: float = 0.0
	for index: int in 30:
		await _steps(1)
		peak = maxf(peak, impacts.flash_strength())
	check(peak > 0.6, "real wall contact makes a visible bump")
	check(player.linear_velocity.x < 0.1, "wall changed the physical suit velocity")
	await _steps(50)
	check_eq(impacts.flash_strength(), 0.0, "settled contact does not keep flashing")
	player.linear_velocity = Vector3.LEFT
	await _steps(20)
	player.linear_velocity = Vector3.RIGHT * 2.0
	peak = 0.0
	for index: int in 25:
		await _steps(1)
		peak = maxf(peak, impacts.flash_strength())
	check(peak > 0.6, "a second real bump retriggers the indicator")
	player.free()
	wall.free()


## Open-space thrusters, wheel motion and coasting are not collisions.
func test_controls_in_vacuum_do_not_flash() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	var impacts: SuitImpacts = _observe(player)
	player.set_motion_input(Vector3.RIGHT, 1.0)
	await _steps(30)
	check(player.linear_velocity.length() > 0.1, "thrusters accelerated suit")
	check(player.angular_velocity.length() > 0.1, "wheel rotated suit")
	check_eq(impacts.flash_strength(), 0.0, "self-generated acceleration does not flash")
	player.set_motion_input(Vector3.ZERO, 0.0)
	await _steps(10)
	check_eq(impacts.flash_strength(), 0.0, "free coasting does not flash")
	player.free()


## Rotating shoulders into nearby geometry is visible even without approach translation.
func test_rotating_suit_bumps_wall() -> void:
	var player: Player = _spawn_player(Vector3(-0.7, 0.0, 0.0))
	var wall: StaticBody3D = _spawn_wall(Vector3.ZERO)
	var impacts: SuitImpacts = _observe(player)
	await _steps(3)
	player.angular_velocity = Vector3.BACK
	var peak: float = 0.0
	for index: int in 70:
		await _steps(1)
		peak = maxf(peak, impacts.flash_strength())
	check(peak > 0.6, "turning into a wall produces collision feedback")
	check(player.linear_velocity.length() > 0.01, "off-centre contact physically deflected the suit")
	player.free()
	wall.free()


## Steady pressure against a surface does not repeatedly announce the same contact.
func test_sustained_wall_pressure_fades() -> void:
	var player: Player = _spawn_player(Vector3(-0.52, 0.0, 0.0))
	var wall: StaticBody3D = _spawn_wall(Vector3.ZERO)
	var impacts: SuitImpacts = _observe(player)
	await _steps(3)
	player.set_motion_input(Vector3.RIGHT, 0.0)
	await _steps(100)
	check(absf(player.linear_velocity.x) < 0.05, "steady thrust is opposed by the wall")
	check_eq(impacts.flash_strength(), 0.0, "sustained gentle contact does not flash")
	player.free()
	wall.free()


## Tiny docking drift below the impact threshold does not create distracting flashes.
func test_very_soft_contact_stays_quiet() -> void:
	var player: Player = _spawn_player(Vector3(-0.505, 0.0, 0.0))
	var wall: StaticBody3D = _spawn_wall(Vector3.ZERO)
	var impacts: SuitImpacts = _observe(player)
	await _steps(3)
	player.linear_velocity = Vector3.RIGHT * 0.01
	var peak: float = 0.0
	for index: int in 70:
		await _steps(1)
		peak = maxf(peak, impacts.flash_strength())
	check(player.linear_velocity.x < 0.005, "gentle drift reached the wall")
	check_eq(peak, 0.0, "sub-threshold physical contact stays quiet")
	player.free()
	wall.free()


func _spawn_player(at: Vector3) -> Player:
	var packed: PackedScene = load("res://scenes/player.tscn")
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	player.position = at
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


func _observe(player: Player) -> SuitImpacts:
	var impacts: SuitImpacts = SuitImpacts.new()
	impacts.configure(player)
	player.add_child(impacts)
	return impacts


func _spawn_wall(at: Vector3) -> StaticBody3D:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.position = at
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.3, 8.0, 8.0)
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	wall.add_child(collision)
	(Engine.get_main_loop() as SceneTree).root.add_child(wall)
	return wall


func _steps(count: int) -> void:
	for index: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
