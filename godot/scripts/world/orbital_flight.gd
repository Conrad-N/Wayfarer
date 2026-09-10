## Connect orbital flight, physical encounters, persistent salvage and the shared ship API.
class_name OrbitalFlight
extends Node

var session: OrbitalSession
var ship: PlayerShip
var player: Player
var wreck: SalvageWreck
var hazards: SalvageHazards
var frame: LocalOrbitFrame = LocalOrbitFrame.new()
var reference_id: String = ""
var requested_warp: float = 1.0
var enabled: bool = true
var ship_is_local: bool = false
var _station: StaticBody3D
var _rcs_direction: Vector3 = Vector3.ZERO
var _approaching: bool = false
var _publish_elapsed: float = 1.0
const EVA_REFERENCE_ID: String = "__eva_coast_reference"
const ATTITUDE_TORQUE_NM: float = 5500.0


## Start a session with the existing physical ship and tool scene as its local actors.
func configure(owner_session: OrbitalSession, owner_ship: PlayerShip, suit: Player, salvage: SalvageWreck, vents: SalvageHazards) -> void:
	session = owner_session
	ship = owner_ship
	player = suit
	wreck = salvage
	hazards = vents
	process_physics_priority = -95
	session.start_session()
	ship.api.bind_flight(_command)
	var aboard_pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	ship.freeze = true
	ship.global_transform = Transform3D(LocalOrbitFrame.ship_basis(session.world.orientation), Vector3.ZERO)
	player.global_transform = ship.global_transform * aboard_pose
	ship.api.publish_flight({"available": true}, float(session.world.ship.propellant_kg))
	ship.mass = float(ship.api.get_telemetry().mass_kg)
	_sync_mass()
	session.world.attitude_lead_seconds = 60.0
	_make_sky()
	_publish()


## Whether the suit is physically inside the ship's enclosed interior envelope.
func is_aboard() -> bool:
	return AABB(Vector3(-1.9, -1.4, -7.0), Vector3(3.8, 2.8, 12.8)).has_point(ship.to_local(player.global_position))


func _physics_process(delta: float) -> void:
	if not enabled or session == null or session.world == null:
		return
	_sync_mass()
	_sync_attitude_authority()
	if reference_id.is_empty() and not is_aboard():
		_begin_open_space_eva()
	if not bool(ship.api.get_telemetry().power_available):
		session.world.set_executor(false)
		session.world.set_throttle(0.0)
		_rcs_direction = Vector3.ZERO
		_approaching = false
	if ship_is_local:
		_advance_local(delta)
	else:
		_advance_orbit(delta)
	if reference_id.is_empty():
		for id: String in session.objects:
			if str(session.objects[id].get("kind", "")) not in ["station", "derelict"]:
				continue
			var target: Dictionary = session.object_state(id, session.world.time)
			if not target.is_empty() and SimVector.distance(session.world.ship_root_state().position, target.position) <= LocalOrbitFrame.LOCAL_RADIUS_M + 1.0:
				_enter_encounter(id)
				break
	else:
		var reference: Dictionary = session.object_state(reference_id, session.world.time)
		frame.set_reference(reference.position, reference.velocity)
		var distance: float = SimVector.distance(session.world.ship_root_state().position, reference.position)
		if not ship_is_local and distance <= LocalOrbitFrame.LOCAL_RADIUS_M:
			_enter_local_ship()
		elif ship_is_local and distance > LocalOrbitFrame.EXIT_RADIUS_M and hazards.active_count() == 0 and (is_aboard() or ship.global_position.distance_to(player.global_position) > LocalOrbitFrame.LOCAL_RADIUS_M):
			_leave_local_ship()
			if is_aboard():
				_leave_encounter()
		if player.global_position.length() > LocalOrbitFrame.RECENTRE_DISTANCE_M:
			var nodes: Array[Node3D] = [ship, player]
			for body: WreckBody in wreck.bodies:
				nodes.append(body)
			if is_instance_valid(_station):
				nodes.append(_station)
			frame.recentre(nodes, player.global_position)
	if reference_id == EVA_REFERENCE_ID and ship_is_local and is_aboard() and not player.grapple.is_attached():
		_leave_local_ship()
		_leave_encounter()
	_publish_elapsed += delta
	if _publish_elapsed >= 0.2:
		_publish_elapsed = 0.0
		_publish()


