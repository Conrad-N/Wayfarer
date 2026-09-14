## Authoritative scalar-double orbital world, ported from the browser simulation.
## Analytic coasts meet fixed 1/64-second powered/attitude integration at events.
class_name OrbitalWorld
extends RefCounted

const DT_PHYS: float = 1.0 / 64.0
const MAX_SUBSTEPS: int = 4096
const SAFE_WARP: float = 10.0
const SOI_LEAD: float = 120.0
const CAPTURE_SAMPLES: int = 2000
const MAX_RATE: float = 1000000.0
const ATTITUDE_MODES: PackedStringArray = ["manual", "kill", "prograde", "retrograde", "normal", "antinormal", "radial_in", "radial_out", "target", "anti_target", "node"]
## Automatic slews cruise with at most this share of wheel capacity in the hull.
## Rotor energy grows with momentum squared, so a slew that fills a wheel ties up
## 5 MJ and loses over 1 MJ to motor inefficiency; a quarter-capacity slew loses ~0.2 MJ.
const SLEW_WHEEL_FRACTION: float = 0.25

var system: OrbitalSystem
var central_body_id: String = "cradle"
var ship: Dictionary = {}
var time: float = 0.0
var rate: float = 1.0
var orientation: Dictionary = {"w": 1.0, "x": 0.0, "y": 0.0, "z": 0.0}
var angular_vel: SimVector = SimVector.new()
var attitude_mode: String = "manual"
var manual_torque: SimVector = SimVector.new()
var reaction_wheel: ShipReactionWheel = ShipReactionWheel.new()
var rate_cap: float = deg_to_rad(20.0)
var attitude_lead_seconds: float = 20.0
var throttle: float = 0.0
var powered_state: Dictionary = {}
var nodes: Array[Dictionary] = []
var executor_on: bool = false
var burn_target_dir: SimVector = null
var burn_delivered: float = 0.0
var warp_auto_limited: bool = false
var pending_maneuver: Dictionary = {}
var targets: Array[Dictionary] = []
var selected_target: int = 0
var next_soi: Dictionary = {}
var _phys_accum: float = 0.0
var _in_burn_window: bool = false
var _cargo_mass_override: float = -1.0
var _local_rv: Dictionary = {}
var _local_control_remaining: float = 0.0
var _local_force: SimVector = SimVector.new()
var _local_torque: SimVector = SimVector.new()


func _init() -> void:
	system = SimConstants.default_system()
	ship = {
		"id": "SHIP-01", "name": "Wayfarer", "dry_mass_kg": 8000.0,
		"propellant_kg": 24000.0, "isp_seconds": 900.0, "thrust_n": 250000.0,
		"inertia": {"ix": 14000.0, "iy": 107000.0, "iz": 107000.0},
		"max_torque_nm": 5500.0,
		"elements": SimConstants.circular_orbit(get_body(), 400000.0, deg_to_rad(51.6)),
		"cargo_capacity_kg": 8000.0, "cargo_capacity_m3": 40.0, "cargo": [],
	}
	targets = [
		{"id": "kestrel", "name": "Kestrel Station", "kind": "station", "body_id": "cradle", "elements": _ring(450.0, 20.0)},
		{"id": "depot", "name": "Depot Six", "kind": "depot", "body_id": "cradle", "elements": _ring(520.0, 75.0)},
		{"id": "ariel", "name": "Probe Ariel", "kind": "probe", "body_id": "cradle", "elements": _ring(360.0, 325.0)},
		{"id": "vesper", "name": "Vesper", "kind": "planet", "body_id": "sol", "transfer_body_id": "vesper", "elements": SimConstants.vesper()["elements"]},
	]
	recompute_next_soi()


## Everything needed to resume this world exactly, except the body hierarchy:
## OrbitalSession.start_session() always rebuilds `system` deterministically, so
## apply_save() is only ever called on a world that already has the right one.
func to_save() -> Dictionary:
	var saved_nodes: Array = []
	for node: Dictionary in nodes:
		saved_nodes.append(SaveCodec.plain(node))
	var saved_targets: Array = []
	for target: Dictionary in targets:
		saved_targets.append(SaveCodec.plain(target))
	return {
		"time": time, "rate": rate, "central_body_id": central_body_id,
		"ship": SaveCodec.plain(ship),
		"orientation": SaveCodec.plain(orientation),
		"angular_vel": SaveCodec.sim_vector(angular_vel),
		"attitude_mode": attitude_mode,
		"manual_torque": SaveCodec.sim_vector(manual_torque),
		"reaction_wheel": reaction_wheel.to_save(),
		"rate_cap": rate_cap, "attitude_lead_seconds": attitude_lead_seconds, "throttle": throttle,
		"powered_state": SaveCodec.plain(powered_state),
		"nodes": saved_nodes,
		"executor_on": executor_on,
		"burn_target_dir": SaveCodec.sim_vector(burn_target_dir) if burn_target_dir != null else null,
		"burn_delivered": burn_delivered, "warp_auto_limited": warp_auto_limited,
		"pending_maneuver": SaveCodec.plain(pending_maneuver),
		"targets": saved_targets, "selected_target": selected_target,
		"next_soi": SaveCodec.plain(next_soi),
		"_phys_accum": _phys_accum, "_in_burn_window": _in_burn_window, "_cargo_mass_override": _cargo_mass_override,
		"_local_rv": SaveCodec.plain(_local_rv),
		"_local_control_remaining": _local_control_remaining,
		"_local_force": SaveCodec.sim_vector(_local_force),
		"_local_torque": SaveCodec.sim_vector(_local_torque),
	}


