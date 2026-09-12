# Small tasks for a local model

These are for a smaller model (local Qwen through Pi) while GPT is unavailable.
Each task is self-contained, has an exact definition of done, and needs no design
judgment. Do them **in order, one per session**. Finish one, commit it, tick its
box, report to Conrad in a few plain sentences, and **stop**. Conrad starts the next.

Ground rules for every task here:

- Touch only the files the task names. If you believe another file must change,
  stop and ask Conrad instead of changing it.
- Run `./check.sh --quick` after every edit. Run the full `./check.sh` before committing.
- If a check fails and the fix is not obvious within two attempts, stop and report
  the exact error. Do not work around a failing test by weakening it.
- If anything in a task is ambiguous, pick nothing: stop and ask Conrad.
- Never edit `godot/scripts/sim/orbital_world.gd`, `godot/scripts/world/orbital_flight.gd`,
  `godot/scripts/world/player.gd`, `godot/scripts/world/magnetic_boots.gd`, or any
  `.tscn` file unless the task says so explicitly.
- Commit message format: `<area>: <what changed>`, one commit per task.

---

## T1 — Test that every input action used in code exists in the input map

- [x] Done

**Why:** a typo in an action name fails silently in Godot. This test catches it.

**Create:** `godot/tests/test_input_actions.gd` (extends `TestCase`, like the others).

**What it does:**
1. Walk every `.gd` file under `res://scripts` and `res://ui` (use `DirAccess`, recurse).
2. In each file's text, find every `is_action_pressed("…")`, `is_action_just_pressed("…")`,
   `is_action_just_released("…")`, `is_action("…")`, and `Input.get_action_strength("…")`
   call and collect the quoted action names. A `RegEx` with pattern
   `is_action(?:_just_pressed|_just_released|_pressed)?\("([a-z_]+)"` plus a second
   one for `get_action_strength\("([a-z_]+)"` is enough.
3. For each collected name, `check(InputMap.has_action(name), "action %s exists" % name)`.
   Built-in `ui_*` actions count as existing.
4. Also check that at least ten distinct names were found, so the test cannot pass
   by finding nothing.

**Done when:** the new test passes inside `./check.sh`, nothing else changed.
No other files are touched.

---

## T2 — Add two hull variants to the part kit

- [x] Done

**Why:** M6 wants a larger part kit. These two are copies of existing parts with
different dimensions, so there is nothing to design.

**Edit only:** `tools/blender/make_part_kit.py`, `godot/tests/test_part_import.gd`.
**Generated output:** two new files under `godot/assets/models/parts/` plus their
`.import` sidecars (Godot writes those when `./check.sh` runs its import step).

**Parts to add, exact numbers:**

| name | based on | change |
|---|---|---|
| `hull_segment_c` | `hull_segment_a` (6 m long, 2 m radius, 4200 kg, 900 cr) | 9 m long, same radius, mass 6300 kg, value 1350 cr |
| `radiator_panel_c` | `radiator_panel_a` (`radiator(n, 2.0, 1.0, 8)`) | `radiator(n, 3.0, 1.0, 12)` |

For `hull_segment_c`, add a small function next to `hull_small`:

```python
def hull_long(name):
    body = build_hull_segment(name, 9.0, 2.0)
    body["mass_kg"] = 6300.0
    body["value_cr"] = 1350.0
    return body
```

(`build_hull_segment` already returns the mesh object.) Register it as
`"hull_segment_c": hull_long`.

**Steps:**
1. Add the two `BUILDERS` entries next to the existing ones.
2. Regenerate: `blender -b -P tools/blender/make_part_kit.py -- --out godot/assets/models/parts`
3. In `test_part_import.gd`, add the two parts to `KIT` with kind and size:
   `"hull_segment_c": ["hull", Vector3(4, 4, 9)]` and
   `"radiator_panel_c": ["radiator", Vector3(3, 1, .12)]` (radiator_panel_a is
   `Vector3(2, 1, .12)`, so width is X).
4. Change the kit-size check from 12 to 14.
5. `./check.sh` (the full one, it runs the import).

**Done when:** `./check.sh` is green with 14 kit parts, and the two `.glb` files plus
`.import` sidecars are committed. Do not delete or rename any existing part.

---

## T3 — Stress test: a fast-spinning wreck must not gain energy

- [x] Done

