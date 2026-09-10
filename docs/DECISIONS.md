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
- 2026-09-10 — The M1 debris field is a reusable scene with a fixed, clear layout
  of eleven box props and the existing 4,200 kg hull. Equal-sized 20/100/1,000 kg
  crates isolate the effect of mass. Debris starts at rest with zero damping and
  debug mass labels, making player-caused motion easy to read and repeat.
- 2026-09-10 — M1 generates convex collision for the existing hull at runtime and
  preserves its imported transform and mass metadata. This exercises the current
  asset now; the Blender `-convcol` pipeline change remains part of M2.
- 2026-09-10 — Conrad changed the suit brake binding from X to Alt. Hold behavior
  and braking physics are unchanged.
- 2026-09-10 — M1 grapple uses left click to attach, right click to release, and
  R/T to reel in/out. The click that captures the mouse does not fire; Escape or
  focus loss cancels pending shots and motor input but keeps an existing tether.
- 2026-09-10 — Grapple tension is an equal opposing pull between the suit centre
  and the selected target surface, including target torque. The tunable spring
  is 200 N/m with 50 N·s/m damping and a 300 N cap; slack cable cannot push. The
  reel moves at 2 m/s between 1 and 30 m. This gives light debris and heavy anchors
  distinct responses without changing either body's velocity directly.
- 2026-09-10 — Grapple attachment costs 100 J; reeling draws 1,000 W for actual
  cable travel, leaving room above its 600 W peak mechanical output. Passive
  holding and release cost nothing; empty batteries preserve the tether but stop
  new shots and motor travel. These are initial tool tuning values.
- 2026-09-10 — M1 draws the tether as a straight line and releases it when another
  body blocks the line, the target disappears, or separation exceeds 30 m. Rope
  wrapping and sag are deferred; the prototype cannot pull through obstacles.
- 2026-09-10 — F12 captures a completed viewport frame including the HUD into
  `godot/build/screens/`. Filenames use Windows-safe timestamps and a unique suffix;
  existing images are preserved. Held-key repeats and overlapping requests are
  ignored. A four-second notice confirms success or failure, and is hidden before
  the next capture. Headless capture reports unavailable immediately; this debug
  feature remains a scene node rather than an autoload.
- 2026-09-10 — M2 represents physical definitions as Resources, individual part
  condition/scan state as RefCounted data, and socket connections as a deterministic
  ShipGraph. Different sockets may form parallel connections; parts separate only
  when disconnected. This supports multiple mounts without tying connectivity to
  scene nodes.
- 2026-09-10 — The first kit contains twelve generated parts across all seven M2
  kinds. `-convcol` imports convex collision, while volume is an envelope estimate
  and thickness is explicit cutter tuning. New cut markers sit on the skin near
  their sockets; size suffixes are removed when resolving CUT names. The original
  large hull remains compatible with the M1 collision playground.
- 2026-09-10 — M2 uses each model's bounding box as its homogeneous mass envelope,
  while collisions use the imported convex shape. The full assembly inertia is
  diagonalized and set explicitly on each component body, so the same mass model
  preserves linear/angular momentum and energy through an isolated split. Bodies
  are replaced at the next physics boundary before new forces, preserving queued
  vent impulses. A tether on a replaced body releases and can be attached again.
- 2026-09-10 — The practice wreck has two small hulls, nose, engine, fuel tank,
  radiator, antenna, and shield, with 0.12 m socket gaps and initial spin. Both ends
  of every joint have selectable gold cut points; cutting the volatile part's end
  opens its line, while cutting the hull end avoids that leak. This makes approach
  and cut order matter without implementing the later power-shutdown panels.
- 2026-09-10 — Tools use keys 1–4 for grapple/cutter/tractor/scanner. Cutter tuning
  is 4 mm/s (aluminium time ×0.6), 1,200 W, heat +0.24/s, cooling −0.18/s, and a
  0.25 restart threshold after overheating. Tractor is 250 N/900 W, with reaction
  at the suit tool position. Scanner is two stationary seconds at 150 W; completed
  scans stop drawing power. Every tool scales its last work tick to battery left.
