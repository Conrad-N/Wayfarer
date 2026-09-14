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
var _wheel_energy_before_j: float = 0.0
var _suit_dump_settle_s: float = 0.0
## Warp a seated pilot asked for while the suit wheels still had to be unloaded.
var _pending_warp: float = 1.0
const EVA_REFERENCE_ID: String = "__eva_coast_reference"
const ATTITUDE_TORQUE_NM: float = 5500.0
## Fastest closing speed the local approach will command, whatever the range.
const APPROACH_SPEED_LIMIT_MPS: float = 20.0
## Solar integration granularity: warp must not skip eclipse passages.
const SOLAR_SAMPLE_S: float = 30.0
const SOLAR_MAX_SAMPLES: int = 512


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
	# A loaded hull slews about 2°/s, so a half-turn needs roughly 90 s before a burn.
	session.world.attitude_lead_seconds = 120.0
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
	_drive_pending_warp()
	_suit_dump_settle_s = 0.3 if player.is_wheel_dumping() else maxf(0.0, _suit_dump_settle_s - delta)
	if reference_id.is_empty() and (not is_aboard() or _needs_inertial_interior()):
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
	if reference_id == EVA_REFERENCE_ID and ship_is_local and is_aboard() and not player.grapple.is_attached() and not _needs_inertial_interior():
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
	# Flight budgets include the transported suit. The physical hull keeps its own mass;
	# a local joint/collision supplies the suit's inertia instead of counting it twice.
	var occupant_mass: float = player.mass if is_aboard() else 0.0
	session.world.sync_mass(float(session.world.ship.propellant_kg), float(data.cargo_mass_kg), float(data.dry_mass_kg) + float(data.propellant_kg) + occupant_mass)


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
	var time_before: float = session.world.time
	var controls: Dictionary = session.world.advance_local(delta, SimVector.sub(root_position, parent.position), SimVector.sub(root_velocity, parent.velocity), LocalOrbitFrame.orbital_orientation(ship.global_basis), LocalOrbitFrame.scalar(omega))
	_settle_wheel_energy()
	_advance_solar(time_before)
	ship.api.publish_flight(ship.api.get_telemetry().flight, float(controls.propellant_kg))
	ship.mass = float(ship.api.get_telemetry().mass_kg)
	ship.apply_central_force(LocalOrbitFrame.native(controls.force_world))
	var simulation_basis: Basis = ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed()
	# The sim owns motor momentum/energy; the physical hull applies passive gyro
	# using its complete inertia tensor, including with motor power switched off.
	ship.rotor_momentum_body = LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(session.world.reaction_wheel.momentum_body)
	ship.apply_torque(simulation_basis * LocalOrbitFrame.native(controls.torque_body))
	_apply_rcs(delta)
	_refresh_local_snapshot()


func _attitude_available() -> bool:
	var data: Dictionary = ship.api.get_telemetry()
	return bool(data.power_available) and bool(data.systems.reaction_wheel.enabled) and float(data.systems.reaction_wheel.health) > 0.0


func _sync_attitude_authority() -> void:
	session.world.ship.max_torque_nm = ATTITUDE_TORQUE_NM if _attitude_available() else 0.0
	var data: Dictionary = ship.api.get_telemetry()
	_wheel_energy_before_j = float(data.battery_energy_j)
	session.world.reaction_wheel.battery_energy_j = _wheel_energy_before_j
	session.world.reaction_wheel.enabled = _attitude_available()


func _settle_wheel_energy() -> void:
	var spent: float = _wheel_energy_before_j - session.world.reaction_wheel.battery_energy_j
	if spent > 0.0:
		ship.api.consume_energy(spent)
	elif spent < 0.0:
		ship.api.store_energy(-spent)


