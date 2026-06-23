# 11 — Interplanetary Transfer Planner (cross-SOI "FIND WINDOW")

**Status:** ✅ implemented (2026-06-23). Supersedes the two-step interplanetary flow
shipped in M2 ([05 §M2](05-roadmap.md)) with the one-button flow the design always
implied. Also folds in two small, related fixes (warp + time display). The §2.3 design
below reflects what shipped, including the implementation-time corrections (minimal
ejection + parent-frame injection; resolve-gating across the handoff).

---

## 0. Why

Today's `FIND WINDOW (interplanetary)` ([planTransferWindow](../src/sim/api.ts)) only
works **after** you've manually escaped your body and are co-frame with the destination
planet. That has two consequences, both of which a play session just surfaced:

1. **You can't aim before you leave.** Selecting Vesper from low Cradle orbit gives
   `Vesper is in another body's sphere of influence — escape your current SOI first`.
   The planner refuses to look at the trip until you've already committed to it.
2. **Manual escape overshoots.** With the ~12.2 km/s interplanetary drive, "burn
   prograde until I leave Cradle" dumps far more than the ~3.2 km/s needed and flings
   you onto a large eccentric *solar* orbit (a = 2–6 AU). From there a transfer back
   in to Vesper is genuinely slow and dear, and the porkchop's TOF range — which scales
   off the ship's now-enormous period — offers multi-year / decade departures. (Verified:
   a 1200 s manual escape → a = 6 AU, e = 0.85, window TOF 3387 d, Δv 15 km/s. That is
   the "depart in ~100 years" the player saw — **not** a `maxRevs` bug.)

The fix is the planner the roadmap deferred: **a real interplanetary transfer planner
invoked from inside the departure body's SOI that sizes the ejection burn itself.** It
removes the overshoot footgun and the cross-frame confusion in one move.

This stays inside the three keystones: it's a deterministic solver in `src/sim`
(Keystone 2 — the AI/panels only *call* it), it's one API used by every client
(Keystone 1), and the client computes no truth (Keystone 3).

---

## 1. The mental model (what the player gets)

From a parking orbit around **Cradle**, select sibling planet **Vesper** and press
**FIND WINDOW → PLANET**. The planner returns ONE reviewable plan:

```
TRANSFER → Vesper        depart +603 d   arrive +827 d
  1  EJECTION    Cradle → Sol      Δv 3.22 km/s   prograde (clears the SOI)
  2  INJECTION   heliocentric      Δv ~3.8 km/s   (guided, resolved live in the Sol frame)
  3  TRIM        heliocentric      Δv ~1.0 km/s   (guided)
  4  TRIM        heliocentric      Δv ~0   (guided)
  (capture into Vesper's SOI happens on the coast; circularize manually to park)
```

Execute → the executor flies the ejection burn, the SOI handoff drops you into the Sol
frame, the guided injection + trims fly the heliocentric leg, and the transfer threads
Vesper's position so you enter its SOI on a close approach. Circularize there to park
(manual, like docking). The two-step flow still exists for hand-flyers; this is the
guided path that "just works." *(Numbers above are the actual Cradle→Vesper solve.)*

---

## 2. The math

Departure body **A** (current, e.g. Cradle) and destination body **B** (e.g. Vesper)
both orbit the same parent **P** (Sol). All of A's and B's states are already analytic
via [`System.bodyStateInRoot`](../src/sim/system.ts). The planner has three pieces.

### 2.1 Heliocentric porkchop (the outer leg) — *frame-independent*

This runs in the **parent (Sun) frame** regardless of which SOI the ship is in — which
is exactly why it can be computed from inside Cradle's SOI. Search departure time
`t_dep` × time-of-flight `tof`:

