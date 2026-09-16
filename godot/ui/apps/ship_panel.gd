## Shared NAV, PLAN and SHIP apps: every reading and command goes through ShipApi.
class_name ShipPanel
extends Control

const AMBER: Color = Color("efbd72")
const CYAN: Color = Color("74dbe1")
const MUTED: Color = Color("536b78")

var api: ShipApi
var current_app: String = "SHIP"
var _elapsed: float = 0.0
var _title: Label
var _readout: Label
var _detail: Label
var _message: Label
var _nav: Control
var _ship: Control
var _buttons: Dictionary = {}
var _plan: Control
var _nav_pages: Dictionary = {}
var _nav_page: String = "scope"
var _flight_readout: Label
var _scope_readout: Label
var _dock_readout: Label
var _rcs_readout: Label
var _wheel_readout: Label
var _flight_wheels: Label
var _scope: OrbitDisplay
var _navball: OrbitDisplay
var _target: OptionButton
var _solver: OptionButton
var _attitude: OptionButton
var _warp: OptionButton
var _throttle: HSlider
var _inputs: Dictionary = {}
var _input_labels: Dictionary = {}
var _plan_setup: Control
var _plan_preview: Control
var _plan_summary: Label
var _preview_visible: bool = false
var _target_ids: PackedStringArray = []
var _rcs_held: bool = false
const ATTITUDES: PackedStringArray = ["manual", "kill", "prograde", "retrograde", "normal", "antinormal", "radial_out", "radial_in", "target", "anti_target", "node"]
const WARP_RATES: Array[float] = [1.0, 10.0, 100.0, 1000.0]
const SOLVERS: PackedStringArray = ["Intercept", "Circularize apoapsis", "Circularize periapsis", "Hohmann", "Match velocity", "Manual maneuver"]


func _ready() -> void:
	_build()
	refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		refresh()


## Use the same ship connection on a fixed terminal or handheld tablet.
func configure(ship_api: ShipApi, initial_app: String = "SHIP") -> void:
	api = ship_api
	select_app(initial_app)


## Switch the displayed app without replacing controls or losing their signals.
func select_app(app: String) -> void:
	if _rcs_held:
		_release_rcs()
	current_app = app if app in ["NAV", "PLAN", "SHIP"] else "SHIP"
	refresh()


## Read fresh telemetry without reaching into the ship body or simulation.
func refresh() -> void:
	if not is_instance_valid(_title):
		return
	_nav.visible = current_app == "NAV"
	_ship.visible = current_app == "SHIP"
	_plan.visible = current_app == "PLAN"
	_readout.visible = current_app == "SHIP"
	_detail.visible = current_app == "SHIP"
	if api == null:
		_title.text = "WAYFARER / NO CONNECTION"
		_readout.text = "Ship telemetry unavailable."
		_detail.text = ""
		_message.text = ""
		for button: Button in _buttons.values():
			button.disabled = button.name not in [&"nav_tab", &"plan_tab", &"ship_tab"]
		return
	for button: Button in _buttons.values():
		button.disabled = false
	var data: Dictionary = api.get_telemetry()
	_title.text = "%s / %s" % [str(data.get("ship_name", "WAYFARER")).to_upper(), current_app]
	_message.text = str(data.get("last_message", ""))
	if current_app == "NAV":
		_refresh_nav(data)
	elif current_app == "PLAN":
		_refresh_plan(data)
	else:
		_refresh_ship(data)


## Release held physical controls when an interface is closed or loses power.
func cancel_input() -> void:
	_release_rcs()
	var popup: PopupMenu = active_popup()
	if popup != null:
		popup.hide()


## Return the visible embedded selector so the physical screen can route its input.
func active_popup() -> PopupMenu:
	for selector: OptionButton in [_target, _solver, _attitude, _warp]:
		if is_instance_valid(selector) and selector.get_popup().visible:
			return selector.get_popup()
	return null


## Return a named control for focus, accessibility, and integration checks.
func get_button(action: String) -> Button:
	return _buttons.get(action) as Button


