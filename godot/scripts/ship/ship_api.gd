## The shared, node-free boundary for ship commands and copied telemetry in SI units.
class_name ShipApi
extends RefCounted

signal changed()
signal command_requested(command: String, args: Dictionary)

const DRY_MASS_KG: float = 8000.0
const PROPELLANT_CAPACITY_KG: float = 2000.0
const BATTERY_CAPACITY_J: float = 20000000.0
const CARGO_CAPACITY_M3: float = 50.4
const DOOR_SIZE_M: Vector2 = Vector2(2.2, 2.2)
const BAY_SIZE_M: Vector3 = Vector3(3.6, 2.8, 5.0)
const DOOR_ENERGY_J: float = 1000.0

var last_message: String:
	get:
		return _last_message

var _propellant_kg: float = PROPELLANT_CAPACITY_KG
var _battery_energy_j: float = BATTERY_CAPACITY_J
var _cargo_door_open: bool = false
var _airlock_inner_open: bool = true
var _airlock_outer_open: bool = false
var _braking: bool = false
var _last_message: String = "SHIP READY"
var _systems: Dictionary = {
	"hull": {"health": 1.0, "enabled": true},
	"rcs": {"health": 1.0, "enabled": true},
	"reaction_wheel": {"health": 1.0, "enabled": true},
	"power": {"health": 1.0, "enabled": true},
	"cargo": {"health": 1.0, "enabled": true},
	"airlock": {"health": 1.0, "enabled": true},
	"sensors": {"health": 1.0, "enabled": true},
	"solar": {"health": 1.0, "enabled": true},
}
var _manifest: Array[Dictionary] = []
var _motion: Dictionary = {
	"position_m": Vector3.ZERO,
	"velocity_mps": Vector3.ZERO,
	"angular_velocity_radps": Vector3.ZERO,
	"range_m": 0.0,
	"relative_velocity_mps": Vector3.ZERO,
	"local_frame": "SALVAGE PRACTICE",
	"orbital_available": false,
}
var _door_validator: Callable = Callable()
var _flight_handler: Callable = Callable()
var _flight: Dictionary = {"available": false}
var _main_propellant_kg: float = 0.0
var _main_capacity_kg: float = 0.0
var _solar_power_w: float = 0.0
var _solar_sunlit: bool = false


## Return an independent snapshot; clients cannot change the ship through dictionaries.
func get_telemetry() -> Dictionary:
	var cargo_mass: float = 0.0
	var cargo_volume: float = 0.0
	for entry: Dictionary in _manifest:
		cargo_mass += float(entry["mass_kg"])
		cargo_volume += float(entry["volume_m3"])
	var health: float = 0.0
	for state: Dictionary in _systems.values():
		health += float(state["health"])
	health /= float(_systems.size())
	return {
		"ship_name": "WAYFARER",
		"dry_mass_kg": DRY_MASS_KG,
		"mass_kg": DRY_MASS_KG + _propellant_kg + _main_propellant_kg + cargo_mass,
		"propellant_kg": _propellant_kg,
		"main_propellant_kg": _main_propellant_kg,
		"flight": _flight.duplicate(true),
		"battery_energy_j": _battery_energy_j,
		"ship_health": health,
		"systems": _systems.duplicate(true),
		"cargo_door_open": _cargo_door_open,
		"airlock_inner_open": _airlock_inner_open,
		"airlock_outer_open": _airlock_outer_open,
		"braking": _braking,
		"cargo_mass_kg": cargo_mass,
		"cargo_volume_m3": cargo_volume,
		"cargo_capacity_m3": CARGO_CAPACITY_M3,
		"door_size_m": DOOR_SIZE_M,
		"bay_size_m": BAY_SIZE_M,
		"cargo_manifest": _manifest.duplicate(true),
		"motion": _motion.duplicate(true),
		"power_available": _has_power(),
		"solar_power_w": _solar_power_w,
		"solar_sunlit": _solar_sunlit,
		"last_message": _last_message,
	}


## Install the owning scene's clearance check; an invalid callable removes it.
func set_door_validator(validator: Callable) -> void:
	_door_validator = validator


