## First-person orbital flight with persistent local salvage encounters.
extends Node3D

@export var salvage_practice: bool = false

@onready var _player: Player = $Player
@onready var _readout: Label = $HUD/Readout
@onready var _supplies: Label = $HUD/Supplies
@onready var _supply_warning: Label = $HUD/SupplyWarning
@onready var _grapple_status: Label = $HUD/GrappleStatus
@onready var _screenshot_status: Label = $HUD/ScreenshotStatus
@onready var _screenshot: DebugScreenshot = $DebugScreenshot
@onready var _wreck: SalvageWreck = $Wreck
@onready var _hazards: SalvageHazards = $Hazards
@onready var _tool_status: Label = $HUD/ToolStatus
@onready var _salvage_status: Label = $HUD/SalvageStatus
@onready var _target_status: Label = $HUD/TargetStatus

var _ship: PlayerShip
var _cargo: CargoHold
var _interaction: ShipInteraction
var _grip: PhysicalGrip
var _boots: MagneticBoots
var _flight: OrbitalFlight

var _screenshot_notice_seconds: float = 0.0


func _ready() -> void:
	_apply_startup_window_mode()
	_screenshot.capture_started.connect(_on_capture_started)
	_screenshot.capture_finished.connect(_on_capture_finished)
	if salvage_practice:
		_wreck.spawn(PracticeWreck.make_graph(), Transform3D(Basis(Vector3.UP, 0.3), Vector3(-7, 0, 0)), Vector3.ZERO, Vector3(0.0, 0.06, 0.025))
	_hazards.configure(_wreck)
	var tools: SalvageTools = SalvageTools.new()
	tools.name = "SalvageTools"
	_player.add_child(tools)
	tools.configure(_player, _wreck, _hazards)
	_player.salvage_tools = tools
	var impacts: SuitImpacts = SuitImpacts.new()
	impacts.name = "SuitImpacts"
	impacts.configure(_player)
	_player.add_child(impacts)
	_build_contacts()
	_build_ship()
	if not salvage_practice:
		_flight = OrbitalFlight.new()
		_flight.name = "OrbitalFlight"
		add_child(_flight)
		_flight.configure(get_node("/root/Sim") as OrbitalSession, _ship, _player, _wreck, _hazards)
		print("Wayfarer M4: orbital flight. F terminal / Tab tablet / PLAN transfer.")
		return
	var wall: Color = Color(0.12, 0.16, 0.20)
	var deck: Color = Color(0.22, 0.26, 0.29)
	var amber: Color = Color(0.85, 0.48, 0.12)
	var cyan: Color = Color(0.13, 0.58, 0.65)
	_add_box("Deck", Vector3(40, 0.5, 44), Vector3(0, -9.25, 0), deck)
	_add_box("Ceiling", Vector3(40, 0.5, 44), Vector3(0, 9.25, 0), wall)
	_add_box("Port", Vector3(0.5, 18, 44), Vector3(-20.25, 0, 0), wall)
	_add_box("Starboard", Vector3(0.5, 18, 44), Vector3(20.25, 0, 0), wall)
	_add_box("Forward", Vector3(40, 18, 0.5), Vector3(0, 0, -22.25), wall)
	_add_box("Aft", Vector3(40, 18, 0.5), Vector3(0, 0, 22.25), wall)
	for z: int in range(-18, 22, 6):
		_add_box("DeckStripe", Vector3(40, 0.04, 0.12), Vector3(0, -8.98, z), amber)
		_add_box("PortRib", Vector3(0.15, 18, 0.15), Vector3(-19.95, 0, z), amber)
		_add_box("StarboardRib", Vector3(0.15, 18, 0.15), Vector3(19.95, 0, z), cyan)
	_add_box("ForwardMarker", Vector3(5, 0.25, 0.15), Vector3(0, 1.8, -21.95), cyan)
	_add_box("ForwardMarker", Vector3(0.25, 3.5, 0.15), Vector3(0, 0.2, -21.95), cyan)
	print("Wayfarer M3: ship, terminals, tablet, and physical cargo. F terminal / Tab tablet.")


func _apply_startup_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Some window managers ignore the initial fullscreen hint before the window exists.
	get_window().set_deferred("mode", ProjectSettings.get_setting("display/window/size/mode", Window.MODE_WINDOWED))