## Charge the battery from the solar wings for the sim time that just passed,
## regardless of ship power (a flat battery must be able to recover). Warp can
## cover a whole orbit in one frame, so the interval is swept in sub-steps of
## at most SOLAR_SAMPLE_S (capped at SOLAR_MAX_SAMPLES, averaged evenly if
## capped) so eclipse passages are not skipped. Orientation is held at its
## current value for the whole interval; only the ship's orbital position
## (and so eclipse state) is resampled per sub-step.
func _advance_solar(time_before: float) -> void:
	var world: OrbitalWorld = session.world
	var elapsed: float = world.time - time_before
	if not is_finite(elapsed) or elapsed <= 0.0:
		return
	var span: SimVector = SolarArray.span_axis(world.orientation)
	var body: Dictionary = world.get_body()
	var solar: Dictionary = ship.api.get_telemetry().systems.get("solar", {})
	var health: float = float(solar.get("health", 1.0))
	var enabled: bool = bool(solar.get("enabled", true))
	var samples: int = clampi(ceili(elapsed / SOLAR_SAMPLE_S), 1, SOLAR_MAX_SAMPLES)
	var step: float = elapsed / float(samples)
	var energy_j: float = 0.0
	for index: int in samples:
		var at_time: float = time_before + step * (float(index) + 0.5)
		var reading: Dictionary = _solar_reading_at(world, at_time, span, body, health, enabled)
		energy_j += float(reading.power_w) * step
	if energy_j > 0.0:
		ship.api.store_energy(energy_j)
	var now: Dictionary = _solar_reading_at(world, world.time, span, body, health, enabled)
	ship.api.publish_solar(float(now.power_w), bool(now.sunlit))
	ship.set_solar_tracking(_local_sun_direction(now.sun_dir, world.orientation))


## Output, eclipse state and Sun bearing at one instant, in the hierarchy's root frame.
func _solar_reading_at(world: OrbitalWorld, at_time: float, span: SimVector, body: Dictionary, health: float, enabled: bool) -> Dictionary:
	var local_r: SimVector = world.orbit_at(at_time).get("position", SimVector.new()) as SimVector
	var base: SimVector = world.system.body_state_in_root(world.central_body_id, at_time).get("position", SimVector.new()) as SimVector
	var bearing: Dictionary = SolarArray.sun_bearing(world.system, SimVector.add(base, local_r), at_time)
	var power_w: float = SolarArray.output_w(bearing.direction, bearing.distance_m, span, local_r, body, health, enabled)
	return {"power_w": power_w, "sunlit": not SolarArray.shadowed(local_r, bearing.direction, body), "sun_dir": bearing.direction}


## Convert a root-frame Sun bearing into the ship's own local (hull) axes, the
## same rotation the navball uses to place orbital directions on the dial.
func _local_sun_direction(sun_dir_root: SimVector, orientation: Dictionary) -> Vector3:
	var body_dir: SimVector = FlightMath.rotate(FlightMath.q_conj(orientation), sun_dir_root)
	return LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(body_dir)


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
	var limit: float = requested_warp if aboard and _seated() and reference_id.is_empty() else 1.0
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
	var time_before: float = session.world.time
	session.world.advance(delta)
	_settle_wheel_energy()
	_advance_solar(time_before)
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
		var carrier_spin: Vector3 = ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(session.world.angular_vel)
		var lever: Vector3 = player.global_position - ship.to_global(ship.center_of_mass)
		player.linear_velocity += frame.to_local_velocity(root_state.velocity) + carrier_spin.cross(lever)
		player.angular_velocity += carrier_spin
	hazards.configure(wreck)
	if str(session.objects[id].kind) == "derelict":
		EncounterStore.restore(session, id, frame, wreck, hazards)
	elif str(session.objects[id].kind) == "station":
		_make_station()
	_enter_local_ship()
	ship.api.set_cargo_message("ARRIVED NEAR " + str(session.objects[id].name).to_upper())
	DebugLog.event("flight", "entered %s near %s at %.1f m/s" % [str(session.objects[id].kind), id, ship.linear_velocity.length()])


