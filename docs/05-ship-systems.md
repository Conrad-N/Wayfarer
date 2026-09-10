# 05 — The player's ship: systems and maintenance

The player's ship is built from the same part kit as derelicts. It starts small and
worn.

## Systems

| system | provides | consumes | fails when | effect of failure |
|---|---|---|---|---|
| Main engine | thrust (N), Isp | propellant | damaged, no power to pumps | cannot burn; RCS only |
| RCS | jet braking and translation | RCS propellant | damaged or empty | no jet braking or docking translation |
| Reaction wheels | electrical attitude control | charge and finite momentum storage | damaged, unpowered or saturated | cannot supply the requested wheel torque; existing spin remains |
| Reactor | power (kW) | fuel (slow) | damaged, overheated | everything electrical degrades to battery |
| Battery | buffer power | charge | depleted | lights, screens, life support stop when reactor is down |
| Radiators | heat rejection | none | damaged | reactor and engine overheat and throttle down |
| Life support | oxygen, CO2 scrubbing, temperature | power, O2 stores | damaged, no power | oxygen clock starts; you are on suit air |
| Comms | contract board, rescue calls, market | power | damaged | cannot call rescue; must repair first |
| Sensors | scanner range, target tracking | power | damaged | planner loses target data |
| Cargo bay | volume, door size | power to open | door jammed | cannot load |
| Airlock | EVA | power | damaged | can still cycle manually, slowly |
| Terminals | the screens | power | none | screens go dark on power loss; the tablet still works on its own battery |

Each system is a `Resource` definition (rating, mass, spare needed) plus runtime state
(health 0 to 1, on/off, temperature). `ShipApi` exposes all of it.

## Damage

- **Collision:** kinetic energy of an impact above a threshold damages the part hit.
  Debris you cut loose can hit your ship. Your ship can hit the wreck.
- **Hazards:** vented fuel, coolant, and bursts hit whatever is nearby.
- **Wear:** engines and reactors lose health slowly with use. Radiators wear with heat.
- **Your own tools:** cutting near your ship cuts your ship.

## Maintenance

- Spares are inventory items bought at stations or salvaged from wrecks.
- Repairs take sim time and a spare of the right kind. Some repairs need a dock
  (engine bell, reactor core).
- Repair is done at the system's panel in the ship, in first person, by holding
  interact with the spare in inventory. No minigame in the first version.

## Disabled ship

The interesting failure. Examples and what the player can do:

- **No power:** battery runs down. Priority: restart the reactor (spare or cool it),
  or salvage a power core from the wreck and fit it. Terminals are dark, so you use
  the tablet.
- **No comms:** cannot call rescue. Fix comms, or wait for the insurer's overdue
  check (if insured), which arrives after a fixed period from the contract's
  expected return time.
- **No propellant:** call rescue, or salvage propellant from the wreck's tanks with
  a transfer hose (a tool bought at stations).
- **Tumbling ship:** wheels are saturated or disabled and jet braking is unavailable.
  Restore an attitude actuator or accept the ride and use the tablet to call for help.

## Time and rest

Time warp is available from the ship's terminals when nothing is happening nearby.
"Rest" is the in-fiction warp: you sleep, time passes, the ship coasts. Warp is
capped at 1x in the local scene while anything is loose.

## M3 implementation (2026-09-10)

The starter ship has an 8,000 kg dry hull, 40 kg RCS propellant and a 2 kWh
battery. Its kit-panel shell encloses a hab, an interlocked airlock and a cargo
bay. The bay is 3.6 × 2.8 × 5 m (50.4 m³); its external opening is fixed at
2.2 × 2.2 m. Doors refuse to close across a body. Each actual door movement
costs 1,000 J; repeated requests for the current position cost nothing.