## Open or close the cargo hatch, subject to power, health, and physical clearance.
func set_cargo_door(opening: bool) -> bool:
	if opening == _cargo_door_open:
		return true
	if not _can_move_door("cargo", opening):
		return false
	_cargo_door_open = opening
	_spend_door_energy()
	_publish_command("set_cargo_door", {"open": opening}, "CARGO DOOR OPEN" if opening else "CARGO DOOR CLOSED")
	return true


## Move one airlock door; the interlock never allows both doors to be open.
func set_airlock_door(which: String, opening: bool) -> bool:
	if which != "inner" and which != "outer":
		return _reject("UNKNOWN AIRLOCK DOOR")
	var current: bool = _airlock_inner_open if which == "inner" else _airlock_outer_open
	if current == opening:
		return true
	var other_open: bool = _airlock_outer_open if which == "inner" else _airlock_inner_open
	if opening and other_open:
		return _reject("CLOSE THE OTHER AIRLOCK DOOR FIRST")
	if not _can_move_door(which, opening):
		return false
	if which == "inner":
		_airlock_inner_open = opening
	else:
		_airlock_outer_open = opening
	_spend_door_energy()
	_publish_command("set_airlock_door", {"which": which, "open": opening}, "%s AIRLOCK %s" % [which.to_upper(), "OPEN" if opening else "CLOSED"])
	return true


## Command the ship's local-frame RCS brake; releasing it is always permitted.
func set_braking(enabled: bool) -> bool:
	if enabled and (not _system_working("rcs") or not _has_power() or _propellant_kg <= 0.0):
		return _reject("RCS BRAKE UNAVAILABLE: CHECK POWER, RCS AND PROPELLANT")
	if _braking == enabled:
		return true
	_braking = enabled
	_publish_command("set_braking", {"enabled": enabled}, "SHIP BRAKE ON" if enabled else "SHIP COASTING")
	return true


## Toggle a known system; damage cannot be repaired by cycling its switch.
func set_system_enabled(id: String, enabled: bool) -> bool:
	if not _systems.has(id):
		return _reject("UNKNOWN SYSTEM")
	var state: Dictionary = _systems[id]
	if enabled and float(state["health"]) <= 0.0:
		return _reject("%s DESTROYED" % id.to_upper())
	if bool(state["enabled"]) == enabled:
		return true
	state["enabled"] = enabled
	_refresh_brake()
	_publish_command("set_system_enabled", {"id": id, "enabled": enabled}, "%s %s" % [id.to_upper(), "ON" if enabled else "OFF"])
	return true


## The owning physics scene publishes local motion; no orbital values are invented.
func set_motion(position: Vector3, velocity: Vector3, angular: Vector3, target_position: Vector3, target_velocity: Vector3) -> void:
	if not position.is_finite() or not velocity.is_finite() or not angular.is_finite() or not target_position.is_finite() or not target_velocity.is_finite():
		return
	var distance: float = position.distance_to(target_position)
	var relative: Vector3 = target_velocity - velocity
	if not is_finite(distance) or not relative.is_finite():
		return
	_motion["position_m"] = position
	_motion["velocity_mps"] = velocity
	_motion["angular_velocity_radps"] = angular
	_motion["range_m"] = distance
	_motion["relative_velocity_mps"] = relative
	changed.emit()


## The owning physics scene receives only the propellant actually available.
func consume_propellant(request_kg: float) -> float:
	if not is_finite(request_kg) or request_kg <= 0.0:
		return 0.0
	var supplied: float = minf(request_kg, _propellant_kg)
	_propellant_kg -= supplied
	_refresh_brake()
	if supplied > 0.0:
		changed.emit()
	return supplied


## The owning scene receives only the energy actually available, never a negative store.
func consume_energy(request_j: float) -> float:
	if not is_finite(request_j) or request_j <= 0.0:
		return 0.0
	var supplied: float = minf(request_j, _battery_energy_j)
	_battery_energy_j -= supplied
	_refresh_brake()
	if supplied > 0.0:
		changed.emit()
	return supplied