## Restore state written by to_save(). Never touches `system`; call this only on a
## world whose OrbitalSession.start_session() has already run.
func apply_save(data: Dictionary) -> void:
	time = float(data.get("time", 0.0))
	rate = float(data.get("rate", 1.0))
	central_body_id = str(data.get("central_body_id", central_body_id))
	ship = SaveCodec.unplain(data.get("ship", {})) as Dictionary
	orientation = SaveCodec.unplain(data.get("orientation", orientation)) as Dictionary
	angular_vel = SaveCodec.to_sim_vector(data.get("angular_vel"))
	attitude_mode = str(data.get("attitude_mode", attitude_mode))
	manual_torque = SaveCodec.to_sim_vector(data.get("manual_torque"))
	reaction_wheel.apply_save(data.get("reaction_wheel", {}) as Dictionary)
	rate_cap = float(data.get("rate_cap", rate_cap))
	attitude_lead_seconds = float(data.get("attitude_lead_seconds", attitude_lead_seconds))
	throttle = float(data.get("throttle", 0.0))
	powered_state = SaveCodec.unplain(data.get("powered_state", {})) as Dictionary
	var restored_nodes: Array[Dictionary] = []
	for node: Variant in (data.get("nodes", []) as Array):
		restored_nodes.append(SaveCodec.unplain(node) as Dictionary)
	nodes = restored_nodes
	executor_on = bool(data.get("executor_on", false))
	var saved_burn_dir: Variant = data.get("burn_target_dir")
	burn_target_dir = SaveCodec.to_sim_vector(saved_burn_dir) if saved_burn_dir != null else null
	burn_delivered = float(data.get("burn_delivered", 0.0))
	warp_auto_limited = bool(data.get("warp_auto_limited", false))
	pending_maneuver = SaveCodec.unplain(data.get("pending_maneuver", {})) as Dictionary
	var restored_targets: Array[Dictionary] = []
	for target: Variant in (data.get("targets", []) as Array):
		restored_targets.append(SaveCodec.unplain(target) as Dictionary)
	targets = restored_targets
	selected_target = int(data.get("selected_target", 0))
	next_soi = SaveCodec.unplain(data.get("next_soi", {})) as Dictionary
	_phys_accum = float(data.get("_phys_accum", 0.0))
	_in_burn_window = bool(data.get("_in_burn_window", false))
	_cargo_mass_override = float(data.get("_cargo_mass_override", -1.0))
	_local_rv = SaveCodec.unplain(data.get("_local_rv", {})) as Dictionary
	_local_control_remaining = float(data.get("_local_control_remaining", 0.0))
	_local_force = SaveCodec.to_sim_vector(data.get("_local_force"))
	_local_torque = SaveCodec.to_sim_vector(data.get("_local_torque"))


## Whether it is honest to write a save right now. False only while the main
## engine is actually delivering thrust this instant (throttle open on real
## propellant); an executor armed and coasting toward an unstarted node, or one
## waiting in its approach window for alignment before firing, is fine to save.
func can_save() -> bool:
	return not (throttle > 0.0 and float(ship["propellant_kg"]) > 0.0)


## Resolve the current central body after any sphere-of-influence handoff.
func get_body() -> Dictionary:
	return system.body(central_body_id)


## Return the selected target, or an empty dictionary if the world has none.
func selected_target_def() -> Dictionary:
	if targets.is_empty():
		return {}
	return targets[clampi(selected_target, 0, targets.size() - 1)]


## Return the target's state about its own central body.
func target_state() -> Dictionary:
	var target: Dictionary = selected_target_def()
	if target.is_empty():
		return {}
	return OrbitMath.propagate(target["elements"], system.body(target["body_id"]), time)


