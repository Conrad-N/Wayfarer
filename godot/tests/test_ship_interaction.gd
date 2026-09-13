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
func test_seat_requires_near_slow_approach_and_snaps_to_forward_pose() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position = Vector3(1.5, 0, 1)
	check(not interaction.strap_in(), "seat cannot pull pilot from across the hab")
	player.position = PlayerShip.SEAT_POSITION
	player.linear_velocity = Vector3.RIGHT * 1.5
	check(not interaction.strap_in(), "fast approach rejected")
	player.linear_velocity = Vector3.ZERO
	player.position += Vector3(0.5, 0.15, 0.1)
	player.basis = Basis(Vector3.FORWARD, 1.2) * Basis(Vector3.UP, -0.7)
	player.head_angles_rad = Vector2(0.8, -0.4)
	player.queue_mouse_look(Vector2(100, 100))
	var camera: Camera3D = player.get_node("Camera3D") as Camera3D
	var standing_position: Vector3 = camera.position
	check(interaction.strap_in(), "near still pilot straps in from an offset tilted approach")
	check(interaction.is_seated() and bool(player.get_meta("seated", false)), "restraint published")
	check(not player.freeze, "seat is a physical constraint, not a frozen suit")
	check(player.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)), "engagement snaps into the forward-facing seat pose")
	check_eq(player.head_angles_rad, Vector2.ZERO, "engagement centres free head look")
	check_near(camera.position.y, 0.35, 0.0001, "seated eye height faces centre of NAV")
	await _frames(4)
	check(player.head_angles_rad.length() < 0.001, "queued approach mouse movement cannot undo seated view")
	check(interaction.is_seated(), "new seated pose remains physically restrained")
	interaction.unstrap()
	check(not interaction.is_seated() and not bool(player.get_meta("seated", true)), "release clears restraint")
	check(camera.position.is_equal_approx(standing_position), "unstrap restores normal EVA eye height")
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


## A strapped pilot can freely inspect the cabin without turning the suit or firing motors.
func test_seated_mouse_look_is_free_and_keeps_physical_restraint() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var ship: PlayerShip = fixture.ship
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	await _frames(3)
	check(interaction.strap_in(), "pilot straps in for cabin look")
	await _frames(3)
	var relative: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	var battery: float = player.suit.battery_energy_j
	var propellant: float = player.suit.propellant_kg
	player.queue_mouse_look(Vector2(-PI * 1.5 / player.mouse_sensitivity, -PI / player.mouse_sensitivity))
	await _frames(12)
	check_near(player.head_angles_rad.x, -PI * 0.5, 1e-5, "seated yaw permits a full three-quarter turn without Z")
	check_near(player.head_angles_rad.y, deg_to_rad(85.0), 1e-5, "seated view can look almost straight up")
	check(interaction.is_seated(), "looking around never releases the seat restraint")
	var moved: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	check(moved.origin.distance_to(relative.origin) < 0.01, "head aim does not move the restrained body")
	check(moved.basis.z.distance_to(relative.basis.z) < 0.001, "head aim does not turn the restrained body")
	check_near(player.angular_velocity.length(), 0.0, 0.001, "free seated aim produces no body spin")
	check_eq(player.suit.battery_energy_j, battery, "seated camera aim uses no electrical charge")
	check_eq(player.suit.propellant_kg, propellant, "seated camera aim uses no propellant")
	var aimed: Vector2 = player.head_angles_rad
	player.set_freelooking(true)
	player.set_freelooking(false)
	check_eq(player.head_angles_rad, aimed, "Z transitions preserve the seated view")
	await _frames(6)
	check_eq(player.head_angles_rad, aimed, "seated view stays aimed when the mouse stops")
	interaction.unstrap()
	check_eq(player.head_angles_rad, Vector2.ZERO, "unstrapping centres view on the physical suit")
	check((player.get_node("Camera3D") as Camera3D).basis.is_equal_approx(Basis.IDENTITY), "unstrapped camera restores ordinary EVA orientation")
	(fixture.root as Node).free()