func _process(_delta: float) -> void:
	if enabled and ship_is_local:
		_refresh_local_snapshot()


func _sync_mass() -> void:
	var data: Dictionary = ship.api.get_telemetry()
	session.world.sync_mass(float(session.world.ship.propellant_kg), float(data.cargo_mass_kg), float(data.dry_mass_kg) + float(data.propellant_kg))


func _advance_local(delta: float) -> void:
	_sync_attitude_authority()
	requested_warp = 1.0
	session.world.set_rate(1.0)
	var reference: Dictionary = session.object_state(reference_id, session.world.time)
	frame.set_reference(reference.position, reference.velocity)
	var root_position: SimVector = frame.to_orbital_position(ship.to_global(ship.center_of_mass))
	var root_velocity: SimVector = frame.to_orbital_velocity(ship.linear_velocity)
	var parent: Dictionary = session.world.system.body_state_in_root(session.world.central_body_id, session.world.time)
	var omega: Vector3 = LocalOrbitFrame.GODOT_TO_SIM_BODY * (ship.global_basis.transposed() * ship.angular_velocity)
	_sync_physical_inertia()
	var controls: Dictionary = session.world.advance_local(delta, SimVector.sub(root_position, parent.position), SimVector.sub(root_velocity, parent.velocity), LocalOrbitFrame.orbital_orientation(ship.global_basis), LocalOrbitFrame.scalar(omega))
	ship.api.publish_flight(ship.api.get_telemetry().flight, float(controls.propellant_kg))
	ship.mass = float(ship.api.get_telemetry().mass_kg)
	ship.apply_central_force(LocalOrbitFrame.native(controls.force_world))
	var simulation_basis: Basis = ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed()
	if _attitude_available():
		ship.apply_torque(simulation_basis * LocalOrbitFrame.native(controls.torque_body))
	_apply_rcs(delta)
	_refresh_local_snapshot()


func _attitude_available() -> bool:
	var data: Dictionary = ship.api.get_telemetry()
	return bool(data.power_available) and bool(data.systems.rcs.enabled) and float(data.systems.rcs.health) > 0.0


func _sync_attitude_authority() -> void:
	session.world.ship.max_torque_nm = ATTITUDE_TORQUE_NM if _attitude_available() else 0.0


func _sync_physical_inertia() -> void:
	var inverse: Basis = ship.get_inverse_inertia_tensor()
	if absf(inverse.determinant()) <= 1e-30:
		return
	var physical: Basis = ship.global_basis.transposed() * inverse.inverse() * ship.global_basis
	# Sim body +X is hull -Z; principal diagonal moments follow that axis map.
	session.world.ship.inertia = {"ix": maxf(1.0, physical.z.z), "iy": maxf(1.0, physical.y.y), "iz": maxf(1.0, physical.x.x)}


func _refresh_local_snapshot() -> void:
	if reference_id.is_empty() or session == null or session.world == null:
		return
	var reference: Dictionary = session.object_state(reference_id, session.world.time)
	if reference.is_empty():
		return
	frame.set_reference(reference.position, reference.velocity)
	var parent: Dictionary = session.world.system.body_state_in_root(session.world.central_body_id, session.world.time)
	var omega: Vector3 = LocalOrbitFrame.GODOT_TO_SIM_BODY * (ship.global_basis.transposed() * ship.angular_velocity)
	session.world.refresh_local_state(SimVector.sub(frame.to_orbital_position(ship.to_global(ship.center_of_mass)), parent.position),
		SimVector.sub(frame.to_orbital_velocity(ship.linear_velocity), parent.velocity), LocalOrbitFrame.orbital_orientation(ship.global_basis), LocalOrbitFrame.scalar(omega))


func _begin_open_space_eva() -> void:
	var state: Dictionary = session.world.ship_root_state()
	if not session.store_object(EVA_REFERENCE_ID, state.position, state.velocity, session.world.central_body_id):
		return
	session.objects[EVA_REFERENCE_ID].kind = "reference"
	session.objects[EVA_REFERENCE_ID].name = "Free flight"
	_enter_encounter(EVA_REFERENCE_ID)


