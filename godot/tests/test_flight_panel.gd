## Shared orbital screens exercise real widgets and SI command routing through ShipApi.
extends TestCase

const SCREEN: PackedScene = preload("res://ui/world_screen.tscn")
var _commands: Array[Dictionary] = []


## Every calculator previews through the same API, converting user-facing units once.
func test_plan_calculators_and_manual_burn_use_api() -> void:
	_commands.clear()
	var api: ShipApi = _api()
	var panel: ShipPanel = _panel(api, "PLAN")
	check_eq(panel.current_app, "PLAN", "PLAN is a shared terminal/tablet app")
	panel._solver.select(0)
	panel._inputs.duration.value = 90.0
	panel.get_button("calculate_plan").pressed.emit()
	check_eq(_commands.back().name, "plan_intercept", "Intercept calculator command")
	check_near(_commands.back().arguments.tof_seconds, 5400.0, 0.0, "Minutes convert to SI seconds")
	for index: int in [1, 2]:
		panel._solver.select(index)
		panel.get_button("calculate_plan").pressed.emit()
		check_eq(_commands.back().name, "plan_circularize", "Circularization calculator command")
		check_eq(_commands.back().arguments.at, "apoapsis" if index == 1 else "periapsis", "Requested apsis preserved")
	panel._solver.select(3)
	panel._inputs.altitude.value = 850.0
	panel.get_button("calculate_plan").pressed.emit()
	check_near(_commands.back().arguments.altitude_m, 850000.0, 0.0, "Kilometres convert to SI metres")
	panel._solver.select(4)
	panel.get_button("calculate_plan").pressed.emit()
	check_eq(_commands.back().name, "plan_match_velocity", "Velocity-match calculator command")
	panel._solver.select(5)
	panel._inputs.delay.value = 3.0
	panel._inputs.prograde.value = 25.0
	panel._inputs.normal.value = -4.0
	panel._inputs.radial.value = 6.0
	panel.get_button("calculate_plan").pressed.emit()
	check_eq(_commands.back().name, "plan_maneuver", "Manual node command")
	check_near(_commands.back().arguments.time, 280.0, 0.0, "Relative minutes become an absolute burn time")
	check_eq(_commands.back().arguments.dv_local, {"prograde": 25.0, "normal": -4.0, "radial": 6.0}, "Orbital components remain SI")
	panel.get_button("execute_plan").pressed.emit()
	check_eq(_commands.back().name, "execute_plan", "Execution is an explicit separate command")
	panel.get_button("cancel_plan").pressed.emit()
	check_eq(_commands.back().name, "cancel_plan", "Cancellation routes through API")
	panel.free()


## Throttle, attitude, warp, target choice and held local translation share one control path.
func test_flight_and_rcs_controls_release_on_close() -> void:
	_commands.clear()
	var api: ShipApi = _api()
	var panel: ShipPanel = _panel(api, "NAV")
	panel._throttle.value = 35.0
	check_eq(_commands.back().name, "set_throttle", "Slider commands main throttle")
	check_near(_commands.back().arguments.throttle, 0.35, 1e-12, "Percent converts to a fraction")
	panel._attitude.item_selected.emit(2)
	check_eq(_commands.back().arguments.mode, "prograde", "Attitude selector sends semantic direction")
	panel._warp.item_selected.emit(3)
	check_near(_commands.back().arguments.rate, 1000.0, 0.0, "Warp selector sends multiplier")
	panel.get_button("throttle_cutoff").pressed.emit()
	check_eq(_commands.back().name, "cutoff", "Main thrust cutoff remains accessible")
	panel.get_button("next_event").pressed.emit()
	check_eq(_commands.back().name, "next_event", "Event coasting routes through validation")
	panel.get_button("approach").pressed.emit()
	check_eq(_commands.back().name, "approach", "Finite-RCS approach uses owner controller")
	panel.get_button("rcs_forward").button_down.emit()
	check_eq(_commands.back().arguments.direction, Vector3.FORWARD, "Held forward button commands forward RCS")
	panel.get_button("rcs_forward").button_up.emit()
	check_eq(_commands.back().arguments.direction, Vector3.ZERO, "Release stops translation")
	panel.get_button("rcs_right").button_down.emit()
	panel.cancel_input()
	check_eq(_commands.back().arguments.direction, Vector3.ZERO, "Closing interface cancels held thrust")
	panel.get_button("rcs_up").button_down.emit()
	panel.select_app("SHIP")
	check_eq(_commands.back().arguments.direction, Vector3.ZERO, "App switching cancels held thrust")
	panel.select_app("PLAN")
	panel._target.item_selected.emit(1)
	check_eq(_commands.back().arguments.id, "station", "Targets use stable identifiers")
	panel.free()


## Float64 orbital positions are normalized before narrowing to drawing coordinates.
func test_scope_projection_preserves_astronomical_scale() -> void:
	var display: OrbitDisplay = OrbitDisplay.new()
	display.size = Vector2(400, 200)
	display.set_flight({"available": true, "scope": {"radius_m": 6371000.0, "ship_path": [PackedFloat64Array([1.5e11, 0.0]), PackedFloat64Array([0.0, 1.5e11])], "ship_position": PackedFloat64Array([1.5e11, 0.0])}})
	var right: Vector2 = display.project_scope(PackedFloat64Array([1.5e11, 0.0]))
	var top: Vector2 = display.project_scope(PackedFloat64Array([0.0, 1.5e11]))
	check_near(right.x, 288.0, 0.0001, "Astronomical point fits viewport")
	check_near(right.y, 100.0, 0.0001, "Origin remains centered")
	check_near(top.y, 12.0, 0.0001, "Positive orbital y points up")
	check_eq(display.project_scope(PackedFloat64Array([NAN, INF])), Vector2(200, 100), "Invalid display data fails softly")
	display.free()


