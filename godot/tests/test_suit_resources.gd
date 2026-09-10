## Suit stores and actual Jolt movement share a finite propellant and energy budget.
extends TestCase

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const SAMPLE_STEPS: int = 12


## Each new suit starts full and owns its stores independently.
func test_full_stores_are_independent() -> void:
	var first: SuitResources = SuitResources.new()
	var second: SuitResources = SuitResources.new()
	check_eq(first.propellant_kg, 8.0, "initial propellant in kilograms")
	check_eq(first.battery_energy_j, 720000.0, "initial battery in joules")
	first.consume_propellant(1.0)
	first.consume_energy(3600.0)
	check_eq(second.propellant_kg, 8.0, "other suit retains its propellant")
	check_eq(second.battery_energy_j, 720000.0, "other suit retains its battery")


## A request returns only what was available, including the final partial draw.
func test_consumption_and_empty_stores() -> void:
	var suit: SuitResources = SuitResources.new()
	check_eq(suit.consume_propellant(2.0), 2.0, "normal propellant draw")
	check_eq(suit.propellant_kg, 6.0, "propellant remainder")
	check_eq(suit.consume_propellant(10.0), 6.0, "partial final propellant draw")
	check_eq(suit.consume_propellant(1.0), 0.0, "empty tank provides nothing")
	check_eq(suit.propellant_kg, 0.0, "tank never goes negative")
	check_eq(suit.battery_energy_j, 720000.0, "propellant does not drain battery")
	check_eq(suit.consume_energy(20000.0), 20000.0, "normal energy draw")
	check_eq(suit.battery_energy_j, 700000.0, "battery remainder")
	check_eq(suit.consume_energy(800000.0), 700000.0, "partial final energy draw")
	check_eq(suit.consume_energy(1.0), 0.0, "empty battery provides nothing")
	check_eq(suit.battery_energy_j, 0.0, "battery never goes negative")


## Invalid requests neither refill nor drain a suit.
func test_invalid_requests_leave_stores_unchanged() -> void:
	var suit: SuitResources = SuitResources.new()
	for invalid: float in [0.0, -1.0, INF, -INF, NAN]:
		check_eq(suit.consume_propellant(invalid), 0.0, "invalid propellant request is rejected")
		check_eq(suit.consume_energy(invalid), 0.0, "invalid energy request is rejected")
	check_eq(suit.propellant_kg, 8.0, "invalid requests leave tank full")
	check_eq(suit.battery_energy_j, 720000.0, "invalid requests leave battery full")


## Restored or edited resource values cannot exceed capacity or become nonfinite.
func test_assignments_keep_stores_finite_and_bounded() -> void:
	var suit: SuitResources = SuitResources.new()
	suit.propellant_kg = 100.0
	suit.battery_energy_j = 1000000.0
	check_eq(suit.propellant_kg, 8.0, "tank capacity clamps oversized assignment")
	check_eq(suit.battery_energy_j, 720000.0, "battery capacity clamps oversized assignment")
	for invalid: float in [-1.0, INF, -INF, NAN]:
		suit.propellant_kg = invalid
		suit.battery_energy_j = invalid
		check_eq(suit.propellant_kg, 0.0, "invalid tank value becomes empty")
		check_eq(suit.battery_energy_j, 0.0, "invalid battery value becomes empty")
	suit.propellant_kg = 0.25
	suit.battery_energy_j = 900.0
	check_eq(suit.propellant_kg, 0.25, "valid partial tank value survives")
	check_eq(suit.battery_energy_j, 900.0, "valid partial energy value survives")


