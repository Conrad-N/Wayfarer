## Legacy reference-system constants and constructors, all in SI units.
class_name SimConstants
extends RefCounted

const TWO_PI: float = TAU
const AU: float = 1.495978707e11


## Degrees to radians for readable scenario definitions.
static func deg(degrees: float) -> float:
	return degrees * PI / 180.0


## Independent Sol reference definition.
static func sol() -> Dictionary:
	return {"id": "sol", "name": "Sol", "mu": 1.32712440018e20, "radius": 6.957e8, "rotation_period": null, "parent_id": null, "elements": null, "soi_radius": null}


## Independent Earth-like Cradle reference definition.
static func cradle() -> Dictionary:
	return {"id": "cradle", "name": "Cradle", "mu": 3.986004418e14, "radius": 6.371e6, "rotation_period": null, "parent_id": "sol", "elements": _body_orbit(AU, 0.0), "soi_radius": OrbitalSystem.soi_radius(AU, 3.986004418e14, 1.32712440018e20)}


## Independent inner Mars-like Vesper reference definition.
static func vesper() -> Dictionary:
	return {"id": "vesper", "name": "Vesper", "mu": 4.282837e13, "radius": 3.3895e6, "rotation_period": null, "parent_id": "sol", "elements": _body_orbit(0.8 * AU, deg(40.0)), "soi_radius": OrbitalSystem.soi_radius(0.8 * AU, 4.282837e13, 1.32712440018e20)}


## Fresh legacy hierarchy used for numerical parity and interplanetary tests.
static func default_system() -> OrbitalSystem:
	return OrbitalSystem.new([sol(), cradle(), vesper()])


## Circular parking orbit at an altitude in metres and inclination in radians.
static func circular_orbit(body: Dictionary, altitude: float, inclination: float = 0.0) -> Dictionary:
	var elements: Dictionary = _body_orbit(float(body.get("radius", 0.0)) + altitude, 0.0)
	elements.i = inclination
	return elements


static func _body_orbit(a: float, anomaly: float) -> Dictionary:
	return {"a": a, "e": 0.0, "i": 0.0, "raan": 0.0, "argp": 0.0, "mean_anomaly_at_epoch": anomaly, "epoch": 0.0}