## Accept recovered electrical energy up to battery capacity; excess becomes heat.
func store_energy(recovered_j: float) -> float:
	if not is_finite(recovered_j) or recovered_j <= 0.0:
		return 0.0
	var stored: float = minf(recovered_j, BATTERY_CAPACITY_J - _battery_energy_j)
	_battery_energy_j += stored
	if stored > 0.0:
		changed.emit()
	return stored


## Apply normalized system damage and return the health actually lost.
func apply_damage(system: String, amount: float) -> float:
	if not _systems.has(system) or not is_finite(amount) or amount <= 0.0:
		return 0.0
	var state: Dictionary = _systems[system]
	var lost: float = minf(float(state["health"]), amount)
	state["health"] = float(state["health"]) - lost
	if float(state["health"]) <= 0.0:
		state["enabled"] = false
	_refresh_brake()
	if lost > 0.0:
		_last_message = "%s DAMAGED" % system.to_upper()
		changed.emit()
	return lost


## Assess projected bay-local dimensions, mass, occupied volume, and duplicate identity.
func assess_cargo(id: String, size_in_bay: Vector3, mass_kg: float, volume_m3: float) -> Dictionary:
	if id.strip_edges().is_empty():
		return _assessment(false, "CARGO HAS NO ID")
	for entry: Dictionary in _manifest:
		if String(entry["id"]) == id:
			return _assessment(false, "CARGO ALREADY ABOARD")
	if not size_in_bay.is_finite() or size_in_bay.x <= 0.0 or size_in_bay.y <= 0.0 or size_in_bay.z <= 0.0 or not is_finite(mass_kg) or mass_kg <= 0.0 or not is_finite(volume_m3) or volume_m3 <= 0.0:
		return _assessment(false, "INVALID CARGO DIMENSIONS OR MASS")
	if not _cargo_door_open:
		return _assessment(false, "OPEN CARGO DOOR FIRST")
	if not _system_working("cargo"):
		return _assessment(false, "CARGO SYSTEM UNAVAILABLE")
	if not _has_power():
		return _assessment(false, "CARGO CLAMPS NEED SHIP POWER")
	if size_in_bay.x > DOOR_SIZE_M.x or size_in_bay.y > DOOR_SIZE_M.y:
		return _assessment(false, "PART DOES NOT FIT THROUGH DOOR: ROTATE OR CUT SMALLER")
	if size_in_bay.x > BAY_SIZE_M.x or size_in_bay.y > BAY_SIZE_M.y or size_in_bay.z > BAY_SIZE_M.z:
		return _assessment(false, "PART DOES NOT FIT INSIDE BAY")
	var occupied: float = 0.0
	var loaded_mass: float = DRY_MASS_KG + _propellant_kg + _main_propellant_kg
	for entry: Dictionary in _manifest:
		occupied += float(entry["volume_m3"])
		loaded_mass += float(entry["mass_kg"])
	if occupied + volume_m3 > CARGO_CAPACITY_M3:
		return _assessment(false, "CARGO BAY FULL")
	if not is_finite(loaded_mass + mass_kg):
		return _assessment(false, "INVALID CARGO MASS")
	return _assessment(true, "CARGO FITS")


## The owning scene records a secured physical part after checking its current fit.
func register_cargo(id: String, size_in_bay: Vector3, mass_kg: float, volume_m3: float, details: Dictionary = {}) -> bool:
	var assessment: Dictionary = assess_cargo(id, size_in_bay, mass_kg, volume_m3)
	if not bool(assessment["ok"]):
		return _reject(String(assessment["reason"]))
	var entry: Dictionary = details.duplicate(true)
	entry.merge({"id": id, "size_m": size_in_bay, "mass_kg": mass_kg, "volume_m3": volume_m3}, true)
	_manifest.append(entry)
	_last_message = "CARGO SECURED: %s" % id
	changed.emit()
	return true


## The owning scene removes a released part from the mass and volume ledger.
func remove_cargo(id: String) -> bool:
	for index in _manifest.size():
		if String(_manifest[index]["id"]) == id:
			_manifest.remove_at(index)
			_last_message = "CARGO RELEASED: %s" % id
			changed.emit()
			return true
	return false