## Return the live ship state in the hierarchy's root inertial frame.
func ship_root_state() -> Dictionary:
	var state: Dictionary = current_rv()
	var base: Dictionary = system.body_state_in_root(central_body_id, time)
	return {"position": SimVector.add(base["position"], state["r"]), "velocity": SimVector.add(base["velocity"], state["v"])}


## Return an orbiting target's state in the hierarchy's root inertial frame.
func target_root_state(target: Dictionary) -> Dictionary:
	if target.is_empty() or not system.has(target.get("body_id", "")):
		return {"position": SimVector.new(), "velocity": SimVector.new()}
	var base: Dictionary = system.body_state_in_root(target["body_id"], time)
	var state: Dictionary = OrbitMath.propagate(target["elements"], system.body(target["body_id"]), time)
	return {"position": SimVector.add(base["position"], state["position"]), "velocity": SimVector.add(base["velocity"], state["velocity"])}


## Advance validated real seconds multiplied by warp; excess fixed work is carried.
## Coasting stops at SOI and burn-window boundaries, including inside a large tick.
func advance(real_dt_seconds: float) -> void:
	if not is_finite(real_dt_seconds) or real_dt_seconds < 0.0:
		return
	if not is_finite(rate) or rate <= 0.0 or rate > MAX_RATE:
		return
	if not is_finite(time + _phys_accum + real_dt_seconds * rate):
		return
	_local_rv = {}
	if executor_on:
		_drive_executor()
	_limit_warp_for_soi()
	var delta: float = real_dt_seconds * rate
	if rate > SAFE_WARP:
		var sensitive_in: float = INF
		if executor_on and not nodes.is_empty():
			sensitive_in = maxf(0.0, _burn_window_start(nodes[0]) - time)
		if not next_soi.is_empty():
			sensitive_in = minf(sensitive_in, maxf(0.0, float(next_soi["time"]) - time - SOI_LEAD))
		if delta > sensitive_in:
			delta = sensitive_in + maxf(0.0, real_dt_seconds - sensitive_in / rate) * SAFE_WARP
			rate = SAFE_WARP
			warp_auto_limited = true
	if not is_finite(delta + _phys_accum):
		return
	_phys_accum += delta
	var steps: int = 0
	while _phys_accum > 0.0 and steps < MAX_SUBSTEPS:
		if executor_on:
			_drive_executor()
		var powered: bool = throttle > 0.0 and float(ship["propellant_kg"]) > 0.0
		if not powered and not powered_state.is_empty():
			_fold_to_coast()
		var fixed_needed: bool = powered or _in_burn_window or _attitude_active()
		if not fixed_needed:
			var coast: float = _phys_accum
			if executor_on and not nodes.is_empty():
				coast = minf(coast, maxf(0.0, _burn_window_start(nodes[0]) - time))
			if coast > 1e-9:
				_step_coast_with_soi(coast)
				_phys_accum -= coast
				continue
			# The analytic jump landed on an executor boundary to floating precision.
			_in_burn_window = executor_on
		if _phys_accum + 1e-12 < DT_PHYS:
			break
		if powered:
			if powered_state.is_empty():
				_seed_powered()
			_step_powered_substep()
		else:
			_step_attitude(DT_PHYS)
			_step_coast_with_soi(DT_PHYS)
		_phys_accum = maxf(0.0, _phys_accum - DT_PHYS)
		steps += 1
		if powered and float(ship["propellant_kg"]) <= 0.0:
			throttle = 0.0
			executor_on = false
			_in_burn_window = false
			_fold_to_coast()


