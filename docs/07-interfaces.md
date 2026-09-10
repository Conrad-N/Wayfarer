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
- Walking up and pressing interact "docks" the player to the terminal: the camera
  eases to face the screen, the mouse is released, and mouse and keyboard events are
  forwarded to the viewport (`SubViewport.push_input`) mapped through the mesh UV
  under the cursor's ray. Escape or interact again undocks.
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

## M3 controls (2026-09-10)

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