`ShipApi` owns resources, commands, health and the cargo ledger. The physical ship
publishes local motion through it. NAV can hold station with bounded RCS force
and torque, consuming real propellant. No orbital solution is fabricated.
Hull, power, RCS, cargo, airlock and sensors have health and enabled state.
Impacts use incoming relative velocity and reduced mass; energy above 2,000 J
reduces the contacted section's health by excess energy / 300,000 J. Intercepted
fuel and coolant plumes cumulatively damage power and RCS respectively, using
20 kW and 8 kW while the finite plume actually reaches the ship. Walls shield it.

Cargo must be observed outside, pass the open aperture with clear alignment,
fit entirely inside, and settle below 0.5 m/s and 0.35 rad/s relative to the ship.
An active leak prevents clamping. Powered clamps then add the load's mass and
volume to the shared manifest. The load becomes part of the ship's compound
collision body, so its mass is counted once. Loading preserves linear and angular
momentum; it is an inelastic attachment, with ship-axis diagonal inertia used as
an approximation after clamping. There is no sale, unloading UI or repair yet.

Reactor generation, temperature, life support, wear, manual airlock cycling,
spares and repairs remain later work described above. M3 is a local salvage yard;
orbital flight and navigation arrive in M4.

## M4 implementation (2026-09-10)

The flight starter adds 24,000 kg of main propellant to the existing hull and RCS
stores. The inherited main drive provides 250 kN at 900 s specific impulse.
Finite burns consume main propellant and update total mass; cargo and remaining
RCS propellant also count in acceleration and the available delta-v budget.
An empty main tank stops thrust while preserving motion. Loss of ship power
cancels burns and local approach. Engine wear and thermal limits remain later work.

Orbital attitude control and maneuver execution use the ported bounded torque
controller. During physical encounters its braking calculation uses the actual
hull inertia, with a 60-second pointing lead before maneuver nodes. The reaction-wheel actuator now has finite momentum and electrical budgets,
separate from the RCS section (see below). Local translation and station holding
use the finite RCS tank.

NAV's local controls provide six translation directions. Approach uses at most
10 kN and 0.5 m/s to settle 30 m from the selected encounter reference, consuming
the finite RCS store at a 2,000 m/s exhaust velocity. It requires relative speed
below 10 m/s and a finished maneuver sequence. Closing the screen or losing focus
releases held translation. Changing target or cutting off cancels approach.

## Physical pilot support (2026-09-10)

A seat beside NAV has a mechanical harness. Its live constraint transfers ship
forces to the suit; release preserves motion. Terminal and tablet use alone
provide no restraint. The steel deck accepts switchable magnetic soles for
walking; wall panels and arbitrary salvage do not automatically count as magnetic.
Suit wheel unloading can transmit torque through any of these physical contacts.
A carrier responds according to its own inertia and active controls.

## Reaction-wheel module (2026-09-10)

The starter ship has three finite wheels rated at ±100,000 N·m·s per axis,
1,000 kg·m² rotor inertia and 5,500 N·m torque. These are provisional industrial
module ratings, with module mass included in the existing 8,000 kg dry hull.
A full single-axis wheel stores 5 MJ. Motors use the ship battery for positive
work and losses of 2 J per N·m·s transferred; generating returns 90% of available
energy up to battery capacity. Excess energy is dissipated, never extra charge.
Momentum storage and battery charge are distinct limits.

The `reaction_wheel` system has independent health and on/off state. NAV attitude
AUTO OFF leaves automatic compensation disabled; STOP ROTATION or a direction
hold requests torque from the bounded wheel module. A disabled, damaged,
unpowered or saturated module cannot silently cancel spin. RCS station holding
remains a separate propellant-consuming control. ShipApi exposes signed wheel
momentum, capacity, utilization, torque rating and stored energy to every client.

When a suit unloads while attached, its motor torques the suit, contact transfers
torque to the ship, and the ship rotates. Only an enabled attitude controller then
counteracts the observed rotation with its own actuator. There is no suit-to-ship
wheel transfer command. This same physical path can later support ship unloading
against a docking constraint or opposing jets. Station unloading, a ship dump
control, environmental magnetic torques and a removable wheel part remain future
work; the module's own state and ratings keep that later part separate from the
attitude controller.
