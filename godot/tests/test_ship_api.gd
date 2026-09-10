## Pure ship rules cover shared commands, physical cargo limits, stores, and damage.
extends TestCase

const API_SCRIPT: GDScript = preload("res://scripts/ship/ship_api.gd")


## A fresh API owns independent full stores, empty cargo, and a safe airlock.
func test_default_state_and_independence() -> void:
	var first: RefCounted = API_SCRIPT.new()
	var second: RefCounted = API_SCRIPT.new()
	var state: Dictionary = first.get_telemetry()
	check_eq(state["dry_mass_kg"], 8000.0, "dry mass")
	check_eq(state["mass_kg"], 8040.0, "wet mass includes initial propellant")
	check_eq(state["propellant_kg"], 40.0, "propellant in kilograms")
	check_eq(state["battery_energy_j"], 7200000.0, "battery in joules")
	check_eq(state["cargo_mass_kg"], 0.0, "empty cargo mass")
	check_eq(state["cargo_volume_m3"], 0.0, "empty cargo volume")
	check_eq(state["cargo_capacity_m3"], 50.4, "interior volume")
	check_eq(state["door_size_m"], Vector2(2.2, 2.2), "door clear dimensions")
	check_eq(state["ship_health"], 1.0, "initial health")
	check(not state["cargo_door_open"] and state["airlock_inner_open"] and not state["airlock_outer_open"], "safe default doors")
	first.consume_energy(1000.0)
	first.consume_propellant(1.0)
	first.apply_damage("cargo", 0.5)
	check_eq(second.get_telemetry()["battery_energy_j"], 7200000.0, "separate battery")
	check_eq(second.get_telemetry()["propellant_kg"], 40.0, "separate tank")
	check_eq(second.get_telemetry()["systems"]["cargo"]["health"], 1.0, "separate systems")


## Snapshots and supplied cargo metadata cannot silently mutate stored state.
func test_snapshots_and_manifest_are_deep_copies() -> void:
	var api: RefCounted = _open_ship()
	var details: Dictionary = {"name": "BATTERY", "nested": {"condition": 0.8}, "id": "forged", "mass_kg": 999.0}
	check(api.register_cargo("part", Vector3.ONE, 25.0, 1.0, details), "register valid part")
	details["nested"]["condition"] = 0.0
	var snapshot: Dictionary = api.get_telemetry()
	check_eq(snapshot["cargo_manifest"][0]["nested"]["condition"], 0.8, "input copied recursively")
	check_eq(snapshot["cargo_manifest"][0]["id"], "part", "metadata cannot override identity")
	check_eq(snapshot["cargo_manifest"][0]["mass_kg"], 25.0, "metadata cannot override accounting")
	snapshot["cargo_manifest"][0]["mass_kg"] = -500.0
	snapshot["cargo_manifest"][0]["nested"]["condition"] = 0.1
	snapshot["systems"]["power"]["health"] = 0.0
	snapshot["motion"]["range_m"] = -100.0
	var fresh: Dictionary = api.get_telemetry()
	check_eq(fresh["cargo_mass_kg"], 25.0, "snapshot cannot modify ledger")
	check_eq(fresh["cargo_manifest"][0]["nested"]["condition"], 0.8, "snapshot nested copy")
	check_eq(fresh["systems"]["power"]["health"], 1.0, "snapshot cannot damage power")
	check_eq(fresh["motion"]["range_m"], 0.0, "snapshot cannot alter motion")


## Actual hatch changes consume one fixed motor budget; retries consume nothing.
func test_door_commands_and_energy() -> void:
	var api: RefCounted = API_SCRIPT.new()
	check(api.set_cargo_door(true), "open cargo")
	check(api.get_telemetry()["cargo_door_open"], "hatch published open")
	check_eq(api.get_telemetry()["battery_energy_j"], 7199000.0, "one motor draw")
	check(api.set_cargo_door(true), "idempotent open")
	check_eq(api.get_telemetry()["battery_energy_j"], 7199000.0, "repeated open costs nothing")
	check(api.set_cargo_door(false), "close cargo")
	check_eq(api.get_telemetry()["battery_energy_j"], 7198000.0, "closing also costs energy")
	api.consume_energy(7197500.0)
	check(not api.set_cargo_door(true), "cannot partially move motor with insufficient energy")
	check_eq(api.get_telemetry()["battery_energy_j"], 500.0, "failed movement spends nothing")
	check(not api.get_telemetry()["cargo_door_open"], "failed movement leaves hatch closed")