func _advance_orbit(delta: float) -> void:
	_sync_attitude_authority()
	var world: OrbitalWorld = session.world
	var aboard: bool = is_aboard()
	var relative_pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	var old_basis: Basis = ship.global_basis
	var limit: float = requested_warp if aboard and reference_id.is_empty() else 1.0
	if limit > 10.0 and (world.throttle > 0.0 or not world.powered_state.is_empty() or world.attitude_mode not in ["manual", "kill"] or SimVector.length(world.angular_vel) > 1e-9):
		limit = 10.0
	var sim_delta: float = delta * limit
	var root_state: Dictionary = session.world.ship_root_state()
	for id: String in session.objects:
		if str(session.objects[id].get("kind", "")) not in ["station", "derelict"]:
			continue
		var target: Dictionary = session.object_state(id, session.world.time)
		if target.is_empty():
			continue
		var range_m: float = SimVector.distance(root_state.position, target.position)
		var speed: float = SimVector.distance(root_state.velocity, target.velocity)
		var safe_time: float = maxf(delta, (range_m - LocalOrbitFrame.LOCAL_RADIUS_M) * 0.8 / (speed + 500.0))
		sim_delta = minf(sim_delta, safe_time)
	session.world.set_rate(sim_delta / delta)
	session.world.advance(delta)
	root_state = session.world.ship_root_state()
	if reference_id.is_empty():
		frame.set_reference(root_state.position, root_state.velocity)
		frame.shift = SimVector.new()
	else:
		var target: Dictionary = session.object_state(reference_id, session.world.time)
		frame.set_reference(target.position, target.velocity)
	ship.global_basis = LocalOrbitFrame.ship_basis(session.world.orientation)
	ship.global_position = frame.to_local_position(root_state.position) - ship.global_basis * ship.center_of_mass
	if aboard:
		player.global_transform = ship.global_transform * relative_pose
		player.linear_velocity = ship.global_basis * old_basis.transposed() * player.linear_velocity
	ship.api.publish_flight(ship.api.get_telemetry().flight, float(session.world.ship.propellant_kg))


func _enter_encounter(id: String) -> void:
	var aboard: bool = is_aboard()
	var player_pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	reference_id = id
	frame.shift = SimVector.new()
	var reference: Dictionary = session.object_state(id, session.world.time)
	frame.set_reference(reference.position, reference.velocity)
	var root_state: Dictionary = session.world.ship_root_state()
	ship.global_position = frame.to_local_position(root_state.position) - ship.global_basis * ship.center_of_mass
	if aboard:
		player.global_transform = ship.global_transform * player_pose
		player.linear_velocity += frame.to_local_velocity(root_state.velocity)
	hazards.configure(wreck)
	if str(session.objects[id].kind) == "derelict":
		EncounterStore.restore(session, id, frame, wreck, hazards)
	elif str(session.objects[id].kind) == "station":
		_make_station()
	_enter_local_ship()
	ship.api.set_cargo_message("ARRIVED NEAR " + str(session.objects[id].name).to_upper())


func _enter_local_ship() -> void:
	ship_is_local = true
	requested_warp = 1.0
	ship.freeze = false
	ship.collision_layer = 1
	ship.collision_mask = 1
	var state: Dictionary = session.world.ship_root_state()
	ship.global_position = frame.to_local_position(state.position) - ship.global_basis * ship.center_of_mass
	ship.linear_velocity = frame.to_local_velocity(state.velocity)
	var simulation_basis: Basis = ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed()
	ship.angular_velocity = simulation_basis * LocalOrbitFrame.native(session.world.angular_vel)


func _leave_local_ship() -> void:
	var root_position: SimVector = frame.to_orbital_position(ship.to_global(ship.center_of_mass))
	var root_velocity: SimVector = frame.to_orbital_velocity(ship.linear_velocity)
	var parent: Dictionary = session.world.system.body_state_in_root(session.world.central_body_id, session.world.time)
	session.world.replace_state(SimVector.sub(root_position, parent.position), SimVector.sub(root_velocity, parent.velocity))
	session.world.orientation = LocalOrbitFrame.orbital_orientation(ship.global_basis)
	session.world.angular_vel = LocalOrbitFrame.scalar(LocalOrbitFrame.GODOT_TO_SIM_BODY * (ship.global_basis.transposed() * ship.angular_velocity))
	if is_aboard():
		player.linear_velocity -= ship.linear_velocity
	ship_is_local = false
	ship.freeze = true
	ship.collision_layer = 0
	ship.collision_mask = 0
	_approaching = false
	_rcs_direction = Vector3.ZERO


