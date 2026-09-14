## Save from the Esc menu, change things, load: the game comes back as it was saved.
extends TestCase

const TEST_SAVE: String = "user://test_saves/save_game.json"


## Open orbit: time, suit, ship systems, the pilot's spot and the selected tool return.
func test_save_and_load_in_open_orbit() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	player.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.6, 0.0, -0.5))
	player.linear_velocity = ship.linear_velocity
	await _frames(3)
	player.suit.battery_energy_j = 123456.0
	check(ship.api.set_system_enabled("sensors", false), "sensors switched off before saving")
	ship.api.consume_energy(2000000.0)
	player.salvage_tools.select_tool(SalvageTools.Tool.CUTTER)
	var saved_time: float = flight.session.world.time
	var saved_pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	var saved_battery: float = float(ship.api.get_telemetry().battery_energy_j)
	var menu: PauseMenu = _open_menu(main)
	menu._save_button.pressed.emit()
	check_eq(menu.message(), "Game saved.", "saving reports success")
	check(FileAccess.file_exists(TEST_SAVE), "the save file is on disk")
	# Change everything after saving; loading must undo it.
	player.suit.battery_energy_j = 1.0
	ship.api.set_system_enabled("sensors", true)
	player.salvage_tools.select_tool(SalvageTools.Tool.SCANNER)
	var reloads: Array[int] = [0]
	main.set("reload_action", func() -> void: reloads[0] += 1)
	menu._load_button.pressed.emit()
	check_eq(reloads[0], 1, "loading rebuilds the game scene")
	check(not menu.is_open() and not (Engine.get_main_loop() as SceneTree).paused, "loading closes the menu and unpauses")
	main.free()
	main = await _main()
	player = main.get_node("Player") as Player
	ship = main.get_node("PlayerShip") as PlayerShip
	flight = main.get_node("OrbitalFlight") as OrbitalFlight
	check_near(flight.session.world.time, saved_time, 0.5, "orbital time is back to the save")
	check_near(player.suit.battery_energy_j, 123456.0, 50.0, "suit battery is back to the save")
	check(not bool(ship.api.get_telemetry().systems.sensors.enabled), "switched-off sensors stay off")
	check_near(float(ship.api.get_telemetry().battery_energy_j), saved_battery, 20000.0, "ship battery is back to the save")
	var pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	check(pose.origin.distance_to(saved_pose.origin) < 0.05, "pilot is back where they stood")
	check((-pose.basis.z).angle_to(-saved_pose.basis.z) < 0.02, "pilot faces the same way")
	check_eq(player.salvage_tools.selected, SalvageTools.Tool.CUTTER, "the selected tool comes back")
	_finish(main)


## Near the wreck: the encounter, its cut pieces and where they drift come back.
func test_save_and_load_near_the_wreck_keeps_cut_pieces() -> void:
	var main: Node3D = await _main()
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	# Only a strapped-in pilot lets the ship leave free flight and meet the wreck.
	var player: Player = main.get_node("Player") as Player
	var seat_ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	player.global_transform = seat_ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)
	await _frames(3)
	check((main.get_node("ShipInteraction") as ShipInteraction).strap_in(), "pilot straps in for the approach")
	await _frames(3)
	check(await _arrive_at_wreck(main), "ship arrives at the wreck")
	var wreck: SalvageWreck = main.get_node("Wreck") as SalvageWreck
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	check(wreck.cut("Joint_Nose", 100.0, "Spine"), "cut the nose off")
	await _frames(4)
	check_eq(wreck.bodies.size(), 2, "two pieces before saving")
	var saved: Dictionary = _pieces(wreck, ship)
	var menu: PauseMenu = _open_menu(main)
	menu._save_button.pressed.emit()
	check_eq(menu.message(), "Game saved.", "saving near the wreck works")
	check_eq(wreck.bodies.size(), 2, "saving does not disturb the pieces")
	main.set("reload_action", func() -> void: pass)
	menu._load_button.pressed.emit()
	main.free()
	main = await _main()
	flight = main.get_node("OrbitalFlight") as OrbitalFlight
	wreck = main.get_node("Wreck") as SalvageWreck
	ship = main.get_node("PlayerShip") as PlayerShip
	check(flight.reference_id == "kestrel" and flight.ship_is_local, "the game loads at the wreck")
	var loaded: Dictionary = _pieces(wreck, ship)
	check_eq(loaded.keys().size(), saved.keys().size(), "the same number of pieces come back")
	for key: String in saved:
		check(loaded.has(key), "piece %s comes back" % key)
		if loaded.has(key):
			check((loaded[key] as Vector3).distance_to(saved[key] as Vector3) < 0.5, "piece %s is where it was relative to the ship" % key)
	_finish(main)