func _process(delta: float) -> void:
	_screenshot_notice_seconds = maxf(0.0, _screenshot_notice_seconds - delta)
	_screenshot_status.visible = _screenshot_notice_seconds > 0.0
	var capture_hint: String = "Esc releases mouse" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "Click to fly"
	if _player.has_automatic_freelook() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		capture_hint = "FREE LOOK"
	elif _player.is_freelooking():
		capture_hint = "FREE LOOK / release Z to centre"
	var brake_hint: String = "RCS BRAKE" if _player.is_braking() else ("WHEEL BRAKE" if _player.is_wheel_braking() else "FREE FLIGHT")
	if _player.is_wheel_dumping() and not _player.is_braking():
		brake_hint = "WHEEL DUMP / REACTION TORQUE"
	if _player.suit.propellant_kg <= 0.0 and not _player.is_wheel_braking() and not _player.is_wheel_dumping():
		brake_hint = "RCS EMPTY"
	_readout.text = "WAYFARER / SALVAGE YARD\n%.2f m/s  |  %.1f deg/s  |  %s  |  %s" % [
		_player.linear_velocity.length(), rad_to_deg(_player.angular_velocity.length()),
		brake_hint, capture_hint
	]
	_supplies.text = "PROPELLANT  %.3f kg / %.1f kg  |  BATTERY  %.1f Wh / %.0f Wh" % [
		_player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG,
		_player.suit.battery_energy_j / 3600.0, SuitResources.BATTERY_CAPACITY_J / 3600.0
	]
	var warnings: PackedStringArray = []
	if _player.suit.propellant_kg <= 0.0:
		warnings.append("PROPELLANT EMPTY: RCS thrust and Alt brake unavailable")
	elif _player.suit.propellant_kg <= SuitResources.PROPELLANT_CAPACITY_KG * 0.1:
		warnings.append("LOW PROPELLANT")
	if _player.suit.battery_energy_j <= 0.0:
		warnings.append("BATTERY EMPTY: tools, body steering and powered steps unavailable")
	elif _player.suit.battery_energy_j <= SuitResources.BATTERY_CAPACITY_J * 0.1:
		warnings.append("LOW BATTERY")
	_supply_warning.text = "  |  ".join(warnings)
	_grapple_status.text = "GRAPPLE / " + _player.grapple.status
	if _player.grapple.is_attached():
		_grapple_status.text += "  |  CABLE %.1f m" % _player.grapple.cable_length_m
	_tool_status.text = _player.salvage_tools.status
	_grapple_status.text += "\n" + _grip.status + " | " + _boots.status
	_supplies.text += " | WHEELS %.0f%%" % (_player.attitude.utilization() * 100.0)
	if _player.attitude.utilization() >= 0.98:
		_supply_warning.text += " | WHEELS FULL: C dumps into body / Alt unloads with jets"
	_target_status.text = _interaction.hint + "\n" + _player.salvage_tools.target_readout
	var in_ship: Vector3 = _ship.to_local(_player.global_position)
	if in_ship.z < -1.8 and in_ship.z > -12.0 and absf(in_ship.x) < 4.0 and absf(in_ship.y) < 3.0:
		_target_status.text += "\nCARGO / " + str(_ship.api.get_telemetry().last_message)
	for label: String in ["Readout", "Supplies", "SupplyWarning", "GrappleStatus", "ToolStatus", "SalvageStatus", "Reticle", "Controls"]:
		($HUD.get_node(label) as CanvasItem).visible = not _interaction.is_open()
	_target_status.position.y = get_viewport().get_visible_rect().size.y - 40.0 if _interaction.is_open() else 338.0
	_salvage_status.text = "WRECK %d pieces | %d joints | SALVAGED VALUE %.0f cr | %d active leaks" % [
		_wreck.bodies.size(), _wreck.graph.edge_ids().size(), _wreck.salvaged_value(), _hazards.active_count()
	]
	if not salvage_practice:
		var flight: Dictionary = _ship.api.get_telemetry().flight
		if bool(flight.get("available", false)):
			_readout.text = "WAYFARER / %s\nSUIT %.2f m/s | %.1f deg/s | %s | %s" % [str(flight.reference_name), _player.linear_velocity.length(), rad_to_deg(_player.angular_velocity.length()), brake_hint, capture_hint]
			if _wreck.bodies.is_empty():
				_salvage_status.text = "%s / %.1f km | %.1f m/s relative | %.0f× time" % [str(flight.target.name), float(flight.target.range_m) / 1000.0, float(flight.target.relative_speed_mps), float(flight.warp)]



func _on_capture_started() -> void:
	# Keep the previous capture notice out of the next saved frame.
	_screenshot_notice_seconds = 0.0
	_screenshot_status.visible = false


func _on_capture_finished(path: String, error: Error) -> void:
	_screenshot_status.text = "Saved screenshot: " + path.get_file() if error == OK else "Screenshot failed: " + error_string(error)
	_screenshot_status.modulate = Color(0.4, 0.85, 0.95) if error == OK else Color(1, 0.35, 0.25)
	_screenshot_notice_seconds = 4.0
	_screenshot_status.visible = true


func _add_box(label: String, size: Vector3, at: Vector3, colour: Color) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = label
	body.position = at
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	box.material = material
	mesh.mesh = box
	body.add_child(mesh)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_ship() -> void:
	_ship = preload("res://scenes/player_ship.tscn").instantiate() as PlayerShip
	_ship.name = "PlayerShip"
	_ship.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(8, 0, 4))
	add_child(_ship)
	_ship.set_navigation_target(_wreck.bodies[0] if not _wreck.bodies.is_empty() else null)
	_wreck.structure_changed.connect(_refresh_navigation_target)
	for app: String in ["NAV", "SHIP"]:
		var screen: WorldScreen = preload("res://ui/world_screen.tscn").instantiate() as WorldScreen
		screen.name = app + "Screen"
		screen.configure(_ship.api, app)
		_ship.get_node("NavTerminalMount" if app == "NAV" else "ShipTerminalMount").add_child(screen)
	_player.global_transform = _ship.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 0, 1))
	_cargo = CargoHold.new()
	_cargo.name = "CargoHold"
	add_child(_cargo)
	_cargo.configure(_ship, _wreck, _hazards)
	_interaction = ShipInteraction.new()
	_interaction.name = "ShipInteraction"
	add_child(_interaction)
	_interaction.configure(_player, _ship)


func _refresh_navigation_target() -> void:
	_ship.set_navigation_target(_wreck.bodies[0] if not _wreck.bodies.is_empty() else null)


func _build_contacts() -> void:
	_grip = PhysicalGrip.new()
	_grip.name = "PhysicalGrip"
	_player.add_child(_grip)
	_grip.configure(_player, _player.get_node("Camera3D") as Camera3D)
	_player.brake_reference = _grip.brake_state
	_boots = MagneticBoots.new()
	_boots.name = "MagneticBoots"
	_player.add_child(_boots)
	_boots.configure(_player)
	var contacts: SuitContacts = SuitContacts.new()
	contacts.name = "SuitContacts"
	_player.add_child(contacts)
	contacts.configure(_player, _grip, _boots)
