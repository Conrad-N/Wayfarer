# 07 — Interfaces: terminals, tablet, calculators, ship AI

## Principle

You never leave the world to control the ship. Controls are screens that physically
exist: terminals bolted inside your ship, and the tablet on your arm. The only
out-of-world screen is Settings.

## In-world terminals

One reusable scene, `WorldScreen`:

- A `SubViewport` renders a `Control` scene (an "app") at a deliberately low
  resolution (640 x 400) for a chunky in-fiction look.
- A `ViewportTexture` is applied to the screen mesh's material (unshaded, emissive).
- Walking up and pressing interact opens terminal input: the mouse is released,
  and mouse and keyboard events are
  forwarded to the viewport (`SubViewport.push_input`) mapped through the mesh UV
  under the cursor's ray. Escape or interact again closes input. The seat, hand grips or boots provide
  physical support; the terminal itself does not restrain you.
- The 3D world keeps rendering the whole time. You can see the wreck through the
  window while you plan.

Terminals go dark when the ship has no power. The tablet does not.

## Tablet

The same app scenes rendered onto a handheld quad in front of the camera, toggled
with the tablet key. Works on EVA and inside the ship. It talks to `ShipApi` over
"radio", which in the first version means no range limit inside the local scene.
When you are away from the ship, this is how you fire the ship's RCS to hold
station, open the cargo door, or call rescue.

## Apps

| app | shows | does |
|---|---|---|
| NAV | orbit readouts, orbit scope, navball, target relative state | set target, warp |
| PLAN | maneuver nodes, transfer planner, rendezvous solver, budgets | create, edit, execute nodes |
| SHIP | every system: health, on/off, temperature, resources | toggle systems, start repairs |
| CARGO | manifest, mass, volume, door size, tow list | jettison, declare for insurance |
| COMMS | contract board, insurance, rescue call, market (when docked) | accept, buy, sell, call |
| AI | chat with the ship AI, if configured | talk; approve its actions if confirmation is on |
| SETTINGS | out-of-world | graphics, input, AI endpoint |

All apps are `Control` scenes under `godot/ui/apps/` and take a `ShipApi` reference.
They must work identically on a terminal and on the tablet.

## Calculators

Everything the AI might be asked to do exists as a calculator the player can open:

- Transfer planner: from current orbit to target, phase and windows, delta-v, time.
- Rendezvous: closing burns for the last few kilometres.
- Delta-v and mass budget: what the ship can do at its current mass, and after
  loading N tonnes.
- Oxygen and time budget: suit and ship oxygen against a planned trip.

They are pure functions in `godot/scripts/sim/` or `scripts/ship/`, tested headless,
and rendered by PLAN and SHIP.

## Ship AI (optional)

A chat client of `ShipApi`. Configuration in Settings: endpoint URL, model name, API
key, "may act without asking" toggle. Any OpenAI-compatible server works, including
a local one. Its tools are exactly the `ShipApi` functions. It never computes physics;
it calls the calculators and reads their output. If no endpoint is configured, the AI
app shows a plain "no AI installed" screen and nothing else in the game changes.

## Look

Retro-industrial. Monospace text, amber on dark for primary readouts, cyan for
targets and plans, red only for warnings. Low-resolution screens with visible pixels.
No skeuomorphic chrome; flat panels with thick borders.

## Historical M3 controls (superseded by physical controls below)

F grips an aimed terminal within 2.5 m when relative speed is below 0.5 m/s.
The view eases to the screen over 0.35 seconds; the handhold follows the ship.
Esc or F releases with the ship's velocity at that position. Holding F does not
repeat the interaction. Tab opens the handheld screen and Esc/Tab closes it.
The tablet leaves the suit drifting; brake before opening it when necessary.
Mouse clicks and keyboard focus go to the app while either screen is active.
Closing a screen cannot accidentally fire a held salvage tool.

Both terminals and the tablet contain the same NAV and SHIP apps. NAV shows local
wreck range, relative velocity, ship mass, propellant and station-holding control.
SHIP shows system health, battery, cargo totals, doorway dimensions and commands
for power, RCS, the cargo door and both interlocked airlock doors. The same ShipApi
validates commands and supplies telemetry for all three screens. Fixed terminals
go dark with ship power; the handheld remains available to restore it.

PLAN, dedicated CARGO/COMMS/AI apps, repairs, settings and orbital controls remain
later milestones. The tablet's independent battery is not yet depleted by screen
use; the suit's existing battery continues to power salvage tools.

## M4 flight screens (2026-09-10)

NAV now has ORBIT, FLIGHT and APPROACH/RCS pages. ORBIT shows the projected ship
and target paths, altitude, apsides, inclination and a body-relative navball.
FLIGHT shows simulation time, effective warp, mass, main-drive propellant and
remaining delta-v, with throttle, attitude, cutoff and event-warp commands.
APPROACH/RCS has six held translation buttons, local station holding and a bounded
RCS approach to the nearby reference. Button release, switching apps, closing a
screen and power loss cannot leave a manual RCS command held.

PLAN selects the station or wreck and offers intercept, circularization,
Hohmann, velocity matching and custom prograde/normal/radial nodes. Setup uses
friendly units; the preview lists burn times, delta-v and fuel before execution.
The starter Kestrel transfer defaults to 160 minutes; shorter requests may cross the
planet or exceed the available fuel. A preview does not burn
fuel. Execution rechecks the current budget; cancel/cutoff stops the main drive.
Event warp advances through the same simulation and slows at burns and nearby
objects, rather than teleporting to a destination. Manual warp choices are
1/10/100/1000×, with 1× enforced near objects and while on EVA.

Both ship terminals and the tablet run these same apps through ShipApi. PLAN
replaces its M3 placeholder; later COMMS, market, repairs and the optional AI are
still outside M4.

To fly the starter trip: move into the pilot seat facing NAV and press F to strap
in. Aim at NAV and press F again (or use Tab), select PLAN, leave Kestrel
and 160 minutes selected, then CALCULATE PREVIEW and EXECUTE BURNS. Switch to
NAV → FLIGHT and use COAST TO NEXT EVENT. The executor points, burns and coasts
through all five nodes, returning to 1× near the wreck. After the final match,
NAV → APPROACH / RCS provides the short final approach and station holding.
The Tab tablet offers the same controls. Open the airlock from SHIP for EVA;
the scanner, cutter, grapple and physical grips work on the arrived wreck.

## Physical controls update (2026-09-10)

This supersedes the M3 automatic terminal handhold. F opens an aimed nearby
terminal without changing suit motion. The pilot seat has actual restraints:
F straps in from its immediate space; while seated F opens an aimed terminal,
or unstraps when looking away. Closing a screen leaves the harness fastened.
The Tab tablet works in either state. A loose suit is affected by ship maneuvers;
warp and event warp require the seat and remain unavailable near objects.

G grips/releases surfaces with any tool selected; 3 selects hands instead of the
removed tractor. B toggles magnetic soles at steel deck contact. X brakes spin
using battery-powered wheels only; Alt uses jets to brake drift/spin and unload
wheels. The HUD shows attachment status, resources and wheel saturation. Shift
plus mouse steers a hand-held load; normal mouse motion is free head look while
holding it. Escape and focus loss cancel active motors and tools, retaining
passive hand/boot/seat attachments.
