## Sim autoload: owns the pure orbital world and persistent encounter records.
class_name OrbitalSession
extends Node

var world: OrbitalWorld
var encounters: Dictionary = {}
var objects: Dictionary = {}


## Start the M4 planet/moon scenario; the legacy system remains available to parity tests.
func start_session() -> void:
	world = OrbitalWorld.new()
	var planet: Dictionary = SimConstants.cradle()
	planet.parent_id = null
	planet.elements = null
	planet.soi_radius = null
	var moon: Dictionary = {"id": "lune", "name": "Lune", "mu": 4.9048695e12,
		"radius": 1737400.0, "rotation_period": null, "parent_id": "cradle",
		"elements": {"a": 384400000.0, "e": 0.0, "i": deg_to_rad(5.145), "raan": 0.0,
			"argp": 0.0, "mean_anomaly_at_epoch": PI / 2.0, "epoch": 0.0},
		"soi_radius": OrbitalSystem.soi_radius(384400000.0, 4.9048695e12, 3.986004418e14)}
	world.system = OrbitalSystem.new([planet, moon])
	world.central_body_id = "cradle"
	world.ship.elements = SimConstants.circular_orbit(planet, 400000.0, deg_to_rad(51.6))
	var station_orbit: Dictionary = world.ship.elements.duplicate(true)
	station_orbit.mean_anomaly_at_epoch = -0.0045
	var wreck_orbit: Dictionary = SimConstants.circular_orbit(planet, 450000.0, deg_to_rad(51.6))
	wreck_orbit.mean_anomaly_at_epoch = deg_to_rad(20.0)
	world.targets = [
		{"id": "lowline", "name": "Lowline Yard", "kind": "station", "body_id": "cradle", "elements": station_orbit},
		{"id": "kestrel", "name": "Kestrel wreck", "kind": "derelict", "body_id": "cradle", "elements": wreck_orbit},
	]
	world.selected_target = 1
	world.recompute_next_soi()
	encounters.clear()
	objects.clear()
	for target: Dictionary in world.targets:
		objects[str(target.id)] = target


## JSON-safe session: the world, every persistent orbital object and every
## encounter record. The planet and moon themselves are rebuilt by start_session.
func to_save() -> Dictionary:
	var records: Dictionary = {}
	for id: String in encounters:
		records[id] = EncounterStore.record_to_save(encounters[id])
	return {"world": world.to_save(), "objects": SaveCodec.plain(objects), "encounters": records}


## Apply to_save() data to a session that start_session() has just built.
func apply_save(data: Dictionary) -> void:
	world.apply_save(data.get("world", {}) as Dictionary)
	objects = SaveCodec.unplain(data.get("objects", {})) as Dictionary
	encounters.clear()
	var records: Dictionary = data.get("encounters", {}) as Dictionary
	for id: String in records:
		encounters[id] = EncounterStore.record_from_save(records[id] as Dictionary)


## Resolve a persistent object into the root inertial frame at explicit simulation time.
func object_state(id: String, at_time: float) -> Dictionary:
	if world == null or not objects.has(id):
		return {}
	var object: Dictionary = objects[id]
	var state: Dictionary = OrbitMath.propagate(object.elements, world.system.body(str(object.body_id)), at_time)
	if state.is_empty():
		return {}
	var parent: Dictionary = world.system.body_state_in_root(str(object.body_id), at_time)
	return {"position": SimVector.add(parent.position, state.position), "velocity": SimVector.add(parent.velocity, state.velocity)}


## Register a drifting fragment with its own scalar64 conic and stable encounter identity.
func store_object(id: String, root_position: SimVector, root_velocity: SimVector, body_id: String) -> bool:
	var parent: Dictionary = world.system.body_state_in_root(body_id, world.time)
	var elements: Dictionary = ManeuverMath.state_to_elements(SimVector.sub(root_position, parent.position), SimVector.sub(root_velocity, parent.velocity), world.system.body(body_id), world.time)
	if elements.is_empty():
		return false
	objects[id] = {"id": id, "kind": "debris", "body_id": body_id, "elements": elements}
	return true
