# Decision log

Dated, newest last. One line each, with the reason. Agents append here when they
decide something the docs did not cover.

- 2026-09-09 — Dropped multiplayer for good. Reason: the shared-time model and
  hosted server were the costliest parts of the old plan and the new direction is a
  single-player salvage career.
- 2026-09-09 — Pivoted to first-person 3D: Shipbreaker movement and tools plus
  Ostranauts salvage economy and maintenance, keeping real orbital flight.
- 2026-09-09 — Engine: Godot 4.7.2 stable, GDScript only. Reason: all-text project
  files suit AI-written code, Jolt physics is built in, MIT licence, native Linux
  editor. Unity was the second choice.
- 2026-09-09 — Real orbital flight stays. You can strand yourself. Insurance and paid
  rescue are the in-world answers.
- 2026-09-09 — The LLM ship AI stays as an optional feature only. Every capability
  it has must exist as an in-game calculator or screen.
- 2026-09-09 — No player character stats. Difficulty is physical and spatial.
- 2026-09-09 — Ship controls are physical terminals in the ship plus a tablet on EVA,
  both clients of one ShipApi.
- 2026-09-09 — Derelicts are generated from a modular part kit (or a large hand-made
  library built from it) so every wreck is a new shape.
- 2026-09-09 — Two-layer world: orbital layer in 64-bit scalars, local physics scene
  loaded within 10 km with a floating origin.
- 2026-09-09 — Blender 5.2 LTS headless scripts generate parts; glTF extras carry
  part metadata (Godot exposes them as `get_meta("extras")`).
- 2026-09-09 — The previous TypeScript version moved to `legacy/web/` as a reference
  for the sim port. It is not maintained.
- 2026-09-10 — M1 suit starts at 100 kg with 180 N of translation thrust shared
  across simultaneous axes, and 8 N·m of roll torque. Both linear and angular
  damping are zero, so releasing controls preserves motion. These are exposed
  tuning values for movement trials; resource consumption comes in a later item.
- 2026-09-10 — Mouse look rotates the complete suit about its current local axes,
  consuming accumulated mouse movement in the rigid body's physics-state callback.
  Thrust and roll forces run in `_physics_process`. This keeps mouse aiming direct
  without introducing an upright direction or changing the body during rendering.
- 2026-09-10 — The headless runner now awaits test methods so movement tests can
  measure actual Jolt physics over fixed steps. Synchronous data tests still use
  the same runner and require no dependencies.
- 2026-09-10 — Holding X gives suit braking priority over translation/roll commands,
  while keeping mouse aiming available. Braking counters velocity in the local
  scene's frame and targets 99% reduction in one second, capped at 600 N and
  60 N·m. These tunable limits keep ordinary movement quick to stop while making
  high speed and extra mass take longer. Releasing X returns to coasting or the
  thrust commands still held; releasing mouse capture also cancels braking.
- 2026-09-10 — M1 suit stores start at 8 kg of propellant and 720,000 J of tool
  battery energy. RCS fuel cost is impulse divided by a tunable 2,000 m/s exhaust
  velocity; roll and braking torque use a 0.5 m effective jet lever arm. Linear
  and angular demands share the remaining propellant proportionally on the last
  tick. Expelled fuel reduces the suit's initially 100 kg mass. These are movement
  tuning values, pending later playtesting.
- 2026-09-10 — Suit battery remains dedicated to tools, as specified in doc 04;
  there is no idle or RCS battery drain. Coasting and mouse aiming spend nothing.
  Empty propellant disables translation, roll jets, and braking without changing
  existing motion. The debug HUD shows low warnings at 10% and explicit empty
  warnings. Powered tools, oxygen, and ship refilling remain later work.