## Advance main-drive controls while local physics owns position and attitude.
## Commands are sampled on the same fixed control grid; returned time-averaged
## forces preserve impulse and fuel across fractional local physics frames.
func advance_local(delta: float, r: SimVector, v: SimVector, q: Dictionary, omega_body: SimVector) -> Dictionary:
	var result: Dictionary = {"force_world": SimVector.new(), "torque_body": SimVector.new(), "propellant_kg": ship["propellant_kg"], "throttle": throttle}
	if not is_finite(delta) or delta <= 0.0 or delta > 1.0 or not SimVector.is_finite_vector(r) or not SimVector.is_finite_vector(v) or not SimVector.is_finite_vector(omega_body) or SimVector.length(r) <= 0.0:
		return result
	for component: String in ["w", "x", "y", "z"]:
		if not q.has(component) or not is_finite(float(q[component])):
			return result
	_local_rv = {"r": _copy(r), "v": _copy(v)}
	powered_state = {}
	orientation = FlightMath.q_normalize(q)
	angular_vel = _copy(omega_body)
	ship["elements"] = ManeuverMath.state_to_elements(r, v, get_body(), time)
	var remaining: float = delta
	var impulse: SimVector = SimVector.new()
	var angular_impulse: SimVector = SimVector.new()
	var motor_work_omega: SimVector = _copy(angular_vel)
	while remaining > 1e-12:
		if _local_control_remaining <= 1e-12:
			if executor_on:
				_drive_executor()
			_local_force = SimVector.scale(FlightMath.thrust_axis_world(orientation), float(ship["thrust_n"]) * throttle)
			_local_torque = FlightMath.clamp_magnitude(manual_torque, ship["max_torque_nm"]) if attitude_mode == "manual" else FlightMath.control_torque_body(orientation, angular_vel, attitude_target_dir(), ship["inertia"], ship["max_torque_nm"], _slew_rate_cap())
			_local_control_remaining = DT_PHYS
		var step: float = minf(remaining, _local_control_remaining)
		var thrust: float = SimVector.length(_local_force)
		var exhaust: float = float(ship["isp_seconds"]) * 9.80665
		var requested: float = thrust * step / exhaust if exhaust > 0.0 else 0.0
		var available: float = float(ship["propellant_kg"])
		var spent: float = minf(available, requested)
		var fraction: float = spent / requested if requested > 0.0 else 0.0
		var force_impulse: SimVector = SimVector.scale(_local_force, step * fraction)
		burn_delivered += SimVector.length(force_impulse) / current_mass()
		impulse = SimVector.add(impulse, force_impulse)
		var motor_torque: SimVector = reaction_wheel.drive(_local_torque, motor_work_omega, ship["inertia"], step)
		angular_impulse = SimVector.add(angular_impulse, SimVector.scale(motor_torque, step))
		# The native physics adapter owns passive gyro with the exact inertia
		# tensor. Carry only motor work forward between control fragments.
		motor_work_omega = SimVector.add(motor_work_omega, SimVector.new(motor_torque.x * step / float(ship.inertia.ix), motor_torque.y * step / float(ship.inertia.iy), motor_torque.z * step / float(ship.inertia.iz)))
		ship["propellant_kg"] = available - spent
		time += step
		remaining -= step
		_local_control_remaining -= step
		if float(ship["propellant_kg"]) <= 0.0:
			throttle = 0.0
			executor_on = false
			_in_burn_window = false
			_local_force = SimVector.new()
	result["force_world"] = SimVector.scale(impulse, 1.0 / delta)
	result["torque_body"] = SimVector.scale(angular_impulse, 1.0 / delta)
	result["propellant_kg"] = ship["propellant_kg"]
	result["throttle"] = throttle
	return result


## Refresh local physical truth at the current clock without advancing controls.
## Rendering and physics adapters use this after Jolt has integrated a step.
func refresh_local_state(r: SimVector, v: SimVector, q: Dictionary, omega_body: SimVector) -> bool:
	if not SimVector.is_finite_vector(r) or not SimVector.is_finite_vector(v) or not SimVector.is_finite_vector(omega_body):
		return false
	for component: String in ["w", "x", "y", "z"]:
		if not q.has(component) or not is_finite(float(q[component])):
			return false
	var elements: Dictionary = ManeuverMath.state_to_elements(r, v, get_body(), time)
	if elements.is_empty():
		return false
	_local_rv = {"r": _copy(r), "v": _copy(v)}
	ship["elements"] = elements
	powered_state = {}
	orientation = FlightMath.q_normalize(q)
	angular_vel = _copy(omega_body)
	return true


## Simulated seconds awaiting the fixed integration grid or bounded catch-up work.
func pending_sim_time() -> float:
	return _phys_accum


## Set time warp; invalid or unbounded multipliers leave the previous rate intact.
func set_rate(value: float) -> bool:
	if not is_finite(value) or value < 0.0 or value > MAX_RATE:
		return false
	rate = value
	return true


## Command main-engine throttle, clamped to [0,1]; non-finite input is rejected.
func set_throttle(value: float) -> bool:
	if not is_finite(value):
		return false
	throttle = clampf(value, 0.0, 1.0)
	return true


## Choose a supported body attitude control mode.
func set_attitude_mode(mode: String) -> bool:
	if not ATTITUDE_MODES.has(mode):
		return false
	attitude_mode = mode
	return true


## Command finite body-frame reaction-wheel torque; actual authority is clamped.
func set_manual_torque(value: SimVector) -> bool:
	if not SimVector.is_finite_vector(value):
		return false
	manual_torque = _copy(value)
	return true


## Arm or disengage the maneuver executor. Disengagement always cuts thrust.
func set_executor(enabled: bool) -> void:
	executor_on = enabled
	if not enabled:
		throttle = 0.0
		warp_auto_limited = false
		_in_burn_window = false
		burn_target_dir = null
	else:
		burn_delivered = 0.0