- `rA, vA = bodyStateInRoot(A, t_dep)` — A's heliocentric state at departure.
- `rB     = bodyStateInRoot(B, t_dep + tof).position` — B's heliocentric position at arrival.
- `vB     = bodyStateInRoot(B, t_dep + tof).velocity`.
- `lambert(rA, rB, tof, μ_P)` → `v_dep` (heliocentric velocity the ship must have leaving
  A's position) and `v_arr` (heliocentric velocity at B on arrival). Reuse the existing
  Lambert ([solvers.ts](../src/sim/solvers.ts)) unchanged.
- **Hyperbolic excess at departure:** `v∞_out = v_dep − vA`.
- **Hyperbolic excess at arrival:**   `v∞_in  = v_arr − vB`.

**Cost model (what we score on):** the burns the ship actually pays, not the bare
heliocentric Δv —

- **Ejection** from a parking orbit of radius `r_pA` around A:
  `v_peri = √(|v∞_out|² + 2μ_A/r_pA)`, `Δv_eject = v_peri − √(μ_A/r_pA)`.
- **Arrival/capture** into a parking orbit of radius `r_pB` around B:
  `Δv_capture = √(|v∞_in|² + 2μ_B/r_pB) − √(μ_B/r_pB)`.
- Score = `Δv_eject + Δv_capture`.

`r_pA` = the ship's *current* orbital radius about A (so the burn is sized for where the
ship actually is); `r_pB` = a default low parking radius about B (e.g. B.radius + 200 km).

### 2.2 Sane, bounded, soonest-first search

The current porkchop's ranges scale off orbital periods — the root of the decade-long
TOFs. Replace them with ranges anchored to the **Hohmann transfer between the two
heliocentric radii**, which is physical and bounded:

- `t_H = π·√(a_t³/μ_P)` where `a_t = (|rA| + |rB|)/2` (Hohmann half-ellipse time).
- `tofMin = 0.35·t_H`, `tofMax = 1.75·t_H` (covers fast and slow direct arcs; no decades).
- `departSpan = 1.5 · synodic period` of A vs B (≥ one full window recurrence).
- **Prefer the soonest acceptable window, not the absolute cheapest.** Accept the first
  window within `MARGIN` (e.g. 1.15×) of the cheapest-seen Δv; among those, pick the
  earliest departure. (Optimum-decades-out is never what the player wants.)
- Coarse grid (48 × 40) → refine ±1 cell, as today, but over the bounded ranges.
- `maxRevs = 0` (direct interplanetary arc is the norm).

Guards: if either body is the root, or A and B don't share a parent, or no cell solves,
return `null` with a clear reason. This also fixes the **degenerate cross-frame garbage**
the old `suggestTransferWindow` produced when fed a target propagated about the wrong body.

### 2.3 Ejection burn + heliocentric leg (the inner legs)

The plan spans two frames. Node Δv is always *local* (prograde/normal/radial of the
current orbit) and resolved from live state at execution time, so a single plan can
cross the A→P handoff cleanly.

**Key insight (learned in implementation):** a burn *inside* A's SOI can't freely aim the
heliocentric `v∞`. A prograde ejection to an *inner* planet adds energy the wrong way —
the ship just lands on a slightly-higher copy of A's solar orbit, and correcting that in
the parent frame costs more than the budget. So the ejection is kept **cheap and minimal**
(just clear the SOI near the departure time), and the **real transfer burn is done in the
parent frame**, where a Lambert solution can point any direction.

- **Ejection node (A frame), at `t_eject ≈ departure time`:** burn **prograde**, sized for
  a *modest* hyperbolic excess (`EJECT_VINF ≈ 1 km/s`): `Δv = √(EJECT_VINF² + 2μ_A/r0) − v0`.
  Enough to clear the SOI in a few days, small enough that the heliocentric orbit stays
  near A's. `t_eject` is the point in the parking orbit whose prograde best aligns with
  `v∞_out` (so the small excess we add points the right way, shrinking the injection).
- **Predicted escape time `t_esc`:** the analytic outbound SOI crossing of the post-burn
  hyperbola ([`nextEscapeTime`](../src/sim/orbit.ts)). All parent-frame burns are scheduled
  **after** `t_esc` — before it the ship is still in A's frame and B's heliocentric elements
  would propagate about the wrong body.