## Publish cargo arrival or obstruction feedback from the owning scene.
func set_cargo_message(message: String) -> void:
	if message == _last_message:
		return
	_last_message = message
	changed.emit()


## Publish instantaneous solar-array output [W] and whether the Sun is unshadowed.
func publish_solar(power_w: float, sunlit: bool) -> void:
	if not is_finite(power_w) or power_w < 0.0:
		return
	if absf(power_w - _solar_power_w) < 0.05 and sunlit == _solar_sunlit:
		return
	_solar_power_w = power_w
	_solar_sunlit = sunlit
	changed.emit()


func _system_working(id: String) -> bool:
	var state: Dictionary = _systems[id]
	return bool(state["enabled"]) and float(state["health"]) > 0.0


func _has_power() -> bool:
	return _system_working("power") and _battery_energy_j > 0.0


func _refresh_brake() -> void:
	if not _system_working("rcs") or not _has_power() or _propellant_kg <= 0.0:
		_braking = false


func _can_move_door(door: String, opening: bool) -> bool:
	var system: String = "cargo" if door == "cargo" else "airlock"
	if not _system_working(system):
		return _reject("%s SYSTEM UNAVAILABLE" % system.to_upper())
	if not _has_power() or _battery_energy_j < DOOR_ENERGY_J:
		return _reject("INSUFFICIENT POWER TO MOVE DOOR")
	if _door_validator.is_valid() and not bool(_door_validator.call(door, opening)):
		return _reject("DOOR BLOCKED: CLEAR THE OPENING")
	return true


func _spend_door_energy() -> void:
	_battery_energy_j -= DOOR_ENERGY_J
	_refresh_brake()


func _publish_command(command: String, args: Dictionary, message: String) -> void:
	_last_message = message
	command_requested.emit(command, args)
	changed.emit()


func _reject(message: String) -> bool:
	_last_message = message
	changed.emit()
	return false


func _assessment(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}


## Bind flight commands to the owning orbital session; no app accesses its internals.
func bind_flight(handler: Callable, main_capacity_kg: float = 24000.0) -> void:
	_flight_handler = handler
	if is_finite(main_capacity_kg) and main_capacity_kg >= 0.0:
		_main_capacity_kg = main_capacity_kg
		_main_propellant_kg = main_capacity_kg


## Publish an independent SI snapshot and the authoritative main-drive fuel store.
func publish_flight(snapshot: Dictionary, main_propellant_kg: float) -> void:
	if not is_finite(main_propellant_kg) or main_propellant_kg < 0.0:
		return
	_flight = snapshot.duplicate(true)
	_main_propellant_kg = minf(main_propellant_kg, _main_capacity_kg)
	changed.emit()


## Send a flight command through the same validation path for every client.
func flight_command(command: String, arguments: Dictionary = {}) -> bool:
	if not _flight_handler.is_valid():
		return _reject("FLIGHT COMPUTER UNAVAILABLE")
	var releasing_rcs: bool = command == "rcs_translate" and arguments.get("direction") is Vector3 and arguments["direction"] == Vector3.ZERO
	# STOP ROTATION stays available on a flat battery: wheel braking can pay for itself.
	var stopping_rotation: bool = command == "set_attitude_mode" and str(arguments.get("mode", "")) == "kill" and _system_working("power")
	if not _has_power() and not releasing_rcs and not stopping_rotation and command not in ["cutoff", "cancel_plan", "set_warp"]:
		return _reject("FLIGHT CONTROLS NEED SHIP POWER")
	var result: Dictionary = _flight_handler.call(command, arguments.duplicate(true))
	if not bool(result.get("ok", false)):
		return _reject(str(result.get("message", "FLIGHT COMMAND REJECTED")))
	_publish_command(command, arguments, str(result.get("message", "FLIGHT COMMAND ACCEPTED")))
	return true


## Command main-engine throttle as a fraction of full thrust.
func set_throttle(throttle: float) -> bool:
	return flight_command("set_throttle", {"throttle": throttle})


## Select a bounded, validated simulation time multiplier.
func set_warp(rate: float) -> bool:
	return flight_command("set_warp", {"rate": rate})


## Ask the attitude controller to point or stop rotation.
func set_attitude_mode(mode: String) -> bool:
	return flight_command("set_attitude_mode", {"mode": mode})