func _build() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "monospace"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	var background: ColorRect = ColorRect.new()
	background.color = Color("101c23")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_title = _label(self, Vector2(16, 12), Vector2(356, 30), 18, AMBER)
	_button(self, "nav_tab", "NAV", Rect2(380, 8, 74, 34))
	_button(self, "plan_tab", "PLAN", Rect2(462, 8, 78, 34))
	_button(self, "ship_tab", "SHIP", Rect2(548, 8, 76, 34))
	_readout = _label(self, Vector2(16, 56), Vector2(608, 96), 17, AMBER)
	_detail = _label(self, Vector2(16, 158), Vector2(608, 58), 12, CYAN)
	_nav = Control.new()
	_nav.name = "NavControls"
	add_child(_nav)
	_build_nav()
	_build_plan()
	_ship = Control.new()
	_ship.name = "ShipControls"
	add_child(_ship)
	_button(_ship, "power", "POWER", Rect2(16, 268, 192, 34))
	_button(_ship, "rcs", "RCS", Rect2(224, 268, 192, 34))
	_wheel_readout = _label(_ship, Vector2(16, 222), Vector2(608, 38), 12, AMBER)
	_button(_ship, "reaction_wheel", "WHEELS", Rect2(432, 268, 192, 34))
	_button(_ship, "cargo", "CARGO DOOR", Rect2(432, 310, 192, 34))
	_button(_ship, "inner", "INNER AIRLOCK", Rect2(16, 310, 192, 34))
	_button(_ship, "outer", "OUTER AIRLOCK", Rect2(224, 310, 192, 34))
	_message = _label(self, Vector2(16, 352), Vector2(608, 44), 13, AMBER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _refresh_nav(data: Dictionary) -> void:
	var flight: Dictionary = data.get("flight", {})
	var available: bool = bool(flight.get("available", false))
	for page: String in _nav_pages:
		_nav_pages[page].visible = page == _nav_page
	_scope.set_flight(flight)
	_navball.set_flight(flight)
	var orbit: Dictionary = flight.get("orbit", {})
	var target: Dictionary = flight.get("target", {})
	var motion: Dictionary = data.get("motion", {})
	var relative: Vector3 = motion.get("relative_velocity_mps", Vector3.ZERO)
	var range_m: float = target.get("range_m", motion.get("range_m", 0.0))
	var relative_speed: float = target.get("relative_speed_mps", relative.length())
	_scope_readout.text = "%s\nALT  %s\nPe   %s\nAp   %s\nINC  %.1f°\nTGT  %s / %.1f m/s" % [str(flight.get("body_name", "ORBIT UNAVAILABLE")), _distance(orbit.get("altitude_m", 0.0)), _distance(orbit.get("periapsis_altitude_m", 0.0)), _distance(orbit.get("apoapsis_altitude_m", 0.0)), rad_to_deg(float(orbit.get("inclination_rad", 0.0))), _distance(range_m), relative_speed]
	_flight_readout.text = "T + %s   WARP ×%.0f\nMASS %.1f t   FUEL %.1f t   Δv %.0f m/s\n%s" % [_duration(flight.get("time_s", 0.0)), float(flight.get("warp", 1.0)), float(data.get("mass_kg", 0.0)) / 1000.0, float(flight.get("main_propellant_kg", 0.0)) / 1000.0, float(flight.get("dv_budget_mps", 0.0)), str(flight.get("burn_status", "FLIGHT COMPUTER UNAVAILABLE")) + "  / THRUST %.0f%%" % (float(flight.get("throttle", 0.0)) * 100.0)]
	_throttle.set_value_no_signal(float(flight.get("throttle", 0.0)) * 100.0)
	var attitude_index: int = ATTITUDES.find(str(flight.get("attitude_mode", "manual")))
	_attitude.select(maxi(0, attitude_index))
	var warp_index: int = WARP_RATES.find(float(flight.get("requested_warp", 1.0)))
	_warp.select(maxi(0, warp_index))
	_throttle.editable = available
	_attitude.disabled = not available
	_warp.disabled = not available
	_rcs_readout.text = "%s\nRANGE %s   REL SPD %.2f m/s\nRCS %.2f kg / %s" % [str(target.get("name", "WRECK")), _distance(range_m), relative_speed, float(data.get("propellant_kg", 0.0)), "LOCAL CONTROL" if bool(flight.get("local", true)) else "ORBITAL FLIGHT"]
	_flight_wheels.text = _wheel_status(data)
	_buttons["nav_brake"].text = "RELEASE HOLD" if bool(data.get("braking", false)) else "HOLD STATION"
	for action: String in ["throttle_cutoff", "next_event", "approach"]:
		_buttons[action].disabled = not available
	var docking: Dictionary = flight.get("docking", {})
	var nearby: bool = bool(docking.get("available", false))
	var docked: bool = bool(docking.get("docked", false))
	_dock_readout.text = "NO STATION RING NEARBY\nSelect Lowline Yard in PLAN and match velocity."
	if nearby:
		_dock_readout.text = "%s\nGAP %.2f m / 0–0.50   SIDE %.2f m / ≤0.30\nSPEED %.2f m/s / ≤0.30   ALIGN %.1f° / ≤5\nSPIN %.2f°/s / ≤1.15\n%s" % [str(docking.status), float(docking.gap_m), float(docking.lateral_m), float(docking.speed_mps), rad_to_deg(float(docking.angle_rad)), rad_to_deg(float(docking.spin_rad_s)), "GUIDING — press DOCK when ready" if bool(docking.get("guiding", false)) else "Enter from the marked front; cargo end first."]
	_buttons["approach_dock"].disabled = not nearby or docked
	_buttons["dock"].disabled = not nearby or docked
	_buttons["undock"].disabled = not docked
	_buttons["dock_cancel"].disabled = not bool(docking.get("guiding", false))
	if docked:
		_throttle.editable = false
		_attitude.disabled = true
		_buttons["nav_brake"].disabled = true
		_buttons["approach"].disabled = true


func _refresh_plan(data: Dictionary) -> void:
	var flight: Dictionary = data.get("flight", {})
	var targets: Array = flight.get("targets", [])
	var ids: PackedStringArray = []
	for target: Dictionary in targets:
		ids.append(str(target.get("id", "")))
	if ids != _target_ids:
		_target_ids = ids
		_target.clear()
		for target: Dictionary in targets:
			_target.add_item(str(target.get("name", "Target")))
	var selected: String = str((flight.get("target", {}) as Dictionary).get("id", ""))
	var target_index: int = _target_ids.find(selected)
	if target_index >= 0:
		_target.select(target_index)
	_target.disabled = not bool(flight.get("available", false)) or targets.is_empty()
	_plan_setup.visible = not _preview_visible
	_plan_preview.visible = _preview_visible
	_update_plan_inputs()
	var plan: Dictionary = flight.get("plan", {})
	if (plan.get("nodes", []) as Array).is_empty():
		plan = {}
	var lines: PackedStringArray = []
	if plan.is_empty():
		lines.append("NO MANEUVER PLANNED")
		lines.append("Choose a calculator, then preview its burns.")
	else:
		lines.append(str(plan.get("label", "Maneuver plan")))
		lines.append("%s   Δv %.1f m/s   FUEL %.1f kg" % ["EXECUTING" if bool(flight.get("executor_on", false)) else ("READY" if bool(plan.get("feasible", false)) else "PLAN NOT FEASIBLE"), float(plan.get("dv_mps", 0.0)), float(plan.get("propellant_kg", 0.0))])
		var index: int = 0
		for node: Dictionary in plan.get("nodes", []):
			index += 1
			lines.append("%d T+%s  P%+.1f N%+.1f R%+.1f m/s" % [index, _duration(node.get("time_s", 0.0)), float(node.get("prograde_mps", 0.0)), float(node.get("normal_mps", 0.0)), float(node.get("radial_mps", 0.0))])
		lines.append("BUDGET %.0f m/s   %s" % [float(flight.get("dv_budget_mps", 0.0)), str(flight.get("burn_status", ""))])
	_plan_summary.text = "\n".join(lines)
	_buttons["execute_plan"].disabled = plan.is_empty() or not bool(plan.get("feasible", false)) or bool(flight.get("executor_on", false))
	_buttons["calculate_plan"].disabled = not bool(flight.get("available", false))


func _refresh_ship(data: Dictionary) -> void:
	var manifest: Array = data.get("cargo_manifest", [])
	var door: Vector2 = data.get("door_size_m", Vector2.ZERO)
	var solar_line: String = "SOLAR %.1f kW%s" % [float(data.get("solar_power_w", 0.0)) / 1000.0, "" if bool(data.get("solar_sunlit", true)) else " (SHADOW)"]
	_readout.text = "SHIP %3.0f%%   BATTERY %.1f kWh\nCARGO %d LOADS / %.1f kg / %.1f of %.1f m³\n%s\nDOOR CLEARANCE %.1f × %.1f m" % [float(data.get("ship_health", 0.0)) * 100.0, float(data.get("battery_energy_j", 0.0)) / 3600000.0, manifest.size(), float(data.get("cargo_mass_kg", 0.0)), float(data.get("cargo_volume_m3", 0.0)), float(data.get("cargo_capacity_m3", 0.0)), solar_line, door.x, door.y]
	var systems: Dictionary = data.get("systems", {})
	var lines: PackedStringArray = []
	var row: PackedStringArray = []
	for id: String in systems:
		var system: Dictionary = systems[id]
		var caption: String = "WHEELS" if id == "reaction_wheel" else id.to_upper()
		row.append("%-7s %3.0f%% %-3s" % [caption, float(system.get("health", 0.0)) * 100.0, "ON" if bool(system.get("enabled", false)) else "OFF"])
		if row.size() == 3:
			lines.append("  ".join(row))
			row.clear()
	if not row.is_empty():
		lines.append("  ".join(row))
	_detail.text = "\n".join(lines)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var wheel: Dictionary = (data.get("flight", {}) as Dictionary).get("reaction_wheel", {})
	var momentum: Dictionary = wheel.get("momentum_nms", {})
	_wheel_readout.text = _wheel_status(data)
	if not wheel.is_empty():
		_wheel_readout.text += "\nH [%+.0f, %+.0f, %+.0f] / ±%.0f N·m·s per axis" % [float(momentum.get("x", 0.0)), float(momentum.get("y", 0.0)), float(momentum.get("z", 0.0)), float(wheel.get("capacity_nms", 0.0))]
	_buttons["reaction_wheel"].text = "WHEELS: " + _system_state(systems, "reaction_wheel")
	_buttons["reaction_wheel"].disabled = not systems.has("reaction_wheel")
	_buttons["power"].text = "POWER: " + _system_state(systems, "power")
	_buttons["rcs"].text = "RCS: " + _system_state(systems, "rcs")
	_buttons["cargo"].text = "CLOSE CARGO" if bool(data.get("cargo_door_open", false)) else "OPEN CARGO"
	_buttons["inner"].text = "CLOSE INNER" if bool(data.get("airlock_inner_open", false)) else "OPEN INNER"
	_buttons["outer"].text = "CLOSE OUTER" if bool(data.get("airlock_outer_open", false)) else "OPEN OUTER"


func _wheel_status(data: Dictionary) -> String:
	var flight: Dictionary = data.get("flight", {})
	var wheel: Dictionary = flight.get("reaction_wheel", {})
	if wheel.is_empty():
		return "REACTION WHEELS / TELEMETRY UNAVAILABLE"
	var system: Dictionary = (data.get("systems", {}) as Dictionary).get("reaction_wheel", {})
	var status: String = "AUTO OFF" if str(flight.get("attitude_mode", "manual")) == "manual" else "AUTO ON"
	if not bool(system.get("enabled", false)) or float(system.get("health", 0.0)) <= 0.0:
		status = "UNAVAILABLE"
	elif not bool(data.get("power_available", false)):
		status = "NO POWER"
	elif float(wheel.get("utilization", 0.0)) >= 0.98:
		status = "SATURATED"
	return "WHEEL STORAGE %.0f%% / %s" % [float(wheel.get("utilization", 0.0)) * 100.0, status]


func _system_state(systems: Dictionary, id: String) -> String:
	var system: Dictionary = systems.get(id, {})
	return "ON" if bool(system.get("enabled", false)) else "OFF"


func _label(parent: Node, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, action: String, caption: String, bounds: Rect2) -> void:
	var button: Button = Button.new()
	button.name = action
	button.position = bounds.position
	button.size = bounds.size
	button.text = caption
	button.add_theme_color_override("font_color", CYAN)
	button.pressed.connect(_command.bind(action))
	parent.add_child(button)
	_buttons[action] = button


func _command(action: String) -> void:
	if action in ["nav_tab", "plan_tab", "ship_tab"]:
		select_app(action.trim_suffix("_tab").to_upper())
		return
	if api == null:
		return
	var data: Dictionary = api.get_telemetry()
	match action:
		"nav_scope", "nav_flight", "nav_rcs", "nav_dock":
			_release_rcs()
			_nav_page = action.trim_prefix("nav_")
		"plan_setup", "plan_preview":
			_preview_visible = action == "plan_preview"
		"calculate_plan":
			_calculate_plan(data)
		"execute_plan":
			api.execute_plan()
		"cancel_plan":
			api.cancel_plan()
		"throttle_cutoff":
			api.flight_command("cutoff")
		"next_event":
			api.advance_to_next_event()
		"approach_dock":
			api.approach_dock()
		"dock":
			api.dock()
		"undock":
			api.undock()
		"dock_cancel":
			api.cancel_plan()
		"approach":
			api.flight_command("approach")
		"nav_brake":
			api.set_braking(not bool(data.get("braking", false)))
		"cargo":
			api.set_cargo_door(not bool(data.get("cargo_door_open", false)))
		"inner", "outer":
			api.set_airlock_door(action, not bool(data.get("airlock_" + action + "_open", false)))
		"power", "rcs", "reaction_wheel":
			var systems: Dictionary = data.get("systems", {})
			var system: Dictionary = systems.get(action, {})
			api.set_system_enabled(action, not bool(system.get("enabled", false)))
	refresh()


func _build_nav() -> void:
	_button(_nav, "nav_scope", "ORBIT", Rect2(16, 54, 144, 34))
	_button(_nav, "nav_flight", "FLIGHT", Rect2(172, 54, 144, 34))
	_button(_nav, "nav_rcs", "RCS", Rect2(328, 54, 144, 34))
	_button(_nav, "nav_dock", "DOCK", Rect2(484, 54, 140, 34))
	for page: String in ["scope", "flight", "rcs", "dock"]:
		var control: Control = Control.new()
		control.name = page
		control.visible = page == "scope"
		_nav.add_child(control)
		_nav_pages[page] = control
	var scope_page: Control = _nav_pages.scope
	_scope = OrbitDisplay.new()
	_scope.position = Vector2(16, 96)
	_scope.size = Vector2(364, 248)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_page.add_child(_scope)
	_navball = OrbitDisplay.new()
	_navball.display_kind = "navball"
	_navball.position = Vector2(396, 96)
	_navball.size = Vector2(228, 128)
	_navball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_page.add_child(_navball)
	_scope_readout = _label(scope_page, Vector2(396, 232), Vector2(228, 112), 12, CYAN)
	var flight_page: Control = _nav_pages.flight
	_flight_readout = _label(flight_page, Vector2(16, 100), Vector2(608, 76), 15, AMBER)
	_label(flight_page, Vector2(16, 183), Vector2(108, 30), 14, CYAN).text = "THROTTLE %"
	_throttle = HSlider.new()
	_throttle.position = Vector2(132, 182)
	_throttle.size = Vector2(354, 32)
	_throttle.min_value = 0.0
	_throttle.max_value = 100.0
	_throttle.step = 1.0
	_throttle.value_changed.connect(_throttle_changed)
	flight_page.add_child(_throttle)
	_button(flight_page, "throttle_cutoff", "CUTOFF", Rect2(504, 180, 120, 34))
	_label(flight_page, Vector2(16, 234), Vector2(112, 30), 14, CYAN).text = "ATTITUDE"
	_attitude = OptionButton.new()
	_attitude.position = Vector2(132, 230)
	_attitude.size = Vector2(208, 36)
	for mode: String in ATTITUDES:
		_attitude.add_item("AUTO OFF" if mode == "manual" else ("STOP ROTATION" if mode == "kill" else mode.replace("_", " ").to_upper()))
	_attitude.item_selected.connect(_attitude_selected)
	flight_page.add_child(_attitude)
	_label(flight_page, Vector2(360, 234), Vector2(72, 30), 14, CYAN).text = "WARP"
	_warp = OptionButton.new()
	_warp.position = Vector2(432, 230)
	_warp.size = Vector2(192, 36)
	for rate: float in WARP_RATES:
		_warp.add_item("×%.0f" % rate)
	_warp.item_selected.connect(_warp_selected)
	flight_page.add_child(_warp)
	_flight_wheels = _label(flight_page, Vector2(16, 276), Vector2(608, 26), 12, CYAN)
	_button(flight_page, "next_event", "COAST TO NEXT EVENT", Rect2(16, 310, 608, 34))
	var rcs_page: Control = _nav_pages.rcs
	_rcs_readout = _label(rcs_page, Vector2(16, 100), Vector2(608, 74), 15, AMBER)
	for action: String in ["forward", "back", "left", "right", "up", "down"]:
		var positions: Dictionary = {"forward": Vector2(140, 180), "back": Vector2(140, 266), "left": Vector2(16, 223), "right": Vector2(264, 223), "up": Vector2(456, 180), "down": Vector2(456, 266)}
		_button(rcs_page, "rcs_" + action, action.to_upper(), Rect2(positions[action], Vector2(116, 34)))
		var button: Button = _buttons["rcs_" + action]
		button.button_down.connect(_press_rcs.bind(action))
		button.button_up.connect(_release_rcs)
	_label(rcs_page, Vector2(140, 226), Vector2(116, 28), 12, MUTED).text = "HOLD TO THRUST"
	_button(rcs_page, "nav_brake", "HOLD STATION", Rect2(16, 310, 292, 34))
	_button(rcs_page, "approach", "APPROACH TARGET", Rect2(324, 310, 300, 34))
	var dock_page: Control = _nav_pages.dock
	_dock_readout = _label(dock_page, Vector2(16, 100), Vector2(608, 160), 16, AMBER)
	_button(dock_page, "approach_dock", "GUIDE TO RING", Rect2(16, 268, 292, 34))
	_button(dock_page, "dock_cancel", "CANCEL APPROACH", Rect2(324, 268, 300, 34))
	_button(dock_page, "dock", "DOCK / ENGAGE CLAMP", Rect2(16, 310, 292, 34))
	_button(dock_page, "undock", "UNDOCK / RELEASE", Rect2(324, 310, 300, 34))


func _build_plan() -> void:
	_plan = Control.new()
	_plan.name = "PlanControls"
	add_child(_plan)
	_label(_plan, Vector2(16, 59), Vector2(80, 30), 14, CYAN).text = "TARGET"
	_target = OptionButton.new()
	_target.position = Vector2(96, 54)
	_target.size = Vector2(310, 36)
	_target.item_selected.connect(_target_selected)
	_plan.add_child(_target)
	_button(_plan, "plan_setup", "SETUP", Rect2(422, 54, 94, 36))
	_button(_plan, "plan_preview", "PREVIEW", Rect2(530, 54, 94, 36))
	_plan_setup = Control.new()
	_plan.add_child(_plan_setup)
	_plan_preview = Control.new()
	_plan_preview.visible = false
	_plan.add_child(_plan_preview)
	_solver = OptionButton.new()
	_solver.position = Vector2(16, 106)
	_solver.size = Vector2(608, 36)
	for caption: String in SOLVERS:
		_solver.add_item(caption.to_upper())
	_solver.item_selected.connect(_solver_selected)
	_plan_setup.add_child(_solver)
	_numeric_input("duration", "FLIGHT TIME / min", Vector2(16, 168), 1.0, 360.0, 1.0, 160.0)
	_numeric_input("altitude", "TARGET ALTITUDE / km", Vector2(16, 168), 1.0, 1000000.0, 1.0, 800.0)
	_numeric_input("delay", "BURN IN / min", Vector2(16, 168), 0.0, 1000000.0, 1.0, 2.0)
	_numeric_input("prograde", "PROGRADE / m/s", Vector2(224, 168), -50000.0, 50000.0, 1.0, 10.0)
	_numeric_input("normal", "NORMAL / m/s", Vector2(432, 168), -50000.0, 50000.0, 1.0, 0.0)
	_numeric_input("radial", "RADIAL / m/s", Vector2(16, 244), -50000.0, 50000.0, 1.0, 0.0)
	_button(_plan_setup, "calculate_plan", "CALCULATE PREVIEW", Rect2(16, 310, 608, 34))
	_plan_summary = _label(_plan_preview, Vector2(16, 106), Vector2(608, 194), 14, AMBER)
	_plan_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_plan_preview, "execute_plan", "EXECUTE BURNS", Rect2(16, 310, 292, 34))
	_button(_plan_preview, "cancel_plan", "CANCEL / CUTOFF", Rect2(324, 310, 300, 34))