## The airlock interlock protects both opening directions.
func test_airlock_interlock() -> void:
	var api: RefCounted = API_SCRIPT.new()
	check(not api.set_airlock_door("outer", true), "inner initially open blocks outer")
	check_eq(api.get_telemetry()["battery_energy_j"], 7200000.0, "interlocked command costs nothing")
	check(api.set_airlock_door("inner", false), "close inner")
	check(api.set_airlock_door("outer", true), "open outer after inner closes")
	check(not api.set_airlock_door("inner", true), "outer open blocks inner")
	check(api.set_airlock_door("outer", false), "close outer")
	check(api.set_airlock_door("inner", true), "return to interior")
	check(not api.set_airlock_door("wrong", false), "reject unknown door")
	check_eq(api.get_telemetry()["battery_energy_j"], 7196000.0, "only four actual movements charged")


## Clearance callbacks block closing and opening before state or battery changes.
func test_door_clearance_validation() -> void:
	var api: RefCounted = API_SCRIPT.new()
	var calls: Array[Dictionary] = []
	api.set_door_validator(func(door: String, opening: bool) -> bool:
		calls.append({"door": door, "opening": opening})
		return false)
	check(not api.set_cargo_door(true), "obstruction blocks cargo")
	check(not api.set_airlock_door("inner", false), "obstruction blocks inner")
	check_eq(calls, [{"door": "cargo", "opening": true}, {"door": "inner", "opening": false}], "validator receives proposed movements")
	check_eq(api.get_telemetry()["battery_energy_j"], 7200000.0, "obstruction costs no energy")
	check(api.last_message.contains("BLOCKED"), "actionable feedback")
	api.set_door_validator(Callable())
	check(api.set_cargo_door(true), "clearance callback can be removed")


## Power loss denies motors and brakes but leaves system switches and stored doors intact.
func test_power_switch_and_brake_dependencies() -> void:
	var api: RefCounted = API_SCRIPT.new()
	check(api.set_braking(true), "fresh ship can brake")
	check(api.set_system_enabled("power", false), "power switched off")
	check(not api.get_telemetry()["braking"], "power loss drops brake")
	check(not api.get_telemetry()["power_available"], "power telemetry off")
	check(not api.set_cargo_door(true), "unpowered cargo cannot open")
	check(not api.set_airlock_door("inner", false), "unpowered airlock cannot close")
	check(not api.set_braking(true), "unpowered brake cannot engage")
	check(api.set_braking(false), "brake release always permitted")
	check(api.set_system_enabled("power", true), "healthy power can restart from tablet")
	check(api.set_braking(true), "brake restored")
	check(api.set_system_enabled("rcs", false), "disable rcs")
	check(not api.get_telemetry()["braking"], "rcs off releases brake")
	check(not api.set_braking(true), "disabled rcs cannot brake")
	check(api.set_system_enabled("rcs", true), "restore rcs")
	check(api.set_braking(true), "restored rcs can brake")
	check(not api.set_system_enabled("unknown", true), "unknown system rejected")


## Empty finite stores disable braking and partial final consumption remains exact.
func test_resource_accounting_and_exhaustion() -> void:
	var api: RefCounted = API_SCRIPT.new()
	api.set_braking(true)
	check_eq(api.consume_propellant(39.5), 39.5, "normal propellant draw")
	check_eq(api.get_telemetry()["mass_kg"], 8000.5, "expelled propellant leaves ship mass")
	check_eq(api.consume_propellant(9.0), 0.5, "final partial fuel draw")
	check_eq(api.consume_propellant(1.0), 0.0, "empty tank")
	check(not api.get_telemetry()["braking"], "empty tank drops brake")
	check(not api.set_braking(true), "empty tank cannot brake")
	check_eq(api.consume_energy(7199999.5), 7199999.5, "normal battery draw")
	check_eq(api.consume_energy(3.0), 0.5, "final partial battery draw")
	check_eq(api.consume_energy(1.0), 0.0, "empty battery")
	check_eq(api.get_telemetry()["battery_energy_j"], 0.0, "battery never negative")
	check(not api.get_telemetry()["power_available"], "empty battery means no electrical power")
	var powered: RefCounted = API_SCRIPT.new()
	powered.set_braking(true)
	powered.consume_energy(7200000.0)
	check(not powered.get_telemetry()["braking"], "battery exhaustion drops brake even with fuel")
	check_eq(powered.get_telemetry()["propellant_kg"], 40.0, "battery consumption does not consume fuel")


