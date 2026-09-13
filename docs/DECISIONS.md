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
- 2026-09-10 — Conrad requested borderless fullscreen at startup. The project uses
  Godot's regular fullscreen window mode, preserving the desktop display mode;
  the existing GNOME launcher inherits this setting. The main scene reapplies it
  after window creation for desktops that ignore the initial hint.

- 2026-09-10 — Conrad approved a physical interaction revision before M5: remove
  the tractor beam, add hand grips, suit reaction wheels, magnetic boots and a
  pilot seat. The grapple remains the long-range hauling tool. Slot 3 is hands;
  G works alongside the cutter. No dependency or asset download was needed.
- 2026-09-10 — Hands use a live fixed Jolt constraint at the caught pose, retaining
  collisions and following stable part identity through splits. Catching conserves
  momentum and may dissipate kinetic energy. Initial tuning is 2 m reach, 3 m/s
  maximum catch speed, and monitored 2,500 N / 350 N·m load thresholds. These are
  grip release thresholds, not a claim that every solver impulse is capped.
  Cargo clamps require releasing the grip before attaching the part to the hull.
- 2026-09-10 — The suit has three 8 N·m reaction-wheel motors with 20 N·m·s
  storage per axis and 0.15 kg·m² rotor inertia. They spend battery for motor
  losses and positive work; passive rotor/body gyroscopic reactions conserve
  angular momentum. Free head look is ±60° yaw / ±50° pitch, with powered body
  follow beyond 12°. While hand-gripping, Shift explicitly enables body steering.
  Q/E uses wheel torque. Alt spends propellant on combined-body braking and wheel
  unloading; X, requested by Conrad during implementation, brakes spin using
  wheels alone and leaves drift unchanged. Full wheels leave residual rotation.
- 2026-09-10 — Switchable magnetic soles engage only aligned, slow feet at steel
  deck contact. A 50 J pulse latches; idle holding needs no continuous electricity,
  stepping/turning uses battery (rated up to 1,800 W walking plus 500 W turning),
  and mechanical release works without power. Foot forces and torque react on
  the deck; 1,200 N / 1,000 N·m limits or lost contact release the latch. Carrier
  rotation carries the idle head and suit without commanding powered counter-turns.
- 2026-09-10 — The NAV-side pilot seat uses the same physical constraint with
  harness load thresholds of 200 kN / 50 kN·m. F straps in locally without a pose
  snap; aimed terminals can be used while seated and closing them retains the
  harness. Terminal use alone no longer freezes or transports the player. Free
  suits, handholds and boots use a live local coast frame even in open-space
  coasting, while seated transit allows analytic propagation and warp. Frame
  transitions preserve seat spin and tangential velocity, hull collisions remain
  active aboard, and flight budgets include the transported suit's mass.
- 2026-09-10 — Explicit rigid-body gyroscopic correction is applied to the suit
  and wreck fragments because the engine's default constant angular velocity
  otherwise drifts in world angular momentum for off-axis rotation. This supports
  the spinning-wreck catch acceptance rather than relying on single-axis tests.
- 2026-09-10 — Conrad requested automatic seat alignment after playtesting. F
  now snaps a slow pilot within 1.5 m into the chair's fixed pose facing NAV,
  centres head look, and uses a seated eye height of 0.35 m. This explicitly
  supersedes the earlier no-snap boarding choice. The physical harness still
  carries the pilot afterward; unstrapping restores normal eye height and leaves
  solved motion intact. Wheel storage remains the original provisional 20 N·m·s
  per axis; Conrad's low-capacity feedback is recorded pending further tuning.

- 2026-09-10 — Conrad's wearable reaction-wheel design note supersedes the
  provisional 20 N·m·s / 0.15 kg·m² suit rating: ±100 N·m·s per axis,
  0.0239 kg·m² rotor inertia, approximately 40,000 rpm, and a 15 kg assembly
  included in the existing 100 kg suit mass. Motor torque remains 8 N·m.
  Motor-generators recover energy with losses while preserving angular momentum.