## A pilot strapped in when saving is strapped in after loading.
func test_seated_pilot_stays_seated_after_load() -> void:
	var main: Node3D = await _main()
	var player: Player = main.get_node("Player") as Player
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	var interaction: ShipInteraction = main.get_node("ShipInteraction") as ShipInteraction
	player.global_transform = ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), PlayerShip.SEAT_POSITION)
	await _frames(3)
	check(interaction.strap_in(), "pilot straps in")
	var menu: PauseMenu = _open_menu(main)
	menu._save_button.pressed.emit()
	main.set("reload_action", func() -> void: pass)
	menu._load_button.pressed.emit()
	main.free()
	main = await _main()
	interaction = main.get_node("ShipInteraction") as ShipInteraction
	await _frames(5)
	check(interaction.is_seated(), "the harness is fastened after loading")
	_finish(main)


## Saving mid-burn is refused and writes nothing.
func test_cannot_save_during_an_engine_burn() -> void:
	var main: Node3D = await _main()
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	var ship: PlayerShip = main.get_node("PlayerShip") as PlayerShip
	check(ship.api.set_throttle(1.0), "engine lit")
	await _frames(3)
	check(not flight.session.world.can_save(), "the world reports a burn in progress")
	var menu: PauseMenu = _open_menu(main)
	menu._save_button.pressed.emit()
	check_eq(menu.message(), "Cannot save during an engine burn.", "the menu explains why")
	check(not FileAccess.file_exists(TEST_SAVE), "nothing is written")
	ship.api.set_throttle(0.0)
	_finish(main)


func _main() -> Node3D:
	var game: SaveGames = (Engine.get_main_loop() as SceneTree).root.get_node("Game") as SaveGames
	if game.save_path != TEST_SAVE:
		game.save_path = TEST_SAVE
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	var main: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	(main.get_node("Player") as Player).input_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	await _frames(3)
	return main


func _open_menu(main: Node3D) -> PauseMenu:
	main.call("_open_pause_menu")
	return main.get_node("PauseMenu") as PauseMenu


func _arrive_at_wreck(main: Node3D) -> bool:
	var flight: OrbitalFlight = main.get_node("OrbitalFlight") as OrbitalFlight
	var world: OrbitalWorld = flight.session.world
	var wreck_state: Dictionary = flight.session.object_state("kestrel", world.time)
	var parent: Dictionary = world.system.body_state_in_root(world.central_body_id, world.time)
	var arrival_position: SimVector = SimVector.add(wreck_state.position, SimVector.new(120.0, 0, 0))
	world.replace_state(SimVector.sub(arrival_position, parent.position), SimVector.sub(wreck_state.velocity, parent.velocity))
	for step: int in 60:
		await _frames(1)
		if flight.reference_id == "kestrel" and flight.ship_is_local:
			await _frames(5)
			return true
	return false


func _pieces(wreck: SalvageWreck, ship: PlayerShip) -> Dictionary:
	var result: Dictionary = {}
	for body: WreckBody in wreck.bodies:
		var ids: PackedStringArray = body.part_ids.duplicate()
		ids.sort()
		result["+".join(ids)] = body.global_position - ship.global_position
	return result


func _finish(main: Node3D) -> void:
	(Engine.get_main_loop() as SceneTree).paused = false
	main.free()
	var game: SaveGames = (Engine.get_main_loop() as SceneTree).root.get_node("Game") as SaveGames
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	game.save_path = SaveGames.DEFAULT_PATH
	game.take_pending_load()


func _frames(count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for index: int in range(count):
		await tree.physics_frame
		await tree.process_frame