## Invalid consumption and damage cannot create resources, healing, or nonfinite values.
func test_invalid_resource_and_damage_requests() -> void:
	var api: RefCounted = API_SCRIPT.new()
	for value: float in [0.0, -1.0, INF, -INF, NAN]:
		check_eq(api.consume_propellant(value), 0.0, "invalid fuel ignored")
		check_eq(api.consume_energy(value), 0.0, "invalid energy ignored")
		check_eq(api.apply_damage("cargo", value), 0.0, "invalid damage ignored")
	check_eq(api.apply_damage("unknown", 0.5), 0.0, "unknown damage target ignored")
	check_eq(api.get_telemetry()["propellant_kg"], 40.0, "fuel unchanged")
	check_eq(api.get_telemetry()["battery_energy_j"], 7200000.0, "energy unchanged")
	check_eq(api.get_telemetry()["ship_health"], 1.0, "health unchanged")


## Damage clamps at zero, changes aggregate health, and permanently disables a broken system.
func test_damage_health_and_failed_commands() -> void:
	var api: RefCounted = API_SCRIPT.new()
	var count: int = api.get_telemetry()["systems"].size()
	check_eq(api.apply_damage("cargo", 0.25), 0.25, "partial damage")
	check_near(api.get_telemetry()["ship_health"], 1.0 - 0.25 / float(count), 0.000001, "aggregate normalized health")
	check(api.set_cargo_door(true), "partly damaged door still works")
	check_eq(api.apply_damage("cargo", 2.0), 0.75, "damage clamps to remaining health")
	check_eq(api.apply_damage("cargo", 1.0), 0.0, "destroyed system loses nothing further")
	check(not api.set_cargo_door(false), "destroyed cargo actuator cannot move")
	check(api.get_telemetry()["cargo_door_open"], "damage does not teleport the door")
	check(not api.set_system_enabled("cargo", true), "switch cannot repair destroyed actuator")
	check(not api.get_telemetry()["systems"]["cargo"]["enabled"], "destroyed system disabled")
	check(not api.assess_cargo("box", Vector3.ONE, 1.0, 1.0)["ok"], "damaged cargo system cannot secure new loads")
	api.apply_damage("airlock", 1.0)
	check(not api.set_airlock_door("inner", false), "destroyed airlock actuator cannot move")
	api.set_braking(true)
	api.apply_damage("rcs", 1.0)
	check(not api.get_telemetry()["braking"], "rcs destruction drops brake")
	api.apply_damage("power", 1.0)
	check(not api.get_telemetry()["power_available"], "destroyed power cuts supply")


## Motion uses local vectors and target-relative velocity; bad updates retain the last sample.
func test_motion_is_local_and_finite() -> void:
	var api: RefCounted = API_SCRIPT.new()
	api.set_motion(Vector3(1, 2, 3), Vector3(2, 0, -1), Vector3(0, 0.5, 0), Vector3(4, 6, 3), Vector3(0, 1, 2))
	var motion: Dictionary = api.get_telemetry()["motion"]
	check_eq(motion["position_m"], Vector3(1, 2, 3), "local position")
	check_eq(motion["velocity_mps"], Vector3(2, 0, -1), "local velocity")
	check_eq(motion["angular_velocity_radps"], Vector3(0, 0.5, 0), "angular radians per second")
	check_eq(motion["range_m"], 5.0, "target distance metres")
	check_eq(motion["relative_velocity_mps"], Vector3(-2, 1, 3), "target relative velocity")
	check(not motion["orbital_available"], "no fabricated orbit")
	for index in 5:
		var values: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
		values[index] = Vector3(NAN, 0, 0)
		api.set_motion(values[0], values[1], values[2], values[3], values[4])
		check_eq(api.get_telemetry()["motion"], motion, "invalid motion component keeps prior snapshot")