- 2026-09-10 — Hold C unloads suit wheels with equal opposite torque on the suit;
  physical hands, boots or the pilot harness transmit that reaction to a carrier.
  A carrier's controller independently responds to the resulting motion only
  when enabled. No system transfers momentum directly between wheel stores.
  Alt retains propellant-compensated unloading; X retains wheel-only spin braking.
  Seated suits with stored wheel momentum retain local physics for gyroscopic
  contact torque, so suit wheels must be unloaded before orbital warp.
- 2026-09-10 — Replace the ship's ideal M4 attitude actuator with a finite wheel
  module and independent `reaction_wheel` health/on-off system. Provisional
  industrial ratings are ±100,000 N·m·s per axis, 1,000 kg·m² rotor inertia and
  5,500 N·m torque; module mass is included in the existing 8,000 kg dry hull.
  Regeneration is 90% efficient, with 2 J/N·m·s transfer losses. ShipApi exposes
  persistent wheel telemetry across local and orbital flight. AUTO OFF disables
  compensation; STOP ROTATION and direction holds command the bounded module.
  Docking-based ship unloading, opposing-jet unloading, magnetic torquers and a
  discrete removable wheel part remain future extensions of this torque path.
- 2026-09-10 — Full-capacity testing exposed artificial energy growth in explicit
  gyroscopic stepping. Suit and ship passive rotation now use implicit midpoint
  integration; the scalar orbital path also uses its matching orientation step.
  Local bodies use their complete physical inertia tensors and retain Jolt's
  finite-step orientation accuracy. Tests cover saturated rotors with motors off,
  as well as hand, boot and harness transfer followed by independent compensation.

- 2026-09-10 — Conrad replaces automatic head-look/body-follow with direct mouse
  requests for physical body turns. The camera stays centred unless Z is held;
  free head motion remains ±60° yaw / ±50° pitch and snaps to centre on release.
  Fast swipes retain their requested turn. Remove the
  artificial 0.8 rad/s turn-rate cap; finite inertia, motor torque, battery
  and wheel capacity determine the response. Hand grips still require Shift to
  steer the load; the pilot harness restrains the torso. Boots use normal mouse
  yaw for powered deck turns,
  while free look leaves their heading unchanged.
- 2026-09-10 — Conrad raises suit wheel motor torque from 8 N·m to 50 N·m for
  faster physical turns. The same rating applies to mouse steering, Q/E roll,
  wheel braking and unloading; ±100 N·m·s per-axis storage remains unchanged.
  Conrad also requests a visual bump indicator driven by actual suit contacts,
  so collisions are easier to recognize during movement.
- 2026-09-10 — Boot pivots consume normal mouse yaw independently of head aim,
  with a finite 250 N·m foot motor and a conservative 500 J/rad command budget.
  Large turn requests reach the physical controller without an imposed speed
  cap or an instant adhesion overload. Walking follows the torso during free look.
  The bump HUD flashes amber below the crosshair for 0.6 seconds after a contact
  impulse increase of at least 5 N·s; steady pressure and gentle touching stay quiet.

- 2026-09-10 — B toggles magnetic boots between off and armed while free-floating.
  Armed soles automatically latch on suitable steel contact once alignment, speed
  and battery checks pass. Rejected attempts consume no energy; the 50 J engagement
  pulse is paid only on success. B cancels arming or releases contact. Overload,
  loss of contact, hand gripping and seating disarm the boots to prevent repeated
  catches. Prompts distinguish OFF, ARMED and LATCHED and refer to steel surfaces.