- **Injection node (P frame), just after `t_esc`:** a guided `retarget:{kind:"transfer",
  targetEl: B_helio, arrivalTime: t_arrive, maxRevs:0}` — **this is the real transfer burn.**
  [`resolveRetarget`](../src/sim/world.ts) re-solves the Lambert leg from the ship's *actual*
  post-escape heliocentric state to B's arrival position, so it aims correctly regardless of
  the ejection direction (~3–4 km/s for Cradle→Vesper).
- **Two trim nodes (P frame):** at `t_inject + f·(t_arrive − t_inject)` for `f ∈ {0.45, 0.8}`,
  same `transfer` retarget — cancel the residual open-loop error of the long arc (small Δv).
- **Arrival:** no match burn. The transfer threads B's position, so the ship enters B's SOI
  on the coast and the capture handoff ([`computeNextSoi`](../src/sim/world.ts)) drops it into
  B's frame on a close approach. Circularizing into a parking orbit is a manual follow-up
  (consistent with the docking MVP; powered capture is §6).

**Resolve gating (critical):** a retarget is resolved only once *no SOI handoff is still
pending before its node time* — otherwise the executor would resolve a parent-frame trim
while still in A's frame (the bug that froze every trim to a garbage Δv). `jumpToNextNode`
is likewise made SOI-aware: it coasts *through* a pending handoff (via `stepCoastWithSoi`)
instead of teleporting past it.

