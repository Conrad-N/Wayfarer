# 09 — Roadmap

Work top to bottom. Tick boxes as items are finished (definition of done is in
AGENTS.md). Each milestone ends with something you can run and feel.

## M0 — Scaffold ✅

- [x] Godot 4.7.2 project, Jolt, zero gravity, input map
- [x] Headless test runner and `check.sh`
- [x] Blender headless part script and an import test proving sockets and metadata
- [x] Design docs and AGENTS.md
- [x] Previous version moved to `legacy/web/`

## M1 — Float ✅

Goal: zero-g first-person movement that feels like Shipbreaker. You should end up
upside down without meaning to and have to think to fix it.

- [x] `Player` as a `RigidBody3D` capsule with 6DOF thrust: forward/back, left/right,
      up/down, roll. Mouse look rotates the body freely (no up vector, no clamping).
- [x] Brake key: kills linear and angular velocity over about a second (suit RCS).
- [x] Suit propellant and battery as numbers on a debug HUD.
- [x] A test scene: a big box room with a dozen rigid bodies of different masses
      (use `hull_segment_a` and primitives). Bumping into things transfers momentum.
- [x] Grapple tool: raycast, tether visual, reel in/out, pulls the lighter body.
- [x] Debug screenshot key F12 saves to `godot/build/screens/`.
- [x] Headless tests: thrust produces expected acceleration for a given mass; brake
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

Brake progress (2026-09-10): hold X (subsequently changed to Alt) to counter drift
and spin with limited suit thrust and torque; release to coast. Mouse look remains available. Eight new Jolt
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

Grapple progress (2026-09-10): left click attaches to the aimed surface, right click
releases, and R/T reel in/out. Equal opposing tension moves the lighter end more;
off-centre anchors spin debris. The HUD shows status and cable length. Attachment
and reel travel spend battery; an empty battery leaves the passive tether intact.
Fifteen new Jolt tests cover selection, anchors, mass response, momentum, torque,
tension limits, release/coasting, slack, battery costs/depletion, and lost/blocked
targets. `./check.sh` passes 330 checks; the main scene boots headless. A windowed
exercise used player input events/polling to attach, reel both ways, release, and
brake with the new Alt binding. It verified a 20 kg crate, a 1,000 kg crate, a wall,
and battery depletion. The cable, controls, and status/warnings were inspected in
`godot/build/screens/m1-grapple-*.png` (ignored). F12 capture and the final movement
feel review remain before M1 is complete.

Screenshot progress (2026-09-10): F12 saves a completed game frame with its HUD to
`godot/build/screens/`, creates the folder if needed, and briefly reports success
or failure. Unique Windows-safe names preserve earlier captures; key repeats and
overlapping requests do not produce extra images. Two headless tests cover the
binding and immediate refusal without rendering. `./check.sh` passes 336 checks;
the main scene boots headless. Windowed checks exercised actual F12 input,
1280×720 PNG output, repeated presses, released mouse capture, folder creation,
an invalid destination, recovery, and notice expiry. Saved images and both notices
were visually inspected (`wayfarer_*.png` and `m1-screenshot-*.png`, ignored).

M1 implementation review (2026-09-10): all checklist items are implemented. A
306-second continuous scripted windowed exercise mixed thrust, coast, roll, mouse
look, braking, and grapple reel/release without resetting the scene or supplies.
All 16 cycles kept finite motion and the suit inside the room; 5.05 kg propellant
and 186.1 Wh remained. F12 captures showed freely rotated views and readable HUD
controls. This verifies stability, not the subjective "fun and disorienting"
criterion, which remains a player playtesting judgment. Next implementation work
is the M2 ship graph. Conrad accepted M1 as complete on 2026-09-10.

## M2 — Cut ✅

Goal: take a wreck apart.

- [x] `ShipGraph` data class and tests (parts, sockets, edges, connected components).
- [x] Part kit v1: 12 parts across hull, cap, tank, engine, radiator, mast, plating.
      Add `-convcol` collision and `volume_m3`, `thickness_mm` metadata. Update the
      import test.
- [x] Spawn a hand-written `ShipGraph` of 8 parts as one compound `RigidBody3D`.
- [x] Cutter tool with cut points and progress; splitting into new rigid bodies with
      conserved momentum. Tests on the maths.
- [x] Tractor beam with reaction force. Scanner with reveal.
- [x] One hazard: coolant spray. Then fuel vent.
- [x] Part value and condition; a debug tally of "salvaged value".

Done when: you can strip a spinning 8-part wreck in an order that matters.

M2 completed (2026-09-10): the main scene is now the eight-part practice wreck.
The twelve-model generated kit covers all seven kinds with convex import shapes,
sockets, exposed cut points, volatile markers, volume, and thickness metadata.
The graph handles parallel mounts and loops; imported shapes form one compound
body per connected component. Repeated splits preserve pose and both kinds of
momentum using consistent principal mass frames and inherited tangential velocity.
Body replacement occurs at the next physics boundary so a cut cannot discard an
already queued vent force.