## Replace a coast state after local physics, retaining the same physical r/v.
## This command ends powered integration and discards no accepted elapsed time.
func replace_state(r: SimVector, v: SimVector, body_id: String = "", at_time: float = -1.0) -> bool:
	var frame: String = central_body_id if body_id.is_empty() else body_id
	var epoch: float = time if at_time < 0.0 else at_time
	if not system.has(frame) or not SimVector.is_finite_vector(r) or not SimVector.is_finite_vector(v) or not is_finite(epoch) or SimVector.length(r) <= 0.0:
		return false
	var elements: Dictionary = ManeuverMath.state_to_elements(r, v, system.body(frame), epoch)
	if elements.is_empty() or not is_finite(float(elements.get("a", NAN))):
		return false
	_local_rv = {}
	_local_control_remaining = 0.0
	central_body_id = frame
	time = epoch
	ship["elements"] = elements
	powered_state = {}
	recompute_next_soi()
	return true


## Synchronize finite propellant and carried inert mass from the shared ship API.
func sync_mass(propellant_kg: float, cargo_mass_kg: float, dry_mass_kg: float = -1.0) -> bool:
	if not is_finite(propellant_kg) or propellant_kg < 0.0 or not is_finite(cargo_mass_kg) or cargo_mass_kg < 0.0:
		return false
	if not is_finite(dry_mass_kg) or (dry_mass_kg != -1.0 and dry_mass_kg <= 0.0):
		return false
	ship["propellant_kg"] = propellant_kg
	_cargo_mass_override = cargo_mass_kg
	if dry_mass_kg > 0.0:
		ship["dry_mass_kg"] = dry_mass_kg
	if not powered_state.is_empty():
		powered_state["m"] = structural_mass_kg() + propellant_kg
	return true


## Coast to the next node's approach window, crossing every intervening SOI.
## A lit engine cannot be skipped; disengage it before requesting a coast jump.
func jump_to_next_node() -> bool:
	if nodes.is_empty() or throttle > 0.0 or not powered_state.is_empty():
		return false
	var node: Dictionary = nodes[0]
	var handoff_before: bool = not next_soi.is_empty() and float(next_soi["time"]) < float(node["time"])
	if node.has("retarget") and not handoff_before:
		_resolve_retarget(node)
	var duration: float = FlightMath.dv_magnitude(node["dv_local"]) / maxf(1e-9, float(ship["thrust_n"]) / current_mass())
	var arrive: float = float(node["time"]) - duration * 0.5 - 25.0
	if arrive > time:
		_step_coast_with_soi(arrive - time)
	_phys_accum = 0.0
	executor_on = true
	return true


## Refresh the earliest escape/capture event after an orbit or frame change.
func recompute_next_soi() -> void:
	next_soi = _compute_next_soi()


## Re-express the live state about another body without a position/velocity jump.
func transition_to(new_body_id: String, at_time: float) -> bool:
	if not system.has(new_body_id) or not is_finite(at_time):
		return false
	var state: Dictionary = current_rv() if at_time == time else _rv_at(at_time)
	var relative: Dictionary = system.relative_state(new_body_id, central_body_id, at_time)
	var r: SimVector = SimVector.add(relative["position"], state["r"])
	var v: SimVector = SimVector.add(relative["velocity"], state["v"])
	var elements: Dictionary = ManeuverMath.state_to_elements(r, v, system.body(new_body_id), at_time)
	if elements.is_empty():
		return false
	central_body_id = new_body_id
	ship["elements"] = elements
	time = at_time
	if not powered_state.is_empty():
		powered_state["r"] = r
		powered_state["v"] = v
	recompute_next_soi()
	return true


## Coast to 25 seconds before the next sphere-of-influence handoff.
func jump_to_next_soi() -> bool:
	if next_soi.is_empty() or throttle > 0.0 or not powered_state.is_empty():
		return false
	var arrive: float = float(next_soi["time"]) - 25.0
	if arrive > time:
		_step_coast_with_soi(arrive - time)
	_phys_accum = 0.0
	return true


## World thrust-axis target for the active directional hold; null means no target.
func attitude_target_dir() -> SimVector:
	if attitude_mode == "manual":
		return null
	if attitude_mode == "node":
		return burn_target_dir
	if attitude_mode == "kill":
		return FlightMath.thrust_axis_world(orientation)
	var rv: Dictionary = current_rv()
	if attitude_mode == "target" or attitude_mode == "anti_target":
		if selected_target_def().is_empty():
			return null
		var target: SimVector = target_root_state(selected_target_def())["position"]
		var position: SimVector = ship_root_state()["position"]
		var relative: SimVector = SimVector.sub(target, position)
		var distance: float = SimVector.length(relative)
		if distance < 1e-6:
			return null
		return SimVector.scale(relative, (-1.0 if attitude_mode == "anti_target" else 1.0) / distance)
	return FlightMath.heading_dir(attitude_mode, rv["r"], rv["v"])


