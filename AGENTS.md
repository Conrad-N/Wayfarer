# AGENTS.md — Wayfarer

Wayfarer is a first-person hard sci-fi salvage game. You fly a small ship between
stations and derelicts with real orbital mechanics, float around wrecks in zero-g
cutting them apart with beam tools, haul the valuable parts home, keep your own ship
working, and take contracts. Think Hardspace: Shipbreaker's movement and tools,
Ostranauts' ship-maintenance and station life, on top of a real orbital sim.
Single-player. Sold on Steam eventually.

This file is the contract for any coding agent working here. Read it fully, then
read the design docs in the order listed under "Docs".

## Stack (pinned — do not drift)

| Thing | Version | Notes |
|---|---|---|
| Godot | **4.7.2 stable** | GDScript only. No C#, no GDExtension unless Conrad approves. |
| Physics | Jolt (set in project.godot) | Gravity is 0 in the local scene. |
| Renderer | Forward+ | Low-poly flat-shaded style. |
| Blender | 5.2 LTS | Headless scripts in `tools/blender/`. Export `.glb`. |
| Tests | `godot/tests/run_tests.gd` | Custom runner, zero dependencies. |

**Godot 4 API only.** Godot 3 patterns are wrong here and will not compile:
`yield` (use `await`), `instance()` (use `instantiate()`), `KinematicBody`
(`CharacterBody3D`), `export var` (`@export var`), `onready var` (`@onready var`),
`connect("sig", self, "fn")` (`sig.connect(fn)`), `Spatial` (`Node3D`),
`RigidBody` (`RigidBody3D`). When unsure about an API, read the 4.7 class
reference: https://docs.godotengine.org/en/4.7/ .

## Setup

