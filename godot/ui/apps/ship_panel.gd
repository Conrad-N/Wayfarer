## Shared NAV and SHIP apps: every reading and command goes through ShipApi.
class_name ShipPanel
extends Control

const AMBER: Color = Color("efbd72")
const CYAN: Color = Color("74dbe1")

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
	current_app = "NAV" if app == "NAV" else "SHIP"
	refresh()


## Read fresh telemetry without reaching into the ship body or simulation.
func refresh() -> void:
	if not is_instance_valid(_title):
		return
	_nav.visible = current_app == "NAV"
	_ship.visible = current_app == "SHIP"
	if api == null:
		_title.text = "WAYFARER / NO CONNECTION"
		_readout.text = "Ship telemetry unavailable."
		_detail.text = ""
		_message.text = ""
		for button: Button in _buttons.values():
			button.disabled = button.name not in [&"nav_tab", &"ship_tab"]
		return
	for button: Button in _buttons.values():
		button.disabled = false
	var data: Dictionary = api.get_telemetry()
	_title.text = "%s / %s" % [str(data.get("ship_name", "WAYFARER")).to_upper(), current_app]
	_message.text = str(data.get("last_message", ""))
	if current_app == "NAV":
		_refresh_nav(data)
	else:
		_refresh_ship(data)


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
	_title = _label(self, Vector2(16, 12), Vector2(440, 30), 18, AMBER)
	_button(self, "nav_tab", "NAV", Rect2(464, 8, 74, 34))
	_button(self, "ship_tab", "SHIP", Rect2(546, 8, 78, 34))
	_readout = _label(self, Vector2(16, 56), Vector2(608, 112), 17, AMBER)
	_detail = _label(self, Vector2(16, 176), Vector2(608, 84), 14, CYAN)
	_nav = Control.new()
	_nav.name = "NavControls"
	add_child(_nav)
	_button(_nav, "nav_brake", "HOLD STATION", Rect2(16, 282, 292, 36))
	_ship = Control.new()
	_ship.name = "ShipControls"
	add_child(_ship)
	_button(_ship, "power", "POWER", Rect2(16, 268, 192, 34))
	_button(_ship, "rcs", "RCS", Rect2(224, 268, 192, 34))
	_button(_ship, "cargo", "CARGO DOOR", Rect2(432, 268, 192, 34))
	_button(_ship, "inner", "INNER AIRLOCK", Rect2(16, 310, 296, 34))
	_button(_ship, "outer", "OUTER AIRLOCK", Rect2(328, 310, 296, 34))
	_message = _label(self, Vector2(16, 352), Vector2(608, 44), 13, AMBER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _refresh_nav(data: Dictionary) -> void:
	var motion: Dictionary = data.get("motion", {})
	var relative: Vector3 = motion.get("relative_velocity_mps", Vector3.ZERO)
	var spin: Vector3 = motion.get("angular_velocity_radps", Vector3.ZERO)
	_readout.text = "WRECK RANGE  %7.1f m\nRELATIVE SPD %7.2f m/s\nSHIP MASS    %7.1f kg\nPROPELLANT   %7.1f kg" % [float(motion.get("range_m", 0.0)), relative.length(), float(data.get("mass_kg", 0.0)), float(data.get("propellant_kg", 0.0))]
	_detail.text = "REL V  %+6.2f  %+6.2f  %+6.2f m/s\nSPIN   %.2f deg/s\nORBITAL SOLUTION UNAVAILABLE" % [relative.x, relative.y, relative.z, rad_to_deg(spin.length())]
	_buttons["nav_brake"].text = "RELEASE STATION HOLD" if bool(data.get("braking", false)) else "HOLD STATION"


func _refresh_ship(data: Dictionary) -> void:
	var manifest: Array = data.get("cargo_manifest", [])
	var door: Vector2 = data.get("door_size_m", Vector2.ZERO)
	_readout.text = "SHIP %3.0f%%   BATTERY %.1f kWh\nCARGO %d LOADS / %.1f kg\nVOLUME %.1f / %.1f m³\nDOOR CLEARANCE %.1f × %.1f m" % [float(data.get("ship_health", 0.0)) * 100.0, float(data.get("battery_energy_j", 0.0)) / 3600000.0, manifest.size(), float(data.get("cargo_mass_kg", 0.0)), float(data.get("cargo_volume_m3", 0.0)), float(data.get("cargo_capacity_m3", 0.0)), door.x, door.y]
	var systems: Dictionary = data.get("systems", {})
	var lines: PackedStringArray = []
	var row: PackedStringArray = []
	for id: String in systems:
		var system: Dictionary = systems[id]
		row.append("%-7s %3.0f%% %-3s" % [id.to_upper(), float(system.get("health", 0.0)) * 100.0, "ON" if bool(system.get("enabled", false)) else "OFF"])
		if row.size() == 3:
			lines.append("  ".join(row))
			row.clear()
	if not row.is_empty():
		lines.append("  ".join(row))
	_detail.text = "SYSTEM HEALTH\n" + "\n".join(lines)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buttons["power"].text = "POWER: " + _system_state(systems, "power")
	_buttons["rcs"].text = "RCS: " + _system_state(systems, "rcs")
	_buttons["cargo"].text = "CLOSE CARGO" if bool(data.get("cargo_door_open", false)) else "OPEN CARGO"
	_buttons["inner"].text = "CLOSE INNER" if bool(data.get("airlock_inner_open", false)) else "OPEN INNER"
	_buttons["outer"].text = "CLOSE OUTER" if bool(data.get("airlock_outer_open", false)) else "OPEN OUTER"


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
	if action == "nav_tab" or action == "ship_tab":
		select_app("NAV" if action == "nav_tab" else "SHIP")
		return
	if api == null:
		return
	var data: Dictionary = api.get_telemetry()
	match action:
		"nav_brake":
			api.set_braking(not bool(data.get("braking", false)))
		"cargo":
			api.set_cargo_door(not bool(data.get("cargo_door_open", false)))
		"inner", "outer":
			api.set_airlock_door(action, not bool(data.get("airlock_" + action + "_open", false)))
		"power", "rcs":
			var systems: Dictionary = data.get("systems", {})
			var system: Dictionary = systems.get(action, {})
			api.set_system_enabled(action, not bool(system.get("enabled", false)))
	refresh()
