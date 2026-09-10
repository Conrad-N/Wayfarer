## Suit input ownership and physical pilot restraints run against real scene nodes.
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


## A terminal owns input only: using it cannot cancel approach momentum.
func test_terminal_requires_reach_but_does_not_restrain() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position.z = -5.0
	check(not interaction.open_terminal(fixture.screen), "distant screen rejected")
	player.position = Vector3(0, 0, 1)
	player.linear_velocity = Vector3.RIGHT
	check(interaction.open_terminal(fixture.screen), "reachable terminal usable while drifting")
	check(not player.freeze and not player.input_enabled, "terminal owns input but physics continues")
	check_near(player.linear_velocity.x, 1.0, 0.001, "screen cannot erase momentum")
	var repeat: InputEventKey = InputEventKey.new()
	repeat.physical_keycode = KEY_F
	repeat.pressed = true
	repeat.echo = true
	interaction._input(repeat)
	check(interaction.is_open(), "held F repeat cannot close terminal")
	interaction.close_screen()
	check_near(player.linear_velocity.x, 1.0, 0.001, "closing preserves actual velocity")
	(fixture.root as Node).free()


## The harness cannot capture a distant pilot or stop an unsafe approach for free.
func test_seat_requires_near_slow_approach_without_snapping_pose() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position = Vector3(1, 0, 1)
	check(not interaction.strap_in(), "seat cannot pull pilot from across the hab")
	player.position = PlayerShip.SEAT_POSITION
	player.linear_velocity = Vector3.RIGHT
	check(not interaction.strap_in(), "fast approach rejected")
	player.linear_velocity = Vector3.ZERO
	var pose: Transform3D = player.global_transform
	check(interaction.strap_in(), "near still pilot straps in")
	check(interaction.is_seated() and bool(player.get_meta("seated", false)), "restraint published")
	check(not player.freeze, "seat is a physical constraint, not a frozen suit")
	check(player.global_transform.is_equal_approx(pose), "engagement does not teleport pilot")
	interaction.unstrap()
	check(not interaction.is_seated() and not bool(player.get_meta("seated", true)), "release clears restraint")
	(fixture.root as Node).free()


## A pilot already in the seat can face NAV and buckle with F without looking away.
func test_seat_interact_while_facing_nav_and_repeat_guard() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	player.basis = Basis(Vector3.UP, PI / 2.0)
	await _frames(2)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	interaction._input(event)
	check(interaction.is_seated(), "F buckles pilot already within the seat")
	event.echo = true
	interaction._input(event)
	check(interaction.is_seated(), "held key repeat does not release")
	event.echo = false
	interaction._input(event)
	check(interaction.is_seated() and interaction.active_screen == fixture.screen, "F aimed at NAV opens real terminal while strapped")
	interaction._input(event)
	check(interaction.is_seated() and not interaction.is_open(), "F closes screen before releasing harness")
	player.basis = Basis.IDENTITY
	interaction._input(event)
	check(not interaction.is_seated(), "F away from a terminal unbuckles")
	(fixture.root as Node).free()


## The harness remains secured with tablet/terminal closure and loss of ship power.
func test_seat_remains_secured_across_screen_and_power_changes() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var ship: PlayerShip = fixture.ship
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	check(interaction.strap_in(), "pilot straps in")
	interaction.open_tablet()
	check(interaction.is_seated() and interaction.is_open(), "tablet usable while strapped")
	interaction.close_screen()
	check(interaction.is_seated(), "closing tablet leaves mechanical straps fastened")
	check(interaction.open_terminal(fixture.screen), "seated pilot can use NAV")
	ship.api.set_system_enabled("power", false)
	await _frames(2)
	check(not interaction.is_open() and interaction.is_seated(), "dark terminal closes but harness holds")
	interaction.unstrap()
	(fixture.root as Node).free()


## Accelerating and turning the ship moves a restrained pilot through joint impulses.
func test_seat_carries_pilot_and_releases_without_velocity_reset() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var ship: PlayerShip = fixture.ship
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	await _frames(2)
	check(interaction.strap_in(), "harness attached")
	var relative: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	ship.apply_central_impulse(Vector3(4000, 0, 0))
	ship.apply_torque_impulse(Vector3(0, 0, 1000))
	await _frames(40)
	var moved: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	check((relative.origin - moved.origin).length() < 0.06, "straps keep pilot in seat during translation and turn")
	check(player.linear_velocity.length() > 0.2, "harness accelerates actual dynamic suit")
	check(player.angular_velocity.length() > 0.001, "harness turns suit with ship")
	var momentum: Vector3 = ship.linear_velocity * ship.mass + player.linear_velocity * player.mass
	check((momentum - Vector3(4000, 0, 0)).length() < 3.0, "restraint shares external impulse without creating momentum")
	var velocity: Vector3 = player.linear_velocity
	var spin: Vector3 = player.angular_velocity
	interaction.unstrap()
	check((player.linear_velocity - velocity).length() < 0.0001, "unstrap preserves solved linear momentum")
	check((player.angular_velocity - spin).length() < 0.0001, "unstrap preserves solved angular momentum")
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
	scene.set("salvage_practice", true)
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
