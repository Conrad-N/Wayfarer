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

## Determinism

Same save plus same inputs must give the same result on Linux and Windows. Sim steps
in fixed quanta; throttle decisions happen only on quantum boundaries; no wall-clock
reads in `scripts/sim/`. Jolt is deterministic on the same build and platform, which
is enough for single-player.
