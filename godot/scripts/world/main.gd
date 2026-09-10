## M1 debris room. Fixed walls and coloured ribs make drift and free roll visible.
extends Node3D

@onready var _player: Player = $Player
@onready var _readout: Label = $HUD/Readout
@onready var _supplies: Label = $HUD/Supplies
@onready var _supply_warning: Label = $HUD/SupplyWarning
@onready var _grapple_status: Label = $HUD/GrappleStatus
@onready var _screenshot_status: Label = $HUD/ScreenshotStatus
@onready var _screenshot: DebugScreenshot = $DebugScreenshot

var _screenshot_notice_seconds: float = 0.0


func _ready() -> void:
	_screenshot.capture_started.connect(_on_capture_started)
	_screenshot.capture_finished.connect(_on_capture_finished)
	var wall: Color = Color(0.12, 0.16, 0.20)
	var deck: Color = Color(0.22, 0.26, 0.29)
	var amber: Color = Color(0.85, 0.48, 0.12)
	var cyan: Color = Color(0.13, 0.58, 0.65)
	_add_box("Deck", Vector3(24, 0.5, 30), Vector3(0, -7.25, 0), deck)
	_add_box("Ceiling", Vector3(24, 0.5, 30), Vector3(0, 7.25, 0), wall)
	_add_box("Port", Vector3(0.5, 14, 30), Vector3(-12.25, 0, 0), wall)
	_add_box("Starboard", Vector3(0.5, 14, 30), Vector3(12.25, 0, 0), wall)
	_add_box("Forward", Vector3(24, 14, 0.5), Vector3(0, 0, -15.25), wall)
	_add_box("Aft", Vector3(24, 14, 0.5), Vector3(0, 0, 15.25), wall)
	for z: int in range(-12, 15, 6):
		_add_box("DeckStripe", Vector3(24, 0.04, 0.12), Vector3(0, -6.98, z), amber)
		_add_box("PortRib", Vector3(0.15, 14, 0.15), Vector3(-11.95, 0, z), amber)
		_add_box("StarboardRib", Vector3(0.15, 14, 0.15), Vector3(11.95, 0, z), cyan)
	_add_box("ForwardMarker", Vector3(5, 0.25, 0.15), Vector3(0, 1.8, -14.95), cyan)
	_add_box("ForwardMarker", Vector3(0.25, 3.5, 0.15), Vector3(0, 0.2, -14.95), cyan)
	print("Wayfarer M1: debris, suit RCS, and grapple. Escape releases mouse.")


func _process(delta: float) -> void:
	_screenshot_notice_seconds = maxf(0.0, _screenshot_notice_seconds - delta)
	_screenshot_status.visible = _screenshot_notice_seconds > 0.0
	var capture_hint: String = "Esc releases mouse" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "Click to fly"
	var brake_hint: String = "RCS BRAKE" if _player.is_braking() else "FREE FLIGHT"
	if _player.suit.propellant_kg <= 0.0:
		brake_hint = "RCS EMPTY"
	_readout.text = "WAYFARER / DEBRIS ROOM\n%.2f m/s  |  %.1f deg/s  |  %s  |  %s" % [
		_player.linear_velocity.length(), rad_to_deg(_player.angular_velocity.length()),
		brake_hint, capture_hint
	]
	_supplies.text = "PROPELLANT  %.3f kg / %.1f kg  |  BATTERY  %.1f Wh / %.0f Wh" % [
		_player.suit.propellant_kg, SuitResources.PROPELLANT_CAPACITY_KG,
		_player.suit.battery_energy_j / 3600.0, SuitResources.BATTERY_CAPACITY_J / 3600.0
	]
	var warnings: PackedStringArray = []
	if _player.suit.propellant_kg <= 0.0:
		warnings.append("PROPELLANT EMPTY: thrust and brake unavailable")
	elif _player.suit.propellant_kg <= SuitResources.PROPELLANT_CAPACITY_KG * 0.1:
		warnings.append("LOW PROPELLANT")
	if _player.suit.battery_energy_j <= 0.0:
		warnings.append("BATTERY EMPTY: no tool power")
	elif _player.suit.battery_energy_j <= SuitResources.BATTERY_CAPACITY_J * 0.1:
		warnings.append("LOW BATTERY")
	_supply_warning.text = "  |  ".join(warnings)
	_grapple_status.text = "GRAPPLE / " + _player.grapple.status
	if _player.grapple.is_attached():
		_grapple_status.text += "  |  CABLE %.1f m" % _player.grapple.cable_length_m


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