Measured 2026-09-11: it does gain energy. Over 1800 frames at ~3.1 rad/s:
angular momentum magnitude +23.3%, rotational energy +50.7%. Committing the
failing test as measurement, per the task; `wreck_body.gd` untouched.

Fixed 2026-09-11 (Conrad asked for the fix after seeing the numbers). The old
correction was a per-tick torque, a chord step along the arc, which inflated
|L| by ~dt²·|ω×L|²/2 every tick; the effect scales with spin⁴, invisible at
slow spin and violent at fast. `WreckBody` now rotates L back about the mean
spin axis each tick (Heun midpoint refinement) and writes angular velocity
directly, so |L| is exact by construction. Same stress test now: momentum
magnitude +0.00005, energy +0.0007 over 1800 frames. The old slow-spin
precession test still passes unchanged.

**Why:** the wreck rotation code applies a small correction every frame
(`godot/scripts/salvage/wreck_body.gd` around line 74). We want to know, not guess,
whether that stays stable at high spin. **This task only measures. Do not fix
anything.**

**Edit only:** `godot/tests/test_wreck_rotation.gd` (add one new test function; keep
the existing one unchanged).

**What the new test does:** copy the setup of the existing test in that file, then
give the wreck an angular velocity of `Vector3(3.0, 0.7, 0.2)` rad/s (an off-axis
tumble), record rotational kinetic energy and angular momentum, run 1800 physics
frames using the file's `_frames` helper, and check:
- angular momentum magnitude changed by less than 2%;
- rotational kinetic energy did not grow by more than 5% (it may fall).

Use the existing `_angular_momentum` helper. For energy use
`0.5 * angular_velocity.dot(inertia_tensor * angular_velocity)` with whatever the
existing test already uses to read inertia; copy its approach.

**Done when:** the test is committed **whether it passes or fails**. If it fails,
commit it anyway with the failing result described in the commit body, and tell
Conrad the exact numbers. Do not change `wreck_body.gd`.

---

## T4 — Test that every scene file loads headless and frees cleanly

- [x] Done

**Edit only:** create `godot/tests/test_scenes_load.gd`.

**What it does:** for each `.tscn` under `res://scenes` and `res://ui` (recurse with
`DirAccess`), `load()` it, check the result is a `PackedScene`, `instantiate()` it,
check the instance is not null, then `free()` it. Count scenes found and check the
count is at least 5.

If instantiating a scene prints errors about missing autoloads or needs
`add_child` to work, **do not** start adding scaffolding: stop and report which
scene, and the exact error text.

**Done when:** the test passes in `./check.sh` and only the one new file was added.

---

## T5 — Accept warp rates that are equal within rounding

- [x] Done

**Why:** `godot/scripts/world/orbital_flight.gd` line ~343 compares floats with exact
equality: `value not in [1.0, 10.0, 100.0, 1000.0]`. Works today, fragile later.

**Edit only:** that one condition in `orbital_flight.gd`, plus one new test function
in `godot/tests/test_orbital_flight.gd` (that file already tests `set_warp` against
the real flight code; `test_flight_api.gd` uses a stub and will not see the change).

**Change:** replace the exact-membership test with a small helper at the bottom of
the file:

```gdscript
func _is_allowed_warp(value: float) -> bool:
	for allowed: float in [1.0, 10.0, 100.0, 1000.0]:
		if is_equal_approx(value, allowed):
			return true
	return false
```

and use `not _is_allowed_warp(value)` in the condition. Change nothing else in the
file. **Test:** copy the setup of the test in `test_orbital_flight.gd` that checks
"aboard in open orbit can warp" (line ~78), and check that `api.set_warp(10.0 + 1e-9)`
returns true and `api.set_warp(11.0)` returns false.

**Done when:** `./check.sh` is green and the diff to `orbital_flight.gd` is only the
condition and the new helper.

---

## T6 — Frame-rate line on the debug HUD

- [x] Done

**Edit only:** `godot/scripts/world/main.gd`, the single line that sets
`_supplies.text` (around line 97, the PROPELLANT / BATTERY readout). Append
`  |  FPS %d` to that format string and `Engine.get_frames_per_second()` to its
argument list. No new files, no new nodes, no new keys, no toggles.

**Done when:** `./check.sh` is green, and a screenshot (`F12` in the running game,
saved under `godot/build/screens/`) shows the FPS value. Tell Conrad the screenshot name.

---

## T7 — Fix a misleading comment in the wreck spin test

- [x] Done

