# 03 — Architecture

## Two layers, one truth

### Orbital layer (`godot/scripts/sim/`)

Pure data, no nodes, no rendering. Every object in the solar system (bodies, stations,
derelicts, the player ship, debris clusters) has an orbital state around a parent
body. Positions and velocities are **64-bit floats stored as separate scalars or
`PackedFloat64Array`**, never `Vector3` (which is 32-bit). Propagation is analytic
Kepler for coasting and fixed-step integration for burns, ported from the previous
version (see `11-legacy-sim-port-notes.md`, which lists the verification numbers
the port must reproduce).

The `Sim` autoload owns sim time, the warp rate, and the list of objects. It steps in
whole fixed quanta of sim time. It never reads the wall clock.

### Local layer (`godot/scripts/world/`)

A Godot scene with Jolt physics and zero gravity. It exists only while the player is
within `LOCAL_RADIUS` (default 10 km) of another object. It is centred on a
**reference object** (the derelict or station) and everything in it is expressed
relative to that object.

Entering: the orbital layer computes the player's position and velocity relative to
the reference object, instantiates the reference object's scene at the origin, and
places the player ship at that offset with that velocity.

Inside: Jolt handles motion. Gravity differences across 10 km are ignored (tidal
effects are far below anything the player could notice at these scales). Warp is
capped at 1x while local.

Recentring (floating origin): when the player is more than `RECENTRE_DISTANCE`
(default 2 km) from the origin, every node is shifted by minus the player's position
in one step. Nothing visibly moves because everything moves together.

Leaving: when the player passes `LOCAL_RADIUS` (with hysteresis), the local position
and velocity are added to the reference object's orbital state to produce the
player's new orbital state, the scene is freed, and the orbital layer continues.
Free-floating cut parts left behind are collapsed into a debris-cluster object in the
orbital layer so they are still there on return.

### Handoff tests (must exist and stay green)

- Enter local, exit immediately: the player's orbital elements match within 1e-6
  relative.
- Enter, translate 1 km along a known axis at a known velocity, exit: the new
  orbital state equals the reference object's state plus that offset and velocity.
- Recentre once mid-scene: relative positions of all bodies unchanged within float
  precision.

## One ship API

`ShipApi` (`godot/scripts/ship/ship_api.gd`) is the only door into the player's ship.
It exposes:

- **Telemetry:** orbital elements, relative state to a target, propellant, oxygen,
  power, system health, cargo manifest, mass and volume totals.
- **Commands:** throttle, attitude target, RCS translate, create and execute a maneuver
  node, toggle a system, open the cargo door, request rescue.
- **Calculators:** transfer planner, rendezvous solver, delta-v and mass budget, oxygen
  and time budget. Pure functions over telemetry; the same code the screens show.

Clients: the in-world terminal screens, the tablet, and the optional AI. None of them
touch sim internals. If you find yourself reaching past `ShipApi`, add to `ShipApi`.

## Scene tree (target shape)

```
Main (Node3D)
  Sim            autoload: orbital layer, time, warp
  Game           autoload: session state, save/load, settings
  LocalScene     present only when near something; reference object at origin
    Reference    the derelict / station (RigidBody3D compound or StaticBody3D)
    Debris...    free bodies produced by cuts
    PlayerShip   RigidBody3D; owns ShipApi, systems, interior, terminals
    Player       RigidBody3D 6DOF controller (inside ship or on EVA)
  UI             tablet and screen viewports; settings (the only out-of-world UI)
```

## Frames and units

- Godot: -Z is forward, +Y is up, right-handed. Blender +Y exports to Godot -Z.
- SI units in sim and API. UI converts to km, km/s, minutes, tonnes at the edge.
- Sim time is seconds since epoch as a 64-bit float. Displayed as DD:HH:MM:SS.

## Save and load

One JSON file: orbital layer state (all objects), player ship state (systems, cargo,
resources), economy state (money, debt, contracts, reputation, insurance), and, if a
local scene is active, a snapshot of every rigid body (transform, velocities) and the
cut state of the reference object. Saving is allowed anywhere except mid-burn.

### First implementation (2026-09-14)

Esc (with no terminal or tablet open) opens `PauseMenu` (`ui/pause_menu.gd`), which
pauses the tree and offers Resume, Save, Load and Quit. The `Game` autoload
(`SaveGames`, `scripts/world/save_games.gd`) owns one save slot at
`user://saves/save.json`, written to a temporary file and renamed into place so a
crash mid-save leaves the old save intact. The file is full-precision JSON wrapped
as `{format, version, saved_at, state}`; `SaveCodec` encodes vectors, bases,
transforms and SimVectors.