Keys 1/2/3/4 select grapple/cutter/tractor/scanner. Cutting has thickness-dependent
progress, a battery budget, and heat/cooldown. Tractor push/pull includes suit
recoil and torque. A stationary scan reveals names, hazards, and aimed-part
mass/condition/value. Fuel and coolant have finite, visible plumes that recoil,
push the first body in their path, follow split parts, and reduce condition.
Selecting the hull-side cut endpoint avoids the volatile line; removing the shield
changes access. Hard impacts also reduce condition using incoming contact velocity.
Individually freed parts contribute their remaining value to the debug tally.

Verification: `./check.sh` passes 1,317 checks, including graph validity, the full
import pipeline, assembly gaps/non-overlap/cut access, inertia and repeated live
splits, queued vent force conservation, tool limits/resources/heat/reveal, finite
hazards, and real wall/dynamic/sibling collision damage. The main scene boots
headless. A windowed scripted exercise used actual tool-key and trigger handling
with controlled camera poses while the wreck remained dynamic: scan, safe cut,
both unsafe volatile cuts, all seven joints stripped to eight separate pieces,
tractor and grapple selection, and live value changes. The final run recovered
about 2,519 cr of debug value after hazardous handling. Inspected the kit gallery,
assembly, markers, cutter, plumes, compact labels, target details, and final tally
in ignored `godot/build/screens/m2-*.png`. No cargo sale, ship systems, or additional
hazard types are implied; those remain later milestones.

## M3 — Ship ✅

Goal: your ship is a place.

- [x] Player ship interior built from kit parts: a hab, an airlock, a cargo bay with
      a door of fixed size, two terminals.
- [x] `ShipApi` with telemetry and commands (placeholder orbital data).
- [x] `WorldScreen` with input forwarding; NAV and SHIP apps showing live data.
- [x] Tablet with the same apps.
- [x] Cargo: parts must fit through the door; bay volume; mass total.
- [x] Ship damage from collisions and hazards; SHIP app shows health.

Done when: you cut a part off the wreck, tractor it to your ship, and it either fits
through the door or doesn't, and the SHIP screen agrees.

M3 completed (2026-09-10): the local yard now starts in the player's dynamic
kit-panel ship, with hab, interlocked airlock, cargo bay and two powered terminals.
NAV and SHIP share one ShipApi with the Tab tablet. F grips a nearby slow-approach
terminal and eases the view; Esc/F releases with ship motion. Screens forward real
mouse/keyboard input, cancel held tool controls, and show live local telemetry,
resources, section health and cargo totals. NAV retargets after wreck body changes.
Ship power loss darkens fixed terminals; the independent tablet can restore power.

The cargo opening is 2.2 × 2.2 m, with 50.4 m³ of bay volume. Actual transformed
mesh vertices measure fit, avoiding false oversize results from rotated tapered
bounding boxes. Cargo requires a witnessed exterior approach, clear door passage,
complete containment, slow relative drift/spin, power and no active leak. Clamping
adds geometry to the ship body and updates mass/volume once, conserving momentum
with the documented diagonal inertia approximation. Doors check obstructions;
RCS station holding spends finite propellant. Incoming collisions and intercepted
fuel/coolant plumes damage ship sections and update every SHIP app.

Verification: `./check.sh` passes 1,699 checks with no failures or node-leak warnings;
the main scene boots headless without script errors. New tests cover ShipApi,
physical passages/doors/RCS/damage, forwarded screen clicks, moving handholds and
input ownership, live navigation after cuts, cargo admission and compound momentum,
and real plume interception/occlusion/expiry. A scripted Forward+ run used controlled
suit camera poses (without camera-body collisions) while salvage bodies remained
dynamic: cut the 90 kg nose, tractor it around the wreck, through the open hatch,
and settle it into clamps. The tablet reported one load, 90 kg and 0.7 m³. A second
windowed exercise checked the SHIP terminal, airlock interlock and open doorway,
then drove an oversized hull into the cargo frame: no manifest entry, with visible
section damage. Inspected NAV, tablet, manifest, airlock and impact screenshots in
ignored `godot/build/screens/m3-*.png`. Broader life support, repair, economy and
orbital systems remain later milestones.

## M4 — Orbit ✅

Goal: real flight between places.

- [x] Port the orbital layer from `11-legacy-sim-port-notes.md` into
      `scripts/sim/` with every verification number as a test.
- [x] `Sim` autoload: time, warp, objects. One planet, one moon, one station, one
      derelict.
- [x] Orbital-to-local handoff with the three handoff tests. Floating origin.
- [x] NAV and PLAN apps live: orbit scope, navball, maneuver nodes, transfer planner,
      rendezvous, budgets.