**Edit only:** `godot/tests/test_wreck_rotation.gd`, the comment block above
`test_fast_tumble_does_not_gain_energy` (around lines 32–37).

The comment says the old gyroscopic correction "double-counted Jolt's own
conservative rotation and was removed the same day". That is wrong: it was
**replaced**, not removed. Change those two lines so the block reads:

```
## Stress measurement: spawn the wreck tumbling fast (~3.1 rad/s off-axis) and
## run 1800 physics frames. Measured red on 2026-09-11 (+50% energy per 30 s)
## while the correction was a per-tick torque; that torque was replaced the
## same day by a per-tick rotation of the momentum vector (see WreckBody).
## This now holds to machine precision; the tolerance stays loose to
## respect Jolt's own integration drift.
```

No code changes. **Done when:** `./check.sh --quick` is green and the diff is
comment lines only.

---

## T8 — Input-action test: also check the four tool-slot actions

- [x] Done

**Edit only:** `godot/tests/test_input_actions.gd`.

**Why:** `player.gd:101` builds the action name from a template,
`"tool_slot_%d" % (slot + 1)`, so the regex scan never sees `tool_slot_1..4`.
They are defined in `project.godot` today, but a rename there would slip past
the test.

**Change:** inside `test_input_actions_exist_in_map`, after the existing `for`
loop, add:

```gdscript
	# player.gd builds these names from a template, so the regex scan misses them.
	for slot: int in range(1, 5):
		var slot_action: String = "tool_slot_%d" % slot
		check(InputMap.has_action(slot_action), "action %s exists" % slot_action)
```

Nothing else changes. **Done when:** `./check.sh --quick` is green and the
test's check count went up by exactly 4.

---

## T9 — Style guard: narrow one pattern and drop a dead one

- [x] Done

**Edit only:** `godot/tests/test_gdscript_idioms.gd`, two entries in the
pattern list near the top of the file.

1. Line 21, the `.instance()` entry. Its pattern `\\.instance\\s*\\(` matches *any*
   method called `instance(`, which a legitimate Godot 4 script might have.
   Replace the entry with one that only fires when the receiver looks like a
   scene being spawned, i.e. `.instance()` with **no arguments**:
   ```
   [".instance() (use .instantiate())", "\\.instance\\s*\\(\\s*\\)", false],
   ```
2. Line 29, the "Godot 3 math helpers" entry. It includes `rad2rad`, which was
   never a Godot function, so that alternative can never match. Remove
   `\\brad2rad\\s*\\(|` from the pattern. Leave `rad2deg`, `deg2rad`,
   `linear2db`, `db2linear` in place.

Do not add new patterns. Do not change the comment/string blanking code.
**Done when:** `./check.sh --quick` is green and `git diff` shows exactly two
changed lines.

---

## T10 — New part family: lattice truss segments (three lengths)

- [ ] Done

**Why:** M6 wants the kit at 30+ parts with parametric generators. T2 reused
existing generators with new numbers. This task adds a generator that does not
exist yet: an open lattice truss (four corner rails, end frames, diagonal
braces). It is a new `part_kind`, so the tests that list kinds grow by one.

**Edit only:** `tools/blender/make_part_kit.py`, `godot/tests/test_part_import.gd`,
`godot/tests/test_part_catalog.gd`.
**Generated output:** three new `.glb` files under `godot/assets/models/parts/`
plus their `.import` sidecars (Godot writes those when `./check.sh` runs).
Do not touch `tools/blender/make_part.py` or any game script.

**Parts, exact numbers (Blender axes: X = width, Y = length/forward, Z = height):**

| name | length (Y) | cross-section (X × Z) | mass_kg | value_cr |
|---|---|---|---|---|
| `truss_segment_a` | 2.0 m | 1.0 × 1.0 m | 120.0 | 180.0 |
| `truss_segment_b` | 4.0 m | 1.0 × 1.0 m | 240.0 | 360.0 |
| `truss_segment_c` | 6.0 m | 1.0 × 1.0 m | 360.0 | 540.0 |

All three: `part_kind` `"truss"`, material `"aluminium"`, colour `ALUMINIUM`,
`thickness_mm` 5.0, `volume_m3` = 1.0 × 1.0 × length (the envelope, same idea
as the radiator).

**Geometry, built only from the existing `box()` and `join()` helpers:**

1. **Four rails.** Boxes of size `(0.10, length, 0.10)` centred at
   `(±0.45, 0, ±0.45)`. Their outer faces sit exactly on ±0.5, which is what
   gives the part its bounds. Nothing else may reach further out than the rails.
