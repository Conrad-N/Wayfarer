## Esc pauses the game behind a menu with resume, save, load and quit.
extends TestCase


## Esc opens the menu and freezes the game; Esc again resumes it.
func test_escape_opens_menu_and_pauses_then_resumes() -> void:
	var scene: Node3D = await _main(false)
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	var player: Player = scene.get_node("Player") as Player
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	check(not menu.is_open(), "the game starts unpaused")
	_press_escape(scene)
	check(menu.is_open(), "Esc opens the pause menu")
	check(tree.paused, "the game is paused behind the menu")
	var position: Vector3 = player.global_position
	player.linear_velocity = Vector3(1, 0, 0)
	for index: int in 5:
		await tree.physics_frame
	check(player.global_position.is_equal_approx(position), "nothing moves while paused")
	_press_escape(scene)
	check(not menu.is_open(), "Esc again closes the menu")
	check(not tree.paused, "closing the menu resumes the game")
	check(player._capture_click_held, "the click or key that resumed does not also fire a tool")
	_cleanup(scene)


## Esc with a terminal or tablet open closes that screen first, not the game.
func test_escape_closes_an_open_screen_before_pausing() -> void:
	var scene: Node3D = await _main(false)
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	var interaction: ShipInteraction = scene.get_node("ShipInteraction") as ShipInteraction
	interaction.open_tablet()
	_press_escape(scene)
	check(not interaction.is_open(), "Esc closes the tablet")
	check(not menu.is_open(), "the same press does not also pause")
	_press_escape(scene)
	check(menu.is_open(), "a second Esc pauses")
	_cleanup(scene)


## Quit goes through the menu's quit action.
func test_quit_button_quits() -> void:
	var scene: Node3D = await _main(false)
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	var quit: Array[bool] = [false]
	menu.quit_action = func() -> void: quit[0] = true
	menu.open()
	menu._quit_button.pressed.emit()
	check(quit[0], "Quit asks the game to quit")
	_cleanup(scene)


## Load with no save file says so and leaves the game as it is.
func test_load_without_a_save_says_so() -> void:
	var game: SaveGames = (Engine.get_main_loop() as SceneTree).root.get_node("Game") as SaveGames
	game.save_path = "user://test_saves/missing.json"
	var scene: Node3D = await _main(false)
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	_press_escape(scene)
	check(menu._load_button.disabled, "Load is greyed out with no save")
	menu._load_button.pressed.emit()
	check_eq(menu.message(), "No saved game found.", "pressing it anyway explains why")
	check(menu.is_open(), "the menu stays open")
	_cleanup(scene)
	game.save_path = SaveGames.DEFAULT_PATH


## The practice room has no orbital game to save.
func test_practice_room_cannot_save() -> void:
	var game: SaveGames = (Engine.get_main_loop() as SceneTree).root.get_node("Game") as SaveGames
	game.save_path = "user://test_saves/practice.json"
	var scene: Node3D = await _main(true)
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	_press_escape(scene)
	check(menu._save_button.disabled, "Save is greyed out in the practice room")
	menu._save_button.pressed.emit()
	check(not FileAccess.file_exists(game.save_path), "nothing is written")
	_cleanup(scene)
	game.save_path = SaveGames.DEFAULT_PATH


func _main(practice: bool) -> Node3D:
	var scene: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	scene.set("salvage_practice", practice)
	(Engine.get_main_loop() as SceneTree).root.add_child(scene)
	await _frames(3)
	return scene


func _press_escape(scene: Node3D) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	scene.get_viewport().push_input(event)
	var release: InputEventAction = InputEventAction.new()
	release.action = "ui_cancel"
	release.pressed = false
	scene.get_viewport().push_input(release)


func _cleanup(scene: Node3D) -> void:
	(Engine.get_main_loop() as SceneTree).paused = false
	scene.free()


func _frames(count: int) -> void:
	for index: int in count:
		await (Engine.get_main_loop() as SceneTree).physics_frame
	await (Engine.get_main_loop() as SceneTree).process_frame