`Main.capture_game()` gathers: `OrbitalFlight.capture_save()` (the whole
`OrbitalSession`: world, every orbital object and every encounter record, plus
`ShipApi` state and the loaded reference id), `CargoHold.to_save()`, and the pilot's
pose and velocity relative to the ship, suit stores, suit wheel momentum, seated
state and selected tool. Near a derelict, the wreck pieces are recorded with the
same `EncounterStore.capture` used when leaving an encounter; it does not disturb
the live pieces.

Load stores the state in `Game`, reloads the main scene, and `Main._ready` applies
it after the normal setup: the session is restored, the saved encounter is
re-entered the normal way (so pieces return from the encounter record), cargo
geometry is regrown, then the pilot is placed and, if saved seated, strapped in.
Not kept: hand grips, boots latches, the grapple, winch cables (all kits return),
tool heat and in-progress scans, active vent plumes (finished ones are kept), and
the practice room, which cannot be saved. The economy does not exist yet.

## Determinism

Same save plus same inputs must give the same result on Linux and Windows. Sim steps
in fixed quanta; throttle decisions happen only on quantum boundaries; no wall-clock
reads in `scripts/sim/`. Jolt is deterministic on the same build and platform, which
is enough for single-player.

## M4 implementation (2026-09-10)

`Sim` is the thin `OrbitalSession` autoload under `scripts/world/`; it owns an
`OrbitalWorld` RefCounted and the persistent object/encounter records. Numerical
code under `scripts/sim/` has no nodes or native vectors. The original +X thrust
axis remains in the port; `LocalOrbitFrame` maps it to Godot's -Z ship nose.

The physical ship interior remains available during transit. `OrbitalFlight`
keeps its nearby frame attached to the ship while orbital data advances. Inside
10 km of a station or wreck, it creates the encounter and hands absolute
position/velocity to Jolt relative to the reference object's propagated state.
The executor continues through that handoff by returning main-drive forces and
attitude torque instead of applying a second orbital integration. Local time is
1×. Exiting beyond 11 km creates the new conic from the ship's actual local state.
Recentring at 2 km shifts independent physical roots together.

Encounter records preserve the ShipGraph, part condition, scans, partial cuts and
spent reservoirs. Each loose connected component gets its own scalar64 orbital
state, and is reconstructed at its propagated position on return. Secured cargo
remains attached to the ship and is not recreated in the wreck. A running plume
finishes before encounter unloading. These are in-session records; disk saving
and loading remain M5.

Leaving the ship in open space creates a propagated coast reference and transfers
the ship to local physics at 1× time, so an EVA suit does not follow a later ship
burn for free. Reboarding returns to orbital transit. Cradle and Lune are drawn
in a procedural sky using their apparent directions and angular sizes; nearby
geometry keeps a normal camera depth range.

The pre-M5 physical interaction update replaces the old frozen terminal handhold
with a live seat constraint. Terminal use alone does not restrain the suit.
Unrestrained suits activate a local coast frame even away from other objects,
so Jolt handles freefall, forces and collisions during both coasts and burns.
Hands and boots likewise require the local inertial frame. Restrained transit can use analytic flight;
warp requires the pilot seat. Local constraints retain relative anchors through
recentring and body replacement. Flight mass budgets include the transported suit;
the physical ship body excludes it because its live suit body supplies that mass.

Reaction-wheel state persists across analytic/local handoffs. The orbital
controller requests bounded torque from the ship's wheel module; the local adapter
applies that torque to the hull while Jolt owns body motion. The suit wheel applies
torque only to its suit body, so hands, boots and the seat transmit it through
ordinary contact. Ship attitude control observes body motion independently.
There is no cross-wheel momentum shortcut. A suit with stored wheel momentum,
an active C dump, or the short post-dump settling interval retains local physics
even when seated, including passive gyroscopic reactions through its restraint.
Unload the suit wheels before orbital warp; ship wheel momentum remains in its
own persistent scalar simulation state during warp.

Local control returns motor torque only. `PlayerShip` applies the passive body
and rotor gyroscopic reaction using its full physical inertia tensor; `Player`
uses the same stable midpoint helper. In orbital flight the pure wheel module
integrates passive precession with a matching orientation update. This avoids
double-applying gyroscopic torque or adding energy at high stored momentum.