- 2026-09-10 — Coolant is a 400 N, four-second pulse; fuel is 1,000 N for six
  seconds. Each part/kind has one reservoir. Plumes follow the outlet and push the
  first other body in a four-metre ray, with recoil on the source. The short M2 pulse
  keeps rated wet mass constant; exhaust carries unabsorbed momentum. This is
  initial hazard tuning, with no pressure/power behavior yet.
- 2026-09-10 — Ruptures cost 0.15 coolant / 0.25 fuel condition. Impacts above
  2,000 J use reduced mass and incoming contact velocity to damage the component,
  capped at half condition per collision. A 0.2 s sibling grace period excludes
  freshly created split contacts. The debug salvage tally counts current value of
  individually freed parts only, without paying credits or implying delivery.
- 2026-09-10 — Scanned names and hazard markers keep a fixed screen size to avoid
  enormous labels near the camera. Detailed kind, mass, condition, and value are
  shown for the aimed scanned part on the debug HUD, keeping cut points visible.
- 2026-09-10 — M3 starts inside a dynamic 8,000 kg dry ship with 40 kg RCS
  propellant and a 2 kWh battery. The cargo bay is 50.4 m³ behind a fixed
  2.2 × 2.2 m opening. Doors cost 1,000 J per movement, refuse obstructed closure,
  and the airlock interlocks its two doors; atmosphere simulation comes later.
- 2026-09-10 — F grips nearby terminals below 0.5 m/s relative speed and eases the
  view over 0.35 s. The simplified handhold transfers approach impulse to the ship,
  carries the suit pose, then releases with ship point velocity. Tab's identical
  apps leave the suit drifting. Fixed screens require ship power; tablet display
  power is independent and not yet metered. Held interaction/clicks cannot repeat
  actions or fire tools on closing.
- 2026-09-10 — Powered cargo clamps require observed exterior entry, clear
  doorway alignment, whole-load containment, relative drift ≤0.5 m/s and spin
  ≤0.35 rad/s, and no active leak. Transformed model vertices measure clearance, avoiding inflated rotated
  bounding boxes for tapered parts. Secured geometry joins the ship body once; mass/volume enter ShipApi.
  Inelastic clamping conserves linear/angular momentum with a ship-axis diagonal
  approximation to combined inertia; cross terms are omitted after clamping.
- 2026-09-10 — M3 section impact health loss is excess over 2,000 J divided by
  300,000 J. Fuel/coolant plume interception deposits 20/8 kW into power/RCS
  damage with the same 300 kJ health scale, without a per-tick threshold. A blocked
  plume cannot damage the ship. Aggregate ship health is the mean section health.
- 2026-09-10 — M4 ports the original scalar64 orbital math and finite-burn controller,
  preserving its +X body axis behind an explicit Godot -Z conversion. Numerical
  parity includes the legacy interplanetary cases; the playable starter system is
  Cradle, Lune, Lowline Yard and the Kestrel wreck.
- 2026-09-10 — The starter flight has 24,000 kg main propellant, 250 kN thrust and
  900 s Isp, matching the inherited drive. PLAN initially offers a 160-minute
  guided Kestrel transfer because shorter initial routes intersect the planet.
  Guided correction nodes recompute their burns during flight, so preview fuel
  remains an estimate. Cargo and RCS mass count in every flight budget.
- 2026-09-10 — Encounters enter at 10 km, unload beyond 11 km, and recenter at
  2 km. Local encounters and EVA use 1× time; free-flight warp offers 1/10/100/1000×
  with automatic burn and approach limits. A free-space EVA gets its own coast
  reference so the suit remains independent of the accelerating ship.
- 2026-09-10 — Physical arrival continues the same maneuver executor using Jolt
  forces and the hull's actual inertia, with a 60-second slew lead. Local RCS
  approach is capped at 0.5 m/s toward a 30 m stand-off and spends existing RCS fuel.
  The inherited attitude actuator is an ideal reaction wheel, gated by power and
  section health; saturation and electrical draw remain later systems work.
  Local translation/holding spends jet propellant. The conservative approach
  speed preserves stopping fuel in the starter ship's small RCS tank.
- 2026-09-10 — M4 stores cut state and individually propagated wreck fragments
  in session memory, preserving drift, spin, damage, scans and exhausted reservoirs
  on revisit. Disk persistence remains M5. Planet/moon discs use a procedural sky
  to preserve camera precision for the ship interior and salvage tools.
