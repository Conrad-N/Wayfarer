## A physical screen with one shared app viewport and world-space pointer mapping.
class_name WorldScreen
extends Node3D

const SIZE_M: Vector2 = Vector2(1.6, 1.0)
const PIXELS: Vector2 = Vector2(640.0, 400.0)

@export var render_on_top: bool = false:
	set(enabled):
		render_on_top = enabled
		if is_node_ready():
			_update_render_order()

var api: ShipApi
var uses_ship_power: bool = true
var panel: ShipPanel:
	get:
		return get_node("SubViewport/ShipPanel") as ShipPanel
var _initial_app: String = "SHIP"


func _ready() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = get_viewport_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	($Display as MeshInstance3D).material_override = material
	var frame: MeshInstance3D = $Frame
	# The shared scene material must not change the ship's fixed terminals.
	frame.material_override = frame.material_override.duplicate() as Material
	_update_render_order()
	panel.configure(api, _initial_app)
	_update_power()


func _process(_delta: float) -> void:
	_update_power()


## Share one ship connection; a handheld screen has its own power supply.
func configure(ship_api: ShipApi, initial_app: String = "SHIP", ship_power: bool = true) -> void:
	api = ship_api
	_initial_app = initial_app
	uses_ship_power = ship_power
	if is_node_ready():
		panel.configure(api, initial_app)
		_update_power()


## A fixed terminal stops accepting input when the ship loses power.
func is_available() -> bool:
	return api != null and (not uses_ship_power or bool(api.get_telemetry().get("power_available", false)))


## Convert a front-face hit to viewport pixels, including rotation and scaling.
func world_to_pixel(point: Vector3) -> Vector2:
	var local: Vector3 = to_local(point)
	return Vector2((local.x / SIZE_M.x + 0.5) * PIXELS.x, (0.5 - local.y / SIZE_M.y) * PIXELS.y)


## Forward a copied event so the host viewport retains its original coordinates.
func forward_input(event: InputEvent, world_point: Vector3) -> void:
	if not is_available():
		return
	var forwarded: InputEvent = event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		var pixel: Vector2 = world_to_pixel(world_point)
		# Outside releases must reach the GUI to cancel a press dragged off screen.
		if not Rect2(Vector2.ZERO, PIXELS).has_point(pixel) and forwarded is InputEventMouseButton and (forwarded as InputEventMouseButton).pressed:
			return
		var mouse: InputEventMouse = forwarded as InputEventMouse
		mouse.position = pixel
		mouse.global_position = pixel
		if mouse is InputEventMouseButton:
			# A docked camera can move between button events without host mouse motion.
			# Refresh hover first so releasing beyond the edge cannot activate a button.
			var pointer: InputEventMouseMotion = InputEventMouseMotion.new()
			pointer.position = pixel
			pointer.global_position = pixel
			pointer.button_mask = mouse.button_mask
			($SubViewport as SubViewport).push_input(pointer, true)
		if mouse is InputEventMouseMotion:
			# Absolute position determines GUI hover; host motion is not screen-local.
			(mouse as InputEventMouseMotion).relative = Vector2.ZERO
	($SubViewport as SubViewport).push_input(forwarded, true)


## Access the screen image for the mesh material and windowed capture checks.
func get_viewport_texture() -> ViewportTexture:
	return ($SubViewport as SubViewport).get_texture()


func _update_power() -> void:
	($Display as MeshInstance3D).visible = is_available()


func _update_render_order() -> void:
	for part: String in ["Frame", "Display"]:
		var material: BaseMaterial3D = (get_node(part) as MeshInstance3D).material_override as BaseMaterial3D
		material.no_depth_test = render_on_top
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED if render_on_top else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		# Alpha rendering places even fully opaque tablet pixels after world geometry.
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if render_on_top else BaseMaterial3D.TRANSPARENCY_DISABLED
		material.render_priority = (127 if part == "Display" else 126) if render_on_top else 0
