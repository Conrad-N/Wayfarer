## Save/load groundwork: JSON round trips and behavioural replay for OrbitalWorld,
## ShipReactionWheel, ShipApi, SuitResources and SuitAttitude.
extends TestCase


## A world with a queued node, custom attitude, wheel state, cargo and an
## in-progress local control quantum reproduces itself exactly after a save/load
## cycle, and keeps behaving identically to the original from that point on.
func test_orbital_world_save_round_trip_matches_and_replays() -> void:
	var original: OrbitalWorld = _customized_world()
	check(original.can_save(), "fixture used for round-trip is a legal save point")
	var saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(original.to_save()))
	var restored: OrbitalWorld = OrbitalWorld.new()
	restored.apply_save(saved)
	var restored_saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(restored.to_save()))
	check_eq(restored_saved, saved, "round-tripped world reproduces its own save exactly")
	var rv: Dictionary = original.current_rv()
	var rv2: Dictionary = restored.current_rv()
	check_near(SimVector.distance(rv.r, rv2.r), 0.0, 1e-6, "restored position matches")
	check_near(SimVector.distance(rv.v, rv2.v), 0.0, 1e-9, "restored velocity matches")
	for step: int in 30:
		var out_a: Dictionary = original.advance_local(1.0 / 60.0, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new(0.01, -0.02, 0.005))
		var out_b: Dictionary = restored.advance_local(1.0 / 60.0, rv2.r, rv2.v, FlightMath.IDENTITY_Q, SimVector.new(0.01, -0.02, 0.005))
		check_near(SimVector.distance(out_a.force_world, out_b.force_world), 0.0, 1e-9, "identical commanded force")
		check_near(SimVector.distance(out_a.torque_body, out_b.torque_body), 0.0, 1e-9, "identical commanded torque")
	check_near(original.time, restored.time, 1e-9, "clock matches after replay")
	check_eq(float(original.ship["propellant_kg"]), float(restored.ship["propellant_kg"]), "propellant matches after replay")
	check_near(SimVector.distance(original.reaction_wheel.momentum_body, restored.reaction_wheel.momentum_body), 0.0, 1e-9, "wheel momentum matches after replay")


## can_save() only refuses a save while the main engine is actually delivering
## thrust; an armed executor with an unstarted node stays safe to save.
func test_orbital_world_can_save_false_only_during_actual_burn() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	check(world.can_save(), "a fresh coasting world can save")
	world.nodes.append({"id": "future", "time": world.time + 500.0, "dv_local": {"prograde": 80.0, "normal": 0.0, "radial": 0.0}})
	world.set_executor(true)
	world.advance(0.0)
	check(world.can_save(), "an armed executor with an unstarted node can still save")
	world.set_throttle(1.0)
	check(not world.can_save(), "open throttle on real propellant blocks a save")
	world.set_throttle(0.0)
	check(world.can_save(), "cutting the throttle makes it safe again")
	world.ship["propellant_kg"] = 0.0
	world.set_throttle(1.0)
	check(world.can_save(), "an open throttle with no propellant delivers no thrust and is safe")


## Momentum, charge and the enabled switch reproduce exactly and drive identically.
func test_ship_reaction_wheel_save_round_trip() -> void:
	var original: ShipReactionWheel = ShipReactionWheel.new()
	original.momentum_body = SimVector.new(15000.0, -30000.0, 5000.0)
	original.battery_energy_j = original.battery_capacity_j - 250000.0
	original.enabled = false
	var saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(original.to_save()))
	var restored: ShipReactionWheel = ShipReactionWheel.new()
	restored.apply_save(saved)
	check_eq(SaveCodec.parse(SaveCodec.stringify(restored.to_save())), saved, "round-tripped wheel reproduces its own save exactly")
	check_near(SimVector.distance(original.momentum_body, restored.momentum_body), 0.0, 1e-9, "momentum matches")
	check_eq(original.battery_energy_j, restored.battery_energy_j, "battery matches")
	check_eq(original.enabled, restored.enabled, "enabled switch matches")
	original.enabled = true
	restored.enabled = true
	var inertia: Dictionary = {"ix": 14000.0, "iy": 107000.0, "iz": 107000.0}
	var torque_a: SimVector = original.drive(SimVector.new(1000.0, -500.0, 0.0), SimVector.new(0.01, 0.0, 0.0), inertia, 0.5)
	var torque_b: SimVector = restored.drive(SimVector.new(1000.0, -500.0, 0.0), SimVector.new(0.01, 0.0, 0.0), inertia, 0.5)
	check_near(SimVector.distance(torque_a, torque_b), 0.0, 1e-9, "identical command gives identical torque")
	check_near(original.battery_energy_j, restored.battery_energy_j, 1e-9, "identical command spends identical charge")


