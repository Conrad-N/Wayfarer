# Fix Specs — Wayfarer Health Pass

**Date:** 2026-06-22 · Companion to [HEALTH-REPORT.md](HEALTH-REPORT.md). Every finding
from the audit, with a full implementation spec: root cause, the exact change (with code),
acceptance criteria, and risk notes. This is a punch list to work through — nothing here is
implemented yet.

**Ground rules that constrain every fix:**
- `src/sim/**` stays pure & deterministic — no `Date.now()`, no `Math.random()`, no Node/DOM,
  identical output for identical inputs (Keystones 1 & 3).
- Unit conversion (SI → friendly) only at the client edge.
- After any change: `npm run typecheck` clean and `npm run check` green. Several specs add new
  assertions to [scripts/check-sim.ts](../scripts/check-sim.ts).

**Suggested order:** C1 → H1 → H2 → H3 → C2 → H4/H5 → H6/H8/H9 → Mediums → Lows.

Legend: ⏱ effort (S < 30 min · M a couple hours · L a day+) · 🎯 risk of regression.

---

# Critical

## C1 — Wrap the sim tick in an error boundary ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/server/index.ts:45-50](../src/server/index.ts#L45-L50)

**Problem.** The tick is the heartbeat of the server-authoritative sim. It calls
`world.advance(...)` with no guard:
```ts
let last = performance.now();
setInterval(() => {
  const now = performance.now();
  world.advance((now - last) / 1000);
  last = now;
}, 50);
```
If `advance()` ever throws (a degenerate solver in `driveExecutor`/`resolveRetarget`, a NaN
reaching `stateToElements`, any future sim bug), the exception escapes the interval callback.
Sim-time stops advancing while the HTTP server keeps answering with frozen telemetry — the AI
reads a dead clock, panels render a frozen orbit, and nothing signals that the authority died.

**Fix.** Catch, log, keep the clock honest, and stop runaway warp on repeated failure. Also
install process-level handlers so a stray async throw is visible rather than silent.
```ts
let last = performance.now();
let tickFailures = 0;
setInterval(() => {
  const now = performance.now();
  try {
    world.advance((now - last) / 1000);
    tickFailures = 0;
  } catch (e) {
    console.error("[sim] tick failed:", e);
    // Don't let a broken state keep getting time-warped: fall back to real-time
    // until it recovers, and after a burst of failures stop advancing the burn.
    if (++tickFailures >= 5) world.rate = 0;
  } finally {
    last = now; // always advance the clock reference so we don't bank a huge delta (see M-tick)
  }
}, 50);

process.on("uncaughtException", (e) => console.error("[fatal] uncaughtException:", e));
process.on("unhandledRejection", (e) => console.error("[fatal] unhandledRejection:", e));
```

**Acceptance.**
- Manually throw once inside `advance()` (temporary), confirm the server keeps serving and logs
  the error instead of freezing/exiting; remove the throw.
- Normal play unaffected; `npm run check` green (no sim change).

**Notes.** Pair the `finally { last = now }` with the clamp in **M-tick** so a long synchronous
stall can't inject a giant time jump on the next tick.

---

## C2 — Powered flight must integrate on a fixed sim-time quantum, not wall-clock `dt` ⏱L 🎯med — ✅ DONE (2026-06-22)