- 2026-09-10 — Conrad requests more forgiving boot movement. Raise provisional
  sole holding limits from 1,200 N / 1,000 N·m to 3,000 N / 2,000 N·m; keep the
  50 J engagement pulse and passive zero-draw hold. Latched mouse look is free
  camera aim with unrestricted yaw and ±85° pitch, independent of Z and without
  battery, propellant or rotor momentum cost. Walking follows the view projected
  onto the surface; releasing boots centres the view and restores physical EVA
  turning. Replace powered foot-yaw look with this explicit playability allowance.
  Add a 0.30 m step-over allowance; larger obstacles block walking rather than
  letting a growing walking-target error topple the suit. External overloads
  still exceed finite adhesion and release the boots.
  Step assistance uses bounded anchor lift at up to 0.8 m/s, dense foot-path probes
  and a capsule clearance sweep; it does not teleport the suit or remove collision.
  Steel lower doorway sills support the soles. The walking target stays within
  0.12 m of the actual body to avoid runaway pushing against walls. Full walking
  input budgets 5,000 W to cover the increased force rating and combined lift/
  translation speed; idle and view-only resource use remain zero.

- 2026-09-10 — Conrad requests hold-B alignment and gentle surface approach.
  After a 0.35 s hold while unlatched, seek the nearest visible boot-compatible
  surface within 3 m of the suit centre. Use the existing finite suit thrusters
  and 50 N·m reaction wheels, with a 0.25 m/s target approach speed and capsule
  path checks. A sideways suit first backs off enough to rotate safely. This
  consumes ordinary propellant and electricity; no remote magnetic force or
  momentum reset is introduced. Release/focus loss/braking/wheel dumping stops
  assistance and preserves passive arming. Hand grips and seats exclude it. A
  press which begins latched releases without immediately recatching on hold;
  holding an already-armed press may rearm after the initial cancel tap.
  Reject initial sole anchors whose spring load already consumes more than half
  the holding-force budget before charging engagement power. Held approaches
  wait for close sole alignment and low relative angular speed before latching.

- 2026-09-10 — Conrad requests forced free look while seated and a dedicated exit
  button. Seated mouse aim uses the boots' free camera mode (unrestricted yaw,
  ±85° pitch), with no Z modifier or resource cost. V releases the harness even
  while aimed at a terminal or using a terminal/tablet, closes screen input,
  restores standing eye height and centres the EVA view while preserving motion.
  F retains its contextual behavior. Unexpected harness release also restores
  the seated camera state to EVA.

- 2026-09-10 — Conrad requests that nearby geometry never cover the tablet GUI.
  The handheld screen and frame render after world geometry with depth testing
  and depth writes disabled; the display draws after its frame. Each screen owns
  its material copy so fixed terminals retain normal world occlusion. The tablet
  keeps its existing viewport apps, camera-relative placement and pointer mapping.

- 2026-09-11 — The wreck gyroscopic correction changes from a per-tick torque
  to a per-tick rotation. The old correction (anti omega-cross-L torque in
  `WreckBody._physics_process`) was needed because Jolt omits the gyroscopic
  term, but applied as a straight-line step it inflated the angular momentum
  magnitude by a chord error (~dt²·|ω×L|²/2 per tick), which scales with the
  fourth power of spin: measured +23% momentum and +50% energy per 30 s at
  ~3 rad/s. `WreckBody` now rotates L back about the mean spin axis (Heun
  midpoint refinement) and writes angular velocity directly, making |L| exact
  by construction. The fast-tumble stress test in
  `tests/test_wreck_rotation.gd` holds to machine precision; slow-spin
  precession behaviour is unchanged.

- 2026-09-12 — Warp no longer requires the pilot seat (Q9). Conrad decided the
  player may move freely inside the ship while time warp runs, and may not leave
  it. Rationale: the ship coasts during warp (thrust is only applied in local mode
  at 1x; rotation and burns cap warp at 10x), so the interior is a still room and
  Jolt can simulate a free player against the frozen hull honestly. Airlock doors
  refuse to move above 1x. Warp still drops to 1x near objects, and the local-mode
  handoff must hand an unseated player the same velocity offset as the seated
  pilot. Not yet implemented; assigned to GPT at the start of M5.

