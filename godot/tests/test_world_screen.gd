## Shared screen geometry, power boundaries, and actual app command routing.
extends TestCase

const SCREEN: PackedScene = preload("res://ui/world_screen.tscn")


## Pointer mapping must survive a terminal rotated and scaled inside the ship.
func test_screen_coordinates_follow_its_transform() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var screen: WorldScreen = SCREEN.instantiate() as WorldScreen
	tree.root.add_child(screen)
	screen.position = Vector3(5.0, -2.0, 7.0)
	screen.rotation = Vector3(0.2, 1.0, -0.3)
	screen.scale = Vector3(0.7, 0.7, 0.7)
	var samples: Array[Vector3] = [Vector3(-0.8, 0.5, 0.0), Vector3.ZERO, Vector3(0.8, -0.5, 0.0)]
	var expected: Array[Vector2] = [Vector2.ZERO, Vector2(320, 200), Vector2(640, 400)]
	for index: int in samples.size():
		var pixel: Vector2 = screen.world_to_pixel(screen.to_global(samples[index]))
		check_near(pixel.x, expected[index].x, 0.001, "screen-local x maps to pixel x")
		check_near(pixel.y, expected[index].y, 0.001, "screen-local y flips to pixel y")
	screen.free()


## Both physical clients share commands and resulting telemetry through one API.
func test_ship_panel_commands_share_state_and_airlock_rejections() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var api: ShipApi = ShipApi.new()
	var terminal: WorldScreen = SCREEN.instantiate() as WorldScreen
	var tablet: WorldScreen = SCREEN.instantiate() as WorldScreen
	terminal.configure(api, "SHIP")
	tablet.configure(api, "NAV", false)
	tree.root.add_child(terminal)
	tree.root.add_child(tablet)
	check(terminal.is_available() and tablet.is_available(), "both clients initially powered")
	terminal.panel.get_button("cargo").pressed.emit()
	check(bool(api.get_telemetry()["cargo_door_open"]), "SHIP button opens cargo through API")
	tablet.panel.get_button("nav_brake").pressed.emit()
	check(bool(api.get_telemetry()["braking"]), "NAV button enables ship brake through API")
	terminal.panel.get_button("outer").pressed.emit()
	check(not bool(api.get_telemetry()["airlock_outer_open"]), "panel preserves API airlock interlock")
	check(api.last_message.contains("OTHER AIRLOCK"), "API rejection reaches shared telemetry")
	terminal.panel.get_button("inner").pressed.emit()
	terminal.panel.get_button("outer").pressed.emit()
	check(bool(api.get_telemetry()["airlock_outer_open"]), "outer can open after inner closes")
	terminal.panel.get_button("power").pressed.emit()
	check(not terminal.is_available(), "fixed terminal goes dark when it switches ship power off")
	check(tablet.is_available(), "tablet remains accessible without ship power")
	check(not bool(api.get_telemetry()["braking"]), "power loss clears ship brake")
	tablet.panel.get_button("ship_tab").pressed.emit()
	tablet.panel.get_button("power").pressed.emit()
	check(terminal.is_available(), "tablet can restore fixed terminal power")
	terminal.panel.get_button("rcs").pressed.emit()
	tablet.panel.get_button("nav_tab").pressed.emit()
	tablet.panel.get_button("nav_brake").pressed.emit()
	check(not bool(api.get_telemetry()["braking"]), "NAV honors disabled RCS")
	terminal.free()
	tablet.free()


## A ray hit delivers actual GUI clicks without mutating host mouse coordinates.
func test_forwarded_pointer_click_reaches_button_and_respects_power() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var api: ShipApi = ShipApi.new()
	var screen: WorldScreen = SCREEN.instantiate() as WorldScreen
	screen.configure(api)
	tree.root.add_child(screen)
	await tree.process_frame
	var pixel: Vector2 = screen.panel.get_button("cargo").get_global_rect().get_center()
	var world_point: Vector3 = screen.to_global(Vector3((pixel.x / 640.0 - 0.5) * 1.6, (0.5 - pixel.y / 400.0), 0.0))
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = Vector2(5, 7)
	screen.forward_input(motion, world_point)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position = Vector2(11, 13)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	screen.forward_input(click, world_point)
	click.pressed = false
	screen.forward_input(click, world_point)
	check(bool(api.get_telemetry()["cargo_door_open"]), "mapped viewport click opens cargo")
	check_eq(click.position, Vector2(11, 13), "forwarding preserves original button event")
	check_eq(motion.position, Vector2(5, 7), "forwarding preserves original motion event")
	api.set_system_enabled("power", false)
	click.pressed = true
	screen.forward_input(click, world_point)
	click.pressed = false
	screen.forward_input(click, world_point)
	check(bool(api.get_telemetry()["cargo_door_open"]), "dark screen cannot send commands")
	api.set_system_enabled("power", true)
	click.pressed = true
	screen.forward_input(click, screen.to_global(Vector3(4, 4, 0)))
	click.pressed = false
	screen.forward_input(click, screen.to_global(Vector3(4, 4, 0)))
	check(bool(api.get_telemetry()["cargo_door_open"]), "off-screen ray cannot click controls")
	click.pressed = true
	screen.forward_input(click, world_point)
	click.pressed = false
	screen.forward_input(click, screen.to_global(Vector3(4, 4, 0)))
	check(bool(api.get_telemetry()["cargo_door_open"]), "dragged-off release cancels click")
	check(not screen.panel.get_button("cargo").is_pressed(), "dragged-off release clears held button")
	screen.free()


## Missing connection is a normal UI state, including a handheld screen.
func test_unconnected_screen_and_app_fail_softly() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var screen: WorldScreen = SCREEN.instantiate() as WorldScreen
	screen.configure(null, "NAV", false)
	tree.root.add_child(screen)
	check(not screen.is_available(), "tablet needs a ship connection even with its own power")
	check_eq(screen.panel.current_app, "NAV", "initial app retained before ready")
	check(screen.panel.get_button("cargo").disabled, "missing connection disables ship commands")
	check(not screen.panel.get_button("ship_tab").disabled, "tabs remain navigable")
	screen.panel.get_button("ship_tab").pressed.emit()
	check_eq(screen.panel.current_app, "SHIP", "app tabs work without telemetry")
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = Vector2(9, 7)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	screen.forward_input(event, screen.global_position)
	check_eq(event.position, Vector2(9, 7), "refused forwarding leaves host input untouched")
	screen.free()