Linux (Conrad's desktop, Ubuntu 24.04): Godot is at `~/.local/bin/godot`
(symlink to `~/Apps/godot/`). Blender is the snap, `blender` on PATH.

Windows (Conrad's laptop): install Godot 4.7.2 and either put `godot` on PATH or
set `GODOT=path\to\Godot_v4.7.2-stable_win64.exe` before running `check.sh`
(Git Bash). Nothing else is machine-specific.

This folder is synced between the two machines by Syncthing. `godot/.godot/`
and `legacy/web/node_modules/` are excluded from sync and from git. Never put
large generated files (renders, exports, builds) inside the repo except under
`godot/build/`, which is ignored.

## The verify loop (use it constantly)

```
./check.sh            # re-import assets, then run all tests headless. Exit 0 = healthy.
./check.sh --quick    # tests only
godot --headless --path godot --quit-after 3        # main scene boots without script errors
godot --path godot                                  # run the game with a window
godot --path godot -e                               # open the editor
blender -b -P tools/blender/make_part.py -- --out godot/assets/models/parts --name hull_segment_a
```

Rules:
- `./check.sh` must pass before every commit. If it cannot pass, say so in the commit
  message and in your report; do not skip it silently.
- Every rule in the sim, salvage, economy, and ship-systems layers gets a test in
  `godot/tests/test_<area>.gd` (extend `TestCase`, methods named `test_*`). Tests run
  headless, so they cannot depend on rendering.
- Things that need eyes (movement feel, UI layout) are verified by running the game
  and, when useful, saving a screenshot to `godot/build/screens/` via the debug
  screenshot key (F12, to be added in M1). Say what you looked at.
- Headless runs print `Pages in use exist at exit` warnings when a script leaks nodes.
  Free what you instantiate in tests.

## Repo layout

```
AGENTS.md            this file (CLAUDE.md just points here)
check.sh             the one health command
docs/                design docs, numbered in reading order. Source of truth.
godot/               the Godot project (open this folder in the editor)
  project.godot      settings, input map. Text; edit by hand or in-editor, commit either way.
  scenes/            .tscn files (text). main.tscn is the entry.
  scripts/sim/       orbital layer: 64-bit scalar math, no nodes, no Vector3. Pure and testable.
  scripts/world/     scene management, the orbital<->local handoff, floating origin.
  scripts/ship/      the player's ship: systems, ShipApi, damage.
  scripts/salvage/   parts, cut points, hazards, tools (cutter, grapple, scanner).
  ui/                terminals, tablet, calculators. Control scenes rendered to in-world screens.
  assets/models/     .glb from tools/blender. Committed.
  tests/             headless test suites + runner.
tools/blender/       Python scripts that generate part-kit models. Copy make_part.py.
legacy/web/          the previous TypeScript version. Reference only. Do not extend it.
```

## Design rules (the keystones)

These are decided. Do not undo them in code. If a task seems to need a change, stop
and ask Conrad (see below).

1. **Two layers, one truth.** The *orbital layer* (`scripts/sim/`) holds every ship,
   station, and derelict as pure data: positions and velocities as 64-bit floats, never
   `Vector3`, propagated with real orbital mechanics. The *local layer* is a Godot scene
   loaded silently when the player is within a few kilometres of something. It is
   centred near the player and recentred (floating origin) if the player drifts. On
   leaving, local position and velocity are handed back to the orbital layer as a new
   orbit. `docs/03-architecture.md` has the details and the handoff tests.
2. **One ship API, many clients.** Every way of controlling or reading the ship goes
   through `ShipApi` (`scripts/ship/ship_api.gd`): the physical panels in the ship,
   the tablet you carry on EVA, the in-game calculators, and the optional AI. Nothing
   reads sim internals directly. If a panel can do it, the tablet and the AI can too.
3. **The AI is optional and never physics.** The game is complete without any LLM.
   The ship AI is a chat client of `ShipApi` that talks to any OpenAI-compatible
   endpoint the player configures. It never computes orbital or physical quantities;
   it calls the same calculators the player can open.
4. **No character stats.** The player has no skill tree. Difficulty is physical and
   spatial: what a part weighs, whether it fits through the hole you cut, what is in
   the way, what leaks if you cut wrong, whether you have the fuel to get home.
5. **Getting stuck is real.** Ships break. Volatiles move. You can strand yourself. The
   answers are in-game: insurance, paid rescue, or improvisation. Never a free respawn.
6. **Everything is text.** Scenes are `.tscn`, resources are `.tres`, settings are in
   `project.godot`. No state may exist only in the editor without landing in a committed
   file. The only binary assets are `.glb`, images, and audio.
7. **Deterministic sim.** The sim advances in fixed sim-time steps. No wall-clock reads
   inside `scripts/sim/`. Same inputs, same result, on any machine.
8. **SI units inside, friendly units at the edge.** Metres, seconds, kilograms, newtons
   in sim and API. Convert only in UI code.

## GDScript conventions

- Static typing everywhere. `var x: float = 0.0`, `func f(a: int) -> void:`. The
  project enables the untyped-declaration warning; treat warnings as errors.
- Tabs for indentation (Godot's default). `snake_case` files and functions,
  `PascalCase` for `class_name`. One class per file. `##` doc comments on every
  public function and every file.
- Prefer signals and plain objects over autoloads. Allowed autoloads: `Sim`
  (the orbital layer), `Game` (session state, save/load). Ask before adding another.
- Build scenes in text or from code; keep `.tscn` files small and readable. Reusable
  things are their own scene.
- Use `RefCounted` for data classes and `Resource` (`.tres`) for designer-editable
  definitions (part kinds, station prices, contract templates).
- No `assert()` in game code that can be hit by a player. Fail soft, log, keep running.
- Physics runs in `_physics_process`; input and rendering in `_process`.

## Blender pipeline

`tools/blender/make_part.py` is the template. Every part-generating script follows
its conventions (also in `docs/08-art-pipeline.md`):

- Part forward is Blender +Y (imports as Godot -Z).
- Empties named `SOCKET_<name>` are attachment points, `CUT_<name>` are cut points,
  `HAZARD_<kind>_<n>` mark volatiles.
- Custom properties on the mesh object arrive in Godot as one meta entry:
  `mesh.get_meta("extras")` is a Dictionary with `part_kind`, `mass_kg`, `value_cr`,
  `material`. `godot/tests/test_part_import.gd` proves this pipeline; keep it green.
- Low-poly: 8 to 16 sided cylinders, single-segment bevels, flat shading, no textures
  in the first milestones (vertex colours or plain materials).
- Generate, do not hand-model, wherever possible. The scripts are the source; the
  `.glb` is committed output. Re-run the script rather than editing the `.glb`.

## Workflow

1. Take the next unchecked item in `docs/09-roadmap.md` unless Conrad says otherwise.
   Finish it whole, including its tests and doc updates, before starting another.
2. You commit your own work; do not wait for Conrad. Small, focused commits on `main`. Message format: `<area>: <what changed>`, e.g.
   `sim: port Kepler propagation with 400 km check`. Body says what was verified.
3. When you make a design decision the docs did not cover, add a dated line to
   `docs/DECISIONS.md` and, if it changes a rule, update the doc. Unresolved things
   go in `docs/10-open-questions.md`.
4. Report plainly. What works, what you verified and how, what is left. Do not
   claim something is done if `./check.sh` is red.

**Definition of done for a roadmap item:** its tests exist and pass, the main scene
boots headless, the feature is exercised by running the game, the roadmap box is
ticked, and any new decision is logged.

## Stop and ask Conrad when

- You want a new addon, plugin, or dependency of any kind.
- A task conflicts with a design rule above.
- Anything touches Steam, pricing, monetization, or licensing.
- You want to delete files or restructure folders.
- Art style questions beyond "low-poly flat-shaded".
- The task needs an API key, account, or a download over a few hundred MB.

Conrad is learning as he goes. Explain choices in a sentence or two of plain words,
lead with the outcome, and avoid engine jargon in reports.

## Working from a checkpoint (smaller or local models)

Git tag `checkpoint-2026-09-11` is a known-good state: M0 to M4 done, 3064 checks
green. If the tree gets confusing, `git diff checkpoint-2026-09-11 --stat` shows
what changed since; `git stash` or `git checkout checkpoint-2026-09-11 -- <file>`
recovers a single file. Do not reset or force-push.

Extra discipline for a smaller model:

- One roadmap bullet per session. Read the tests for the area first, then the code.
- Run `./check.sh --quick` after every file you touch, not only before committing.
  One broken script fails the whole project with "Failed to compile depended scripts".
- "Nonexistent function 'new' in base GDScript" means a `load()`/`preload()` path is
  wrong and returned null. Check the path before anything else.
- The two hardest files are `godot/scripts/sim/orbital_world.gd` (the orbital core)
  and `godot/scripts/world/orbital_flight.gd` (the orbital-to-local handoff). Read
  them before editing anything that touches flight, warp, or encounters. In
  `orbital_flight.gd` the `_approaching` and `_rcs_direction` resets are repeated in
  several places; if you touch one, check them all.
- Do not start a large refactor. If a file is too big to hold in your head, add a
  small helper next to it rather than rewriting it.

## Machine notes

Desktop: Ubuntu 24.04, Ryzen 5 7600, 32 GB RAM, RTX 5060 Ti 16 GB + RTX 3060 12 GB.
Laptop: Windows 11. Conrad often plays via Moonlight streaming from the desktop.
Local LLMs are available on the desktop through Ollama at
`http://127.0.0.1:11434/v1` (an OpenAI-compatible endpoint) for testing the
optional ship AI.