func _enter_local_ship() -> void:
	ship_is_local = true
	requested_warp = 1.0
	ship.rotor_momentum_body = LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed() * LocalOrbitFrame.native(session.world.reaction_wheel.momentum_body)
	ship.freeze = false
	ship.collision_layer = 1
	ship.collision_mask = 1
	var state: Dictionary = session.world.ship_root_state()
	ship.global_position = frame.to_local_position(state.position) - ship.global_basis * ship.center_of_mass
	ship.linear_velocity = frame.to_local_velocity(state.velocity)
	var simulation_basis: Basis = ship.global_basis * LocalOrbitFrame.GODOT_TO_SIM_BODY.transposed()
	ship.angular_velocity = simulation_basis * LocalOrbitFrame.native(session.world.angular_vel)
	_rebase_grips()
	DebugLog.event("flight", "ship physics on (reference %s)" % reference_id)


func _leave_local_ship() -> void:
	var root_position: SimVector = frame.to_orbital_position(ship.to_global(ship.center_of_mass))
	var root_velocity: SimVector = frame.to_orbital_velocity(ship.linear_velocity)
	var parent: Dictionary = session.world.system.body_state_in_root(session.world.central_body_id, session.world.time)
	session.world.replace_state(SimVector.sub(root_position, parent.position), SimVector.sub(root_velocity, parent.velocity))
	session.world.orientation = LocalOrbitFrame.orbital_orientation(ship.global_basis)
	session.world.angular_vel = LocalOrbitFrame.scalar(LocalOrbitFrame.GODOT_TO_SIM_BODY * (ship.global_basis.transposed() * ship.angular_velocity))
	if is_aboard():
		player.linear_velocity -= ship.linear_velocity + ship.angular_velocity.cross(player.global_position - ship.to_global(ship.center_of_mass))
		player.angular_velocity -= ship.angular_velocity
	ship_is_local = false
	ship.freeze = true
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	ship.collision_layer = 1 if is_aboard() else 0
	ship.collision_mask = ship.collision_layer
	_approaching = false
	_rcs_direction = Vector3.ZERO
	_rebase_grips()
	DebugLog.event("flight", "ship physics off (reference %s)" % reference_id)