**Where:** [src/sim/world.ts:202-216](../src/sim/world.ts#L202-L216),
[src/sim/world.ts:277-318](../src/sim/world.ts#L277-L318) (`driveExecutor`),
[src/sim/world.ts:352-376](../src/sim/world.ts#L352-L376) (`stepPoweredFlight`)

**Problem (determinism hole).** `advance(realDtSeconds)` decides throttle **once per
wall-clock tick** (`driveExecutor` runs at the top of `advance`), then subdivides
`simDelta = realDtSeconds * rate` into fixed `DT_PHYS` (=1/64 s) substeps carrying the
remainder in `physAccum`. The trajectory is only deterministic in *total elapsed sim-time* if
the throttle on/off transitions land at the same sim-time on every machine. But the throttle
decision is re-evaluated per variable, frame-paced tick, so two machines with different frame
cadence cross `burnStart` at a different `physAccum` phase, execute a different integer number
of `throttle===1` substeps, and diverge in `burnDelivered` and final `(r, v)`.
[docs/10](10-flight-model.md) §3 promises identical inputs → identical trajectories — multiplayer
and the away-game depend on it. (The analytic coast path is exact and fine; this is confined to
the powered path + the executor's per-tick control decisions.)

**Fix (design).** Move control decisions onto the fixed substep grid so the burn is a pure
function of elapsed sim-time:
1. Accumulate sim-time into `physAccum` first, then run the sim in whole `DT_PHYS` chunks.
2. Inside the substep loop, make the throttle/attitude decision **at each substep boundary**
   from the sim-time at that boundary (`this.time`), not once per outer tick. In practice: call
   a lightweight `driveExecutor()` (or just the throttle-gating part of it) inside the loop
   before each `stepPowered`, keyed off `this.time` vs `burnStart`/`burnDelivered`.
3. Gate the `burnStart`/`burnDelivered` comparisons strictly on sim-time thresholds so the same
   set of substeps fire regardless of how the wall-clock delta was chunked.

Sketch of the restructured `advance`:
```ts
advance(realDtSeconds: number): void {
  this.physAccum += realDtSeconds * this.rate;
  let steps = 0;
  while (this.physAccum >= DT_PHYS && steps < MAX_SUBSTEPS) {
    if (this.executorOn) this.driveExecutor();          // decide throttle at THIS sim-time
    const powered = this.throttle > 0 && this.ship.propellantKg > 0;
    if (powered) {
      if (!this.poweredState) this.seedPowered();
      this.stepPoweredSubstep(DT_PHYS);                 // exactly one DT_PHYS of powered integration
    } else {
      if (this.poweredState) this.foldToCoast();
      this.stepCoast(DT_PHYS);                          // coast in fixed chunks too, for symmetry
    }
    this.physAccum -= DT_PHYS;
    this.time += DT_PHYS;
    steps++;
  }
  // sub-DT_PHYS remainder: coast-only analytic catch-up is exact, so it's safe to apply it as a
  // partial coast when NOT powered; while powered, leave it in physAccum for the next tick.
  if (this.physAccum > 0 && !(this.throttle > 0 && this.ship.propellantKg > 0)) {
    this.stepCoast(this.physAccum);
    this.time += this.physAccum;
    this.physAccum = 0;
  }
}
```
(The exact refactor must preserve `coastCarry`/`foldToCoast` semantics; keep `stepCoast` analytic.
Coasting can remain a single analytic jump if you prefer — only the *powered + control* path must
be quantized. The minimum viable fix is: **decide throttle per substep, anchored to `this.time`**.)

**Acceptance.**
- Extend the existing determinism test ([check-sim.ts](../scripts/check-sim.ts) "powered integration
  identical regardless of tick size") to drive an **executor-flown** node (not just a fixed
  throttle) through two different tick-chunking schedules (e.g. one 2 s burn delivered as 1×big
  vs many small `advance()` calls with the executor on) and assert final apo/peri and
  `burnDelivered` match to tight tolerance.
- All existing executor tests still pass (autopilot reaches the previewed apoapsis; two-node plan
  consumes both nodes).

**Notes.** This is the largest change here. It's the *real* determinism fix; **C1** protects you
operationally in the meantime. Watch `warpAutoLimited` interaction — warp is already clamped to 1×
near a burn, which shrinks (but doesn't remove) the divergence today.

---

# High

## H1 — `timeToPeriapsis` returns a full period at periapsis ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/sim/orbit.ts:121](../src/sim/orbit.ts#L121)

**Problem.** `timeToPeriapsis: (TWO_PI - meanAnomaly) / meanMotion`. At `meanAnomaly = 0`
(exactly at periapsis) this yields `TWO_PI / meanMotion = period` instead of `0`, and it jumps
discontinuously from ~0 just before periapsis (M≈2π) to a full period at it. The sibling
`timeToApoapsis` ([orbit.ts:97](../src/sim/orbit.ts#L97)) is correct because it wraps:
`wrapTwoPi(Math.PI - meanAnomaly) / meanMotion`.

**Fix.** Mirror the apoapsis form so M=0 maps to 0:
```ts
timeToPeriapsis: wrapTwoPi(TWO_PI - meanAnomaly) / meanMotion,
```
(`wrapTwoPi(2π - 0) = wrapTwoPi(2π) = 0`. ✓)

**Acceptance.** Add to [check-sim.ts](../scripts/check-sim.ts): propagate the canonical orbit to
periapsis (M=0) and assert `timeToPeriapsis ≈ 0`; at apoapsis assert `timeToPeriapsis ≈ period/2`;
and assert `timeToPeriapsis + timeSincePeriapsis ≈ period` for an arbitrary mid-orbit time.

---

## H2 — Guard non-elliptical / degenerate orbits so NaN can't silently poison telemetry ⏱M 🎯med — ⏸ DEFERRED (resolve when a second SoI lands; escape/hyperbolic orbits become real then)

**Where:** [src/sim/orbit.ts:64-126](../src/sim/orbit.ts#L64-L126) (`propagate`),
[src/sim/orbit.ts:27-38](../src/sim/orbit.ts#L27-L38) (`solveKepler`),
[src/sim/maneuver.ts:34-108](../src/sim/maneuver.ts#L34-L108) (`stateToElements`)

**Problem.** `propagate` assumes `0 ≤ e < 1`, `a > 0` but never enforces it. With `e ≥ 1`,
`Math.sqrt(1 - e)` (line 77) and `Math.sqrt(mu*a*(1-e*e))` (line 83) produce `NaN` that
propagates silently into position/velocity and every consumer (nav panel, AI tools, solvers).
`solveKepler` has no hyperbolic branch. `stateToElements` computes `a = -mu/(2*energy)`
([maneuver.ts:67](../src/sim/maneuver.ts#L67)) — for a parabolic burn `energy → 0 ⇒ a → ±∞`; for
a hyperbolic one `e ≥ 1` and `Math.sqrt(1 - e)` at line 104 → NaN mean anomaly. These elements
can be produced by an aggressive `applyBurn` or a bad Lambert leg and fed straight back into
`propagate`.

**Fix (two layers).**
1. **Detect at the source.** In `stateToElements`, after computing `e` and `a`, flag non-finite
   or non-elliptical results rather than returning silent garbage. Simplest robust option for M0
   (single body, bound orbits expected): return the elements but let callers check, OR throw a
   typed error. Recommended: add a cheap validity check helper and have `propagate` refuse to run
   on invalid input:
```ts
// orbit.ts — at the top of propagate()
if (!(el.e >= 0 && el.e < 1) || !(el.a > 0) || !Number.isFinite(el.a)) {
  throw new RangeError(
    `propagate: non-elliptical/degenerate elements (a=${el.a}, e=${el.e}); ` +
    `M0 supports bound orbits only`,
  );
}
```
   Throwing is safe **only because C1 now catches tick-time throws** — do C1 first. For request
   paths, the route-level validation in H4/H5 turns this into a clean 4xx/5xx instead of a crash.
2. **Make the planner honest.** `previewNode`/`buildPlan` currently judge feasibility only on Δv
   and propellant; a burn that yields a hyperbolic/NaN orbit can still be `feasible: true`. Add a
   resulting-orbit validity gate (this is **M-feasible** below — do them together):
```ts
// after computing `after` in previewNode / `after` in buildPlan
const validAfter = Number.isFinite(after.a) && after.e >= 0 && after.e < 1;
const feasible = dvMag > 0 && affordable && validAfter;
// note: "this burn puts you on an escape/hyperbolic trajectory (not supported yet)"
```

**Acceptance.**
- New check: `applyBurn` with a huge prograde Δv produces elements the planner flags
  `feasible: false` with an escape/hyperbolic note (not a NaN `after` with `feasible: true`).
- New check: `propagate` on `e = 1.2` throws a `RangeError` (caught by callers), and a normal
  orbit is unaffected.
- `stateToElements` round-trip on all existing tests still exact.

**Notes.** Keep `src/sim` pure — a thrown `RangeError` is deterministic and fine. If you'd rather
not throw, return a sentinel and have `getOrbit`/tools surface "telemetry unavailable" — but the
planner gate (layer 2) is the important half either way.

---

## H3 — Concurrent AI chats can commit each other's pending burn (confirmation-gate race) ⏱M 🎯med — ✅ DONE (2026-06-22, Option A)

**Where:** [src/server/index.ts:229-247](../src/server/index.ts#L229-L247) (async route over shared
`world`), [src/sim/api.ts:354-377](../src/sim/api.ts#L354-L377) (`executeManeuver` reads/mutates
the single global `world.pendingManeuver`), `selectTarget`/`pendingManeuver` are global slots.

**Problem.** `/api/ai/chat` is fully async over one shared mutable `World` with no serialization.
`pendingManeuver` and `selectedTarget` are single global slots, so session B's
`execute_maneuver(confirm:true)` can fire session A's reviewed-but-uncommitted plan — a burn no
one in B's conversation confirmed. This defeats Keystone 2 and is reachable in the stated
shared-host model. The tick loop also mutates `world` between every `await`.

**Fix (pick one; A is smallest and sufficient for the stated single-ship M1):**

**A. Serialize chat turns with an async mutex.** One ship, one operator-at-a-time mental model:
```ts
// index.ts
let chatChain: Promise<unknown> = Promise.resolve();
app.post("/api/ai/chat", async (req, res) => {
  // ... aiAvailable() + validation (see M-chatvalidate) ...
  const run = chatChain.then(() => runShipAI(world, history, persona));
  chatChain = run.catch(() => {}); // keep the chain alive on failure
  try { res.json({ reply: await run }); }
  catch (err) { /* H5 generic handling */ }
});
```
This guarantees one tool-use loop touches `world` at a time, so a plan-then-execute sequence
inside one turn can't interleave with another turn.

**B. (Stronger, if multi-operator becomes real) Scope the gate per session.** Replace the global
`pendingManeuver` with a keyed map (`Map<sessionId, ManeuverPlan>`); `executeManeuver` takes the
session id and only commits that session's plan. Requires threading a session id from the client.
Defer until the shared-host model is actually built (Q2).

**Acceptance.**
- A test that fires two overlapping `runShipAI` calls where one plans and the other executes; with
  the mutex, the executor only ever commits a plan created in its own turn (or none).
- Single-operator play unchanged.

**Notes.** Document in [docs/03](03-architecture.md)/Q2 that the gate is per-process today; option
B is the multiplayer-correct form.

---

## H4 — Validate `/api/predict` (and other numeric query/body params) ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/server/index.ts:61](../src/server/index.ts#L61)

**Problem.** `app.get("/api/predict", (req, res) => res.json(predictOrbit(world, Number(req.query.t))))`.
`Number(undefined)`/`Number("abc")` is `NaN`, which flows into `propagate(elements, body, NaN)` and
returns an all-NaN `OrbitState` with **HTTP 200**. A huge `t` (e.g. `1e300`) is also accepted.

**Fix.**
```ts
app.get("/api/predict", (req, res) => {
  const t = Number(req.query.t);
  if (!Number.isFinite(t)) {
    return res.status(400).json({ error: "query param t (sim-seconds) must be a finite number" });
  }
  res.json(predictOrbit(world, t));
});
```

**Acceptance.** `GET /api/predict` (no `t`) and `?t=abc` → 400 JSON; `?t=600` → 200 with finite
fields. (Pairs with H2's `propagate` guard, which now also rejects pathological orbits cleanly via
H5's error middleware.)

---

## H5 — Add a global Express error handler; stop leaking stack traces ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** all routes in [src/server/index.ts](../src/server/index.ts); only `/api/ai/chat` has
try/catch.

**Problem.** Every other route calls into the sim synchronously. A throw (now possible from H2's
`propagate` guard, or any solver edge case) produces Express's default **HTML error page with a
stack trace** sent to the client, and there's no central log.

**Fix.** Register a terminal error middleware **after all routes**:
```ts
// after every app.get/app.post, before app.listen
app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error("[http] route error:", err);
  if (res.headersSent) return;
  res.status(500).json({ error: "internal error" });
});
```
Express 5 forwards both synchronous throws and rejected promises from handlers to this middleware,
so most routes need no per-route try/catch. (Keep `/api/ai/chat`'s catch but make its body match
H5 — see M-aileak.)

**Acceptance.** Force a route throw (temporary) → client gets `{ "error": "internal error" }` with
500, server logs the detail. No HTML/stack-trace body ever reaches the client.

---

## H6 — Guard overlapping client polls (in-flight + backoff) ⏱S 🎯low

**Where:** [src/client/main.ts:17-28](../src/client/main.ts#L17-L28)

**Problem.** `setInterval(poll, 100)` fires regardless of whether the previous `poll()` resolved.
Under load an older `/api/state` can resolve last and render after a newer one (altitude/Δv jump
backward). A downed server is hammered 10×/s.

**Fix.** Self-scheduling loop with an in-flight guard and failure backoff:
```ts
const BASE_MS = 100;
let backoff = BASE_MS;
async function poll(): Promise<void> {
  try {
    const res = await fetch("/api/state");
    if (!res.ok) { backoff = Math.min(backoff * 2, 2000); return; }
    const state = (await res.json()) as StateResponse;
    backoff = BASE_MS;
    for (const s of slots) s.render(state);
  } catch {
    backoff = Math.min(backoff * 2, 2000);
  } finally {
    setTimeout(poll, backoff);
  }
}
void poll();
```
This guarantees no two polls overlap (the next is scheduled only after the current settles) and
naturally drops the stale-ordering problem.

**Acceptance.** Throttle the network / stop the server: confirm no overlapping requests in the
Network panel and the request rate decays; restart server → resumes at 100 ms. Telemetry never
visibly steps backward.

---

## H7 — Move scope orbital geometry to the server (Keystone 1) ⏱M 🎯med

**Where:** [src/client/scope.ts:28-31](../src/client/scope.ts#L28-L31) (semi-minor axis, focus
offset), and the target-overlay block ([scope.ts:64-79](../src/client/scope.ts#L64-L79)) deriving
`dArgp`/`ct`/blip angle between two orbits.

**Problem.** The client derives physical geometry the API should own: `b = a·√(1−e²)`, `c = a·e`,
and a relative-argp perifocal projection between the ship and target orbits. This violates
Keystone 1/3 ("the client never computes truth") and silently assumes the two orbits are coplanar.

**Fix (incremental, keep the retro look).** Have the read API return *drawable* geometry so the
client only scales-and-plots:
- Option 1 (smallest): add `semiMinorAxis` and `focusOffset` (= `a·e`) to the `OrbitState` returned
  by `getOrbit`/`getTarget` (computed in `src/sim`, SI), and have the client read them instead of
  recomputing. Removes the ellipse-shape math from the client.
- Option 2 (fuller): add a `scopeGeometry` field — a small polyline of orbit points (PCI, sampled)
  for both ship and target plus the target blip position already expressed in the ship's frame.
  The client just maps SI→pixels. This also kills the coplanar assumption for the overlay.

Recommend Option 1 now (cheap, removes the clearest violation), with a `// TODO Keystone:` note to
do Option 2 when targets gain inclination differences.

**Acceptance.** `scope.ts` contains no orbital-geometry derivation — only SI→pixel scaling and
canvas drawing. Scope renders identically for the current coplanar targets.

**Notes.** This is the only true Keystone violation found. Low operational risk; flagged High
because it's an architecture-rule breach the project explicitly guards against.

---

## H8 — Finite-guard all telemetry formatters ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/client/nav-panel.ts:14-26](../src/client/nav-panel.ts#L14-L26) (`num`/`hms`) and the
equivalent helpers in `flight-panel.ts`, `target-panel.ts`, `maneuver-panel.ts`.

**Problem.** `num()` does `v.toFixed(dp)` and `hms()` does `Math.floor(seconds)` with no finite
check. An `undefined` field throws (`(undefined).toFixed`) and kills the whole panel's
`innerHTML` build; `NaN`/`Infinity` print literally and break the fixed-width column aesthetic
([docs/04](04-aesthetic.md)).

**Fix.** Emit a dash placeholder (matches the "dead segment" look) instead of throwing/garbage:
```ts
function num(v: number, dp: number, width = 9): string {
  return pad(Number.isFinite(v) ? v.toFixed(dp) : "---", width);
}
function hms(seconds: number): string {
  if (!Number.isFinite(seconds)) return pad("--:--:--", 9);
  const s = Math.max(0, Math.floor(seconds));
  // ...unchanged...
}
```
Apply the same guard to the sibling formatters in the other panels (factor into `dom.ts` if you
want one copy).

**Acceptance.** Feed a state with a `NaN`/`undefined` field (temporary) → the panel renders dashes,
not a thrown render or `"NaN km"`. Columns keep their width.

---

## H9 — Escape server-supplied strings before `innerHTML` (XSS) ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** the `row()`/`rowHtml` builders that interpolate values into `innerHTML`:
[nav-panel.ts:46-67](../src/client/nav-panel.ts#L46-L67),
[target-panel.ts:62-74](../src/client/target-panel.ts#L62-L74), `station-panel.ts`,
`flight-panel.ts`, `cargo-panel.ts`. Numeric rows are safe; the hole is string fields rendered raw:
`ship.name`, `body.name`, `target.name`, item/station names, `t.kind`.

**Problem.** "Server-authoritative" ≠ "HTML-safe". The moment a name is AI- or player-influenced,
`` `<span class="v">${value}</span>` `` is stored XSS in every panel.

**Fix.** Add one helper and wrap string interpolations (numbers don't need it but escaping
uniformly is simplest):
```ts
// dom.ts
export function esc(s: unknown): string {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}
```
Then in the row builders: `<span class="v">${esc(value)}</span>` (and `${esc(label)}`), or build
the name rows with `textContent` via the `h()` builder instead of `innerHTML`.

**Acceptance.** A target/ship name containing `<img src=x onerror=alert(1)>` renders as inert text,
not markup. Existing readouts unchanged.

---

# Medium

## M-tick — Clamp the per-tick real delta ⏱S 🎯low

**Where:** [src/server/index.ts:45-50](../src/server/index.ts#L45-L50),
[src/sim/world.ts:352-376](../src/sim/world.ts#L352-L376)

**Problem.** After a GC pause, debugger break, or laptop sleep, `now - last` can be seconds; ×`rate`
(up to 100) asks `advance()` for hundreds of sim-seconds in one call. Powered integration is capped
at `MAX_SUBSTEPS` (~64 sim-s of burn/tick), so a burn under-delivers Δv across a stall, and a coast
jumps the full unbounded delta at once.

**Fix.** Clamp the real delta in the tick (combine with C1's `finally`):
```ts
const realDt = Math.min(now - last, 250) / 1000; // cap a stall at 250 ms of wall-clock
world.advance(realDt);
```
Optionally `console.warn` when `simDelta` exceeds the substep budget so dropped burn time is
legible.

**Acceptance.** Simulate a stall (block the loop ~2 s in dev) at `rate=100` → sim advances by ≤
`250ms*100 = 25 s` that tick, not 200 s; burn integration doesn't silently drop a chunk.

---

## M-feasible — Planner feasibility must validate the resulting orbit; unify thresholds ⏱S 🎯low

**Where:** [src/sim/maneuver.ts:184](../src/sim/maneuver.ts#L184) (`previewNode`, `dvMag > 0`),
[src/sim/maneuver.ts:270](../src/sim/maneuver.ts#L270) (`buildPlan`, `totalDv > 1e-3`)

**Problem.** Two issues: (1) feasibility never checks `after` is a valid bound orbit (see H2 layer
2); (2) the zero-burn thresholds disagree — `previewNode` calls a 0.0005 m/s burn feasible while
`buildPlan` calls it "nothing to do".

**Fix.** Add the `validAfter` gate from H2 to both, and pick one dead-band constant:
```ts
const DV_EPS = 1e-3; // m/s — ignore sub-mm/s dust (circularizing an already-circular orbit)
// previewNode:
const feasible = dvMag > DV_EPS && affordable && Number.isFinite(after.a) && after.e < 1;
// buildPlan: same predicate on totalDv and the final `after`.
```

**Acceptance.** A 0.0005 m/s node is `feasible: false` with the same note in both paths; an escape
burn is `feasible: false` with an escape note; normal plans unchanged (`npm run check` green).

---

## M-kepler — `solveKepler` non-convergence fallback ⏱S 🎯low

**Where:** [src/sim/orbit.ts:27-38](../src/sim/orbit.ts#L27-L38)

**Problem.** Fixed 100-iteration Newton with no convergence signal; near `e→1` it can exit without
converging and return a wrong `E` silently. (M0 orbits are low-e, but `stateToElements` can yield
high-e after a burn.)

**Fix.** Track convergence; on failure fall back to bisection on `[M−1, M+1]` bracket (Kepler's
equation is monotonic in E, globally convergent for `0 ≤ e < 1`):
```ts
export function solveKepler(meanAnomaly: number, e: number): number {
  const M = wrapToPi(meanAnomaly);
  let E = e < 0.8 ? M : Math.PI * (M < 0 ? -1 : 1);
  for (let k = 0; k < 100; k++) {
    const dE = (E - e * Math.sin(E) - M) / (1 - e * Math.cos(E));
    E -= dE;
    if (Math.abs(dE) < 1e-12) return E;
  }
  // Newton stalled (high e): bisect f(E)=E−e·sinE−M, which is increasing in E.
  let lo = M - 1, hi = M + 1;
  for (let k = 0; k < 200; k++) {
    const mid = (lo + hi) / 2;
    if (mid - e * Math.sin(mid) - M > 0) hi = mid; else lo = mid;
  }
  return (lo + hi) / 2;
}
```

**Acceptance.** New check: `solveKepler` at e = 0.95 for several M values reproduces M within 1e-9
after `E - e·sin(E)`. Existing low-e tests unchanged.

---

## M-lambert — Set Lambert branch monotonicity analytically, not by probe ⏱M 🎯med

**Where:** [src/sim/solvers.ts:187-216](../src/sim/solvers.ts#L187-L216)

**Problem.** `decreasing` is inferred from two sampled TOFs (`tofOf(lo + 1e-3·span)`,
`tofOf(hi − 1e-3·span)`); a non-finite sample (common near the singular endpoint where `c2→0`,
`y<0`) defaults to `decreasing = false`, flipping the bisection direction on the genuinely
*decreasing* low branch → diverges and returns `null` even when a solution exists.

**Fix.** You already know the branch. Direct (`nrev≤0`) and the `"high"` branch increase with ψ;
the `"low"` branch decreases. Set it directly and use the probe only as a tie-breaker fallback:
```ts
let decreasing: boolean;
if (nrev <= 0) decreasing = false;          // direct: TOF increases with ψ
else decreasing = branch === "low";          // low branch decreases, high increases
// (optional) sanity-probe inward; if the probe disagrees AND both samples are finite, trust the probe.
```

**Acceptance.** Add a multi-rev Lambert case (e.g. `nrev=2, branch="low"`) with a known TOF and
assert the arrival position matches (like the existing single-rev Lambert check). Existing
rendezvous test still passes.

**Notes.** Verify against the existing rendezvous loop test, which exercises `bestTransfer` over
rev counts — this is the highest-risk sim change after C2; keep tolerances tight.

---

## M-clears — Reject non-finite elements in `transferClears` ⏱S 🎯low

**Where:** [src/sim/solvers.ts:245-253](../src/sim/solvers.ts#L245-L253)

**Problem.** If Lambert returns a hyperbolic/NaN departure, `stateToElements` may give NaN `a`/`e`;
`el.e < 1` is false so it falls to arc sampling, and `mag(NaN) < safeR` is `false` for every
sample → a NaN/through-the-planet trajectory is reported as **clearing**.

**Fix.** Reject up front:
```ts
function transferClears(r1, v1, body, tBurn, tof): boolean {
  const el = stateToElements(r1, v1, body, tBurn);
  if (!Number.isFinite(el.a) || !(el.e >= 0)) return false; // garbage conic never "clears"
  const safeR = body.radius + TRANSFER_CLEARANCE;
  if (el.e < 1 && el.a * (1 - el.e) >= safeR) return true;
  for (let k = 0; k <= ARC_SAMPLES; k++) {
    const p = propagate(el, body, tBurn + (tof * k) / ARC_SAMPLES).position;
    if (!Number.isFinite(p.x) || mag(p) < safeR) return false;
  }
  return true;
}
```
(With H2's `propagate` guard throwing on `e≥1`, wrap the sample loop in the early-return so you
never call `propagate` on an invalid conic.)

**Acceptance.** A hyperbolic departure is filtered out of `solveIntercept` candidates (returns
`null` rather than proposing a through-planet arc). Existing intercept test unchanged.

---

## M-aileak — Don't return raw AI/SDK error text to the client ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/server/index.ts:242-246](../src/server/index.ts#L242-L246); thrown from
[ai-bridge.ts:496-497](../src/server/ai-bridge.ts#L496-L497)

**Problem.** `res.status(500).json({ error: err.message })` returns
`ship AI did not complete: <SDK detail>` verbatim — can carry auth-failure detail, paths, or
token-related strings to the browser (and any shared-host peer).

**Fix.** Log full detail server-side (already done), return generic to client; map known cases:
```ts
} catch (err) {
  console.error("[ai] ", err);
  res.status(500).json({ error: "ship AI error — see server logs" });
}
```
(Optionally detect rate-limit/auth substrings and return a friendlier specific message, but never
the raw string.)

**Acceptance.** Trigger an AI failure (bad model id) → client sees the generic message; full error
only in server logs.

---

## M-staletime — Reject a maneuver node whose burn time is already past ⏱S 🎯low

**Where:** [src/sim/api.ts:354-377](../src/sim/api.ts#L354-L377) (`executeManeuver`)

**Problem.** The plan is rebuilt against live fuel/orbit, but each `node.time` is the absolute
sim-time captured at plan time. If the operator warps past it between review and execute,
`driveExecutor` computes `burnStart = node.time - burnDur/2` already behind `this.time` and fires
immediately at a different orbital point than was reviewed.

**Fix.** In `executeManeuver`, reject/warn when any node time is in the past:
```ts
if (pending.nodes.some((n) => n.time < w.time - 1)) {
  return { ok: false, error: "plan's burn time has already passed — re-plan from the current orbit" };
}
```
(Choose a small slack, e.g. 1 s. Live/retarget nodes that recompute in flight are exempt if their
intended fire time is still ahead.)

**Acceptance.** Plan a node at T+300 s, warp past it, then execute → rejected with a clear message
rather than an immediate mis-placed burn.

---

## M-chatvalidate — Validate `/api/ai/chat` body shape and bound size ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/server/index.ts:237-238](../src/server/index.ts#L237-L238),
[ai-bridge.ts:449-456](../src/server/ai-bridge.ts#L449-L456) (`composePrompt` calls `m.content.trim()`)

**Problem.** `const history = (req.body?.messages ?? []) as ChatMessage[]` is a blind cast. A
malformed `messages` (`[{role:"user"}]` with no `content`, or a string) makes `composePrompt`
throw → 500. No cap on count/size, so a large body becomes a large prompt billed to the host's
subscription (the Q2 cost concern).

**Fix.** Validate with zod (already a dependency) and bound it:
```ts
const ChatBody = z.object({
  messages: z.array(z.object({
    role: z.enum(["user", "assistant"]),
    content: z.string().max(8000),
  })).max(50),
  persona: z.string().optional(),
});
const parsed = ChatBody.safeParse(req.body);
if (!parsed.success) return res.status(400).json({ error: "invalid chat payload" });
const { messages: history, persona } = parsed.data;
```

**Acceptance.** `messages: "hi"` or a 1000-entry array → 400; a valid short history works. No 500
from a malformed body.

---

## M-cors — Document localhost-only; add CORS/auth before any exposure ⏱S 🎯low

**Where:** [src/server/index.ts:52-53](../src/server/index.ts#L52-L53)

**Problem.** No CORS policy and no auth on write routes (`/api/maneuver/execute`,
`/api/flight/throttle`, `/api/ai/chat`). Fine while Vite proxies same-origin in dev, but the
shared-host model would expose burns and the AI subscription to any LAN peer.

**Fix (now).** Bind explicitly to localhost and document it:
```ts
app.listen(PORT, "127.0.0.1", () => { /* ... */ });
```
Add a `// SECURITY:` comment that exposure requires CORS allow-listing + an auth gate (tie to Q2).
No CORS middleware needed while same-origin.

**Acceptance.** Server reachable on `localhost`, not on the machine's LAN IP. Comment present.

---

## M-aireply — Validate `data.reply` is a string in the AI console ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/client/ai-console.ts:98-104](../src/client/ai-console.ts#L98-L104)

**Problem.** `pending.textContent = data.reply` with no type check; a non-string reply coerces to
`"undefined"`/`"[object Object]"` and is pushed into `history`, poisoning every later turn's
payload.

**Fix.**
```ts
const data = await res.json().catch(() => ({}));
if (res.ok && typeof data.reply === "string") {
  pending.textContent = data.reply;
  history.push({ role: "assistant", content: data.reply });
} else {
  pending.textContent = `[${typeof data.error === "string" ? data.error : "error"}]`;
  pending.className = "ai-line system";
}
```

**Acceptance.** A malformed 200 (no/`null` `reply`) shows an error line and does **not** push a
poisoned assistant turn into history.

---

## M-jsonerr — Client error paths shouldn't mislabel real server errors as "[connection error]" ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [maneuver-panel.ts:65](../src/client/maneuver-panel.ts#L65),
[maneuver-panel.ts:155](../src/client/maneuver-panel.ts#L155),
[target-panel.ts:38](../src/client/target-panel.ts#L38),
[station-panel.ts:40](../src/client/station-panel.ts#L40)

**Problem.** `await res.json()` on a non-JSON 4xx/5xx body (e.g. an HTML error page) throws and is
caught by the surrounding handler, mislabeling genuine validation errors as connection failures.

**Fix.** A small helper that reads an error message safely:
```ts
// dom.ts
export async function errText(res: Response): Promise<string> {
  try {
    const ct = res.headers.get("content-type") ?? "";
    if (ct.includes("json")) return (await res.json()).error ?? res.statusText;
  } catch { /* fall through */ }
  return res.statusText || `HTTP ${res.status}`;
}
```
Use `errText(res)` where the panels currently inline `(await res.json()).error`.

**Acceptance.** A 400 with a JSON `{error}` shows that message; a 500 HTML page shows the status
text, not "[connection error]".

---

## M-aihistory — Cap AI console history client-side ⏱S 🎯low — ✅ DONE (2026-06-22)

**Where:** [src/client/ai-console.ts:88-101](../src/client/ai-console.ts#L88-L101)

**Problem.** `history` grows unbounded and the full array is POSTed each turn (memory + cost).

**Fix.** Keep a sliding window (pairs with the server cap in M-chatvalidate):
```ts
const MAX_HISTORY = 40;
history.push({ role: "user", content: text });
if (history.length > MAX_HISTORY) history.splice(0, history.length - MAX_HISTORY);
```

**Acceptance.** After 100 turns the POST body holds ≤ 40 messages; conversation still coherent.

---

## M-tests — Add coverage for the untested layers ⏱M 🎯low

**Where:** [scripts/check-sim.ts](../scripts/check-sim.ts) (scope); targets in
[src/sim/api.ts](../src/sim/api.ts), [src/sim/solvers.ts](../src/sim/solvers.ts)

**Problem.** The HTTP/API layer, AI bridge, and most sim error/edge paths are untested. The
confirmation gate is only tested at the `api.ts` function level, never the route level.

**Fix.** Add assertions (call `api.ts` write functions directly — no need to boot Express):
- Confirmation gate: `executeManeuver(w, /*confirm*/ false)` returns `ok: false` and mutates
  nothing; `executeManeuver(w, true)` after a plan commits.
- `selectTarget(w, 999)` (out of range) returns an error; valid index switches telemetry.
- `transferCargo` while undocked returns an error; the volume cap is selected before the mass cap
  for a bulky-but-light load; loading reduces `getShip().dvBudget`, unloading restores it.
- Solver null paths: a far/un-phased target where `solveIntercept` returns `null`; a Lambert call
  with TOF below the N-rev minimum returns `null`.
- Long-run determinism: propagate the canonical orbit to `t = 100·period` and assert altitude is
  still ~400 km (cheap, analytic).

**Acceptance.** New checks pass; `npm run check` still exits 0. Consider a `check()` helper
(below) so every assertion funnels through the failure counter.

---

# Low

## L-test-helper — Funnel boolean checks through one counter ⏱S
**Where:** many hand-rolled `if (!ok) failures++` sites in [check-sim.ts](../scripts/check-sim.ts).
A future edit dropping the `failures++` line still prints PASS-looking output. Add a
`check(label: string, ok: boolean)` helper mirroring `approx()` and route all boolean assertions
through it.

## L-test-script — Add `test` alias and drop dead dep ⏱S
**Where:** [package.json](../package.json). Add `"test": "tsx scripts/check-sim.ts"` (alias of
`check`); remove the unused `concurrently` devDependency (replaced by `scripts/dev.mjs`).

## L-envexample — Add `.env.example` ⏱S
**Where:** repo root (referenced by [CLAUDE.md](../CLAUDE.md) but absent). Create it with
commented, valueless keys: `CLAUDE_CODE_OAUTH_TOKEN=`, `ANTHROPIC_API_KEY=`, `SHIP_AI_MODEL=`,
`SHIP_AI_EFFORT=`, `SHIP_AI_MAX_TURNS=`, `PORT=`.

## L-envvalidate — Validate AI env knobs ⏱S
**Where:** [ai-bridge.ts:48-49](../src/server/ai-bridge.ts#L48-L49). `Number(SHIP_AI_MAX_TURNS)` is
`NaN` for a bad value (may disable the loop bound); `EFFORT` is cast to the union unchecked. Clamp:
```ts
const EFFORT_VALUES = ["low", "medium", "high", "xhigh", "max"] as const;
const EFFORT = (EFFORT_VALUES as readonly string[]).includes(process.env.SHIP_AI_EFFORT ?? "")
  ? (process.env.SHIP_AI_EFFORT as Effort) : "low";
const parsedTurns = Number(process.env.SHIP_AI_MAX_TURNS);
const MAX_TURNS = Number.isFinite(parsedTurns) && parsedTurns > 0 ? Math.floor(parsedTurns) : 12;
```
Log the resolved model/effort at startup so misconfig is visible.

## L-rate-400 — `/api/rate` should reject invalid input ⏱S
**Where:** [src/server/index.ts:88-92](../src/server/index.ts#L88-L92). A non-finite/negative rate
is silently dropped and the route returns 200 with the old clock. Return 400 on invalid input for
symmetry with the maneuver routes.

## L-burn-final-substep — Land the burn exactly on target Δv ⏱S
**Where:** [src/sim/world.ts:305](../src/sim/world.ts#L305),
[src/sim/world.ts:369](../src/sim/world.ts#L369). `burnDelivered >= dvMag` overshoots by up to one
substep's Δv (systematic over-delivery, compounded across multi-node plans). On the final substep,
scale throttle so `burnDelivered` lands on `dvMag`:
```ts
const remaining = dvMag - this.burnDelivered;
const fullStepDv = (this.ship.thrustN / mPre) * DT_PHYS;
const throttle = Math.min(1, remaining / fullStepDv); // partial last step
```
(Must remain deterministic; fold into the C2 substep loop.)

## L-wrap-dedup — De-duplicate `wrapTwoPi`/`wrapToPi`/`clamp` ⏱S
**Where:** [orbit.ts:11-24](../src/sim/orbit.ts#L11-L24), [maneuver.ts:22-29](../src/sim/maneuver.ts#L22-L29).
Same primitives copied across files (drift risk). Extract to a pure `src/sim/math.ts` and import.

## L-latitude — Use the spec's closed form for latitude ⏱S
**Where:** [orbit.ts:123](../src/sim/orbit.ts#L123). `Math.asin(z/radius)` is equivalent to
`sin(lat)=sin i·sin(ω+ν)` ([docs/07](07-milestone-0-spec.md) §3.2) but couples to the full rotation
pipeline. Optional: switch to the closed form for spec-conformance, or leave with a comment noting
the equivalence.

## L-slot-listener — Remove per-slot document listener on teardown ⏱S
**Where:** [slot.ts:85-87](../src/client/slot.ts#L85-L87). Each slot adds a permanent
`document.addEventListener("click", …)` with no removal; harmless at 4 slots but leaks if slots
become dynamic. Store the handler and remove it in a slot-level teardown, or use one shared
delegated listener. While here, either implement `ViewInstance.destroy()` where views register
listeners/fetches or drop the unused contract method ([types.ts:144](../src/client/types.ts#L144)).

## L-input-zero — Don't coerce empty maneuver inputs to a dangerous `0` ⏱S
**Where:** [maneuver-panel.ts:74-76](../src/client/maneuver-panel.ts#L74-L76),
[maneuver-panel.ts:142-146](../src/client/maneuver-panel.ts#L142-L146),
[target-panel.ts:47](../src/client/target-panel.ts#L47). `Number(input.value) || 0` turns
empty/garbage into `0` (e.g. altitude 0 km = a deorbit; TOF 0). Validate and surface an error in
the panel's status line instead of coercing.

## L-scope-color — Cache the phosphor color out of the draw hot path ⏱S
**Where:** [scope.ts:22](../src/client/scope.ts#L22). `getComputedStyle(canvas).color` runs every
frame (10×/s) and forces style resolution. Read it once on view creation (or pass it in).

## L-num-overflow — Right-align via CSS so wide values don't break columns ⏱S
**Where:** [nav-panel.ts:17](../src/client/nav-panel.ts#L17). `pad(...,9)` only pads up to width 9;
a value wider than 9 chars (high orbit, or NaN before H8) shifts the layout. Right-align with CSS
instead of space-padding so overflow can't reflow the column.

## L-select-focus — Reconcile the target `<select>` while open, not merely focused ⏱S
**Where:** [target-panel.ts:58](../src/client/target-panel.ts#L58). Skipping reconciliation while
`document.activeElement === select` leaves a stale selection if the AI changes the target while the
operator has the dropdown focused. Minor; comment the trade-off or detect "open" more precisely.

## L-warp-optimistic — Don't show an unconfirmed warp rate as active ⏱S
**Where:** [nav-panel.ts:88-94](../src/client/nav-panel.ts#L88-L94). The warp highlight is set
optimistically before the POST is confirmed; if the server is down it shows a rate never accepted.
Apply the active class only on the next successful poll, or revert when `post()` returns null.

## L-client-types — Share API return types instead of re-declaring them ⏱M
**Where:** [src/client/types.ts](../src/client/types.ts) re-declares shapes returned by
[src/sim/api.ts](../src/sim/api.ts) with no compile-time link → silent drift if the API changes.
Export the API return types from `src/sim` and import them in the client (the client already
imports `OrbitState` from `../sim/types`, so the precedent exists).

---

## Cross-references
- **C1 + M-tick** share the tick callback — do them together.
- **H2 + M-feasible + M-clears + M-kepler** are the "NaN/degenerate-orbit hygiene" cluster — one
  coherent pass over `orbit.ts`/`maneuver.ts`/`solvers.ts`.
- **H4 + H5 + M-aileak + M-chatvalidate + L-rate-400** are the "server input/error hardening"
  cluster.
- **H8 + H9 + M-aireply + M-jsonerr + M-aihistory** are the "client robustness" cluster.
- **C2 + L-burn-final-substep** both touch the powered substep loop — do C2 first, fold the
  partial-final-step in.