## The actual projected width and height must both pass the cargo door.
func test_cargo_door_fit_and_bay_length() -> void:
	var api: RefCounted = API_SCRIPT.new()
	check(not api.assess_cargo("box", Vector3.ONE, 10.0, 1.0)["ok"], "closed door denies load")
	api.set_cargo_door(true)
	check(api.assess_cargo("box", Vector3(2.2, 2.2, 5.0), 10.0, 20.0)["ok"], "exact clearance dimensions accepted")
	check(not api.assess_cargo("wide", Vector3(2.201, 1, 1), 10.0, 1.0)["ok"], "width too large")
	check(not api.assess_cargo("tall", Vector3(1, 2.201, 1), 10.0, 1.0)["ok"], "height too large")
	check(not api.assess_cargo("long", Vector3(1, 1, 5.001), 10.0, 1.0)["ok"], "part cannot exceed bay length")
	check(api.assess_cargo("rotated", Vector3(1, 1, 3), 10.0, 3.0)["ok"], "turning long axis toward door allows passage")
	api.set_system_enabled("cargo", false)
	check(not api.assess_cargo("disabled", Vector3.ONE, 10.0, 1.0)["ok"], "disabled cargo cannot secure load")


## Cargo must have a finite positive shape, mass, volume, and nonblank identity.
func test_invalid_cargo_values() -> void:
	var api: RefCounted = _open_ship()
	for id: String in ["", " \t\n"]:
		check(not api.register_cargo(id, Vector3.ONE, 1.0, 1.0), "blank id rejected")
	for value: float in [0.0, -1.0, INF, -INF, NAN]:
		check(not api.assess_cargo("mass", Vector3.ONE, value, 1.0)["ok"], "invalid cargo mass")
		check(not api.assess_cargo("volume", Vector3.ONE, 1.0, value)["ok"], "invalid cargo volume")
		for axis in 3:
			var dimensions: Vector3 = Vector3.ONE
			dimensions[axis] = value
			check(not api.assess_cargo("size", dimensions, 1.0, 1.0)["ok"], "invalid cargo dimension")
	check_eq(api.get_telemetry()["cargo_manifest"].size(), 0, "invalid cargo never added")


## Every secured part appears once, adds wet mass, and releases its exact ledger totals.
func test_cargo_registration_duplicates_and_unloading() -> void:
	var api: RefCounted = _open_ship()
	check(api.register_cargo("battery", Vector3.ONE, 75.0, 0.8, {"part_kind": "battery"}), "battery secured")
	check(api.register_cargo("panel", Vector3(2, 1, 1), 25.0, 1.2), "panel secured")
	check(not api.register_cargo("battery", Vector3.ONE, 999.0, 2.0), "duplicate identity rejected")
	check_eq(api.get_telemetry()["mass_kg"], 8140.0, "cargo changes wet ship mass")
	check_eq(api.get_telemetry()["cargo_mass_kg"], 100.0, "mass ledger")
	check_eq(api.get_telemetry()["cargo_volume_m3"], 2.0, "volume ledger")
	check_eq(api.get_telemetry()["cargo_manifest"].size(), 2, "manifest has two unique parts")
	check(api.remove_cargo("battery"), "release first load")
	check_eq(api.get_telemetry()["cargo_mass_kg"], 25.0, "release subtracts exact mass")
	check_eq(api.get_telemetry()["cargo_volume_m3"], 1.2, "release subtracts exact volume")
	check(not api.remove_cargo("battery"), "cannot release twice")
	check(api.register_cargo("battery", Vector3.ONE, 75.0, 0.8), "released identity can reload")
	api.consume_propellant(5.0)
	check_eq(api.get_telemetry()["mass_kg"], 8135.0, "fuel and cargo accounting coexist")
	check(api.remove_cargo("panel") and api.remove_cargo("battery"), "unload remaining parts")
	check_eq(api.get_telemetry()["cargo_mass_kg"], 0.0, "unloaded mass exact zero")
	check_eq(api.get_telemetry()["cargo_volume_m3"], 0.0, "unloaded volume exact zero")


