## Orbit scope and attitude instrument drawing from ShipApi snapshots only.
class_name OrbitDisplay
extends Control

const CYAN: Color = Color("74dbe1")
const AMBER: Color = Color("efbd72")
const MUTED: Color = Color("536b78")
var display_kind: String = "scope"
var _flight: Dictionary = {}
var _extent: float = 1.0


## Supply a display snapshot; simulation state stays behind the ship API.
func set_flight(flight: Dictionary) -> void:
	_flight = flight.duplicate(true)
	_extent = _calculate_extent()
	queue_redraw()


## Project a scalar-double orbital point after scaling it down to the display bounds.
func project_scope(point: PackedFloat64Array) -> Vector2:
	if point.size() < 2 or not is_finite(point[0]) or not is_finite(point[1]):
		return size * 0.5
	var radius: float = _extent
	var pixels: float = maxf(1.0, minf(size.x, size.y) * 0.44)
	return size * 0.5 + Vector2(float(point[0]) / radius, -float(point[1]) / radius) * pixels


func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	if not bool(_flight.get("available", false)):
		_text(Vector2(12, size.y * 0.5), "NO ORBITAL SOLUTION", MUTED, 13)
		return
	if display_kind == "navball":
		_draw_navball()
	else:
		_draw_scope()


func _draw_scope() -> void:
	var scope: Dictionary = _flight.get("scope", {})
	var center: Vector2 = size * 0.5
	for fraction: float in [0.25, 0.5, 0.75]:
		draw_line(Vector2(size.x * fraction, 8), Vector2(size.x * fraction, size.y - 8), Color("192d38"))
		draw_line(Vector2(8, size.y * fraction), Vector2(size.x - 8, size.y * fraction), Color("192d38"))
	var radius: float = maxf(0.0, float(scope.get("radius_m", _flight.get("body_radius_m", 0.0))))
	var body_pixels: float = radius / _extent * minf(size.x, size.y) * 0.44
	draw_circle(center, maxf(2.0, body_pixels), Color("263e49"))
	draw_arc(center, maxf(2.0, body_pixels), 0, TAU, 64, MUTED, 1.0, true)
	_draw_path(scope.get("target_path", []), AMBER.darkened(0.3))
	_draw_path(scope.get("ship_path", []), CYAN)
	var ship_point: PackedFloat64Array = scope.get("ship_position", PackedFloat64Array())
	var target_point: PackedFloat64Array = scope.get("target_position", PackedFloat64Array())
	if ship_point.size() >= 2:
		var position_px: Vector2 = project_scope(ship_point)
		draw_colored_polygon(PackedVector2Array([position_px + Vector2(0, -5), position_px + Vector2(-4, 4), position_px + Vector2(4, 4)]), CYAN)
	if target_point.size() >= 2:
		draw_arc(project_scope(target_point), 5.0, 0, TAU, 16, AMBER, 2.0, true)
	_text(Vector2(9, 17), str(_flight.get("body_name", "ORBIT")).to_upper(), MUTED, 12)
	_text(Vector2(9, size.y - 8), "SHIP  /  TARGET", CYAN, 12)


func _draw_navball() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.40
	draw_circle(center, radius, Color("203848"))
	draw_arc(center, radius, 0, TAU, 64, MUTED, 2.0, true)
	draw_arc(center, radius * 0.5, 0, TAU, 48, Color("355061"), 1.0, true)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), MUTED, 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), MUTED, 1.0)
	var markers: Dictionary = _flight.get("navball", {})
	for key: String in ["prograde", "normal", "radial", "target"]:
		var direction: Vector3 = markers.get(key, Vector3.ZERO)
		if not direction.is_finite() or direction.length_squared() < 0.001:
			continue
		direction = direction.normalized()
		var pixel: Vector2 = center + Vector2(direction.x, -direction.y) * radius
		var color: Color = AMBER if key == "target" else CYAN
		if direction.z > 0.0:
			color = color.darkened(0.55)
			draw_arc(pixel, 5, 0, TAU, 16, color, 1.0, true)
		else:
			draw_circle(pixel, 4, color)
		_text(pixel + Vector2(6, -4), key.left(1).to_upper(), color, 12)
	draw_line(center + Vector2(-13, 0), center + Vector2(-5, 0), AMBER, 2.0)
	draw_line(center + Vector2(5, 0), center + Vector2(13, 0), AMBER, 2.0)
	draw_line(center + Vector2(0, 5), center + Vector2(0, 10), AMBER, 2.0)
	_text(Vector2(8, 15), "ATTITUDE", MUTED, 12)
	_text(Vector2(8, size.y - 5), "DIM = BEHIND", MUTED, 10)


func _draw_path(path: Array, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for point: PackedFloat64Array in path:
		if point.size() >= 2 and is_finite(point[0]) and is_finite(point[1]):
			points.append(project_scope(point))
	if points.size() >= 2:
		draw_polyline(points, color, 1.5, true)


func _calculate_extent() -> float:
	var scope: Dictionary = _flight.get("scope", {})
	var largest: float = maxf(1.0, float(scope.get("radius_m", 1.0)))
	for key: String in ["ship_path", "target_path"]:
		for point: PackedFloat64Array in scope.get(key, []):
			if point.size() >= 2 and is_finite(point[0]) and is_finite(point[1]):
				largest = maxf(largest, sqrt(point[0] * point[0] + point[1] * point[1]))
	for key: String in ["ship_position", "target_position"]:
		var point: PackedFloat64Array = scope.get(key, PackedFloat64Array())
		if point.size() >= 2 and is_finite(point[0]) and is_finite(point[1]):
			largest = maxf(largest, sqrt(point[0] * point[0] + point[1] * point[1]))
	return largest


func _background() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("0b161d")
	style.border_color = Color("29424d")
	style.set_border_width_all(1)
	return style


func _text(at: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string(get_theme_default_font(), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