## Translation uses propellant and roll uses electricity; only expelled fuel reduces mass.
func test_translation_and_roll_use_separate_resources() -> void:
	var translation: Player = _spawn_player(Vector3.ZERO)
	var roll: Player = _spawn_player(Vector3(10.0, 0.0, 0.0))
	translation.set_motion_input(Vector3.FORWARD, 0.0)
	roll.set_motion_input(Vector3.ZERO, 1.0)
	await _physics_steps(3)
	var translation_before: float = translation.suit.propellant_kg
	var roll_before: float = roll.suit.propellant_kg
	var mass_before: float = translation.mass
	await _physics_steps(SAMPLE_STEPS)
	var translation_spent: float = translation_before - translation.suit.propellant_kg
	var roll_spent: float = roll_before - roll.suit.propellant_kg
	check_close(translation_spent, translation.thrust_force_n * _sample_seconds() / translation.exhaust_velocity_mps,
		0.00001, "translation expels propellant for its impulse")
	check_eq(roll_spent, 0.0, "reaction-wheel roll uses no propellant")
	check_near(mass_before - translation.mass, translation_spent, 0.0001, "expelled propellant leaves the body mass")
	check_eq(translation.suit.battery_energy_j, 720000.0, "translation leaves tool battery unchanged")
	check(roll.suit.battery_energy_j < 720000.0, "roll draws suit battery")
	translation.free()
	roll.free()


## Coasting, mouse aiming, and a stationary brake command need no propellant.
func test_coasting_and_stationary_brake_use_no_resources() -> void:
	var coast: Player = _spawn_player(Vector3.ZERO)
	var stationary: Player = _spawn_player(Vector3(10.0, 0.0, 0.0))
	coast.linear_velocity = Vector3.FORWARD
	coast.angular_velocity = Vector3.BACK * 0.2
	stationary.set_motion_input(Vector3.FORWARD, 1.0)
	stationary.set_braking(true)
	stationary.set_freelooking(true)
	stationary.queue_mouse_look(Vector2(0.0, -PI / stationary.mouse_sensitivity))
	await _physics_steps(SAMPLE_STEPS)
	for player: Player in [coast, stationary]:
		check_eq(player.suit.propellant_kg, 8.0, "no jets means no fuel use")
		check_eq(player.suit.battery_energy_j, 720000.0, "no tool means no battery use")
		check_near(player.mass, 100.0, 0.00001, "coasting mass remains unchanged")
	coast.free()
	stationary.free()


## Linear braking and angular braking each draw from the same finite tank.
func test_braking_drift_and_spin_spends_propellant() -> void:
	var drift: Player = _spawn_player(Vector3.ZERO)
	var spin: Player = _spawn_player(Vector3(10.0, 0.0, 0.0))
	drift.linear_velocity = Vector3.FORWARD * 2.0
	spin.angular_velocity = Vector3.BACK * 0.5
	await _physics_steps(3)
	drift.set_braking(true)
	spin.set_braking(true)
	await _physics_steps(SAMPLE_STEPS)
	check(drift.suit.propellant_kg < 8.0, "linear brake expels propellant")
	check(spin.suit.propellant_kg < 8.0, "angular brake expels propellant")
	check(drift.linear_velocity.length() < 2.0, "fuelled brake slows drift")
	check(spin.angular_velocity.length() < 0.5, "fuelled brake slows spin")
	drift.free()
	spin.free()


## Empty tanks disable jets, while powered wheels still steer and bounded head look remains free.
func test_empty_tank_preserves_motion_with_controls_and_brake() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.suit.propellant_kg = 0.0
	player.linear_velocity = Vector3(0.5, -0.3, 1.0)
	player.angular_velocity = Vector3.BACK * 0.2
	player.set_motion_input(Vector3.UP, 1.0)
	await _physics_steps(3)
	var velocity: Vector3 = player.linear_velocity
	var spin: Vector3 = player.angular_velocity
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, velocity, 0.00001, "empty thrust preserves drift")
	check(player.angular_velocity.length() > spin.length(), "powered roll still works without propellant")
	spin = player.angular_velocity
	player.set_braking(true)
	await _physics_steps(3)
	spin = player.angular_velocity
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, velocity, 0.00001, "empty brake preserves drift")
	_check_vector(player.angular_velocity, spin, 0.00001, "empty brake preserves spin")
	player.set_freelooking(true)
	player.queue_mouse_look(Vector2(0.0, -PI / player.mouse_sensitivity))
	await _physics_steps(3)
	check_near(player.head_angles_rad.y, Player.HEAD_PITCH_LIMIT_RAD, 1e-5, "empty tank still allows bounded head aiming")
	check_eq(player.suit.propellant_kg, 0.0, "empty tank never refills itself")
	player.free()


