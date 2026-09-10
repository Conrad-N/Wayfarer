# 05 — The player's ship: systems and maintenance

The player's ship is built from the same part kit as derelicts. It starts small and
worn.

## Systems

| system | provides | consumes | fails when | effect of failure |
|---|---|---|---|---|
| Main engine | thrust (N), Isp | propellant | damaged, no power to pumps | cannot burn; RCS only |
| RCS | attitude and translation | RCS propellant | damaged | cannot point the ship; no docking |
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
- **Tumbling ship:** RCS damaged and the ship is spinning. Fix RCS or accept the
  ride and use the tablet to call for help.

## Time and rest

Time warp is available from the ship's terminals when nothing is happening nearby.
"Rest" is the in-fiction warp: you sleep, time passes, the ship coasts. Warp is
capped at 1x in the local scene while anything is loose.