2. **Two end frames.** At each end (`y = ±(length/2 − 0.05)`), four boxes of
   thickness 0.10 closing the square between the rails: two along X
   (size `(0.80, 0.10, 0.10)` at `z = ±0.45`) and two along Z
   (size `(0.10, 0.10, 0.80)` at `x = ±0.45`).
3. **Diagonal braces.** Divide the length into 1.0 m bays (2, 4 or 6 bays).
   In every bay, put one diagonal on each of the four faces, alternating
   direction from bay to bay so the pattern zig-zags. A diagonal is a bar of
   thickness 0.08 m running between two points. For a side face at `x = ±0.45`,
   the endpoints are `(x, bay_start + 0.10, −0.40)` and `(x, bay_end − 0.10, +0.40)`
   (or mirrored in Z on the alternate bay). Top and bottom faces are the same
   with X and Z swapped. The 0.10 and 0.40 insets are there so the rotated
   bar's corners stay inside the ±0.5 envelope; do not enlarge them.

   Write a new helper for this, `bar(start, end, thickness)`, next to `box()`.
   It should make a box of size `(thickness, distance, thickness)`, rotate it so
   its local +Y points from `start` to `end`, move it to the midpoint, and apply
   the transform. Hint: `socket()` already turns a direction into an Euler
   rotation with `Vector((0, 1, 0)).rotation_difference(direction).to_euler()`;
   set that on `body.rotation_euler`, set `body.location`, then call
   `bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)`.
   Test `bar()` on its own first: `bar((0, 0, 0), (0, 2, 0), 0.1)` must give the
   same shape as `box((0.1, 2, 0.1))`, and `bar((0, 0, 0), (0, 0, 2), 0.1)` must
   stand upright along Z.
4. **Join** everything into one mesh and `finish()` it.
5. **Sockets:** `fore` at `(0, length/2, 0)` facing `(0, 1, 0)` and `aft` at
   `(0, −length/2, 0)` facing `(0, −1, 0)`, default size M. Put the cut points on
   the top-starboard rail, not in the empty middle: `cut_point=(.45, ±(length/2 − .35), .45)`.

**Triangle budget:** the import test refuses parts of 2000 triangles or more.
Each bevelled box is 44 triangles. The 6 m truss has 4 rails + 8 frame bars +
24 diagonals = 36 boxes ≈ 1584 triangles, so it fits, but only just. Do not add
intermediate frames or extra bars. If a part still comes out over budget, drop
the top and bottom diagonals and keep the side ones.

**Register** in `BUILDERS` as `"truss_segment_a": lambda n: truss(n, 2.0)` and
so on, next to the radiator entries. Change the docstring's "fourteen-part" to
"seventeen-part".

**Steps:**
1. Write `bar()` and `truss(name, length)`; add the three `BUILDERS` entries.
2. Regenerate: `blender -b -P tools/blender/make_part_kit.py -- --out godot/assets/models/parts`
   (the same command T2 used; it rewrites every part, and the existing ones must
   come out byte-identical apart from the three new files).
3. In `test_part_import.gd`: add to `KIT`
   `"truss_segment_a": ["truss", Vector3(1, 1, 2)]`,
   `"truss_segment_b": ["truss", Vector3(1, 1, 4)]`,
   `"truss_segment_c": ["truss", Vector3(1, 1, 6)]`
   (Blender Y becomes Godot Z, so length is the last number). Change the
   kit-size check from 14 to 17 and its message to "seventeen". Change the
   kinds check from 7 to 8 and add "truss" to its message.
4. In `test_part_catalog.gd`: add `"truss"` to `KNOWN_KINDS`; change the count
   from 14 to 17 and its message to "seventeen".
5. `./check.sh` (the full one, it runs the import).

**Done when:** `./check.sh` is green with 17 kit parts, the three `.glb` files
and their `.import` sidecars are committed, and `git status` shows no changes to
the other fourteen `.glb` files. If the bounds check fails for a truss, the
diagonal insets are wrong; fix the geometry, do not loosen the test. Do not
delete or rename any existing part. Commit and stop.

---

## Not for the local model (leave for GPT)

Docking, market, insurance, save/load, the derelict generator, anything in the
orbital core or the orbital-to-local handoff beyond T5, and any change to feel,
controls, or physics tuning. If Conrad asks for one of these, say it is on the
GPT list and ask him to confirm before starting.