## Choose an orbital target by its stable session identifier.
func select_target(id: String) -> bool:
	return flight_command("select_target", {"id": id})


## Calculate a transfer and velocity match, leaving the preview unexecuted.
func plan_intercept(tof_seconds: float) -> bool:
	return flight_command("plan_intercept", {"tof_seconds": tof_seconds})


## Preview a custom maneuver in the orbital prograde/normal/radial frame.
func plan_maneuver(time: float, prograde: float, normal: float, radial: float) -> bool:
	return flight_command("plan_maneuver", {"time": time, "dv_local": {"prograde": prograde, "normal": normal, "radial": radial}})


## Commit the currently previewed plan to the finite-burn executor.
func execute_plan() -> bool:
	return flight_command("execute_plan")


## Cancel pending and executing nodes, cutting main thrust immediately.
func cancel_plan() -> bool:
	return flight_command("cancel_plan")


## Coast toward the next event while respecting nearby objects and burn windows.
func advance_to_next_event() -> bool:
	return flight_command("next_event")


## Translate with the ship's finite local RCS, in right/up/back body axes.
func set_rcs_translation(direction: Vector3) -> bool:
	if not direction.is_finite():
		return _reject("INVALID RCS DIRECTION")
	return flight_command("rcs_translate", {"direction": direction.limit_length(1.0)})


## Everything this class owns that must survive a save: RCS propellant, battery,
## door and airlock positions, every system's health/enabled flag, the cargo
## manifest, and the main-drive propellant mirrored in from the flight session.
## Skips Callables (_door_validator, _flight_handler — rebuilt by the owning
## scene) and the per-frame published snapshots (_motion, _flight, solar
## readings), which the next physics tick republishes anyway. Also skips
## _main_capacity_kg (an owner-set rating from bind_flight(), not this class's
## own state) and _last_message (status text, not ship state).
func to_save() -> Dictionary:
	return {
		"propellant_kg": _propellant_kg,
		"battery_energy_j": _battery_energy_j,
		"cargo_door_open": _cargo_door_open,
		"airlock_inner_open": _airlock_inner_open,
		"airlock_outer_open": _airlock_outer_open,
		"braking": _braking,
		"systems": _systems.duplicate(true),
		"cargo_manifest": SaveCodec.plain(_manifest),
		"main_propellant_kg": _main_propellant_kg,
	}


## Restore saved ship state. Health clamps to [0,1], propellant and battery clamp
## to their tank capacities, the airlock interlock is re-enforced rather than
## trusted, and the brake is rechecked against the restored power/RCS/propellant
## state instead of taken on faith.
func apply_save(data: Dictionary) -> void:
	_propellant_kg = clampf(float(data.get("propellant_kg", _propellant_kg)), 0.0, PROPELLANT_CAPACITY_KG)
	_battery_energy_j = clampf(float(data.get("battery_energy_j", _battery_energy_j)), 0.0, BATTERY_CAPACITY_J)
	_cargo_door_open = bool(data.get("cargo_door_open", _cargo_door_open))
	_airlock_inner_open = bool(data.get("airlock_inner_open", _airlock_inner_open))
	_airlock_outer_open = bool(data.get("airlock_outer_open", _airlock_outer_open)) and not _airlock_inner_open
	var loaded_systems: Variant = data.get("systems", {})
	if loaded_systems is Dictionary:
		for id: String in (loaded_systems as Dictionary).keys():
			if not _systems.has(id):
				continue
			var entry: Dictionary = (loaded_systems as Dictionary)[id]
			_systems[id] = {
				"health": clampf(float(entry.get("health", 1.0)), 0.0, 1.0),
				"enabled": bool(entry.get("enabled", true)),
			}
	_manifest.clear()
	for item: Variant in (data.get("cargo_manifest", []) as Array):
		_manifest.append(SaveCodec.unplain(item) as Dictionary)
	_main_propellant_kg = maxf(0.0, float(data.get("main_propellant_kg", _main_propellant_kg)))
	_braking = bool(data.get("braking", _braking))
	_refresh_brake()
	changed.emit()