## Angular pointing error between the main-engine axis and a world unit vector.
func pointing_error(target: SimVector) -> float:
	if target == null or SimVector.length(target) < 1e-12:
		return 0.0
	var axis: SimVector = FlightMath.thrust_axis_world(orientation)
	return acos(clampf(SimVector.dot(axis, target) / SimVector.length(target), -1.0, 1.0))


## Cargo mass [kg], including a physical ship API override when supplied.
func cargo_mass_kg() -> float:
	if _cargo_mass_override >= 0.0:
		return _cargo_mass_override
	var total: float = 0.0
	for item: Dictionary in ship["cargo"]:
		total += float(item["mass_kg"]) * float(item.get("qty", 1.0))
	return total


## Cargo volume [m³] from manifest entries, independently of their mass.
func cargo_volume_m3() -> float:
	var total: float = 0.0
	for item: Dictionary in ship["cargo"]:
		total += float(item["volume_m3"]) * float(item.get("qty", 1.0))
	return total


## Non-propellant mass [kg] used as the rocket-equation burnout floor.
func structural_mass_kg() -> float:
	return float(ship["dry_mass_kg"]) + cargo_mass_kg()


## Live total mass [kg], including dry hull, cargo and remaining propellant.
func current_mass() -> float:
	return float(powered_state["m"]) if not powered_state.is_empty() else structural_mass_kg() + float(ship["propellant_kg"])


## Live central-body position and velocity, copied to protect authoritative state.
func current_rv() -> Dictionary:
	if not _local_rv.is_empty():
		return {"r": _copy(_local_rv["r"]), "v": _copy(_local_rv["v"])}
	if not powered_state.is_empty():
		return {"r": _copy(powered_state["r"]), "v": _copy(powered_state["v"])}
	return _rv_at(time)


## Orbital telemetry from the live osculating conic, including during a burn.
func orbit() -> Dictionary:
	return OrbitMath.propagate(current_elements(), get_body(), time)


## Predict the current osculating conic at absolute simulation time [s].
func orbit_at(at_time: float) -> Dictionary:
	if not is_finite(at_time):
		return {}
	return OrbitMath.propagate(current_elements(), get_body(), at_time)


## Return a copied coast conic or derive it from the live integrated state.
func current_elements() -> Dictionary:
	if not powered_state.is_empty():
		return ManeuverMath.state_to_elements(powered_state["r"], powered_state["v"], get_body(), time)
	return (ship["elements"] as Dictionary).duplicate(true)


func _ring(altitude_km: float, phase_degrees: float) -> Dictionary:
	var elements: Dictionary = SimConstants.circular_orbit(get_body(), altitude_km * 1000.0, deg_to_rad(51.6))
	elements["mean_anomaly_at_epoch"] = deg_to_rad(phase_degrees)
	return elements


func _resolve_retarget(node: Dictionary) -> void:
	var retarget: Dictionary = node.get("retarget", {})
	if retarget.is_empty():
		return
	var state: Dictionary = OrbitMath.propagate(ship["elements"], get_body(), node["time"])
	var dv_world: SimVector = SimVector.new()
	if retarget["kind"] == "match":
		var target: Dictionary = OrbitMath.propagate(retarget["target_el"], get_body(), node["time"])
		dv_world = SimVector.sub(target["velocity"], state["velocity"])
	else:
		var tof: float = float(retarget["arrival_time"]) - float(node["time"])
		var arrival: Dictionary = OrbitMath.propagate(retarget["target_el"], get_body(), retarget["arrival_time"])
		var solution: Dictionary = {}
		if tof > 0.0:
			solution = OrbitalSolvers.best_transfer(state["position"], arrival["position"], tof, get_body()["mu"], state["velocity"], arrival["velocity"], retarget.get("max_revs", 4))
		if not solution.is_empty():
			dv_world = SimVector.sub(solution["v1"], state["velocity"])
	var magnitude: float = SimVector.length(dv_world)
	var budget: float = ManeuverMath.dv_budget(ship["propellant_kg"], structural_mass_kg(), ship["isp_seconds"])
	node["dv_local"] = FlightMath.world_dv_to_local(dv_world, state["position"], state["velocity"]) if is_finite(magnitude) and magnitude <= budget else {"prograde": 0.0, "normal": 0.0, "radial": 0.0}
	node.erase("retarget")