## Embedded selector popups remain in the screen and accept forwarded keyboard selection.
func test_world_screen_target_popup_accepts_forwarded_input() -> void:
	_commands.clear()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var screen: WorldScreen = SCREEN.instantiate() as WorldScreen
	screen.configure(_api(), "PLAN", false)
	tree.root.add_child(screen)
	await tree.process_frame
	check((screen.get_node("SubViewport") as SubViewport).gui_embed_subwindows, "Popup windows stay inside the physical screen")
	var point: Vector2 = screen.panel._target.get_global_rect().get_center()
	var world_point: Vector3 = screen.to_global(Vector3((point.x / 640.0 - 0.5) * 1.6, 0.5 - point.y / 400.0, 0))
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	screen.forward_input(mouse, world_point)
	mouse.pressed = false
	screen.forward_input(mouse, world_point)
	await tree.process_frame
	check(screen.panel._target.get_popup().visible, "Forwarded screen click opens target selector")
	for keycode: Key in [KEY_DOWN, KEY_DOWN, KEY_ENTER]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.pressed = true
		screen.forward_input(event, world_point)
		event.pressed = false
		screen.forward_input(event, world_point)
	await tree.process_frame
	check(not _commands.is_empty(), "Forwarded popup keys reach a real API command")
	if not _commands.is_empty():
		check_eq(_commands.back().name, "select_target", "Popup selection chooses an orbital target")
		check_eq(_commands.back().arguments.id, "station", "Popup advances from derelict to station")
	screen.free()


## Both physical screens and tablet panels send docking actions through ShipApi.
func test_docking_controls_and_live_status() -> void:
	_commands.clear()
	var api: ShipApi = _api()
	var flight: Dictionary = api.get_telemetry().flight
	flight.docking = {"available": true, "docked": false, "guiding": true, "ready": true,
		"status": "READY TO DOCK", "gap_m": 0.2, "lateral_m": 0.1, "speed_mps": 0.05, "angle_rad": 0.01, "spin_rad_s": 0.005}
	api.publish_flight(flight, 24000.0)
	var panel: ShipPanel = _panel(api, "NAV")
	panel.get_button("nav_dock").pressed.emit()
	check(panel._nav_pages.dock.visible, "NAV exposes dedicated docking page")
	check(panel._dock_readout.text.contains("READY TO DOCK"), "capture status comes from copied telemetry")
	check(panel._dock_readout.text.contains("0.20 m"), "gap shown in metres")
	for action: String in ["approach_dock", "dock", "dock_cancel"]:
		panel.get_button(action).pressed.emit()
		check_eq(_commands.back().name, "cancel_plan" if action == "dock_cancel" else action, "docking action uses shared command path")
	flight.docking.docked = true
	flight.docking.status = "DOCKED / LOWLINE YARD"
	api.publish_flight(flight, 24000.0)
	panel.refresh()
	check(panel.get_button("dock").disabled and not panel.get_button("undock").disabled, "capture and release reflect the live clamp")
	check(not panel._throttle.editable and panel._attitude.disabled, "dock disables propulsion controls")
	panel.get_button("undock").pressed.emit()
	check_eq(_commands.back().name, "undock", "release uses shared command path")
	panel.free()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var screen: WorldScreen = SCREEN.instantiate() as WorldScreen
	screen.configure(api, "NAV", false)
	tree.root.add_child(screen)
	screen.panel.get_button("nav_dock").pressed.emit()
	await tree.process_frame
	var point: Vector2 = screen.panel.get_button("undock").get_global_rect().get_center()
	var world_point: Vector3 = screen.to_global(Vector3((point.x / 640.0 - 0.5) * 1.6, 0.5 - point.y / 400.0, 0))
	_commands.clear()
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	screen.forward_input(mouse, world_point)
	mouse.pressed = false
	screen.forward_input(mouse, world_point)
	await tree.process_frame
	check(not _commands.is_empty(), "physical screen click reaches docking command")
	if not _commands.is_empty():
		check_eq(_commands.back().name, "undock", "physical screen uses identical release validation")
	screen.free()


func _api() -> ShipApi:
	var api: ShipApi = ShipApi.new()
	api.bind_flight(_record_command)
	api.publish_flight({"available": true, "time_s": 100.0, "warp": 1.0, "requested_warp": 1.0, "local": true, "body_name": "Cradle", "body_radius_m": 6371000.0,
		"orbit": {"altitude_m": 400000.0, "periapsis_altitude_m": 400000.0, "apoapsis_altitude_m": 400000.0, "inclination_rad": 0.0},
		"main_propellant_kg": 24000.0, "dv_budget_mps": 12000.0, "throttle": 0.0, "attitude_mode": "manual", "executor_on": false, "burn_status": "COASTING",
		"target": {"id": "wreck", "name": "Derelict", "range_m": 100.0, "relative_speed_mps": 0.1}, "targets": [{"id": "wreck", "name": "Derelict"}, {"id": "station", "name": "Station"}],
		"plan": {"label": "Transfer", "feasible": true, "dv_mps": 50.0, "propellant_kg": 100.0, "nodes": [{"time_s": 160.0, "dv_mps": 50.0}]}, "scope": {}, "navball": {}}, 24000.0)
	return api


func _panel(api: ShipApi, app: String) -> ShipPanel:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var panel: ShipPanel = ShipPanel.new()
	panel.size = Vector2(640, 400)
	panel.configure(api, app)
	tree.root.add_child(panel)
	return panel


func _record_command(command: String, arguments: Dictionary) -> Dictionary:
	_commands.append({"name": command, "arguments": arguments})
	return {"ok": true, "message": "COMMAND ACCEPTED"}
