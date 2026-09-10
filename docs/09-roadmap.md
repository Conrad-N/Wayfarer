# 09 — Roadmap

Work top to bottom. Tick boxes as items are finished (definition of done is in
AGENTS.md). Each milestone ends with something you can run and feel.

## M0 — Scaffold ✅

- [x] Godot 4.7.2 project, Jolt, zero gravity, input map
- [x] Headless test runner and `check.sh`
- [x] Blender headless part script and an import test proving sockets and metadata
- [x] Design docs and AGENTS.md
- [x] Previous version moved to `legacy/web/`

## M1 — Float

Goal: zero-g first-person movement that feels like Shipbreaker. You should end up
upside down without meaning to and have to think to fix it.

- [x] `Player` as a `RigidBody3D` capsule with 6DOF thrust: forward/back, left/right,
      up/down, roll. Mouse look rotates the body freely (no up vector, no clamping).
- [x] Brake key: kills linear and angular velocity over about a second (suit RCS).
- [x] Suit propellant and battery as numbers on a debug HUD.
- [x] A test scene: a big box room with a dozen rigid bodies of different masses
      (use `hull_segment_a` and primitives). Bumping into things transfers momentum.
- [ ] Grapple tool: raycast, tether visual, reel in/out, pulls the lighter body.
- [ ] Debug screenshot key F12 saves to `godot/build/screens/`.
- [ ] Headless tests: thrust produces expected acceleration for a given mass; brake
      converges; grapple reels the lighter body.

Done when: five minutes in the box is fun and disorienting in the right way.

Progress (2026-09-10): the reusable player scene runs in a simple room with static
walls and coloured orientation markers. Eight player tests exercise real headless
Jolt physics: six thrust directions, mass scaling, diagonal force limits, coasting,
local thrust/roll axes, and unrestricted mouse look. `./check.sh` passes 75 checks;
the main scene boots headless. A windowed input exercise verified forward thrust,
coasting, roll, mouse look, Escape/click capture, and wall contact. The room lighting,
control text, and rotated views were inspected in screenshots under
`godot/build/screens/m1-movement-*.png` (ignored, generated locally).
At this stage the debris room was still pending; the full five-minute
movement-feel milestone remains unfinished.

Brake progress (2026-09-10): hold X to counter drift and spin with limited suit
thrust and torque; release to coast. Mouse look remains available. Eight new Jolt
tests cover convergence, gradual stopping without reversal, force/torque limits,
mass response, release, control priority, mouse look, and the X binding.
`./check.sh` passes 100 checks and the main scene boots headless. A windowed exercise
verified the brake through input polling, settling, release/coasting, and Escape
cancellation. The braking indicator, speed/spin readouts, and stable rotated view
were inspected in `godot/build/screens/m1-brake-*.png` (ignored local captures).

Suit supplies progress (2026-09-10): the HUD shows propellant in kg and battery in
Wh, with low/empty warnings. Translation, roll, and braking spend propellant;
empty tanks leave momentum intact. Battery stores are ready for future powered
tools and do not drain during movement. Eleven resource tests cover accounting,
invalid requests, isolation, movement costs, mass loss, depletion, and the final
partial tick. `./check.sh` passes 175 checks; the main scene boots headless.
A windowed exercise verified live consumption and stopping with fuel, then used
explicit low/empty test fixtures to inspect warnings and depletion behavior.
Captures: `godot/build/screens/m1-supplies-*.png` (ignored).

Debris room progress (2026-09-10): twelve loose bodies span 20 to 4,200 kg,
including the generated hull with its imported mass and runtime convex collision.
Equal-sized 20/100/1,000 kg crates near the spawn make mass effects easy to compare;
debug labels identify every object's mass. All start at rest, clear of the suit,
walls, and one another. Six new Jolt tests cover the layout, hull collision/mass,
suit impacts, total linear momentum, and undamped drift/spin. `./check.sh` passes
250 checks and the main scene boots headless. A windowed exercise bumped the
20 kg crate, 1,000 kg crate, and hull from the same 2 m/s approach and inspected
their different responses, labels, and the room layout. Captures:
`godot/build/screens/m1-debris-*.png` (ignored).

## M2 — Cut

Goal: take a wreck apart.

- [ ] `ShipGraph` data class and tests (parts, sockets, edges, connected components).
- [ ] Part kit v1: 12 parts across hull, cap, tank, engine, radiator, mast, plating.
      Add `-convcol` collision and `volume_m3`, `thickness_mm` metadata. Update the
      import test.
- [ ] Spawn a hand-written `ShipGraph` of 8 parts as one compound `RigidBody3D`.
- [ ] Cutter tool with cut points and progress; splitting into new rigid bodies with
      conserved momentum. Tests on the maths.
- [ ] Tractor beam with reaction force. Scanner with reveal.
- [ ] One hazard: coolant spray. Then fuel vent.
- [ ] Part value and condition; a debug tally of "salvaged value".

Done when: you can strip a spinning 8-part wreck in an order that matters.

## M3 — Ship

Goal: your ship is a place.

- [ ] Player ship interior built from kit parts: a hab, an airlock, a cargo bay with
      a door of fixed size, two terminals.
- [ ] `ShipApi` with telemetry and commands (placeholder orbital data).
- [ ] `WorldScreen` with input forwarding; NAV and SHIP apps showing live data.
- [ ] Tablet with the same apps.
- [ ] Cargo: parts must fit through the door; bay volume; mass total.
- [ ] Ship damage from collisions and hazards; SHIP app shows health.

Done when: you cut a part off the wreck, tractor it to your ship, and it either fits
through the door or doesn't, and the SHIP screen agrees.

## M4 — Orbit

Goal: real flight between places.

- [ ] Port the orbital layer from `11-legacy-sim-port-notes.md` into
      `scripts/sim/` with every verification number as a test.
- [ ] `Sim` autoload: time, warp, objects. One planet, one moon, one station, one
      derelict.
- [ ] Orbital-to-local handoff with the three handoff tests. Floating origin.
- [ ] NAV and PLAN apps live: orbit scope, navball, maneuver nodes, transfer planner,
      rendezvous, budgets.
- [ ] Burns move the ship in the orbital layer; RCS moves it in the local layer.

Done when: you plan a transfer at a terminal, burn, warp, arrive, and the wreck is
there.

## M5 — Loop

Goal: the whole job, once.

- [ ] Station docking (approach a docking ring, dock when slow enough).
- [ ] Market, contract board, spares, propellant, oxygen.
- [ ] Insurance (hull, rescue, cargo). Rescue call and tug arrival. Debt and interest.
- [ ] Save and load.
- [ ] Failure states: stranded, overdue, dead suit. Uninsured loss.

Done when: a new player can take a contract, do it, and come back richer or poorer.

## M6 — Ships

- [ ] Part kit to 30+ parts with parametric generators.
- [ ] `DerelictGenerator` with six class templates and seeds; tests for validity.
- [ ] All four hazards. Wreck-side power shutdown panels.
- [ ] Ship maintenance: wear, spares, dock-only repairs.
- [ ] Three stations with different prices; price drift.

## M7 — Ship AI (optional feature)

- [ ] AI app: chat, OpenAI-compatible client, tools = ShipApi, confirmation toggle.
- [ ] Test against the local Ollama endpoint on the desktop.

## M8 — Polish and Steam

- [ ] Audio, work lights, planet and sun rendering, skybox.
- [ ] Settings screen, key rebinding, resolution.
- [ ] GodotSteam addon, export presets for Linux and Windows, achievements.
