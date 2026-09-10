## Flight clients share validated commands and immutable snapshots without touching the sim.
extends TestCase


## Initial practice ships stay light; a configured main drive joins the same mass ledger.
func test_main_drive_mass_and_snapshot_ownership() -> void:
	var api: ShipApi = ShipApi.new()
	check_near(float(api.get_telemetry().mass_kg), 8040.0, 0.001, "practice mass remains compatible")
	api.bind_flight(_accept)
	check_near(float(api.get_telemetry().mass_kg), 32040.0, 0.001, "main propellant joins physical mass")
	var snapshot: Dictionary = {"available": true, "time_s": 12.0, "orbit": {"altitude_m": 400000.0}, "plan": {"nodes": [{"time_s": 60.0}]}}
	api.publish_flight(snapshot, 23900.0)
	snapshot.orbit.altitude_m = 0.0
	var telemetry: Dictionary = api.get_telemetry()
	telemetry.flight.plan.nodes[0].time_s = 0.0
	check_near(float(api.get_telemetry().flight.orbit.altitude_m), 400000.0, 0.0, "publisher cannot mutate cached orbit")
	check_near(float(api.get_telemetry().flight.plan.nodes[0].time_s), 60.0, 0.0, "client cannot change maneuver through telemetry")
	check_near(float(api.get_telemetry().mass_kg), 31940.0, 0.001, "burn fuel loss reaches physical mass")
	api.publish_flight({}, NAN)
	check(bool(api.get_telemetry().flight.available), "invalid fuel update leaves snapshot intact")
	api.publish_flight(snapshot, 50000.0)
	check_near(float(api.get_telemetry().main_propellant_kg), 24000.0, 0.0, "fuel cannot exceed installed capacity")


## All UI routes use one command callback and pass copied command arguments.
func test_commands_share_backend_and_report_rejection() -> void:
	var api: ShipApi = ShipApi.new()
	check(not api.set_throttle(1.0), "unconnected flight controls fail softly")
	var calls: Array[Dictionary] = []
	api.bind_flight(func(command: String, args: Dictionary) -> Dictionary:
		calls.append({"command": command, "args": args})
		return {"ok": command != "execute_plan", "message": "NO PLAN" if command == "execute_plan" else "ACCEPTED"}
	)
	check(api.set_throttle(0.5), "throttle accepted by owner")
	check_eq(calls[-1].command, "set_throttle", "same throttle command")
	check_near(float(calls[-1].args.throttle), 0.5, 0.0, "throttle fraction unchanged")
	check(api.plan_intercept(4800.0), "planner command forwarded")
	check_eq(calls[-1].args.tof_seconds, 4800.0, "API remains in SI seconds")
	check(not api.execute_plan(), "backend rejection preserved")
	check_eq(api.last_message, "NO PLAN", "reason reaches every screen")
	var args: Dictionary = {"nested": {"value": 1.0}}
	api.flight_command("custom_test", args)
	calls[-1].args.nested.value = 9.0
	check_near(float(args.nested.value), 1.0, 0.0, "backend receives copied arguments")


## Electrical loss blocks new flight actions while cutoff and slowing time stay available.
func test_power_loss_keeps_cutoff_available() -> void:
	var api: ShipApi = ShipApi.new()
	api.bind_flight(_accept)
	api.set_system_enabled("power", false)
	check(not api.set_throttle(1.0), "unpowered engine controls refused")
	check(not api.plan_intercept(4800.0), "unpowered flight computer refused")
	check(api.flight_command("cutoff"), "emergency cutoff still reaches owner")
	check(api.cancel_plan(), "cancel remains available")
	check(api.set_rcs_translation(Vector3.ZERO), "power loss cannot latch a held translation")
	check(api.set_warp(1.0), "time can return to real speed")
	check(not api.set_rcs_translation(Vector3(NAN, 0, 0)), "non-finite local RCS input rejected")


func _accept(_command: String, _args: Dictionary) -> Dictionary:
	return {"ok": true, "message": "ACCEPTED"}