func _leave_encounter() -> void:
	if str(session.objects[reference_id].kind) == "derelict":
		EncounterStore.capture(session, reference_id, frame, wreck, hazards)
	player.grapple.detach()
	player.salvage_tools.cancel_input()
	for body: WreckBody in wreck.bodies:
		body.get_parent().remove_child(body)
		body.queue_free()
	wreck.bodies.clear()
	wreck.graph = ShipGraph.new()
	wreck.cut_progress.clear()
	hazards.configure(null)
	if is_instance_valid(_station):
		_station.get_parent().remove_child(_station)
		_station.queue_free()
		_station = null
	var aboard_pose: Transform3D = ship.global_transform.affine_inverse() * player.global_transform
	var state: Dictionary = session.world.ship_root_state()
	frame.set_reference(state.position, state.velocity)
	frame.shift = SimVector.new()
	ship.global_position = -(ship.global_basis * ship.center_of_mass)
	player.global_transform = ship.global_transform * aboard_pose
	reference_id = ""
	wreck.structure_changed.emit()


func _apply_rcs(delta: float) -> void:
	var data: Dictionary = ship.api.get_telemetry()
	if not bool(data.power_available) or not bool(data.systems.rcs.enabled) or float(data.systems.rcs.health) <= 0.0:
		return
	var force: Vector3 = ship.global_basis * _rcs_direction * PlayerShip.BRAKE_FORCE_N
	if _approaching:
		var reference_point: Vector3 = frame.to_local_position(frame.reference_position)
		var offset: Vector3 = ship.to_global(ship.center_of_mass) - reference_point
		var stand_off: Vector3 = offset.normalized() * 30.0 if offset.length() > 0.001 else Vector3.BACK * 30.0
		# The 40 kg RCS reserve gives a loaded ship about 2.5 m/s total delta-v.
		# A 0.5 m/s approach leaves fuel to brake after the main drive matches velocity.
		var desired_velocity: Vector3 = ((stand_off - offset) * 0.03).limit_length(0.5)
		force = ((desired_velocity - ship.linear_velocity) * ship.mass / 2.0).limit_length(PlayerShip.BRAKE_FORCE_N)
		if (offset - stand_off).length() < 1.0 and ship.linear_velocity.length() < 0.1:
			_approaching = false
			ship.api.set_braking(true)
	var requested: float = force.length() * delta / PlayerShip.EXHAUST_VELOCITY_MPS
	if requested > 0.0:
		var spent: float = ship.api.consume_propellant(requested)
		ship.apply_central_force(force * spent / requested)