func _drive_executor() -> void:
	if nodes.is_empty():
		executor_on = false
		throttle = 0.0
		warp_auto_limited = false
		_in_burn_window = false
		return
	var node: Dictionary = nodes[0]
	var handoff_pending: bool = not next_soi.is_empty() and float(next_soi["time"]) < float(node["time"]) - 1e-9
	if node.has("retarget") and powered_state.is_empty() and not handoff_pending:
		_resolve_retarget(node)
	var magnitude: float = FlightMath.dv_magnitude(node["dv_local"])
	var accel: float = float(ship["thrust_n"]) / current_mass()
	var duration: float = magnitude / accel if accel > 0.0 else 0.0
	var burn_start: float = float(node["time"]) - duration * 0.5
	var rv: Dictionary = current_rv()
	burn_target_dir = FlightMath.node_world_dir(node["dv_local"], rv["r"], rv["v"])
	# Far from a node, coast analytically; the approach window owns the slew.
	var in_window: bool = time + 1e-9 >= burn_start - maxf(attitude_lead_seconds, duration)
	_in_burn_window = in_window
	if in_window:
		attitude_mode = "node"
	elif attitude_mode == "node":
		attitude_mode = "kill"
	warp_auto_limited = in_window and rate > SAFE_WARP
	if warp_auto_limited:
		rate = SAFE_WARP
	var aligned: bool = pointing_error(burn_target_dir) < deg_to_rad(2.0)
	if time >= burn_start and burn_delivered >= magnitude:
		nodes.pop_front()
		burn_delivered = 0.0
		throttle = 0.0
		burn_target_dir = null
		attitude_mode = "kill"
		if nodes.is_empty():
			executor_on = false
			attitude_mode = "kill"
			_in_burn_window = false
		return
	throttle = 1.0 if time >= burn_start and aligned and burn_delivered < magnitude else 0.0


func _burn_window_start(node: Dictionary) -> float:
	var duration: float = FlightMath.dv_magnitude(node["dv_local"]) / maxf(1e-9, float(ship["thrust_n"]) / current_mass())
	return float(node["time"]) - duration * 0.5 - maxf(attitude_lead_seconds, duration)


func _compute_next_soi() -> Dictionary:
	var current: Dictionary = get_body()
	var best: Dictionary = {}
	if current.get("parent_id") != null and current.get("soi_radius") != null:
		var escape: Variant = OrbitMath.next_escape_time(ship["elements"], current, time, current["soi_radius"])
		if escape != null and float(escape) > time + 1e-7:
			best = {"time": float(escape), "to_body_id": current["parent_id"]}
	var horizon_end: float = float(best["time"]) if not best.is_empty() else time + _capture_horizon()
	for child: Dictionary in system.children(central_body_id):
		if child.get("soi_radius") == null:
			continue
		var capture: float = _next_capture_time(child, time, horizon_end)
		if is_finite(capture) and (best.is_empty() or capture < float(best["time"])):
			best = {"time": capture, "to_body_id": child["id"]}
	return best


func _capture_horizon() -> float:
	var state: Dictionary = OrbitMath.propagate(ship["elements"], get_body(), time)
	return float(state["period"]) if is_finite(float(state["period"])) else 5e8


func _next_capture_time(child: Dictionary, from_time: float, to_time: float) -> float:
	var soi: float = child["soi_radius"]
	var span: float = to_time - from_time
	if span <= 0.0:
		return INF
	var dt: float = span / float(CAPTURE_SAMPLES)
	var previous: float = _child_distance(child["id"], from_time)
	for sample: int in range(1, CAPTURE_SAMPLES + 1):
		var at_time: float = from_time + float(sample) * dt
		var distance: float = _child_distance(child["id"], at_time)
		if previous >= soi and distance < soi:
			var lo: float = at_time - dt
			var hi: float = at_time
			for iteration: int in range(50):
				var mid: float = (lo + hi) * 0.5
				if _child_distance(child["id"], mid) < soi:
					hi = mid
				else:
					lo = mid
			return hi
		previous = distance
	return INF


func _child_distance(child_id: String, at_time: float) -> float:
	var position: SimVector = OrbitMath.propagate(ship["elements"], get_body(), at_time)["position"]
	var child: SimVector = system.relative_state(central_body_id, child_id, at_time)["position"]
	return SimVector.length(SimVector.sub(position, child))


func _limit_warp_for_soi() -> void:
	if executor_on or _in_burn_window or not powered_state.is_empty():
		return
	if not next_soi.is_empty() and float(next_soi["time"]) - time <= SOI_LEAD:
		if rate > SAFE_WARP:
			rate = SAFE_WARP
			warp_auto_limited = true
	elif warp_auto_limited:
		warp_auto_limited = false