## Suit propellant and battery reproduce exactly and drain identically.
func test_suit_resources_save_round_trip() -> void:
	var original: SuitResources = SuitResources.new()
	original.consume_propellant(3.5)
	original.consume_energy(200000.0)
	var saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(original.to_save()))
	var restored: SuitResources = SuitResources.new()
	restored.apply_save(saved)
	check_eq(SaveCodec.parse(SaveCodec.stringify(restored.to_save())), saved, "round-tripped suit stores reproduce their own save exactly")
	check_eq(original.propellant_kg, restored.propellant_kg, "propellant matches")
	check_eq(original.battery_energy_j, restored.battery_energy_j, "battery matches")
	check_eq(original.consume_propellant(1.0), restored.consume_propellant(1.0), "identical draw behaves identically")


## Suit wheel rotor momentum reproduces exactly and drives identically.
func test_suit_attitude_save_round_trip() -> void:
	var original: SuitAttitude = SuitAttitude.new()
	original.momentum_body = Vector3(12.0, -8.0, 4.0)
	var saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(original.to_save()))
	var restored: SuitAttitude = SuitAttitude.new()
	restored.apply_save(saved)
	check_eq(SaveCodec.parse(SaveCodec.stringify(restored.to_save())), saved, "round-tripped suit wheel reproduces its own save exactly")
	check_eq(original.momentum_body, restored.momentum_body, "momentum matches")
	var suit_a: SuitResources = SuitResources.new()
	var suit_b: SuitResources = SuitResources.new()
	var torque_a: Vector3 = original.drive(Vector3(2.0, 0.0, 0.0), Vector3.ZERO, 8.0, 0.1, suit_a)
	var torque_b: Vector3 = restored.drive(Vector3(2.0, 0.0, 0.0), Vector3.ZERO, 8.0, 0.1, suit_b)
	check_eq(torque_a, torque_b, "identical command gives identical torque")
	check_eq(suit_a.battery_energy_j, suit_b.battery_energy_j, "identical command spends identical charge")


## RCS/battery stores, doors, system health, the cargo manifest (with its Vector3
## size) and the mirrored main propellant all reproduce exactly after a save/load.
func test_ship_api_save_round_trip() -> void:
	var original: ShipApi = ShipApi.new()
	original.set_cargo_door(true)
	original.register_cargo("plate", Vector3(1.0, 1.0, 2.0), 120.0, 3.5, {"part_kind": "hull_plate"})
	original.consume_propellant(400.0)
	original.consume_energy(2500000.0)
	original.apply_damage("sensors", 0.3)
	original.set_system_enabled("solar", false)
	original.set_airlock_door("inner", false)
	original.set_airlock_door("outer", true)
	original.bind_flight(func(_c: String, _a: Dictionary) -> Dictionary: return {"ok": true}, 24000.0)
	original.publish_flight({"available": true}, 18500.0)
	var saved: Dictionary = SaveCodec.parse(SaveCodec.stringify(original.to_save()))
	var restored: ShipApi = ShipApi.new()
	restored.apply_save(saved)
	check_eq(SaveCodec.parse(SaveCodec.stringify(restored.to_save())), saved, "round-tripped ship reproduces its own save exactly")
	var a: Dictionary = original.get_telemetry()
	var b: Dictionary = restored.get_telemetry()
	check_eq(a["propellant_kg"], b["propellant_kg"], "RCS propellant matches")
	check_eq(a["battery_energy_j"], b["battery_energy_j"], "battery matches")
	check_eq(a["main_propellant_kg"], b["main_propellant_kg"], "main propellant matches")
	check_eq(a["cargo_door_open"], b["cargo_door_open"], "cargo door matches")
	check_eq(a["airlock_inner_open"], b["airlock_inner_open"], "airlock inner matches")
	check_eq(a["airlock_outer_open"], b["airlock_outer_open"], "airlock outer matches")
	check_eq(a["systems"], b["systems"], "system health/enabled match")
	check_eq(a["cargo_mass_kg"], b["cargo_mass_kg"], "cargo mass matches")
	check_eq(a["cargo_manifest"][0]["size_m"], b["cargo_manifest"][0]["size_m"], "cargo manifest geometry survives the Vector3 round trip")