func _command(command: String, args: Dictionary) -> Dictionary:
	var world: OrbitalWorld = session.world
	match command:
		"set_warp":
			var value: float = args.get("rate", NAN)
			if not is_finite(value) or value not in [1.0, 10.0, 100.0, 1000.0]:
				return _result(false, "SELECT 1, 10, 100 OR 1000× WARP")
			if value > 1.0 and (not reference_id.is_empty() or not is_aboard()):
				return _result(false, "WARP LIMITED TO 1× NEAR OBJECTS OR DURING EVA")
			requested_warp = value
			if value > 1.0 and not world.executor_on:
				world.set_attitude_mode("kill")
		"set_throttle":
			var value: float = args.get("throttle", NAN)
			if not is_finite(value) or value < 0.0 or value > 1.0:
				return _result(false, "THROTTLE MUST BE BETWEEN ZERO AND ONE")
			world.set_executor(false)
			world.set_throttle(value)
		"set_attitude_mode":
			if not world.set_attitude_mode(str(args.get("mode", ""))):
				return _result(false, "UNKNOWN ATTITUDE MODE")
		"select_target":
			var found: bool = false
			for index: int in world.targets.size():
				if str(world.targets[index].id) == str(args.get("id", "")):
					world.selected_target = index
					_approaching = false
					found = true
			if not found:
				return _result(false, "UNKNOWN TARGET")
		"plan_intercept", "plan_hohmann", "plan_circularize", "plan_match_velocity", "plan_maneuver":
			return _plan(command, args)
		"execute_plan":
			if world.pending_maneuver.is_empty() or not bool(world.pending_maneuver.get("feasible", false)):
				return _result(false, "PREVIEW A FEASIBLE PLAN FIRST")
			for node: Dictionary in world.pending_maneuver.nodes:
				if float(node.time) < world.time:
					return _result(false, "PLAN HAS EXPIRED: CALCULATE IT AGAIN")
			if world.throttle > 0.0 or not world.powered_state.is_empty() or world.executor_on:
				return _result(false, "CANCEL THE ACTIVE BURN BEFORE REPLACING ITS PLAN")
			_sync_mass()
			var fuel: Dictionary = {"dry_mass_kg": world.structural_mass_kg(), "propellant_kg": world.ship.propellant_kg, "isp_seconds": world.ship.isp_seconds}
			var inputs: Array[Dictionary] = []
			inputs.assign(world.pending_maneuver.nodes)
			var rechecked: Dictionary = ManeuverMath.build_plan(world.current_elements(), world.get_body(), fuel, str(world.pending_maneuver.label), inputs)
			if not bool(rechecked.get("feasible", false)):
				return _result(false, "FUEL OR CARGO CHANGED: CALCULATE THE PLAN AGAIN")
			world.nodes.assign(rechecked.nodes.duplicate(true))
			world.pending_maneuver = {}
			world.set_executor(true)
			ship.api.set_braking(false)
			_approaching = false
			_rcs_direction = Vector3.ZERO
		"cancel_plan", "cutoff":
			world.set_executor(false)
			world.set_throttle(0.0)
			world.nodes.clear()
			world.pending_maneuver = {}
			_approaching = false
			_rcs_direction = Vector3.ZERO
		"next_event":
			if not reference_id.is_empty() or not is_aboard():
				return _result(false, "EVENT WARP UNAVAILABLE NEAR OBJECTS OR DURING EVA")
			if world.nodes.is_empty():
				return _result(false, "NO MANEUVER EVENT QUEUED")
			requested_warp = 1000.0
		"rcs_translate":
			if not ship_is_local:
				return _result(false, "LOCAL RCS TRANSLATION AVAILABLE NEAR STATIONS AND WRECKS")
			var direction: Variant = args.get("direction")
			if not direction is Vector3 or not (direction as Vector3).is_finite():
				return _result(false, "INVALID RCS DIRECTION")
			_rcs_direction = (direction as Vector3).limit_length(1.0)
			_approaching = false
			ship.api.set_braking(false)
		"approach":
			if str(world.selected_target_def().get("id", "")) != reference_id:
				return _result(false, "SELECT THE NEARBY OBJECT BEFORE APPROACH")
			if not ship_is_local or world.executor_on:
				return _result(false, "MATCH VELOCITY NEAR THE TARGET BEFORE LOCAL APPROACH")
			if ship.linear_velocity.length() > 10.0:
				return _result(false, "RELATIVE SPEED TOO HIGH FOR RCS APPROACH")
			_approaching = true
			ship.api.set_braking(false)
		_:
			return _result(false, "UNKNOWN FLIGHT COMMAND")
	_publish()
	return _result(true, command.replace("_", " ").to_upper())


