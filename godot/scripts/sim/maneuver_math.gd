## State-to-conic conversion, rocket-equation budgets, and deterministic forward maneuver previews.
class_name ManeuverMath
extends RefCounted


## Recover classical elements from a nonradial inertial state, including circular and retrograde degeneracies.
## Exactly parabolic or invalid states return an empty dictionary rather than poisoning the simulation.
static func state_to_elements(position: SimVector, velocity: SimVector, body: Dictionary, epoch: float) -> Dictionary:
	var mu: float = body.get("mu", 0.0)
	if not SimVector.is_finite_vector(position) or not SimVector.is_finite_vector(velocity) or not is_finite(mu) or mu <= 0.0 or not is_finite(epoch):
		return {}
	var radius: float = SimVector.length(position)
	var speed: float = SimVector.length(velocity)
	var h: SimVector = SimVector.cross(position, velocity)
	var h_mag: float = SimVector.length(h)
	if radius <= 0.0 or h_mag <= 0.0:
		return {}
	var node: SimVector = SimVector.new(-h.y, h.x, 0.0)
	var node_mag: float = SimVector.length(node)
	var e_vector: SimVector = SimVector.scale(SimVector.sub(SimVector.scale(position, speed * speed - mu / radius), SimVector.scale(velocity, SimVector.dot(position, velocity))), 1.0 / mu)
	var e: float = SimVector.length(e_vector)
	var energy: float = speed * speed / 2.0 - mu / radius
	if energy == 0.0 or e == 1.0:
		return {}
	var a: float = -mu / (2.0 * energy)
	var inclination: float = atan2(sqrt(h.x * h.x + h.y * h.y), h.z)
	var raan: float = fposmod(atan2(node.y, node.x), TAU) if node_mag > 1e-9 else 0.0
	var argp: float = 0.0
	var nu: float
	if e > 1e-9:
		argp = _oriented_angle(node, e_vector, h) if node_mag > 1e-9 else fposmod(atan2(e_vector.y, e_vector.x) * signf(h.z), TAU)
		nu = _oriented_angle(e_vector, position, h)
	elif node_mag > 1e-9:
		nu = _oriented_angle(node, position, h)
	else:
		nu = fposmod(atan2(position.y, position.x) * signf(h.z), TAU)
	var mean_anomaly: float
	if e < 1.0:
		var eccentric: float = 2.0 * atan2(sqrt(1.0 - e) * sin(nu / 2.0), sqrt(1.0 + e) * cos(nu / 2.0))
		mean_anomaly = fposmod(eccentric - e * sin(eccentric), TAU)
	else:
		var hyper: float = 2.0 * OrbitMath.atanh_scalar(sqrt((e - 1.0) / (e + 1.0)) * tan(nu / 2.0))
		mean_anomaly = e * sinh(hyper) - hyper
	var result: Dictionary = {"a": a, "e": e, "i": inclination, "raan": raan, "argp": argp, "mean_anomaly_at_epoch": mean_anomaly, "epoch": epoch}
	return result if OrbitMath.valid_elements(result, body) else {}


## Available delta-v from propellant and the total mass that remains after burnout, including cargo.
static func dv_budget(propellant_kg: float, dry_mass_kg: float, isp_seconds: float) -> float:
	if not is_finite(propellant_kg) or not is_finite(dry_mass_kg) or not is_finite(isp_seconds) or propellant_kg < 0.0 or dry_mass_kg <= 0.0 or isp_seconds <= 0.0:
		return 0.0
	return isp_seconds * FlightMath.G0 * log((dry_mass_kg + propellant_kg) / dry_mass_kg)


## Propellant required for the magnitude of a delta-v at a given starting total mass.
static func propellant_for_dv(mass_kg: float, dv: float, isp_seconds: float) -> float:
	if not is_finite(mass_kg) or not is_finite(dv) or not is_finite(isp_seconds) or mass_kg <= 0.0 or isp_seconds <= 0.0:
		return INF
	return mass_kg * (1.0 - exp(-absf(dv) / (isp_seconds * FlightMath.G0)))


## Coast to time t and apply one instantaneous local-frame delta-v for planning.
static func apply_burn(el: Dictionary, body: Dictionary, t: float, dv: Dictionary) -> Dictionary:
	var state: Dictionary = OrbitMath.propagate(el, body, t)
	if state.is_empty() or not _valid_dv(dv):
		return {}
	var world_dv: SimVector = FlightMath.local_dv_to_world(dv, state.position, state.velocity)
	return state_to_elements(state.position, SimVector.add(state.velocity, world_dv), body, t)