## V always releases the harness, even when looking at NAV or when a screen owns input.
func test_dedicated_unstrap_key_overrides_nav_tablet_and_terminal() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = true
	check(InputMap.event_is_action(event, "unstrap"), "physical V is the dedicated unstrap action")
	for mode: String in ["looking at NAV", "terminal", "tablet"]:
		var fixture: Dictionary = _fixture()
		var player: Player = fixture.player
		var ship: PlayerShip = fixture.ship
		var interaction: ShipInteraction = fixture.interaction
		var camera: Camera3D = player.get_node("Camera3D") as Camera3D
		var standing_camera_position: Vector3 = camera.position
		player.position = PlayerShip.SEAT_POSITION
		await _frames(3)
		check(interaction.strap_in(), mode + ": pilot straps in")
		ship.apply_central_impulse(Vector3(2000, 0, 0))
		ship.apply_torque_impulse(Vector3(0, 0, 1000))
		await _frames(15)
		if mode == "looking at NAV":
			# The headless fixture disables live input while stepping physics.
			# A pilot looking at NAV has normal suit input until a screen opens.
			player.input_enabled = true
			check(interaction._aimed_screen() == fixture.screen, "unstrap test actually faces the NAV terminal")
		elif mode == "terminal":
			check(interaction.open_terminal(fixture.screen), "terminal owns input before V")
		else:
			interaction.open_tablet()
			check(interaction.active_screen == interaction.tablet, "tablet owns input before V")
		var was_open: bool = interaction.is_open()
		event.echo = true
		interaction._input(event)
		check(interaction.is_seated(), mode + ": key repeat cannot release the harness")
		check_eq(interaction.is_open(), was_open, mode + ": key repeat leaves current UI alone")
		event.echo = false
		var velocity: Vector3 = player.linear_velocity
		var spin: Vector3 = player.angular_velocity
		check(velocity.length() > 0.1 and spin.length() > 0.001, mode + ": restrained pilot has real inherited motion")
		interaction._input(event)
		check(not interaction.is_seated() and not bool(player.get_meta("seated", true)), mode + ": V releases the physical restraint")
		check(not interaction.is_open(), mode + ": V closes any screen before returning to EVA")
		check(player.input_enabled and not player.freeze, mode + ": V restores live suit controls")
		check(camera.position.is_equal_approx(standing_camera_position), mode + ": V restores standing eye height")
		check(camera.basis.is_equal_approx(Basis.IDENTITY) and player.head_angles_rad == Vector2.ZERO, mode + ": V restores centred EVA view")
		check_near(player.linear_velocity.distance_to(velocity), 0.0, 0.0001, mode + ": V preserves linear momentum")
		check_near(player.angular_velocity.distance_to(spin), 0.0, 0.0001, mode + ": V preserves angular momentum")
		interaction._input(event)
		check(not interaction.is_seated() and not interaction.is_open(), mode + ": repeated V cannot reseat or reopen a screen")
		(fixture.root as Node).free()


## Losing the physical harness also restores the seated camera and screen ownership.
func test_broken_harness_restores_eva_camera() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	await _frames(3)
	check(interaction.strap_in(), "pilot seated before restraint loss")
	interaction.open_tablet()
	interaction._seat_restraint.release()
	await _frames(3)
	check(not player.has_automatic_freelook(), "lost harness clears forced seated view")
	check(not interaction.is_open() and player.input_enabled, "lost harness returns screen input to suit")
	check_near((player.get_node("Camera3D") as Camera3D).position.y, 0.55, 0.0001, "lost harness restores ordinary eye height")
	check_eq(player.head_angles_rad, Vector2.ZERO, "lost harness centres view")
	(fixture.root as Node).free()