func _numeric_input(id: String, caption: String, position_px: Vector2, minimum: float, maximum: float, increment: float, initial: float) -> void:
	var label: Label = _label(_plan_setup, position_px - Vector2(0, 22), Vector2(192, 24), 12, CYAN)
	label.text = caption
	_input_labels[id] = label
	var input: SpinBox = SpinBox.new()
	input.position = position_px
	input.size = Vector2(192, 36)
	input.min_value = minimum
	input.max_value = maximum
	input.step = increment
	input.value = initial
	_plan_setup.add_child(input)
	_inputs[id] = input


func _update_plan_inputs() -> void:
	var solver: int = _solver.selected
	for id: String in _inputs:
		var shown: bool = (id == "duration" and solver == 0) or (id == "altitude" and solver == 3) or (solver == 5 and id in ["delay", "prograde", "normal", "radial"])
		_inputs[id].visible = shown
		_input_labels[id].visible = shown


func _calculate_plan(data: Dictionary) -> void:
	var accepted: bool = false
	match _solver.selected:
		0:
			accepted = api.plan_intercept(float(_inputs.duration.value) * 60.0)
		1, 2:
			accepted = api.flight_command("plan_circularize", {"at": "apoapsis" if _solver.selected == 1 else "periapsis"})
		3:
			accepted = api.flight_command("plan_hohmann", {"altitude_m": float(_inputs.altitude.value) * 1000.0})
		4:
			accepted = api.flight_command("plan_match_velocity")
		5:
			var flight: Dictionary = data.get("flight", {})
			accepted = api.plan_maneuver(float(flight.get("time_s", 0.0)) + float(_inputs.delay.value) * 60.0, _inputs.prograde.value, _inputs.normal.value, _inputs.radial.value)
	if accepted:
		_preview_visible = true