## Preview one burn with fuel affordability, before/after orbit, and an actionable failure note.
static func preview_node(el: Dictionary, body: Dictionary, fuel: Dictionary, input: Dictionary) -> Dictionary:
	var dv: Dictionary = input.get("dv_local", {})
	var time: float = input.get("time", NAN)
	var valid: bool = _valid_fuel(fuel) and _valid_dv(dv) and is_finite(time) and OrbitMath.valid_elements(el, body)
	if not valid:
		return {"feasible": false, "note": "Invalid orbit, fuel or maneuver input."}
	var magnitude: float = FlightMath.dv_magnitude(dv)
	var mass: float = float(fuel.dry_mass_kg) + float(fuel.propellant_kg)
	var budget: float = dv_budget(fuel.propellant_kg, fuel.dry_mass_kg, fuel.isp_seconds)
	var propellant: float = propellant_for_dv(mass, magnitude, fuel.isp_seconds)
	var affordable: bool = propellant <= float(fuel.propellant_kg) + 1e-6
	var before: Dictionary = OrbitMath.propagate(el, body, time)
	var after: Dictionary = OrbitMath.propagate(apply_burn(el, body, time, dv), body, time)
	var feasible: bool = magnitude > 0.0 and affordable and not after.is_empty()
	var note: String = ""
	if magnitude == 0.0:
		note = "No delta-v: set a prograde, normal or radial component."
	elif not affordable:
		note = "Needs %.0f kg but only %.0f kg aboard (delta-v budget %.0f m/s)." % [propellant, fuel.propellant_kg, budget]
	elif after.is_empty():
		note = "The resulting radial or exactly parabolic trajectory cannot be represented as a conic."
	return {"time": time, "dv_local": dv.duplicate(), "dv_mag": magnitude, "propellant_kg": propellant, "mass_before_kg": mass, "feasible": feasible, "dv_budget_before": budget, "dv_budget_after": dv_budget(maxf(0.0, float(fuel.propellant_kg) - propellant), fuel.dry_mass_kg, fuel.isp_seconds) if feasible else 0.0, "before": before, "after": after, "note": note}


## Chain an ordered maneuver sequence, threading mass through every burn and analytic coast.
static func build_plan(el: Dictionary, body: Dictionary, fuel: Dictionary, label: String, nodes: Array[Dictionary]) -> Dictionary:
	var budget: float = dv_budget(fuel.get("propellant_kg", 0.0), fuel.get("dry_mass_kg", 0.0), fuel.get("isp_seconds", 0.0))
	var current: Dictionary = el.duplicate()
	var mass: float = float(fuel.get("dry_mass_kg", 0.0)) + float(fuel.get("propellant_kg", 0.0))
	var prop_left: float = fuel.get("propellant_kg", 0.0)
	var total_dv: float = 0.0
	var total_prop: float = 0.0
	var affordable: bool = true
	var valid: bool = _valid_fuel(fuel) and OrbitMath.valid_elements(el, body)
	var burns: Array[Dictionary] = []
	var after: Dictionary = OrbitMath.propagate(el, body, float(nodes[0].get("time", 0.0)) if not nodes.is_empty() else 0.0)
	var previous_time: float = -INF
	for node: Dictionary in nodes:
		var time: float = node.get("time", NAN)
		var dv: Dictionary = node.get("dv_local", {})
		if not valid or not is_finite(time) or time < previous_time or not _valid_dv(dv):
			valid = false
			break
		previous_time = time
		var magnitude: float = FlightMath.dv_magnitude(dv)
		var propellant: float = propellant_for_dv(mass, magnitude, fuel.isp_seconds)
		if propellant > prop_left + 1e-6:
			affordable = false
		burns.append({"time": time, "dv_local": dv.duplicate(), "dv_mag": magnitude, "propellant_kg": propellant, "live": node.has("retarget") and node.retarget != null})
		total_dv += magnitude
		total_prop += propellant
		current = apply_burn(current, body, time, dv)
		after = OrbitMath.propagate(current, body, time)
		if after.is_empty():
			valid = false
			break
		mass -= propellant
		prop_left -= propellant
	var feasible: bool = total_dv > 1e-3 and affordable and valid
	var note: String = ""
	if not valid:
		note = "Invalid orbit, fuel or maneuver sequence; node times must be ordered."
	elif total_dv <= 1e-3:
		note = "No delta-v: nothing to do."
	elif not affordable:
		note = "Needs %.0f kg but only %.0f kg aboard (delta-v budget %.0f m/s)." % [total_prop, fuel.propellant_kg, budget]
	return {"label": label, "nodes": nodes.duplicate(true), "burns": burns, "dv_mag": total_dv, "propellant_kg": total_prop, "feasible": feasible, "dv_budget_before": budget, "dv_budget_after": dv_budget(maxf(0.0, prop_left), fuel.dry_mass_kg, fuel.isp_seconds) if feasible else 0.0, "after": after, "note": note}


static func _oriented_angle(a: SimVector, b: SimVector, normal: SimVector) -> float:
	return fposmod(atan2(SimVector.dot(SimVector.cross(a, b), normal) / SimVector.length(normal), SimVector.dot(a, b)), TAU)


static func _valid_dv(dv: Dictionary) -> bool:
	for key: String in ["prograde", "normal", "radial"]:
		if not is_finite(float(dv.get(key, 0.0))):
			return false
	return true


static func _valid_fuel(fuel: Dictionary) -> bool:
	return float(fuel.get("dry_mass_kg", 0.0)) > 0.0 and float(fuel.get("propellant_kg", -1.0)) >= 0.0 and float(fuel.get("isp_seconds", 0.0)) > 0.0 and is_finite(float(fuel.get("dry_mass_kg", NAN))) and is_finite(float(fuel.get("propellant_kg", NAN))) and is_finite(float(fuel.get("isp_seconds", NAN)))