## Corrupt or hand-edited saves cannot push restored state outside its physical
## limits: wheel momentum and battery, suit wheel momentum, suit stores, ship
## propellant/battery/system health, and the airlock interlock all clamp on load.
func test_apply_save_clamps_out_of_range_values() -> void:
	var wheel: ShipReactionWheel = ShipReactionWheel.new()
	wheel.apply_save({"momentum_body": [wheel.capacity_nms * 5.0, -wheel.capacity_nms * 5.0, 0.0], "battery_energy_j": -100.0, "enabled": true})
	check_near(wheel.momentum_body.x, wheel.capacity_nms, 1e-9, "wheel momentum clamps to positive capacity")
	check_near(wheel.momentum_body.y, -wheel.capacity_nms, 1e-9, "wheel momentum clamps to negative capacity")
	check_eq(wheel.battery_energy_j, 0.0, "wheel battery cannot go negative")
	wheel.apply_save({"momentum_body": [0.0, 0.0, 0.0], "battery_energy_j": wheel.battery_capacity_j * 3.0, "enabled": true})
	check_eq(wheel.battery_energy_j, wheel.battery_capacity_j, "wheel battery clamps to capacity")

	var attitude: SuitAttitude = SuitAttitude.new()
	attitude.apply_save({"momentum_body": [500.0, -500.0, 0.0]})
	check_near(attitude.momentum_body.x, SuitAttitude.MOMENTUM_LIMIT_NMS, 1e-9, "suit wheel momentum clamps positive")
	check_near(attitude.momentum_body.y, -SuitAttitude.MOMENTUM_LIMIT_NMS, 1e-9, "suit wheel momentum clamps negative")

	var suit: SuitResources = SuitResources.new()
	suit.apply_save({"propellant_kg": -5.0, "battery_energy_j": SuitResources.BATTERY_CAPACITY_J * 2.0})
	check_eq(suit.propellant_kg, 0.0, "suit propellant cannot go negative")
	check_eq(suit.battery_energy_j, SuitResources.BATTERY_CAPACITY_J, "suit battery clamps to capacity")

	var api: ShipApi = ShipApi.new()
	api.apply_save({
		"propellant_kg": -50.0, "battery_energy_j": ShipApi.BATTERY_CAPACITY_J * 4.0,
		"cargo_door_open": false, "airlock_inner_open": true, "airlock_outer_open": true,
		"braking": true, "systems": {"cargo": {"health": 9.0, "enabled": true}},
		"cargo_manifest": [], "main_propellant_kg": -10.0,
	})
	check_eq(api.get_telemetry()["propellant_kg"], 0.0, "RCS propellant cannot go negative")
	check_eq(api.get_telemetry()["battery_energy_j"], ShipApi.BATTERY_CAPACITY_J, "ship battery clamps to capacity")
	check_eq(api.get_telemetry()["systems"]["cargo"]["health"], 1.0, "system health clamps to 1.0")
	check_eq(api.get_telemetry()["main_propellant_kg"], 0.0, "main propellant cannot go negative")
	check(api.get_telemetry()["airlock_inner_open"] and not api.get_telemetry()["airlock_outer_open"], "airlock interlock re-enforced on load")
	check(not api.get_telemetry()["braking"], "brake rechecked against restored state: no propellant means no brake regardless of the saved flag")


func _customized_world() -> OrbitalWorld:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_attitude_mode("prograde")
	for step: int in 20:
		world.advance(0.5)
	world.reaction_wheel.momentum_body = SimVector.new(500.0, -200.0, 50.0)
	world.reaction_wheel.battery_energy_j = world.reaction_wheel.battery_capacity_j - 12345.0
	world.nodes.append({"id": "future-burn", "time": world.time + 500.0, "dv_local": {"prograde": 80.0, "normal": 5.0, "radial": -2.0}})
	world.set_executor(true)
	world.advance(0.0)
	world.selected_target = 1
	world.ship["cargo"] = [{"id": "plate", "mass_kg": 300.0, "volume_m3": 0.12, "qty": 2.0}]
	world.sync_mass(23500.0, 360.0, 8000.0)
	world.recompute_next_soi()
	var rv: Dictionary = world.current_rv()
	world.advance_local(0.037, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new(0.02, -0.01, 0.03))
	return world
