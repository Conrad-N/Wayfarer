## M1 movement space. Fixed walls and coloured ribs make drift and free roll visible.
extends Node3D

@onready var _player: Player = $Player
@onready var _readout: Label = $HUD/Readout


func _ready() -> void:
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
	_add_box("ReferenceBlock", Vector3(2, 2, 2), Vector3(3, -3, -5), amber)
	print("Wayfarer M1: free thrust, roll and mouse look. Escape releases mouse.")


func _process(_delta: float) -> void:
	var capture_hint: String = "Esc releases mouse" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "Click to fly"
	var brake_hint: String = "RCS BRAKE" if _player.is_braking() else "FREE FLIGHT"
	_readout.text = "WAYFARER / SUIT MOVEMENT TEST\n%.2f m/s  |  %.1f deg/s  |  %s  |  %s" % [
		_player.linear_velocity.length(), rad_to_deg(_player.angular_velocity.length()),
		brake_hint, capture_hint
	]


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
