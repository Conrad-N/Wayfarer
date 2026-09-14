## Pure solar-wing output: tracking, eclipse, distance falloff, health and switch.
## No nodes, no scene tree; SolarArray only takes sim vectors and body dictionaries.
extends TestCase

## Both 2 m x 4 m, 30%-efficient wings, face-on at 1 AU: 2 x 8 x 0.30 x 1361 W.
const FACE_ON_W: float = 6532.8
const CRADLE_RADIUS_M: float = 6.371e6


## Face-on at 1 AU, unshadowed, full health, switched on: rated output within 1%.
func test_face_on_output_at_one_au() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var sun_dir: SimVector = SimVector.new(1.0, 0.0, 0.0)
	var body: Dictionary = {"id": "cradle", "radius": CRADLE_RADIUS_M}
	var r_ship: SimVector = SimVector.new(CRADLE_RADIUS_M + 400000.0, 0.0, 0.0)
	var output: float = SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body)
	check_close(output, FACE_ON_W, 0.01, "face-on at 1 AU is about 6.53 kW total")


## The Sun on the ship's own span (left-right) axis: single-axis tracking loses everything.
func test_sun_along_span_axis_gives_zero() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var body: Dictionary = {"id": "cradle", "radius": CRADLE_RADIUS_M}
	var r_ship: SimVector = SimVector.new(CRADLE_RADIUS_M + 400000.0, 0.0, 0.0)
	check_eq(SolarArray.tracking_factor(span, span), 0.0, "parallel to span is exactly zero tracking")
	check_eq(SolarArray.output_w(span, SimConstants.AU, span, r_ship, body), 0.0, "sun abeam gives zero output")


## Any Sun direction with no span-axis component (nose, belly, tail, top) tracks to full output.
func test_sun_off_the_beam_is_full_output() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var directions: Array[SimVector] = [SimVector.new(1.0, 0.0, 0.0), SimVector.new(0.0, 1.0, 0.0), SimVector.new(-1.0, 0.0, 0.0), SimVector.new(0.6, 0.8, 0.0)]
	for sun_dir: SimVector in directions:
		check_close(SolarArray.tracking_factor(sun_dir, span), 1.0, 1e-9, "no span component tracks to full output")


## Directly behind the body from the Sun, inside its cylindrical shadow: no output.
func test_eclipse_blocks_output() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var sun_dir: SimVector = SimVector.new(1.0, 0.0, 0.0)
	var body: Dictionary = {"id": "cradle", "radius": CRADLE_RADIUS_M}
	var r_ship: SimVector = SimVector.new(-(CRADLE_RADIUS_M + 400000.0), 0.0, 0.0)
	check(SolarArray.shadowed(r_ship, sun_dir, body), "directly behind the body is shadowed")
	check_eq(SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body), 0.0, "eclipse output is exactly zero")


## A star never shadows its own satellites, whatever the geometry.
func test_star_never_shadows_itself() -> void:
	var sol_body: Dictionary = {"id": "sol", "radius": 6.957e8}
	check(not SolarArray.shadowed(SimVector.new(-1.0, 0.0, 0.0), SimVector.new(1.0, 0.0, 0.0), sol_body), "the star cannot eclipse itself")


## Just past the shadow cylinder's radius, the ship is fully lit again.
func test_just_outside_shadow_edge_is_full_output() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var sun_dir: SimVector = SimVector.new(1.0, 0.0, 0.0)
	var body: Dictionary = {"id": "cradle", "radius": CRADLE_RADIUS_M}
	var r_ship: SimVector = SimVector.new(-400000.0, CRADLE_RADIUS_M + 1.0, 0.0)
	check(not SolarArray.shadowed(r_ship, sun_dir, body), "a metre past the shadow radius is lit")
	check_close(SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body), FACE_ON_W, 0.01, "just outside the shadow is full output")


## Half-damaged cells halve output; a disabled or zero-health array delivers nothing.
func test_health_and_switch_scale_output() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var sun_dir: SimVector = SimVector.new(1.0, 0.0, 0.0)
	var body: Dictionary = {"id": "cradle", "radius": CRADLE_RADIUS_M}
	var r_ship: SimVector = SimVector.new(CRADLE_RADIUS_M + 400000.0, 0.0, 0.0)
	var full: float = SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body)
	check_close(SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body, 0.5, true), full * 0.5, 0.0001, "half health halves output")
	check_eq(SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body, 1.0, false), 0.0, "a disabled array delivers nothing")
	check_eq(SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body, 0.0, true), 0.0, "zero health delivers nothing")


## Irradiance falls off with the square of distance: 0.8 AU is 1/0.64 of the 1 AU output.
func test_distance_falloff_at_point_eight_au() -> void:
	var span: SimVector = SimVector.new(0.0, 0.0, 1.0)
	var sun_dir: SimVector = SimVector.new(1.0, 0.0, 0.0)
	var body: Dictionary = {"id": "vesper", "radius": 3.3895e6}
	var r_ship: SimVector = SimVector.new(float(body.radius) + 400000.0, 0.0, 0.0)
	var full: float = SolarArray.output_w(sun_dir, SimConstants.AU, span, r_ship, body)
	var closer: float = SolarArray.output_w(sun_dir, 0.8 * SimConstants.AU, span, r_ship, body)
	check_close(closer, full / 0.64, 0.001, "0.8 AU delivers 1/0.64 of the face-on 1 AU output")


## The hull's sideways +X axis maps onto the sim body's span axis (sim +Z); at rest
## attitude the mapping is unrotated.
func test_span_axis_maps_hull_sideways_axis() -> void:
	var identity: Dictionary = {"w": 1.0, "x": 0.0, "y": 0.0, "z": 0.0}
	var axis: SimVector = SolarArray.span_axis(identity)
	check_near(axis.x, 0.0, 1e-9, "span axis has no thrust-axis component at rest")
	check_near(axis.y, 0.0, 1e-9, "span axis has no vertical component at rest")
	check_near(axis.z, 1.0, 1e-9, "hull sideways +X maps onto sim body +Z")


## Without a star in the hierarchy (the game's live Cradle session), the bearing
## falls back to a fixed Sun at 1 AU along +X.
func test_sun_bearing_falls_back_without_a_star() -> void:
	var cradle_only: OrbitalSystem = OrbitalSystem.new([{"id": "cradle", "name": "Cradle", "mu": 3.986004418e14, "radius": CRADLE_RADIUS_M, "parent_id": null}])
	var bearing: Dictionary = SolarArray.sun_bearing(cradle_only, SimVector.new(1000.0, 0.0, 0.0), 0.0)
	var direction: SimVector = bearing.direction
	check_eq(Vector3(direction.x, direction.y, direction.z), Vector3(1.0, 0.0, 0.0), "fixed +X bearing when no star exists")
	check_eq(bearing.distance_m, SimConstants.AU, "fixed 1 AU distance when no star exists")


## With a real star in the hierarchy, the bearing points at the actual Sun.
func test_sun_bearing_uses_the_real_star_when_present() -> void:
	var system: OrbitalSystem = SimConstants.default_system()
	var bearing: Dictionary = SolarArray.sun_bearing(system, SimVector.new(SimConstants.AU, 0.0, 0.0), 0.0)
	check_near(bearing.direction.x, -1.0, 1e-9, "Sol sits at the hierarchy origin, so the bearing points back at it")
	check_near(bearing.distance_m, SimConstants.AU, 1.0, "distance matches the ship's offset from Sol")