- 2026-09-13 — Kit: new `truss` part kind (T10). `make_part_kit.py` grew `bar()`
  (a bevelled box turned to face from start to end, used for diagonal braces) and
  `truss(name, length)` for `truss_segment_a/b/c` at 2, 4, 6 m. Design notes: the
  four corner rails sit at (±0.45, 0, ±0.45) and are the only geometry that
  reaches the 0.5 m envelope, so the bounds test is the proof the diagonal insets
  (0.10 / 0.40) were not enlarged; braces alternate direction per bay so the
  ladder zig-zags. `join()` keeps the first piece's origin, which for a truss is a
  rail at (−0.45, 0, −0.45) and would slide every socket added afterwards off
  centre, so `truss()` bakes that offset into the vertices with
  `transform_apply(location=True)` before `finish()`. Volume is the envelope
  (1 × 1 × length), same convention as the radiator.

- 2026-09-13 — Seat: three interaction fixes from play. (1) The "F strap into
  pilot seat" prompt now appears only when `strap_in()` would accept it (within
  2 m and under 1 m/s relative to the ship, loosened from 1.5 m / 0.5 m/s the
  same day at Conrad's request; the harness catch speed moved with it); otherwise an aimed seat shows a
  "move closer and slow down" hint. Before, the prompt fired from the 2.5 m aim
  ray while the gate was 1.5 m, so F looked dead. (2) A deliberate unstrap stands
  the pilot at `PlayerShip.SEAT_EXIT_POSITION` (1.0, 0, 1.0), a full step behind
  the seat back in the clear centre passage (moved out from 0.35 the same day:
  beside the backrest the step-out was too subtle to notice), keeping their facing and solved velocity, after a
  capsule overlap check; a harness that simply broke leaves them in place. The
  seated capsule overlaps the harness bars by a few centimetres, which is what
  made climbing out finicky. (3) The `wheel_dump` action (C) now reaches the suit
  while a terminal or tablet owns input, because the warp refusal message on that
  very screen asks for it; focus loss clears it so a held key cannot stick.

- 2026-09-13 — Warp unloads the suit wheels itself (Conrad, from play). A seated
  pilot's warp or event-warp request used to be refused with "HOLD C TO UNLOAD
  SUIT WHEELS" whenever the reaction wheels held any momentum. Now `OrbitalFlight`
  keeps the request as `_pending_warp`, drives `Player.set_automatic_wheel_dump()`
  (a flag separate from the held C key, so per-frame input polling cannot cancel
  it) until the wheels are empty, waits the existing 0.3 s harness settle, lets
  the interior return to analytic coasting, then applies the warp. The panel shows
  the pending rate meanwhile. The only remaining refusals are not seated / not
  aboard / parked near an object, and holding a handhold, boots or the grapple,
  which the ship cannot release for the pilot.

- 2026-09-13 — Arrival ejected the seated pilot (Conrad's Kestrel incident).
  Entering an object's 10 km bubble switches the ship to Jolt and adds the real
  closing speed to suit and hull in the same frame. `PhysicalGrip` estimates load
  from the suit's velocity change per frame, so it read that bookkeeping jump as
  a multi-MN crash and let go. Every grip now joins `PhysicalGrip.FRAME_GROUP`,
  and `OrbitalFlight` calls `rebase_motion()` on the group after each handoff
  (`_enter_local_ship`, `_leave_local_ship`). Separately, Jolt's default 500 m/s
  speed cap silently took up to kilometres per second off arrivals; the project
  now sets `jolt_physics_3d/limits/max_linear_velocity` to 20000 m/s. With the
  pilot out of the seat, the intercept course then carried the ship through the
  wreck at ~800 m/s: one hit zeroes the power system (screens dark), the ship
  tumbles, and the suit drains its battery fighting the spin, with no recharge.
  That crash is still possible when strapped in; there is no collision warning.
  Debug tooling added: `DebugLog` (event ring buffer, `EVENT`/`ANOMALY` lines in
  the game log) and `DebugDump` (F11 or any anomaly writes a JSON state dump to
  `user://debug`); `check.sh` isolates `XDG_DATA_HOME` so test runs no longer
  rotate the real game's logs out; the game keeps 20 logs.
