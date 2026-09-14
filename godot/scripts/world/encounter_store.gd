## Snapshot loose wreck components as orbital objects so leaving cannot reset salvage.
class_name EncounterStore
extends RefCounted


## Capture cut state, condition, exhausted reservoirs and each remaining component orbit.
static func capture(session: OrbitalSession, id: String, frame: LocalOrbitFrame, wreck: SalvageWreck, hazards: SalvageHazards) -> void:
	var fragments: Array[Dictionary] = []
	for body: WreckBody in wreck.bodies:
		var object_id: String = id + "/" + "+".join(body.part_ids)
		if not session.store_object(object_id, frame.to_orbital_position(body.global_position), frame.to_orbital_velocity(body.linear_velocity), str(session.objects[id].body_id)):
			continue
		fragments.append({"id": object_id, "parts": body.part_ids.duplicate(), "basis": body.global_basis,
			"spin": body.angular_velocity, "time": session.world.time})
	session.encounters[id] = {"graph": wreck.graph, "fragments": fragments,
		"spent": hazards.spent_reservoirs(), "cut_progress": wreck.cut_progress.duplicate(true)}


## Recreate only the surviving components at their newly propagated relative states.
static func restore(session: OrbitalSession, id: String, frame: LocalOrbitFrame, wreck: SalvageWreck, hazards: SalvageHazards) -> void:
	if not wreck.bodies.is_empty():
		return
	if not session.encounters.has(id):
		wreck.spawn(PracticeWreck.make_graph(), Transform3D(Basis(Vector3.UP, 0.3), frame.to_local_position(frame.reference_position)), Vector3.ZERO, Vector3(0, 0.06, 0.025))
		return
	var record: Dictionary = session.encounters[id]
	wreck.graph = record.graph
	wreck.cut_progress = record.cut_progress.duplicate(true)
	for fragment: Dictionary in record.fragments:
		var state: Dictionary = session.object_state(str(fragment.id), session.world.time)
		if state.is_empty():
			continue
		var body: WreckBody = WreckBody.new()
		body.top_level = true
		wreck.add_child(body)
		body.configure(wreck, fragment.parts, Transform3D.IDENTITY)
		var spin: Vector3 = fragment.spin
		var spin_angle: float = fmod(spin.length() * (session.world.time - float(fragment.time)), TAU)
		var rotation: Basis = Basis(spin.normalized(), spin_angle) if spin.length() > 1e-10 else Basis.IDENTITY
		body.global_transform = Transform3D(rotation * (fragment.basis as Basis), frame.to_local_position(state.position))
		body.linear_velocity = frame.to_local_velocity(state.velocity)
		body.angular_velocity = spin
		wreck.bodies.append(body)
	hazards.restore_spent_reservoirs(record.spent)
	wreck.structure_changed.emit()


## Convert one session.encounters[id] record to JSON-safe data: the graph, each
## fragment's identity/orientation/spin/time, spent reservoirs, and cut progress.
## Fragment positions and velocities are not stored here; they live in
## session.objects as propagated orbital elements, saved by the orbital layer.
static func record_to_save(record: Dictionary) -> Dictionary:
	var fragments: Array = []
	for fragment: Dictionary in (record.get("fragments", []) as Array):
		var parts: Array = []
		for part_id: String in (fragment.get("parts", PackedStringArray()) as PackedStringArray):
			parts.append(part_id)
		fragments.append({
			"id": str(fragment.get("id", "")),
			"parts": parts,
			"basis": SaveCodec.basis(fragment.get("basis", Basis.IDENTITY)),
			"spin": SaveCodec.vector3(fragment.get("spin", Vector3.ZERO)),
			"time": float(fragment.get("time", 0.0)),
		})
	var spent: Dictionary = {}
	for part_id: String in (record.get("spent", {}) as Dictionary).keys():
		var kinds: Array = []
		for kind: String in (record.spent[part_id] as Array):
			kinds.append(kind)
		spent[part_id] = kinds
	var cut_progress: Dictionary = {}
	for edge_id: String in (record.get("cut_progress", {}) as Dictionary).keys():
		cut_progress[edge_id] = float(record.cut_progress[edge_id])
	return {
		"graph": (record.get("graph") as ShipGraph).to_save(),
		"fragments": fragments,
		"spent": spent,
		"cut_progress": cut_progress,
	}


## Rebuild one session.encounters[id] record from record_to_save() data, ready to
## assign straight into session.encounters and pass to restore().
static func record_from_save(data: Dictionary) -> Dictionary:
	var fragments: Array[Dictionary] = []
	for entry: Variant in (data.get("fragments", []) as Array):
		if not entry is Dictionary:
			continue
		var fragment: Dictionary = entry
		fragments.append({
			"id": str(fragment.get("id", "")),
			"parts": PackedStringArray(fragment.get("parts", []) as Array),
			"basis": SaveCodec.to_basis(fragment.get("basis")),
			"spin": SaveCodec.to_vector3(fragment.get("spin")),
			"time": float(fragment.get("time", 0.0)),
		})
	var spent: Dictionary = {}
	for part_id: String in (data.get("spent", {}) as Dictionary).keys():
		var kinds: Array[String] = []
		kinds.assign(data.spent[part_id] as Array)
		spent[part_id] = kinds
	var cut_progress: Dictionary = {}
	for edge_id: String in (data.get("cut_progress", {}) as Dictionary).keys():
		cut_progress[edge_id] = float(data.cut_progress[edge_id])
	return {
		"graph": ShipGraph.from_save(data.get("graph", {}) as Dictionary),
		"fragments": fragments,
		"spent": spent,
		"cut_progress": cut_progress,
	}