func _step_coast_with_soi(delta: float) -> void:
	var remaining: float = delta
	var guard: int = 0
	while remaining > 0.0 and guard < 64:
		guard += 1
		if not next_soi.is_empty() and float(next_soi["time"]) <= time + remaining + 1e-9:
			var until_event: float = maxf(0.0, float(next_soi["time"]) - time)
			time += until_event
			remaining = maxf(0.0, remaining - until_event)
			var destination: String = next_soi["to_body_id"]
			if not transition_to(destination, time):
				return
			if not next_soi.is_empty() and float(next_soi["time"]) <= time + 1e-9:
				return
		else:
			time += remaining
			remaining = 0.0


func _seed_powered() -> void:
	var state: Dictionary = _rv_at(time)
	powered_state = {"r": state["r"], "v": state["v"], "m": structural_mass_kg() + float(ship["propellant_kg"])}


func _fold_to_coast() -> void:
	ship["elements"] = ManeuverMath.state_to_elements(powered_state["r"], powered_state["v"], get_body(), time)
	powered_state = {}
	recompute_next_soi()


func _step_powered_substep() -> void:
	_step_attitude(DT_PHYS)
	var direction: SimVector = FlightMath.thrust_axis_world(orientation)
	var mass_before: float = powered_state["m"]
	var structural: float = structural_mass_kg()
	powered_state = FlightMath.step_powered(powered_state, get_body(), direction, throttle, {"thrust_n": ship["thrust_n"], "isp_seconds": ship["isp_seconds"]}, structural, DT_PHYS)
	# Rocket-equation delivery accounts for a partial final fuel-limited substep.
	var spent: float = maxf(0.0, mass_before - float(powered_state["m"]))
	var requested: float = float(ship["thrust_n"]) * throttle * DT_PHYS / (float(ship["isp_seconds"]) * 9.80665)
	var fraction: float = minf(1.0, spent / requested) if requested > 0.0 else 0.0
	burn_delivered += float(ship["thrust_n"]) * throttle / mass_before * DT_PHYS * fraction
	ship["propellant_kg"] = maxf(0.0, float(powered_state["m"]) - structural)
	time += DT_PHYS
	_check_powered_soi()


func _check_powered_soi() -> void:
	var body: Dictionary = get_body()
	if body.get("soi_radius") != null and body.get("parent_id") != null and SimVector.length(powered_state["r"]) > float(body["soi_radius"]):
		transition_to(body["parent_id"], time)
		return
	for child: Dictionary in system.children(central_body_id):
		var state: Dictionary = system.relative_state(central_body_id, child["id"], time)
		if child.get("soi_radius") != null and SimVector.length(SimVector.sub(powered_state["r"], state["position"])) < float(child["soi_radius"]):
			transition_to(child["id"], time)
			return


## Slew rate [rad/s] whose momentum in the heaviest transverse axis stays within the wheel share.
func _slew_rate_cap() -> float:
	var inertia: float = maxf(float(ship.inertia.iy), float(ship.inertia.iz))
	return minf(rate_cap, SLEW_WHEEL_FRACTION * reaction_wheel.capacity_nms / maxf(1.0, inertia))


func _attitude_active() -> bool:
	if attitude_mode == "manual":
		return SimVector.length(angular_vel) > 1e-12 or SimVector.length(manual_torque) > 0.0
	if attitude_mode == "kill" and SimVector.length(angular_vel) < 1e-9:
		angular_vel = SimVector.new()
		return false
	if attitude_mode == "node" and burn_target_dir == null:
		return SimVector.length(angular_vel) > 1e-12
	return true


func _step_attitude(dt: float) -> void:
	var torque: SimVector = FlightMath.clamp_magnitude(manual_torque, ship["max_torque_nm"]) if attitude_mode == "manual" else FlightMath.control_torque_body(orientation, angular_vel, attitude_target_dir(), ship["inertia"], ship["max_torque_nm"], _slew_rate_cap())
	var motor_torque: SimVector = reaction_wheel.drive(torque, angular_vel, ship["inertia"], dt)
	var after_motor: SimVector = SimVector.add(angular_vel, SimVector.new(motor_torque.x * dt / float(ship.inertia.ix), motor_torque.y * dt / float(ship.inertia.iy), motor_torque.z * dt / float(ship.inertia.iz)))
	var next: Dictionary = reaction_wheel.integrate_passive(orientation, after_motor, ship["inertia"], dt)
	orientation = next["q"]
	angular_vel = next["omega"]


func _rv_at(at_time: float) -> Dictionary:
	var state: Dictionary = OrbitMath.propagate(ship["elements"], get_body(), at_time)
	return {"r": state["position"], "v": state["velocity"]}


static func _copy(value: SimVector) -> SimVector:
	return SimVector.new(value.x, value.y, value.z)