## Frame handoffs change suit and carrier velocity together. Tell every grip so
## its overload estimate does not read the bookkeeping jump as a crushing load.
func _rebase_grips() -> void:
	get_tree().call_group(PhysicalGrip.FRAME_GROUP, "rebase_motion")


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
		# Close as fast as the RCS can still cancel over the remaining distance
		# (a quarter of the ideal stopping margin), easing to a proportional crawl.
		var closing: Vector3 = stand_off - offset
		var remaining: float = closing.length()
		var acceleration: float = PlayerShip.BRAKE_FORCE_N / maxf(ship.mass, 1.0)
		var speed: float = minf(remaining * 0.1, sqrt(0.5 * acceleration * remaining))
		var desired_velocity: Vector3 = closing.normalized() * minf(speed, APPROACH_SPEED_LIMIT_MPS) if remaining > 0.001 else Vector3.ZERO
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
			if not is_finite(value) or not _is_allowed_warp(value):
				return _result(false, "SELECT 1, 10, 100 OR 1000× WARP")
			if value > 1.0 and not _warp_seat_ready():
				return _result(false, "STRAP INTO THE PILOT SEAT TO WARP; 1× NEAR OBJECTS")
			if value > 1.0 and _suit_holding_on():
				return _result(false, "LET GO OF HANDHOLDS, BOOTS AND GRAPPLE BEFORE WARP")
			# Loaded suit wheels are unloaded for the pilot; warp follows once settled.
			_pending_warp = value if value > 1.0 and _needs_inertial_interior() else 1.0
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
			if not _warp_seat_ready():
				return _result(false, "STRAP INTO THE PILOT SEAT FOR EVENT WARP; UNAVAILABLE NEAR OBJECTS")
			if _suit_holding_on():
				return _result(false, "LET GO OF HANDHOLDS, BOOTS AND GRAPPLE BEFORE EVENT WARP")
			if world.nodes.is_empty():
				return _result(false, "NO MANEUVER EVENT QUEUED")
			_pending_warp = 1000.0 if _needs_inertial_interior() else 1.0
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
	var snapshot: Dictionary = {"available": true, "time_s": world.time, "warp": world.rate, "requested_warp": maxf(requested_warp, _pending_warp),
		"local": not reference_id.is_empty(), "reference_name": str(session.objects[reference_id].name) if not reference_id.is_empty() else "OPEN SPACE",
		"body_name": world.get_body().name, "body_radius_m": world.get_body().radius,
		"orbit": {"altitude_m": state.altitude, "periapsis_altitude_m": state.periapsis_altitude, "apoapsis_altitude_m": state.apoapsis_altitude,
			"period_s": state.period, "inclination_rad": state.i, "eccentricity": state.e},
		"mass_kg": world.current_mass(), "main_propellant_kg": world.ship.propellant_kg, "rcs_propellant_kg": data.propellant_kg,
		"dv_budget_mps": ManeuverMath.dv_budget(world.ship.propellant_kg, world.structural_mass_kg(), world.ship.isp_seconds),
		"throttle": world.throttle, "attitude_mode": world.attitude_mode, "executor_on": world.executor_on,
		"reaction_wheel": world.reaction_wheel.snapshot(),
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


func _seated() -> bool:
	return bool(player.get_meta("seated", false))


## Seated, aboard, and not parked near an object: the only state that may warp.
## The free-flight reference is allowed because a seated pilot is only there while
## the interior waits for the suit wheels to unload.
func _warp_seat_ready() -> bool:
	return _seated() and is_aboard() and (reference_id.is_empty() or reference_id == EVA_REFERENCE_ID)


## Whether the suit is physically attached to anything besides the seat harness.
func _suit_holding_on() -> bool:
	var grip: PhysicalGrip = player.get_node_or_null("PhysicalGrip") as PhysicalGrip
	var boots: MagneticBoots = player.get_node_or_null("MagneticBoots") as MagneticBoots
	return (grip != null and grip.is_attached()) or (boots != null and boots.is_attached()) or player.grapple.is_attached()


## Unload the seated pilot's suit wheels for a pending warp request, then engage
## it once the harness has settled and the interior is analytic again.
func _drive_pending_warp() -> void:
	if _pending_warp <= 1.0:
		player.set_automatic_wheel_dump(false)
		return
	if not _warp_seat_ready() or _suit_holding_on():
		_pending_warp = 1.0
		player.set_automatic_wheel_dump(false)
		return
	player.set_automatic_wheel_dump(player.attitude.momentum_body.length_squared() > 1e-8)
	if reference_id.is_empty() and not _needs_inertial_interior():
		requested_warp = _pending_warp
		_pending_warp = 1.0


func _needs_inertial_interior() -> bool:
	# A live joint must transmit the suit motor's impulse. Keep physical ownership
	# while its spinning rotors can react against the carrier, and briefly after
	# unloading so the constraint solver finishes transmitting the last impulse.
	if player.is_wheel_dumping() or _suit_dump_settle_s > 0.0 or player.attitude.momentum_body.length_squared() > 1e-8:
		return true
	if _suit_holding_on():
		return true
	# Even coasting collisions and walking must exchange momentum with a live hull.
	# Only the strapped pilot permits analytic transit; free suits always use Jolt.
	return not _seated()


## Warp rates come from UI controls that may pass a value computed elsewhere
## (a dial, a save file, a keybind macro), so membership of the allowed set is
## judged with is_equal_approx instead of exact float equality.
func _is_allowed_warp(value: float) -> bool:
	for allowed: float in [1.0, 10.0, 100.0, 1000.0]:
		if is_equal_approx(value, allowed):
			return true
	return false