func _plan(command: String, args: Dictionary) -> Dictionary:
	var world: OrbitalWorld = session.world
	if world.throttle > 0.0 or not world.powered_state.is_empty() or world.executor_on:
		return _result(false, "CANCEL THE ACTIVE BURN BEFORE PLANNING")
	_sync_mass()
	var elements: Dictionary = world.current_elements()
	var body: Dictionary = world.get_body()
	var target: Dictionary = world.selected_target_def()
	var nodes: Array[Dictionary] = []
	match command:
		"plan_intercept":
			var tof: float = args.get("tof_seconds", NAN)
			if not is_finite(tof) or tof < 60.0 or tof > 604800.0 or str(target.body_id) != world.central_body_id:
				return _result(false, "TRANSFER NEEDS A SAME-BODY TARGET AND 60 s TO 7 DAYS")
			nodes = OrbitalSolvers.solve_intercept(elements, body, world.time, target.elements, tof, 4, true)
		"plan_hohmann":
			var altitude: float = args.get("altitude_m", NAN)
			if not is_finite(altitude) or altitude < 10000.0:
				return _result(false, "TARGET ALTITUDE MUST EXCEED 10 km")
			nodes = OrbitalSolvers.solve_hohmann(elements, body, world.time + 60.0, float(body.radius) + altitude)
		"plan_circularize":
			var node: Dictionary = OrbitalSolvers.solve_circularize(elements, body, world.time + 60.0, str(args.get("at", "apoapsis")))
			if not node.is_empty():
				nodes.append(node)
		"plan_match_velocity":
			if str(target.body_id) != world.central_body_id:
				return _result(false, "MATCH REQUIRES A SAME-BODY TARGET")
			var node: Dictionary = OrbitalSolvers.solve_match_velocity(elements, body, world.time + 30.0, target.elements)
			if not node.is_empty():
				nodes.append(node)
		"plan_maneuver":
			var at: float = args.get("time", NAN)
			var dv: Dictionary = args.get("dv_local", {})
			if not is_finite(at) or at < world.time + 1.0:
				return _result(false, "NODE TIME MUST BE IN THE FUTURE")
			for axis: String in ["prograde", "normal", "radial"]:
				if not is_finite(float(dv.get(axis, NAN))) or absf(float(dv[axis])) > 50000.0:
					return _result(false, "INVALID MANEUVER DELTA-V")
			nodes.append({"time": at, "dv_local": dv})
	if nodes.is_empty():
		return _result(false, "NO VALID TRANSFER: TRY A DIFFERENT TIME OR ORBIT")
	var fuel: Dictionary = {"dry_mass_kg": world.structural_mass_kg(), "propellant_kg": world.ship.propellant_kg, "isp_seconds": world.ship.isp_seconds}
	world.pending_maneuver = ManeuverMath.build_plan(elements, body, fuel, command.replace("plan_", "").capitalize(), nodes)
	_publish()
	return _result(true, "PLAN READY: CHECK FUEL AND EXECUTE" if bool(world.pending_maneuver.get("feasible", false)) else "PLAN EXCEEDS AVAILABLE FUEL")


func _publish() -> void:
	var world: OrbitalWorld = session.world
	var state: Dictionary = world.orbit()
	if state.is_empty():
		return
	var root_state: Dictionary = world.ship_root_state()
	var target: Dictionary = world.selected_target_def()
	var target_state: Dictionary = world.target_root_state(target)
	var relative: SimVector = SimVector.sub(target_state.position, root_state.position)
	var relative_velocity: SimVector = SimVector.sub(target_state.velocity, root_state.velocity)
	var targets: Array[Dictionary] = []
	for entry: Dictionary in world.targets:
		targets.append({"id": entry.id, "name": entry.name, "kind": entry.kind})
	var data: Dictionary = ship.api.get_telemetry()
	var snapshot: Dictionary = {"available": true, "time_s": world.time, "warp": world.rate, "requested_warp": requested_warp,
		"local": not reference_id.is_empty(), "reference_name": str(session.objects[reference_id].name) if not reference_id.is_empty() else "OPEN SPACE",
		"body_name": world.get_body().name, "body_radius_m": world.get_body().radius,
		"orbit": {"altitude_m": state.altitude, "periapsis_altitude_m": state.periapsis_altitude, "apoapsis_altitude_m": state.apoapsis_altitude,
			"period_s": state.period, "inclination_rad": state.i, "eccentricity": state.e},
		"mass_kg": world.current_mass(), "main_propellant_kg": world.ship.propellant_kg, "rcs_propellant_kg": data.propellant_kg,
		"dv_budget_mps": ManeuverMath.dv_budget(world.ship.propellant_kg, world.structural_mass_kg(), world.ship.isp_seconds),
		"throttle": world.throttle, "attitude_mode": world.attitude_mode, "executor_on": world.executor_on,
		"burn_status": "RCS APPROACH" if _approaching else ("EXECUTING %d NODES" % world.nodes.size() if world.executor_on else ("MAIN THRUST" if world.throttle > 0.0 and float(world.ship.propellant_kg) > 0.0 else "COASTING")),
		"target": {"id": target.id, "name": target.name, "range_m": SimVector.length(relative), "relative_speed_mps": SimVector.length(relative_velocity)},
		"targets": targets, "plan": _plan_snapshot(), "scope": _scope_snapshot(state, target), "navball": _navball_snapshot(state, relative)}
	ship.api.publish_flight(snapshot, float(world.ship.propellant_kg))


