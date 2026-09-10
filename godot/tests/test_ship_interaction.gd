## Suit input ownership and moving terminal handholds run against real scene nodes.
extends TestCase


## A tablet releases the mouse without erasing the suit's physical drift.
func test_tablet_preserves_drift_and_blocks_tools() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.linear_velocity = Vector3(0.1, 0, 0)
	player.set_motion_input(Vector3.FORWARD, 1.0)
	player.set_braking(true)
	interaction.open_tablet()
	check(interaction.is_open(), "tablet owns input")
	check(not player.input_enabled, "suit cannot fire or move from UI keys")
	check(not player.freeze, "tablet does not freeze physics")
	check(not player.is_braking(), "held controls cancelled")
	await _frames(3)
	check_near(player.linear_velocity.x, 0.1, 0.001, "tablet preserves drift")
	check(interaction.tablet.api == (fixture.ship as PlayerShip).api, "same shared ship API")
	interaction.close_screen()
	check(player.input_enabled and not interaction.is_open(), "flight resumes")
	check(player._capture_click_held and player._secondary_blocked, "closing click cannot fire a tool")
	(fixture.root as Node).free()


## Distance and approach speed prevent docking from pulling the player across space.
func test_terminal_requires_near_slow_approach() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position.z = -5.0
	check(not interaction.open_terminal(fixture.screen), "distant screen rejected")
	player.position = Vector3(0, 0, 1)
	player.linear_velocity = Vector3.RIGHT
	check(not interaction.open_terminal(fixture.screen), "fast approach rejected")
	player.linear_velocity = Vector3.ZERO
	check(interaction.open_terminal(fixture.screen), "near still player grips terminal")
	check(player.freeze and not player.input_enabled, "handhold owns pose")
	var repeat: InputEventKey = InputEventKey.new()
	repeat.physical_keycode = KEY_F
	repeat.pressed = true
	repeat.echo = true
	interaction._input(repeat)
	check(interaction.is_open(), "held F repeat cannot release handhold")
	interaction.close_screen()
	check(not player.freeze, "release returns dynamic physics")
	(fixture.root as Node).free()


## The handhold follows the ship and returns its local point velocity on release.
func test_terminal_follows_moving_ship_and_releases_with_motion() -> void:
	var fixture: Dictionary = _fixture()
	var ship: PlayerShip = fixture.ship
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	check(interaction.open_terminal(fixture.screen), "grip accepted")
	await _frames(30)
	var relative: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	ship.linear_velocity = Vector3(0.2, 0, 0)
	ship.angular_velocity = Vector3(0, 0.02, 0)
	await _frames(8)
	var moved: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	check((relative.origin - moved.origin).length() < 0.02, "handhold stays in ship frame")
	var expected: Vector3 = ship.linear_velocity + ship.angular_velocity.cross(player.global_position - ship.to_global(ship.center_of_mass))
	interaction.close_screen()
	check((player.linear_velocity - expected).length() < 0.001, "release inherits point velocity")
	check((player.angular_velocity - ship.angular_velocity).length() < 0.001, "release inherits spin")
	(fixture.root as Node).free()


## A dark terminal lets go; the independently powered tablet can restore ship power.
func test_power_failure_releases_terminal_but_tablet_can_restore_power() -> void:
	var fixture: Dictionary = _fixture()
	var ship: PlayerShip = fixture.ship
	var interaction: ShipInteraction = fixture.interaction
	check(interaction.open_terminal(fixture.screen), "terminal engaged")
	ship.api.set_system_enabled("power", false)
	await _frames(2)
	check(not interaction.is_open(), "power loss releases terminal")
	interaction.open_tablet()
	check(interaction.tablet.is_available(), "tablet remains usable")
	ship.api.set_system_enabled("power", true)
	check(bool(ship.api.get_telemetry().power_available), "tablet connection can restore power")
	interaction.close_screen()
	(fixture.root as Node).free()


func _fixture() -> Dictionary:
	var root: Node3D = Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var ship: PlayerShip = preload("res://scenes/player_ship.tscn").instantiate() as PlayerShip
	root.add_child(ship)
	var player: Player = preload("res://scenes/player.tscn").instantiate() as Player
	player.input_enabled = false
	player.position = Vector3(0, 0, 1)
	root.add_child(player)
	var screen: WorldScreen = preload("res://ui/world_screen.tscn").instantiate() as WorldScreen
	screen.configure(ship.api, "NAV")
	ship.get_node("NavTerminalMount").add_child(screen)
	var interaction: ShipInteraction = ShipInteraction.new()
	root.add_child(interaction)
	interaction.configure(player, ship)
	return {"root": root, "ship": ship, "player": player, "screen": screen, "interaction": interaction}


func _frames(count: int) -> void:
	for index: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
	await (Engine.get_main_loop() as SceneTree).process_frame


## Main connects every screen to one API and keeps NAV meaningful after a cut.
func test_main_shares_ship_connection_and_retargets_after_cut() -> void:
	var scene: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	(scene.get_node("Player") as Player).input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(scene)
	await _frames(3)
	var ship: PlayerShip = scene.get_node("PlayerShip") as PlayerShip
	var wreck: SalvageWreck = scene.get_node("Wreck") as SalvageWreck
	var nav: WorldScreen = ship.get_node("NavTerminalMount/NAVScreen") as WorldScreen
	var screen: WorldScreen = ship.get_node("ShipTerminalMount/SHIPScreen") as WorldScreen
	var interaction: ShipInteraction = scene.get_node("ShipInteraction") as ShipInteraction
	check(nav.api == ship.api and screen.api == ship.api and interaction.tablet.api == ship.api, "three screens share one API")
	wreck.cut("Joint_Nose", 100.0, "Spine")
	await _frames(4)
	check_eq(wreck.bodies.size(), 2, "cut replaces original body")
	check(is_instance_valid(ship.navigation_target), "NAV reference survives replacement")
	check(float(ship.api.get_telemetry().motion.range_m) > 5.0, "NAV keeps real range after cut")
	scene.free()