## The strap-in prompt only appears once the harness can actually catch the pilot.
func test_seat_prompt_matches_strap_in_reach() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION + Vector3(2.4, 0, 0)
	player.basis = Basis(Vector3.UP, PI / 2.0)
	await _frames(2)
	check(interaction._aimed_seat(), "pilot beyond reach is still looking at the seat")
	check_eq(interaction.hint, ShipInteraction.SEAT_APPROACH_HINT, "distant pilot is told to close in, not offered F")
	check(not interaction.strap_in(), "F from beyond reach is rejected, matching the prompt")
	player.position = PlayerShip.SEAT_POSITION + Vector3(1.2, 0, 0)
	await _frames(2)
	check_eq(interaction.hint, ShipInteraction.SEAT_READY_HINT, "pilot within reach is offered F")
	player.linear_velocity = Vector3(0, 0, 1.5)
	await _frames(1)
	check_eq(interaction.hint, ShipInteraction.SEAT_APPROACH_HINT, "a fast pilot is told to slow down")
	player.linear_velocity = Vector3.ZERO
	await _frames(1)
	check(interaction.strap_in(), "the offered F succeeds")
	(fixture.root as Node).free()


## Unbuckling stands the pilot in the clear passage beside the seat, not inside its cushions.
func test_unstrap_steps_out_beside_the_seat() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var ship: PlayerShip = fixture.ship
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	await _frames(2)
	check(interaction.strap_in(), "pilot straps in")
	var facing: Basis = player.global_basis
	interaction.unstrap()
	var exit_point: Vector3 = ship.to_global(PlayerShip.SEAT_EXIT_POSITION)
	check(player.global_position.is_equal_approx(exit_point), "release places the pilot at the seat exit spot")
	check(player.global_basis.is_equal_approx(facing), "stepping out keeps the pilot's facing")
	await _frames(10)
	check(player.linear_velocity.length() < 0.01 and player.angular_velocity.length() < 0.01, "exit spot is clear: nothing shoves the freed pilot")
	check(player.global_position.distance_to(exit_point) < 0.05, "freed pilot stays where they stood up")
	check_eq(interaction.hint, ShipInteraction.SEAT_READY_HINT, "standing behind the seat, the pilot is offered F again")
	check(interaction.strap_in(), "the seat can be entered from behind, straight from the exit spot")
	(fixture.root as Node).free()


## The terminal's warp refusal asks for C, so C must reach the suit while that screen is open.
func test_wheel_dump_key_works_while_a_screen_is_open() -> void:
	var fixture: Dictionary = _fixture()
	var player: Player = fixture.player
	var interaction: ShipInteraction = fixture.interaction
	player.position = PlayerShip.SEAT_POSITION
	await _frames(2)
	check(interaction.strap_in(), "pilot straps in")
	check(interaction.open_terminal(fixture.screen), "NAV owns input")
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_C
	event.pressed = true
	check(InputMap.event_is_action(event, "wheel_dump"), "physical C is the wheel dump action")
	interaction._input(event)
	check(player.is_wheel_dumping() and interaction.is_open(), "holding C unloads the wheels without closing the terminal")
	await _frames(2)
	check(player.is_wheel_dumping(), "the suit keeps dumping while the screen owns the other input")
	event.pressed = false
	interaction._input(event)
	check(not player.is_wheel_dumping(), "releasing C stops the dump")
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


## A new game starts the pilot standing clear of the seat back in both modes.
func test_spawn_pose_is_clear_of_ship_geometry() -> void:
	for practice: bool in [false, true]:
		var scene: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
		scene.set("salvage_practice", practice)
		(scene.get_node("Player") as Player).input_enabled = false
		(Engine.get_main_loop() as SceneTree).root.add_child(scene)
		await _frames(1)
		var player: Player = scene.get_node("Player") as Player
		var interaction: ShipInteraction = scene.get_node("ShipInteraction") as ShipInteraction
		check(interaction._pose_is_clear(player.global_transform), "spawn capsule overlaps nothing (practice=%s)" % practice)
		check(not interaction.is_seated(), "spawn leaves the pilot unstrapped (practice=%s)" % practice)
		scene.free()