## A final fraction of a tick provides only the impulse that its propellant can pay for.
func test_fractional_final_supply_scales_thrust() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	await _physics_steps(3)
	var supply: float = 0.00001
	var initial_mass: float = player.mass
	var total_jet_force: float = player.thrust_force_n
	var force_time: float = supply * player.exhaust_velocity_mps / total_jet_force
	player.suit.propellant_kg = supply
	player.set_motion_input(Vector3.FORWARD, 0.0)
	await _physics_steps(5)
	var expected_velocity: Vector3 = Vector3.FORWARD * player.thrust_force_n * force_time / initial_mass
	_check_vector(player.linear_velocity, expected_velocity, 0.000001, "final fuel scales translation impulse")
	check_eq(player.suit.propellant_kg, 0.0, "final supply consumed exactly")
	check_near(initial_mass - player.mass, supply, 0.00001, "final mass loss matches consumed supply")
	var velocity: Vector3 = player.linear_velocity
	var spin: Vector3 = player.angular_velocity
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, velocity, 0.000001, "held thrust stops accelerating after cutoff")
	_check_vector(player.angular_velocity, spin, 0.000001, "translation creates no spin")
	player.free()


## Braking also loses both counter-impulses when the last fuel fraction is exhausted.
func test_fractional_final_supply_scales_brake() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.linear_velocity = Vector3.RIGHT * 20.0
	player.angular_velocity = Vector3.BACK * 10.0
	await _physics_steps(3)
	var supply: float = 0.00001
	var velocity_before: Vector3 = player.linear_velocity
	var spin_before: Vector3 = player.angular_velocity
	var inverse_inertia: Basis = player.get_inverse_inertia_tensor()
	var total_jet_force: float = player.brake_force_n + player.brake_torque_nm / player.thruster_lever_arm_m
	var force_time: float = supply * player.exhaust_velocity_mps / total_jet_force
	var expected_velocity_change: Vector3 = Vector3.RIGHT * player.brake_force_n * force_time / player.mass
	var expected_spin_change: Vector3 = inverse_inertia * Vector3.BACK * player.brake_torque_nm * force_time
	player.suit.propellant_kg = supply
	player.set_braking(true)
	await _physics_steps(5)
	_check_vector(velocity_before - player.linear_velocity, expected_velocity_change, 0.000003,
		"last fuel only buys a fraction of linear braking")
	_check_vector(spin_before - player.angular_velocity, expected_spin_change, 0.000003,
		"last fuel only buys the same fraction of angular braking")
	check_eq(player.suit.propellant_kg, 0.0, "braking exhausts final supply")
	var velocity: Vector3 = player.linear_velocity
	var spin: Vector3 = player.angular_velocity
	await _physics_steps(SAMPLE_STEPS)
	_check_vector(player.linear_velocity, velocity, 0.000001, "held empty brake preserves remaining drift")
	_check_vector(player.angular_velocity, spin, 0.000001, "held empty brake preserves remaining spin")
	player.free()


## Tool battery exhaustion cannot strand an otherwise fuelled suit's RCS.
func test_empty_battery_leaves_rcs_available() -> void:
	var player: Player = _spawn_player(Vector3.ZERO)
	player.suit.consume_energy(SuitResources.BATTERY_CAPACITY_J)
	player.set_motion_input(Vector3.FORWARD, 1.0)
	await _physics_steps(SAMPLE_STEPS)
	check(player.linear_velocity.length() > 0.1, "empty battery still permits translation")
	check(player.angular_velocity.length() < 0.00001, "empty battery disables reaction-wheel roll")
	check(player.suit.propellant_kg < 8.0, "RCS spends its own propellant")
	check_eq(player.suit.battery_energy_j, 0.0, "empty tool battery stays empty")
	player.free()


func _spawn_player(at: Vector3) -> Player:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Player = packed.instantiate() as Player
	player.input_enabled = false
	player.position = at
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