func _target_selected(index: int) -> void:
	if api != null and index >= 0 and index < _target_ids.size():
		api.select_target(_target_ids[index])
	refresh()


func _solver_selected(_index: int) -> void:
	_update_plan_inputs()


func _throttle_changed(percent: float) -> void:
	if api != null:
		api.set_throttle(percent / 100.0)


func _attitude_selected(index: int) -> void:
	if api != null and index >= 0 and index < ATTITUDES.size():
		api.set_attitude_mode(ATTITUDES[index])


func _warp_selected(index: int) -> void:
	if api != null and index >= 0 and index < WARP_RATES.size():
		api.set_warp(WARP_RATES[index])


func _press_rcs(action: String) -> void:
	if api == null:
		return
	var directions: Dictionary = {"forward": Vector3.FORWARD, "back": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT, "up": Vector3.UP, "down": Vector3.DOWN}
	_rcs_held = api.set_rcs_translation(directions.get(action, Vector3.ZERO))


func _release_rcs() -> void:
	if _rcs_held and api != null:
		api.set_rcs_translation(Vector3.ZERO)
	_rcs_held = false


func _exit_tree() -> void:
	_release_rcs()


static func _distance(metres: float) -> String:
	if not is_finite(metres):
		return "ESCAPE"
	return "%.1f km" % (metres / 1000.0) if absf(metres) >= 1000.0 else "%.1f m" % metres


static func _duration(seconds: float) -> String:
	if not is_finite(seconds):
		return "—"
	if seconds >= 86400.0:
		return "%.1f d" % (seconds / 86400.0)
	if seconds >= 3600.0:
		return "%.1f h" % (seconds / 3600.0)
	return "%.1f min" % (seconds / 60.0)
