## Pure model of the ship's two sun-tracking solar wings, in scalar-double sim units.
## Callers supply the Sun bearing, the ship's central-body-relative position, the
## hull span axis and the `solar` system's health and switch state; nothing here
## touches nodes, the scene tree, or the ship API.
class_name SolarArray
extends RefCounted

## Solar irradiance at 1 AU [W/m²].
const IRRADIANCE_AT_AU_WM2: float = 1361.0
## Each wing is 2 m along the hull by 4 m outward.
const PANEL_AREA_M2: float = 8.0
const PANEL_COUNT: int = 2
const CELL_EFFICIENCY: float = 0.30
## Body identifier treated as the star.
const SUN_ID: String = "sol"


## Hull span axis (the ship's left-right axis) in world sim coordinates.
## LocalOrbitFrame.GODOT_TO_SIM_BODY maps the hull's sideways +X onto sim body
## +Z (the thrust axis is sim +X); only the squared dot product with the Sun
## direction is used, so the sign of the axis does not matter.
static func span_axis(orientation: Dictionary) -> SimVector:
	return FlightMath.rotate(FlightMath.q_normalize(orientation), SimVector.new(0.0, 0.0, 1.0))


## Unit Sun bearing and distance [m] in the hierarchy's root frame. Hierarchies
## without the star use the fixed 1 AU bearing along +X (the Cradle session).
static func sun_bearing(system: OrbitalSystem, ship_position_root: SimVector, at_time: float) -> Dictionary:
	if system != null and system.has(SUN_ID):
		var sun: Dictionary = system.body_state_in_root(SUN_ID, at_time)
		if not sun.is_empty():
			var relative: SimVector = SimVector.sub(sun.position, ship_position_root)
			var distance: float = SimVector.length(relative)
			if is_finite(distance) and distance > 0.0:
				return {"direction": SimVector.scale(relative, 1.0 / distance), "distance_m": distance}
	return flat_sun_bearing()


## Fixed root-frame bearing used when no star exists: 1 AU along +X.
static func flat_sun_bearing() -> Dictionary:
	return {"direction": SimVector.new(1.0, 0.0, 0.0), "distance_m": SimConstants.AU}


## Whether the central body's cylindrical shadow covers the ship. The star
## never shadows its own satellites. `sun_dir` must be a unit vector.
static func shadowed(r_ship: SimVector, sun_dir: SimVector, body: Dictionary, sun_id: String = SUN_ID) -> bool:
	if str(body.get("id", "")) == sun_id:
		return false
	var radius: float = float(body.get("radius", 0.0))
	if not is_finite(radius) or radius <= 0.0 or not SimVector.is_finite_vector(r_ship) or not SimVector.is_finite_vector(sun_dir):
		return false
	var along: float = SimVector.dot(r_ship, sun_dir)
	if along >= 0.0:
		return false
	var perpendicular: float = sqrt(maxf(0.0, SimVector.dot(r_ship, r_ship) - along * along))
	return perpendicular < radius


## Total wing output [W]: both panels with tracking, eclipse, distance, health
## and the system switch applied. Face-on at 1 AU this is 6532.8 W.
static func output_w(sun_dir: SimVector, sun_distance_m: float, span: SimVector, r_ship: SimVector, body: Dictionary, health: float = 1.0, enabled: bool = true) -> float:
	if not enabled or not is_finite(health) or health <= 0.0:
		return 0.0
	if shadowed(r_ship, sun_dir, body):
		return 0.0
	var factor: float = tracking_factor(sun_dir, span)
	if factor <= 0.0:
		return 0.0
	var irradiance: float = IRRADIANCE_AT_AU_WM2 * pow(SimConstants.AU / maxf(sun_distance_m, 1.0), 2.0)
	if not is_finite(irradiance) or irradiance <= 0.0:
		return 0.0
	return float(PANEL_COUNT) * PANEL_AREA_M2 * CELL_EFFICIENCY * irradiance * factor * clampf(health, 0.0, 1.0)


## Fraction of full output the single-axis tracking can reach: the wings tilt
## about the span axis, so only the Sun's angle to that axis is lost.
static func tracking_factor(sun_dir: SimVector, span: SimVector) -> float:
	if not SimVector.is_finite_vector(sun_dir) or not SimVector.is_finite_vector(span):
		return 0.0
	var span_length: float = SimVector.length(span)
	var sun_length: float = SimVector.length(sun_dir)
	if span_length <= 0.0 or sun_length <= 0.0:
		return 0.0
	var parallel: float = SimVector.dot(sun_dir, span) / (sun_length * span_length)
	return sqrt(clampf(1.0 - parallel * parallel, 0.0, 1.0))
