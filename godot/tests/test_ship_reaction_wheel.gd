## Ship wheel limits, conservation, electrical work and both simulation adapters.
extends TestCase

const INERTIA: Dictionary = {"ix": 14000.0, "iy": 107000.0, "iz": 107000.0}


## Motors exchange momentum with their carrier and reach a finite axis limit.
func test_momentum_capacity_and_reverse_authority() -> void:
	var wheel: ShipReactionWheel = ShipReactionWheel.new()
	wheel.momentum_body = SimVector.new(-99900.0, 0.0, 0.0)
	var torque: SimVector = wheel.drive(SimVector.new(5500.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)
	check_near(torque.x, 100.0, 1e-8, "only remaining momentum headroom is delivered")
	check_near(wheel.momentum_body.x, -100000.0, 1e-8, "axis has finite speed capacity")
	check_near(wheel.snapshot().utilization, 1.0, 1e-12, "telemetry shows saturation")
	check_near(SimVector.length(wheel.drive(SimVector.new(5500.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)), 0.0, 1e-9, "saturation stops continued positive torque")
	check(wheel.drive(SimVector.new(-5500.0, 0.0, 0.0), SimVector.new(), INERTIA, 0.1).x < 0.0, "reverse command recovers headroom")
	var reported: Dictionary = wheel.snapshot()
	reported.momentum_nms.x = 0.0
	check(wheel.momentum_body.x < 0.0, "telemetry cannot mutate wheel state")


## Small and empty batteries cannot create unpaid kinetic energy.
func test_partial_battery_and_invalid_input() -> void:
	var wheel: ShipReactionWheel = ShipReactionWheel.new()
	wheel.battery_energy_j = 5.0
	var torque: SimVector = wheel.drive(SimVector.new(5500.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)
	var kinetic: float = torque.x * torque.x * 0.5 * (1.0 / wheel.rotor_inertia_kgm2 + 1.0 / float(INERTIA.ix))
	check(torque.x > 0.0 and torque.x < 5500.0, "last battery fraction supplies a partial impulse")
	check(kinetic <= 5.0, "new body and rotor energy is fully paid")
	check_eq(wheel.battery_energy_j, 0.0, "partial work empties battery")
	check_near(SimVector.length(wheel.drive(SimVector.new(5500.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)), 0.0, 1e-12, "unpowered electronics cannot drive")
	wheel.battery_energy_j = 100.0
	var stored: float = wheel.momentum_body.x
	wheel.drive(SimVector.new(INF, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)
	wheel.drive(SimVector.new(100.0, 0.0, 0.0), SimVector.new(), INERTIA, -1.0)
	check_eq(wheel.momentum_body.x, stored, "invalid commands leave physical state intact")
	check_eq(wheel.battery_energy_j, 100.0, "invalid commands do not charge or consume energy")


## Unloading returns energy with losses while delivering the rotor's momentum.
func test_regeneration_preserves_momentum_and_energy() -> void:
	var wheel: ShipReactionWheel = ShipReactionWheel.new()
	wheel.momentum_body = SimVector.new(10000.0, 0.0, 0.0)
	wheel.battery_energy_j = 100000.0
	var impulse: SimVector = wheel.drive(SimVector.new(1000.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)
	check_near(wheel.momentum_body.x + impulse.x, 10000.0, 1e-10, "rotor unloading transfers all momentum to carrier")
	var released: float = (10000.0 * 10000.0 - wheel.momentum_body.x * wheel.momentum_body.x) / (2.0 * wheel.rotor_inertia_kgm2)
	var body_energy: float = impulse.x * impulse.x / (2.0 * float(INERTIA.ix))
	check(wheel.battery_energy_j > 100000.0, "motor generator recovers deceleration energy")
	check(wheel.battery_energy_j - 100000.0 < released - body_energy, "losses prevent recovering all released mechanical energy")
	wheel.battery_energy_j = wheel.battery_capacity_j
	wheel.drive(SimVector.new(1000.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)
	check_eq(wheel.battery_energy_j, wheel.battery_capacity_j, "full battery rejects excess regenerative charge")


## Power switches stop motors but cannot erase the spinning rotor's gyro torque.
func test_disabled_wheel_passive_gyro() -> void:
	var wheel: ShipReactionWheel = ShipReactionWheel.new()
	wheel.momentum_body = SimVector.new(0.0, 100.0, 0.0)
	wheel.enabled = false
	check_near(SimVector.length(wheel.drive(SimVector.new(500.0, 0.0, 0.0), SimVector.new(), INERTIA, 1.0)), 0.0, 1e-12, "disabled motors supply no impulse")
	check_near(wheel.gyroscopic_torque(SimVector.new(1.0, 0.0, 0.0)).z, -100.0, 1e-10, "unpowered rotating axes still torque carrier")


## The orbital controller counters ordinary observed body motion with wheel torque.
func test_orbital_braking_stores_body_momentum() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.angular_vel = SimVector.new(0.1, 0.0, 0.0)
	world.set_attitude_mode("kill")
	for step: int in 640:
		world.advance(OrbitalWorld.DT_PHYS)
	var body_momentum: float = world.angular_vel.x * float(world.ship.inertia.ix)
	check(absf(world.angular_vel.x) < 0.001, "automatic attitude mode arrests externally supplied spin")
	check_near(body_momentum + world.reaction_wheel.momentum_body.x, 1400.0, 0.001, "stopped carrier spin resides in wheel")
	check(world.reaction_wheel.battery_energy_j < world.reaction_wheel.battery_capacity_j, "automatic attitude control spends electricity")
	check_eq(world.ship.propellant_kg, 24000.0, "wheel braking spends no main propellant")


## Pure attitude stepping preserves total world angular momentum with passive rotors.
func test_orbital_passive_gyro_conserves_momentum() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.reaction_wheel.enabled = false
	world.reaction_wheel.momentum_body = SimVector.new(100000.0, -100000.0, 100000.0)
	world.angular_vel = SimVector.new(0.02, 0.03, -0.01)
	var initial: SimVector = _world_momentum(world)
	var initial_energy: float = _body_energy(world)
	for step: int in 640:
		world.advance(OrbitalWorld.DT_PHYS)
	check(SimVector.distance(initial, _world_momentum(world)) / SimVector.length(initial) < 1e-10, "saturated passive rotor plus body world momentum remains conserved")
	check_near(_body_energy(world), initial_energy, 1e-8, "saturated passive precession creates no body kinetic energy")
	check_eq(world.reaction_wheel.battery_energy_j, world.reaction_wheel.battery_capacity_j, "passive precession consumes no electricity")


## Local fractional frames account exactly for every delivered motor impulse.
func test_local_impulses_and_handoff_preserve_wheel_state() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	world.set_manual_torque(SimVector.new(1000.0, 0.0, 0.0))
	var rv: Dictionary = world.current_rv()
	var impulse: float = 0.0
	for delta: float in [0.007, 0.002, 0.013, 0.017]:
		var result: Dictionary = world.advance_local(delta, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new())
		impulse += result.torque_body.x * delta
	check_near(impulse, 39.0, 1e-9, "sub-grid and crossing-grid frames deliver accepted command time")
	check_near(world.reaction_wheel.momentum_body.x, -impulse, 1e-9, "local torque is matched by equal wheel impulse")
	world.replace_state(rv.r, rv.v)
	world.advance(OrbitalWorld.DT_PHYS)
	check_near(world.reaction_wheel.momentum_body.x, -impulse - 1000.0 * OrbitalWorld.DT_PHYS, 1e-9, "return to orbital stepping retains previous stored momentum")
	world.reaction_wheel.enabled = false
	world.reaction_wheel.momentum_body = SimVector.new(0.0, 100.0, 0.0)
	var disabled: Dictionary = world.advance_local(0.01, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new(1.0, 0.0, 0.0))
	check_near(SimVector.length(disabled.torque_body), 0.0, 1e-12, "local sim returns motor torque only; native adapter owns passive gyro")


## Motor power loss is immediate even between sampled control-grid boundaries.
func test_local_power_cut_discards_cached_motor_authority() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var rv: Dictionary = world.current_rv()
	world.set_manual_torque(SimVector.new(5500.0, 0.0, 0.0))
	world.advance_local(0.001, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new())
	var before: float = world.reaction_wheel.momentum_body.x
	world.reaction_wheel.enabled = false
	var stopped: Dictionary = world.advance_local(0.001, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new())
	check_near(SimVector.length(stopped.torque_body), 0.0, 1e-12, "cached control request cannot bypass a disabled motor")
	check_eq(world.reaction_wheel.momentum_body.x, before, "power cut retains stored momentum")


## Several control fragments pay the kinetic energy of their combined impulse.
func test_local_fragment_work_accounts_for_combined_acceleration() -> void:
	var world: OrbitalWorld = OrbitalWorld.new()
	var rv: Dictionary = world.current_rv()
	world.set_manual_torque(SimVector.new(1000.0, 0.0, 0.0))
	world.advance_local(0.1, rv.r, rv.v, FlightMath.IDENTITY_Q, SimVector.new())
	var impulse: float = -world.reaction_wheel.momentum_body.x
	var rotor_energy: float = impulse * impulse / (2.0 * world.reaction_wheel.rotor_inertia_kgm2)
	var body_energy: float = impulse * impulse / (2.0 * float(world.ship.inertia.ix))
	var expected: float = (rotor_energy + body_energy) / world.reaction_wheel.motor_efficiency + impulse * world.reaction_wheel.motor_loss_j_per_nms
	check_near(world.reaction_wheel.battery_capacity_j - world.reaction_wheel.battery_energy_j, expected, 1e-7, "one local frame pays complete carrier and rotor acceleration energy")


func _world_momentum(world: OrbitalWorld) -> SimVector:
	var inertia: Dictionary = world.ship.inertia
	var body: SimVector = SimVector.new(world.angular_vel.x * float(inertia.ix), world.angular_vel.y * float(inertia.iy), world.angular_vel.z * float(inertia.iz))
	return FlightMath.rotate(world.orientation, SimVector.add(body, world.reaction_wheel.momentum_body))


func _body_energy(world: OrbitalWorld) -> float:
	var inertia: Dictionary = world.ship.inertia
	var omega: SimVector = world.angular_vel
	return 0.5 * (omega.x * omega.x * float(inertia.ix) + omega.y * omega.y * float(inertia.iy) + omega.z * omega.z * float(inertia.iz))