- [x] Burns move the ship in the orbital layer; RCS moves it in the local layer.

Done when: you plan a transfer at a terminal, burn, warp, arrive, and the wreck is
there.

M4 completed (2026-09-10): the main scene starts in orbital flight around Cradle,
with Lune, Lowline Yard and the Kestrel wreck propagated as scalar64 data. The
legacy Kepler, state conversion, maneuver, Lambert/rendezvous, powered-flight,
attitude, time-warp and sphere-of-influence code is ported with its numerical
fixtures, including interplanetary cases. Chat concurrency and market arithmetic
checks remain with their later feature milestones.

NAV and PLAN run through ShipApi on both terminals and the tablet. They provide
an orbit scope, navball, live telemetry, transfer/calculator previews, fuel budgets,
manual nodes, finite burns and bounded event warp. A 160-minute starter transfer
uses departure, three guided corrections and a final velocity match. Cargo, main
fuel and RCS mass enter acceleration and budget calculations.

The physical encounter loads within 10 km and returns actual position/velocity to
an orbit beyond 11 km. The shared executor continues through arrival using Jolt
forces and actual hull inertia. A 2 km floating origin preserves nearby precision.
Leaving and revisiting keeps cut state, conditions, scans, spent reservoirs and
independently drifting/spinning fragments. Open-space EVA has its own coast
reference. The terminal handhold temporarily excludes carrier collisions so its
frozen suit cannot brake the arriving ship. Power or attitude-section failure
removes control torque without deleting existing spin.

Verification: `./check.sh` passes **2,451 checks, zero failures**, with no node-leak
warnings, and the main scene boots headless without script errors. Coverage includes
all orbital verification scenarios, the three required handoff cases, AU-scale
precision, actual Jolt recentering and revisit, UI input/resource guards and a full
transfer with the real terminal handhold. A scripted Forward+ run clicked PLAN,
preview, execute and event warp through the in-world screen, then completed every
burn and arrived about 76 m from physical salvage at 0.69 m/s. The external wreck
inspection used a controlled camera pose without changing ship or wreck dynamics.

A second windowed exercise started from a controlled 94 m/0.75 m/s closing arrival,
clicked RCS approach, and stopped at 31 m with about 28 kg RCS fuel remaining.
Held translation spent fuel and changed velocity; release stopped thrust and fuel
use while preserving momentum. The conservative headless approach case starts
with drift away from the wreck and still retains over 12 kg. Inspected scope,
navball, plan, burn, arrival, RCS and planetary-sky screenshots under ignored
`godot/build/screens/m4-*.png` and `m4_orbital_sky*.png`. Station docking, trading,
contracts and disk saves remain M5; the existing local practice scene is retained
through the main scene's `salvage_practice` property.

## Physical interaction update — before M5

Conrad requested this revision after playing M4, before the economy loop.

- [x] Replace tractor beam with physical grip; carry an antenna through the cargo door.
- [x] Catch a spinning wreck with conserved momentum; suit braking slows both bodies.
- [x] Bounded electrical suit rotation, free head look, wheel-only X brake and Alt jet brake.
- [x] Physical pilot seat; unrestrained maneuvers retain freefall and collisions.
- [x] Magnetic boots with powered walking, passive latch and finite holding force.

Physical update completed (2026-09-10): the tractor is replaced with a contact
handhold that survives cutting and transfers suit forces to its load. Bounded
reaction wheels power mouse body steering, Q/E roll and X spin-only braking;
Alt uses propellant to brake the combined load and unload wheel storage. Free
head look remains available. The pilot seat is a live harness, and terminal use
alone supplies no restraint. Unstrapped suits remain in physical freefall during
coasts and burns. Magnetic boots use finite deck forces, powered stepping and a
passive switchable latch.

Acceptance exercises used the real imported 18 kg antenna, cutter, suit thrust,
2.2 m cargo aperture and clamps: hold before cutting, detach, carry over four
metres, brake, release, and secure. A separate native G/Alt input exercise caught
the complete 1,579 kg spinning wreck and stopped both suit and wreck using about
0.29 kg of propellant. Wheel-only tests stop a manageable held load and leave
residual spin when a larger load fills the wheels; a windowed X exercise worked
with an empty propellant tank. Boots walked and turned through actual B/W/mouse
input, while the seat's F-key flow reached real terminal controls.

Coverage includes momentum/energy behavior, powered limits, split identity,
obstructed carry, grip overload, held cargo admission, passive rotating boots,
seat/unstrap/frame transitions and the existing complete orbital transfer. Wreck
and suit free rotation include gyroscopic correction. Inspected fullscreen hand,
cargo, seat, boot and wheel-brake captures under ignored `godot/build/screens/`.
Final verification: `./check.sh` passes **2,660 checks, zero failures**, with no
script errors or node-leak warnings. The main scene boots headless cleanly.
M5 remains the next milestone.

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