`B_helio` = the destination body's orbit-about-parent elements (`System.body("vesper").
elements`), i.e. the same heliocentric element set the Vesper *target* already carries.

---

## 3. Where the code goes

### New solver — `src/sim/solvers.ts`
- `suggestInterplanetaryWindow(A, B, system, tNow, r0, opts)` → `{ departureTime,
  arrivalTime, tof, vInfOut: Vec3, vInfIn: Vec3, dvEject, dvCapture } | null`. The §2.1–2.2
  porkchop. Pure: takes the two `Body`s + `System` + the ship's current radius `r0`.
- `solveInterplanetaryTransfer(shipEl, A, system, tNow, B, window, opts)` →
  `ManeuverInput[] | null`. Assembles the §2.3 nodes (ejection + trims + arrival). Pure;
  emits node inputs only, like every other solver.

### API — `src/sim/api.ts`
- Rework `planTransferWindow(w)`: **drop the co-frame gate.** Resolve the destination
  **body** from the selected target (a target that *is* a sibling body — see §4), run
  `suggestInterplanetaryWindow` from the current body, then `solveInterplanetaryTransfer`,
  `buildPlan`, park it. Return `null` with reason when the target isn't a transferable
  sibling, or no window solves.
- Keep `planIntercept` / `planMatchVelocity` co-frame-gated (they're the in-frame
  rendezvous instruments — unchanged).

### Targets — `src/sim/world.ts`
- The destination needs to resolve to a `System` **Body** (for μ, SOI, capture), not just
  a heliocentric element set. Add `TargetDef.transferBodyId?: string` (e.g. Vesper's
  target → `"vesper"`). `planTransferWindow` uses it; absence ⇒ "not a transfer
  destination."

### Server — `src/server/index.ts`
- `/api/maneuver/transfer_window` already exists; it now succeeds cross-frame. Update the
  failure path: when it returns `null`, send a 422 with the planner's reason (not the old
  "escape first" 409).

### AI — `src/server/ai-bridge.ts`
- `solve_transfer_window` tool description: "plan a full interplanetary transfer from your
  current body to a sibling planet — sizes the ejection burn for you; no need to escape
  first." Update the BEHAVIOR block: interplanetary travel is now **one** guided plan.

### Client — `src/client/maneuver-panel.ts`
- Relabel the button `FIND WINDOW → PLANET` (it no longer requires escaping first). Show
  the returned plan's depart/arrive/Δv summary. No new view needed.

### Tests — `scripts/check-sim.ts`
- Cradle→Vesper from a 400 km parking orbit: a window solves, departure is within the
  bounded horizon (not decades), total Δv ≤ budget.
- Flown end-to-end (advance through the plan at warp): ship escapes Cradle, hands off to
  Sol, and is captured into Vesper's SOI; final range to Vesper within its SOI.
- Soonest-first: with two windows in range, the earlier one is chosen when within margin.
- Bounded-TOF guard: TOF ≤ `tofMax`, no decade-long result even from an eccentric start.

---

## 4. Small fix A — x10 warp at all times

**Why it's blocked now.** Two auto-limits slam warp to **1×**:
[`limitWarpForSoi`](../src/sim/world.ts) (within `SOI_LEAD` = 120 s of an SOI handoff) and
the burn-window clamp in [`driveExecutor`](../src/sim/world.ts) (within `max(20s, burnDur)`
of a node). Both exist for good reasons — don't blast through a capture, and integrate a
burn on the fixed `DT_PHYS` grid — but they're **over-conservative**: they kill *all* warp,
including a gentle 10×.

**Why 10× is safe to keep.** Coasting is analytic and `stepCoastWithSoi` already clamps each
jump exactly to the boundary, so 10× can't skip a handoff. Burns step on a fixed
`DT_PHYS = 1/64 s` grid regardless of warp — 10× merely means ~10 substeps per render tick
(vs. `MAX_SUBSTEPS = 4096`), so integration fidelity is unchanged. It's only the *high*
warps (100×+, which would balloon substeps and flash past events) that must drop near
events.

**Fix.** Introduce `const SAFE_WARP = 10`. In both clamps, replace "force to 1×" with
"clamp to `min(rate, SAFE_WARP)`":
- `limitWarpForSoi`: `if (this.rate > SAFE_WARP) this.rate = SAFE_WARP;` (+ set
  `warpAutoLimited` only when it actually lowered the rate).
- `driveExecutor` burn window: same clamp instead of `if (rate>1) rate=1`.
- The `⚠ HELD` badge ([nav-panel.ts](../src/client/nav-panel.ts)) keeps meaning "warp was
  auto-lowered" — now it lights when clamped from >10× down to 10×.

Result: 10× is always selectable and never force-dropped; 100×/1000×/10000× still clamp
to 10× near burns and SOI boundaries.

## 5. Small fix B — day:hour:minute:second time display

`hms()` currently formats `HH:MM:SS` and overflows hours past a day (e.g. 50 h shows
`50:..`). The countdowns here run to hundreds of days, so add a day field.

- New shared `dhms(seconds)` → **compact**: `HH:MM:SS` under a day, `D:HH:MM:SS` once it
  passes 24 h (days uncapped, no leading zero; hours/min/sec zero-padded). E.g. `00:51:23`,
  `137:04:09:51`. Non-finite ⇒ `--:--:--`. *(Decision: hide the day field under 24 h.)*
- Replace `hms` in [nav-panel.ts](../src/client/nav-panel.ts) (T-PERIAPSIS, T-APOAPSIS,
  T-ESCAPE, SIM CLOCK, SOI XFER) and the duplicate in
  [system-map.ts](../src/client/system-map.ts). Widen the value column pad to fit
  (`9 → 12`).

---

## 6. Out of scope (noted, not built now)

- **Optimal 3-D ejection geometry** (exact asymptote alignment / Oberth-optimal burn point
  and split-plane ejection). MVP uses magnitude-correct prograde ejection + guided trims;
  this is a refinement if the trims ever cost too much.
- **Powered capture / auto-circularization** at the destination. Arrival matches B's
  heliocentric velocity and lets the SOI capture happen; parking is manual.
- **Mid-trip re-planning UI** beyond the existing guided trims.

---

## 7. Stages (each: `npm run typecheck` + `npm run check` green)

1. **Warp + time display** (fix A + B) — small, self-contained, immediately testable.
2. **`suggestInterplanetaryWindow`** (porkchop math) + its check-sim assertions (window
   solves, bounded, soonest-first).
3. **`solveInterplanetaryTransfer`** (node assembly) + API rework + target `transferBodyId`.
4. **Server/AI/client wiring** (route reason, tool/persona text, button relabel + summary).
5. **End-to-end flown test** (escape → Sol → capture into Vesper) + roadmap note.