func _plan_snapshot() -> Dictionary:
	var plan: Dictionary = session.world.pending_maneuver
	var nodes: Array[Dictionary] = []
	var total_dv: float = 0.0
	for node: Dictionary in plan.get("nodes", session.world.nodes):
		var dv: Dictionary = node.dv_local
		var magnitude: float = FlightMath.dv_magnitude(dv)
		total_dv += magnitude
		nodes.append({"time_s": node.time, "dv_mps": magnitude, "prograde_mps": dv.prograde, "normal_mps": dv.normal, "radial_mps": dv.radial})
	var propellant: float = 0.0
	for burn: Dictionary in plan.get("burns", []):
		propellant += float(burn.get("propellant_kg", 0.0))
	return {"label": plan.get("label", "Active flight" if not nodes.is_empty() else "No plan"), "feasible": plan.get("feasible", false), "dv_mps": total_dv, "propellant_kg": propellant, "nodes": nodes}


func _scope_snapshot(state: Dictionary, target: Dictionary) -> Dictionary:
	var basis: Dictionary = FlightMath.orbital_frame(state.position, state.velocity)
	var ship_path: Array[PackedFloat64Array] = []
	var target_path: Array[PackedFloat64Array] = []
	var period: float = minf(float(state.period), 86400.0)
	if not is_finite(period):
		period = 3600.0
	for index: int in range(65):
		var at: float = session.world.time + period * float(index) / 64.0
		var sample: Dictionary = session.world.orbit_at(at)
		if not sample.is_empty():
			ship_path.append(_project(sample.position, basis))
		if str(target.body_id) == session.world.central_body_id:
			var target_sample: Dictionary = OrbitMath.propagate(target.elements, session.world.get_body(), at)
			if not target_sample.is_empty():
				target_path.append(_project(target_sample.position, basis))
	return {"ship_path": ship_path, "target_path": target_path, "ship_position": _project(state.position, basis),
		"target_position": target_path[0] if not target_path.is_empty() else PackedFloat64Array(), "radius_m": session.world.get_body().radius}


func _navball_snapshot(state: Dictionary, relative: SimVector) -> Dictionary:
	var orbital: Dictionary = FlightMath.orbital_frame(state.position, state.velocity)
	var rotation: Dictionary = FlightMath.q_conj(session.world.orientation)
	var result: Dictionary = {}
	for key: String in ["prograde", "normal", "radial"]:
		var direction: SimVector = orbital["radial_out" if key == "radial" else key]
		result[key] = LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(FlightMath.rotate(rotation, direction))
	result.target = LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(FlightMath.rotate(rotation, SimVector.normalized(relative)))
	return result


func _project(position: SimVector, basis: Dictionary) -> PackedFloat64Array:
	return PackedFloat64Array([SimVector.dot(position, basis.radial_out), SimVector.dot(position, basis.prograde)])


func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}


func _make_sky() -> void:
	(player.get_node("Camera3D") as Camera3D).far = 20000.0
	var environments: Array[Node] = get_parent().find_children("*", "WorldEnvironment", true, false)
	var environment: WorldEnvironment
	if environments.is_empty():
		environment = WorldEnvironment.new()
		get_parent().add_child(environment)
	else:
		environment = environments[0] as WorldEnvironment
	var sky: Node = preload("res://scripts/world/orbital_sky.gd").new()
	add_child(sky)
	sky.configure(session, environment)


func _make_station() -> void:
	_station = StaticBody3D.new()
	_station.name = "LowlineYard"
	get_parent().add_child(_station)
	_station.position = frame.to_local_position(frame.reference_position)
	for side: float in [-1.0, 1.0]:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(8, 8, 24)
		mesh.mesh = box
		mesh.position.x = side * 8.0
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.5, 0.55)
		mesh.material_override = material
		_station.add_child(mesh)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var bounds: BoxShape3D = BoxShape3D.new()
		bounds.size = box.size
		shape.shape = bounds
		shape.position = mesh.position
		_station.add_child(shape)
	var sign: Label3D = Label3D.new()
	sign.text = "LOWLINE YARD"
	sign.position = Vector3(0, 6, 0)
	sign.pixel_size = 0.02
	_station.add_child(sign)
