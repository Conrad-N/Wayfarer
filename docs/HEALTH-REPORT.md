# Project Health Report — Wayfarer

**Date:** 2026-06-22 · **Scope:** robustness/correctness pass over the whole tree
(no new features). **Baseline:** `tsc --noEmit` clean; `npm run check` all PASS, exit 0.

Method: four Opus 4.8 subagents deep-read the sim core, the server/AI bridge, the
client, and the tests+docs; key findings were re-verified by hand. Severities:
**Critical** (can silently break the authoritative sim or determinism) · **High**
(wrong output / reachable crash / keystone violation) · **Medium** · **Low**.

Nothing here was changed — this is the punch list. Top six to fix first are starred (★).

---

## Critical

**★ C1 — A throw in the sim tick takes down the whole authority, silently.**
[src/server/index.ts:46-50](../src/server/index.ts#L46-L50)
The `setInterval` tick calls `world.advance(...)` with no `try/catch`. Any edge-case
throw in the sim (a degenerate solver, a NaN reaching `stateToElements`) escapes the
callback: sim-time freezes while the HTTP server keeps serving stale telemetry, with
no signal the heartbeat died. This is the worst failure mode because the tick is the
heartbeat of the server-authoritative design (Keystone 3).
*Fix:* wrap the body in `try/catch`, log, optionally drop warp to 0 on failure; add
`process.on('uncaughtException'|'unhandledRejection', …)`.

**★ C2 — Determinism hole: powered flight integrates against wall-clock `dt`.**
[src/sim/world.ts:205-216](../src/sim/world.ts#L205-L216),
[src/sim/world.ts:352-376](../src/sim/world.ts#L352-L376)
Throttle on/off is decided once per *variable* wall-clock tick, while the burn is
subdivided into fixed `DT_PHYS` substeps with a carried remainder. Two machines with
different frame cadence cross `burnStart` at a different `physAccum` phase, so the
integer substep count executed while `throttle===1` differs and final `(r,v)` /
`burnDelivered` diverge. [docs/10](10-flight-model.md) §3 promises identical
trajectories for identical inputs — multiplayer and skip-resolution depend on it. The
coast path is genuinely analytic and fine; this is confined to the powered path.
*Fix:* accumulate sim-time and step the sim in whole `DT_PHYS` quanta, making throttle
decisions only at substep boundaries — don't let a per-tick `simDelta` drive control.

---

## High

**★ H1 — `timeToPeriapsis` returns a full orbital period at periapsis instead of 0.**
[src/sim/orbit.ts:121](../src/sim/orbit.ts#L121) — `(TWO_PI - meanAnomaly) / meanMotion`
At `meanAnomaly = 0` this yields `period`, and it jumps discontinuously from ~0 just
before periapsis to a full period at it. The sibling `timeToApoapsis`
([orbit.ts:97](../src/sim/orbit.ts#L97)) correctly uses `wrapTwoPi(...)`. User-visible
wrong readout. *Fix:* `wrapTwoPi(TWO_PI - meanAnomaly) / meanMotion`.

**★ H2 — Non-elliptical / degenerate orbits silently poison telemetry with NaN.**
[src/sim/orbit.ts:64-126](../src/sim/orbit.ts#L64-L126),
[src/sim/maneuver.ts:34-108](../src/sim/maneuver.ts#L34-L108)
`propagate` assumes `0 ≤ e < 1`, `a > 0` but never enforces it; `solveKepler` has no
hyperbolic branch. `stateToElements` (`a = -mu/(2·energy)`) can produce `a → ±∞`
(parabolic) or `e ≥ 1` (hyperbolic) from an aggressive burn or a bad Lambert result,
then `sqrt(1-e)` → NaN flows into position/velocity and every downstream consumer
(nav panel, AI tools, solvers) — with no error. Worse, `previewNode`/`buildPlan` only
check Δv magnitude and propellant for feasibility, so a burn yielding a NaN/hyperbolic
orbit can be reported **feasible** and "confirmed."
*Fix:* validate at `propagate`'s entry; have `stateToElements` flag non-finite/`e≥1`
results; have the planners mark such a plan infeasible ("burn yields an escape/hyperbolic
trajectory"). Pairs with the missing planner check in M-row below.

**★ H3 — Shared global confirmation gate defeats the review gate under concurrent chat.**
[src/server/index.ts:229-247](../src/server/index.ts#L229-L247),
[src/sim/api.ts:354-377](../src/sim/api.ts#L354-L377)
`/api/ai/chat` is fully async over one shared mutable `World` with no lock. `pendingManeuver`
and `selectedTarget` are single global slots, so session B's `execute_maneuver(confirm:true)`
can commit session A's pending plan — a burn fires that *no one in that conversation*
confirmed. This directly undermines Keystone 2 and is reachable in the stated shared-host
model. *Fix:* serialize chat turns with an async mutex/queue, or scope
`pendingManeuver`/`selectedTarget` per session, or token-match the reviewed plan.

**H4 — `/api/predict` accepts NaN / unbounded `t` and returns NaN telemetry as HTTP 200.**
[src/server/index.ts:61](../src/server/index.ts#L61) — `Number(req.query.t)` is `NaN`
for a missing/non-numeric `t`, flows straight into `propagate(...)`, and the route
answers 200 with an all-NaN `OrbitState`. (The AI tool path is zod-guarded; the HTTP
route is not.) *Fix:* `if (!Number.isFinite(t)) return res.status(400)...`.

**H5 — No global Express error handler; unguarded routes leak stack traces.**
[src/server/index.ts:52-247](../src/server/index.ts#L52-L247)
Only `/api/ai/chat` has try/catch. Every other route calls into the sim synchronously;
a throw produces Express's default HTML error page (stack trace to the client) with no
central logging. *Fix:* add a terminal error middleware that logs and returns generic
JSON; never serialize raw errors to clients.

**H6 — Overlapping client polls can render stale state out of order.**
[src/client/main.ts:17-28](../src/client/main.ts#L17-L28)
`setInterval(poll, 100)` fires regardless of whether the previous `poll()` resolved;
under load an older `/api/state` can resolve last and render after a newer one (altitude/Δv
jumping backward). Also no backoff — a downed server is hammered 10×/s. *Fix:* in-flight
guard or a self-scheduling `setTimeout` loop; add failure backoff.

**H7 — Keystone violation: the scope computes orbital geometry the server should own.**
[src/client/scope.ts:28-31](../src/client/scope.ts#L28-L31),
[src/client/scope.ts:64-79](../src/client/scope.ts#L64-L79)
The client derives semi-minor axis, focus offset, and a relative-argp projection
between two orbits (`b = a·√(1−e²)`, `c = a·e`, `ang = target.argp + ν − o.argp`). That
is physical geometry the API should provide (Keystone 1/3), and it silently assumes the
two orbits are coplanar. *Fix:* have the API return drawable geometry (or pre-projected
points); the client should only scale-and-plot.

**H8 — Telemetry formatters have no NaN/Infinity/undefined guard.**
[src/client/nav-panel.ts:14-25](../src/client/nav-panel.ts#L14-L25) and the other panels'
`num()`/`hms()` helpers. `(undefined).toFixed()` throws and kills a panel's render;
`NaN`/`Infinity` print literally and break the fixed-width column aesthetic. *Fix:* a
`finite(v, '---')` guard emitting a dash placeholder (matches the "dead segment" look).

**H9 — XSS: server-supplied strings are interpolated into `innerHTML` unescaped.**
[src/client/nav-panel.ts:46-67](../src/client/nav-panel.ts#L46-L67),
[target-panel.ts:62-74](../src/client/target-panel.ts#L62-L74), and the other `row()`
builders. Numeric rows are fine, but `ship.name`, `body.name`, `target.name`, item
names etc. are rendered raw. "Server-authoritative" ≠ "HTML-safe"; the moment a name
is AI- or player-influenced this is stored XSS. *Fix:* an `escapeHtml()` wrapper in the
row builders (or `textContent`).

---

## Medium

- **Tick `last` not clamped → unbounded warp jump after a stall/sleep.**
  [src/server/index.ts:45-50](../src/server/index.ts#L45-L50). After a GC pause or laptop
  resume, `now - last` × `rate` can ask `advance()` for hundreds of sim-seconds; powered
  integration is silently capped at `MAX_SUBSTEPS` (~64 s of burn/tick) so a burn
  under-delivers. *Fix:* clamp the per-tick real delta (e.g. `min(now-last, 250)ms`).
- **Planner feasibility never checks the resulting orbit is valid** (pairs with H2):
  [src/sim/maneuver.ts:184](../src/sim/maneuver.ts#L184),
  [maneuver.ts:270](../src/sim/maneuver.ts#L270) — also inconsistent thresholds
  (`dvMag > 0` vs `totalDv > 1e-3`).
- **`solveKepler` has a fixed 100-iter cap with no non-convergence signal.**
  [src/sim/orbit.ts:27-38](../src/sim/orbit.ts#L27-L38) — near `e→1` it can exit without
  converging and silently return a wrong `E`. *Fix:* detect and fall back to bisection on
  `[−π, π]` (globally convergent for `e<1`).
- **Lambert monotonicity is probed numerically and can flip direction.**
  [src/sim/solvers.ts:189-191](../src/sim/solvers.ts#L189-L191) — a non-finite probe
  sample defaults to "increasing" and the bisection diverges (returns null) on the
  decreasing low branch. *Fix:* set branch monotonicity analytically; probe only as a
  fallback, nudging inward on a bad sample.
- **`transferClears` can report a NaN trajectory as clearing the body.**
  [src/sim/solvers.ts:245-253](../src/sim/solvers.ts#L245-L253) — `mag(NaN) < safeR` is
  `false`. *Fix:* reject non-finite elements up front.
- **AI bridge leaks raw SDK/internal error text to the HTTP client.**
  [src/server/index.ts:242-246](../src/server/index.ts#L242-L246) — `err.message` can carry
  auth/path/token context. Log server-side, return a generic message.
- **A stale maneuver node can fire in the past.**
  [src/sim/api.ts:354-377](../src/sim/api.ts#L354-L377) — if the operator warps past a
  planned node between review and execute, the burn fires at a different orbital point than
  reviewed. *Fix:* reject/warn when `node.time < w.time`.
- **`/api/ai/chat` blind-casts `messages` and caps nothing.**
  [src/server/index.ts:237-238](../src/server/index.ts#L237-L238) — a malformed `messages`
  throws (500); an unbounded history is sent under the host's subscription (cost/DoS). zod
  is already a dep — validate shape and bound size.
- **No CORS policy / no auth on write routes.**
  [src/server/index.ts:52-53](../src/server/index.ts#L52-L53) — fine while localhost-only,
  but every write route is open the moment the shared-host model exposes it. Document
  "localhost only" for now; gate before exposure.
- **AI console doesn't validate `data.reply` is a string.**
  [src/client/ai-console.ts:98-104](../src/client/ai-console.ts#L98-L104) — a non-string
  reply gets coerced (`"undefined"`/`"[object Object]"`) and poisons history for every later
  turn. *Fix:* check `typeof data.reply === 'string'`.
- **Client error paths report genuine server errors as "[connection error]".**
  [maneuver-panel.ts:65](../src/client/maneuver-panel.ts#L65),
  [target-panel.ts:38](../src/client/target-panel.ts#L38),
  [station-panel.ts:40](../src/client/station-panel.ts#L40) — `await res.json()` on a
  non-JSON 4xx/5xx body throws and is mislabeled. *Fix:* guard the parse, fall back to
  `res.statusText`.
- **AI history grows unbounded client-side and re-POSTs the full transcript each turn.**
  [src/client/ai-console.ts:88-100](../src/client/ai-console.ts#L88-L100). *Fix:* sliding
  window cap (or rely on a server cap and document it).

### Tooling / tests / hygiene (Medium)
- **`.env` holds a live OAuth token in a OneDrive-synced folder, and the project is not
  yet a git repo.** [.gitignore](../.gitignore) covers `.env`, but cloud sync is an
  exfiltration surface the ignore can't cover. Confirm it's a low-scope subscription token;
  consider moving the secret out of the synced dir.
- **`.env.example` is missing** though `CLAUDE.md` tells new clones to copy it. Add it with
  commented, valueless keys (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `SHIP_AI_MODEL`,
  `SHIP_AI_EFFORT`, `SHIP_AI_MAX_TURNS`, `PORT`).
- **The entire HTTP/API layer and AI bridge are untested.** `check-sim.ts` exercises
  `src/sim` functions directly; the confirmation gate is only tested at the `api.ts` level,
  never at the route boundary. Add route-level assertions for the `confirm` gate, bad
  `selectTarget` index, and `transferCargo` while undocked.
- **Sim error/edge paths are largely untested:** Lambert/`solveIntercept` returning `null`,
  the cargo volume-vs-mass cap, docking-envelope rejection, cargo shrinking the Δv budget.
  These are deliberately built edge cases with zero assertions.

---

## Low

- `solveHohmann` assumes a near-circular departure without verifying it
  ([solvers.ts:65-81](../src/sim/solvers.ts#L65-L81)).
- `wrapTwoPi`/`wrapToPi` duplicated across `orbit.ts` and `maneuver.ts` (drift risk).
- Burn termination over-delivers by up to one substep's Δv
  ([world.ts:305](../src/sim/world.ts#L305)); scale the final substep to land exactly.
- `latitude` uses Cartesian `z/r` instead of the spec's closed form
  ([orbit.ts:123](../src/sim/orbit.ts#L123)) — equivalent, but a hidden coupling.
- `/api/rate` and other write routes silently ignore invalid input (return 200 with the
  old value) — inconsistent with the maneuver routes' 400/409.
  [src/server/index.ts:88-92](../src/server/index.ts#L88-L92).
- `SHIP_AI_MAX_TURNS`/`SHIP_AI_EFFORT`/`SHIP_AI_MODEL` are unvalidated env parses
  ([ai-bridge.ts:48-49](../src/server/ai-bridge.ts#L48-L49)); a bad value yields NaN/typo'd
  config surfacing only as a runtime error.
- Per-slot `document` click listeners are never removed
  ([slot.ts:85-87](../src/client/slot.ts#L85-L87)); the advertised `ViewInstance.destroy()`
  contract ([types.ts:144](../src/client/types.ts#L144)) is implemented by no view.
- `Number(input.value) || 0` coerces empty/garbage maneuver inputs to a dangerous-but-valid
  `0` ([maneuver-panel.ts:74-76](../src/client/maneuver-panel.ts#L74-L76)).
- `getComputedStyle` runs in the scope draw hot path every frame
  ([scope.ts:22](../src/client/scope.ts#L22)); cache it once.
- `concurrently` is a dead dependency (replaced by `scripts/dev.mjs`); `npm test` is
  unconfigured (only `npm run check` exists). [package.json](../package.json).
- No long-run determinism/drift test (the determinism check compares two identical single
  `propagate` calls, not a long integrated burn or many-orbit stability).
- Client re-declares API return shapes in [src/client/types.ts](../src/client/types.ts)
  with no compile-time link to [src/sim/api.ts](../src/sim/api.ts) — drift risk; later, share
  the types.

---

## Verified-correct (so they don't get "fixed" by mistake)
- Kepler seed, vis-viva, perifocal→PCI 3-1-3 rotation, and the `ν` half-angle `atan2` all
  match [docs/07](07-milestone-0-spec.md) §3.2; SI throughout; `acos`/`asin` args are
  clamped. No `Date.now()`/`Math.random()`/DOM/Node deps anywhere in `src/sim`.
- Token handling is sound: `.env` gitignored, token never logged, and the bridge blanks
  `ANTHROPIC_API_KEY` when a subscription token is present to avoid silent billing.
- The tool loop is bounded by `MAX_TURNS`; both HTTP routes and AI tools call the same
  `src/sim/api.ts` (Keystone 1 holds); the coast path is genuinely analytic/deterministic.

---

## Suggested fix order
1. **C1** (wrap the tick) — cheapest insurance against everything else.
2. **H1** (one-line periapsis fix) and **H2** (NaN/hyperbolic guards + planner feasibility).
3. **H3** (serialize chat / scope the gate) — restores the review-gate guarantee.
4. **C2** (fixed-quantum powered stepping) — the real determinism fix; larger change.
5. **H4/H5** (validate `/api/predict`, add error middleware) and **H6/H8/H9** on the client.