## Capacity is checked again when loading, so stale assessments cannot overfill a bay.
func test_cargo_volume_limit_rechecks_registration() -> void:
	var api: RefCounted = _open_ship()
	check(api.assess_cargo("later", Vector3.ONE, 2.0, 1.0)["ok"], "initial assessment fits")
	check(api.register_cargo("a", Vector3(2, 2, 5), 100.0, 20.0), "first volume")
	check(api.register_cargo("b", Vector3(2, 2, 5), 100.0, 20.0), "second volume")
	check(api.register_cargo("c", Vector3(2, 2, 3), 100.0, 10.4), "exact bay capacity")
	check_near(api.get_telemetry()["cargo_volume_m3"], 50.4, 0.000001, "full volume")
	check(not api.register_cargo("later", Vector3.ONE, 2.0, 1.0), "stale approved load denied after bay fills")
	check_eq(api.get_telemetry()["cargo_manifest"].size(), 3, "rejection leaves ledger unchanged")
	api.remove_cargo("c")
	check(api.register_cargo("later", Vector3.ONE, 2.0, 1.0), "unloading restores space")
	api.set_cargo_door(false)
	check(not api.register_cargo("closed", Vector3.ONE, 2.0, 1.0), "registration rechecks hatch")


## Clients hear successful commands once and receive readable rejection and cargo feedback.
func test_command_signals_and_messages() -> void:
	var api: RefCounted = API_SCRIPT.new()
	var commands: Array[Dictionary] = []
	var notifications: Array[int] = [0]
	api.command_requested.connect(func(command: String, args: Dictionary) -> void:
		commands.append({"command": command, "args": args.duplicate(true)}))
	api.changed.connect(func() -> void: notifications[0] += 1)
	api.set_cargo_door(true)
	api.set_cargo_door(true)
	check_eq(commands.size(), 1, "one actual command emitted")
	check_eq(commands[0], {"command": "set_cargo_door", "args": {"open": true}}, "command payload")
	check_eq(notifications[0], 1, "one state notification for atomic door command")
	api.set_airlock_door("outer", true)
	check_eq(commands.size(), 1, "failed command is not sent to runtime")
	check(api.get_telemetry()["last_message"].contains("CLOSE"), "rejection feedback published")
	api.set_cargo_message("LOAD TOO FAST")
	check_eq(api.last_message, "LOAD TOO FAST", "owner cargo feedback readable")
	var before: int = notifications[0]
	api.set_cargo_message("LOAD TOO FAST")
	check_eq(notifications[0], before, "repeated feedback does not flood signals")


## Regeneration accepts only real positive energy within the battery's capacity.
func test_regenerated_energy_and_independent_wheel_system() -> void:
	var api: ShipApi = ShipApi.new()
	check_eq(api.store_energy(100.0), 0.0, "full battery rejects excess regeneration")
	api.consume_energy(125.0)
	check_eq(api.store_energy(100.0), 100.0, "recover energy into available space")
	check_eq(api.store_energy(100.0), 25.0, "recovery clamps at capacity")
	for invalid: float in [-1.0, 0.0, NAN, INF]:
		check_eq(api.store_energy(invalid), 0.0, "invalid regeneration ignored")
	check_eq(api.get_telemetry().battery_energy_j, ShipApi.BATTERY_CAPACITY_J, "battery never overfills")
	check(api.set_system_enabled("reaction_wheel", false), "wheel has independent switch")
	check(api.get_telemetry().systems.rcs.enabled, "wheel switch leaves jets available")
	check(api.set_braking(true), "RCS brake works with disabled wheel")
	check(api.set_system_enabled("reaction_wheel", true), "healthy wheel can restart")
	api.apply_damage("reaction_wheel", 1.0)
	check(not api.set_system_enabled("reaction_wheel", true), "destroyed wheel cannot restart")
	check(api.get_telemetry().systems.rcs.enabled, "wheel damage does not destroy jets")


func _open_ship() -> RefCounted:
	var api: RefCounted = API_SCRIPT.new()
	api.set_cargo_door(true)
	return api
