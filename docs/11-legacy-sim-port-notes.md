# Legacy Sim Port Notes — Space Game (TypeScript → Godot 4 GDScript)

Source: `legacy/web/src/sim/*.ts`, `legacy/web/scripts/check-sim.ts`, `legacy/web/docs/08-simulation-and-time.md`,
`legacy/web/docs/10-flight-model.md`, `legacy/web/docs/11-interplanetary-transfer-planner.md`. All quantities SI
(meters, seconds, radians, kg) unless noted. `src/sim` is pure/deterministic: no
`Date.now()`, no wall-clock reads, no hidden state — every function is `(inputs) -> outputs`.

## 1. Module map

### `types.ts` (61 lines)
Owns: the shared data shapes. No functions — interfaces only: `OrbitalElements`,
`CentralBody`, `Vec3`, `OrbitState`. Depends on nothing.

### `constants.ts` (78 lines)
Owns: unit helpers and the default solar system's body definitions.
- `deg(degrees: number): number` — degrees → radians.
- `defaultSystem(): System` — builds `[SOL, CRADLE, VESPER]` fresh each call.
- `circularOrbit(body: CentralBody, altitude: number, inclination = 0): OrbitalElements`
  — circular parking orbit, epoch 0, starts at ascending node (M0=0).
Also exports `TWO_PI` and the `Body` constants `SOL`, `CRADLE`, `VESPER` (see §4).
Depends on: `types.ts`, `system.ts` (`Body`, `System`, `soiRadius`).

### `orbit.ts` (221 lines)
Owns: analytic two-body (Kepler) propagation — the entire "coast" physics.
- `solveKepler(meanAnomaly: number, e: number): number` — eccentric anomaly, e<1.
- `solveHyperKepler(meanAnomaly: number, e: number): number` — hyperbolic anomaly, e>1.
- `nextEscapeTime(el: OrbitalElements, body: CentralBody, fromT: number, soiRadius: number): number | null`
  — next outbound SOI-radius crossing, closed-form, or null if it never escapes.
- `propagate(el: OrbitalElements, body: CentralBody, t: number): OrbitState` — the
  single most important function in the sim: elements + time → full telemetry (position,
  velocity, all derived scalars). One evaluation, no stepping.
Depends on: `types.ts`, `constants.ts` (`TWO_PI`).

### `system.ts` (108 lines)
Owns: the body hierarchy (tree: star → planets → [future moons]) and root-frame math.
- `soiRadius(semiMajorAxis: number, muBody: number, muParent: number): number` — Laplace
  SOI radius, `a·(μ_body/μ_parent)^(2/5)`.
- `class System`: `constructor(bodies: Body[])` (throws unless exactly one root body);
  `has(id)`, `body(id)` (throws if unknown), `root()`, `all()`, `children(id)`,
  `bodyStateInRoot(id: string, t: number): BodyState` (sums the conic up the parent chain),
  `relativeState(fromId: string, toId: string, t: number): BodyState` (difference of two
  root-frame states).
Depends on: `types.ts`, `orbit.ts` (`propagate`). Uses a JS `Map<string, Body>` internally.

### `solvers.ts` (584 lines)
Owns: every inverse/targeting solver — turns "I want X" into maneuver-node inputs. All
pure functions of elements + time; nothing mutates state.
- `solveCircularize(el, body, tNow, at: "apoapsis"|"periapsis"): ManeuverInput` — tangential burn at the next apsis.
- `solveSetApsis(el, body, tNow, which: Apsis, targetRadius): ManeuverInput` — burn at the opposite apsis to move `which` to `targetRadius`.
- `solveHohmann(el, body, tNow, targetRadius): ManeuverInput[]` — 2-burn Hohmann to a circular orbit.
- `lambert(r1: Vec3, r2: Vec3, tof, mu, prograde=true, nrev=0, branch="low"|"high"): {v1,v2} | null` — Lambert's problem, universal-variable (Vallado) form.
- `bestTransfer(r1, r2, tof, mu, vNow, vArr, maxRevs=4): {v1,v2} | null` — cheapest Lambert solution over rev counts/branches, scored by total Δv.
- `solveIntercept(shipEl, body, tNow, targetEl, tof, maxRevs=4, guided=false): ManeuverInput[] | null` — 2-node (unguided) or N-node (guided, midcourse trims) rendezvous.
- `suggestInterceptTof(shipEl, body, tNow, targetEl, maxRevs=4): {tofSeconds, dvMag} | null` — scans TOF for cheapest intercept.
- `suggestInterplanetaryWindow(A: Body, B: Body, system, tNow, r0, opts?): InterplanetaryWindow | null` — heliocentric porkchop between sibling bodies, callable from inside A's SOI.
- `solveInterplanetaryTransfer(shipEl, A, tNow, B, window, opts?): ManeuverInput[] | null` — assembles ejection + guided heliocentric injection + 2 trims.
- `solveMatchVelocity(shipEl, body, tNow, targetEl): ManeuverInput` — live Δv nulling relative velocity to a co-frame target.
Depends on: `types.ts`, `orbit.ts` (`propagate`, `nextEscapeTime`), `flight.ts`
(`worldDvToLocal`, `dvMagnitude`), `maneuver.ts` (`stateToElements`), `system.ts` (`Body`, `System`).

### `maneuver.ts` (298 lines)
Owns: state↔elements conversion (RV2COE), rocket-equation fuel math, applying a burn, building a multi-node plan.
- `stateToElements(position, velocity, body, epoch): OrbitalElements` — inverse of `propagate`; handles circular/equatorial degeneracies without NaN.
- `dvBudget(propellantKg, dryMassKg, ispSeconds): number` — Tsiolkovsky: `Isp·g0·ln((dry+prop)/dry)`.
- `propellantForDv(massKg, dv, ispSeconds): number`.
- `applyBurn(el, body, t, dv: LocalDv): OrbitalElements` — impulsive Δv at `t`.
- `previewNode(el, body, fuel: ShipFuel, input: ManeuverInput): NodePreview` — cost + resulting orbit for one node, without committing.
- `buildPlan(el, body, fuel, label, nodes: ManeuverInput[]): ManeuverPlan` — chains burns through analytic coasts, threading mass across burns.
Depends on: `types.ts`, `constants.ts` (`TWO_PI`), `orbit.ts` (`propagate`), `flight.ts` (`LocalDv`, `Retarget`, `dvMagnitude`, `localDvToWorld`).

### `flight.ts` (293 lines)
Owns: quaternion math, rigid-body attitude integration + point-at controller, the
orbital reference frame, Δv↔world-vector conversion, the RK4 powered-flight step.
- `clampMagnitude(a: Vec3, max): Vec3`; `rotate(q: Quat, v: Vec3): Vec3`; `thrustAxisWorld(q): Vec3`.
- `integrateAttitude(q, omega, I: Inertia, torque, dt): {q, omega}` — semi-implicit Euler on `I·ω̇ = τ − ω×(Iω)` + quaternion kinematics.
- `controlTorqueBody(q, omega, targetDirWorld: Vec3|null, I, maxTorque, rateCap): Vec3` — phase-plane (√) slew profile, velocity-loop gain `KGAIN=4`.
- `orbitalFrame(r: Vec3, v: Vec3): OrbitalFrame` — `{prograde, normal, radialOut}`, orthonormal.
- `headingDir(mode: AttitudeMode, r, v): Vec3`.
- `dvMagnitude(d: LocalDv): number`; `localDvToWorld(d, r, v): Vec3`; `nodeWorldDir(d, r, v): Vec3`; `worldDvToLocal(dvWorld: Vec3, r, v): LocalDv`.
- `stepPowered(s: RVMState, body, thrustDirWorld, throttle, engine: Engine, dryMassKg, dt): RVMState` — one fixed RK4 step of gravity+thrust on `(r,v,m)`.
Constants: `G0=9.80665`, `BODY_THRUST_AXIS={1,0,0}`, `IDENTITY_Q`.
Depends on: `types.ts` only — the most self-contained file, and the best one to port first.

### `world.ts` (773 lines)
Owns: the mutable authoritative simulation — the `World` class holding `System`, ship
state, fuel, attitude, cargo, targets, maneuver nodes/executor, wallet, and the hybrid
coast/powered stepping loop + SOI handoff logic. This is the file with the most porting
risk (state machine + fixed-step loop), see §3 and §5.
Key methods: `advance(realDtSeconds: number): void` (the tick entry point),
`setThrottle/setAttitudeMode/setManualTorque/setExecutor`, `jumpToNextNode(): boolean`,
`recomputeNextSoi(): void`, `transitionTo(newBodyId, t): void`, `jumpToNextSoi(): boolean`,
`orbit(): OrbitState`, `orbitAt(t): OrbitState`, `currentRV()`, `currentMass()`,
`cargoMassKg()/cargoVolumeM3()/structuralMassKg()`. Private: `driveExecutor`,
`resolveRetarget`, `computeNextSoi`, `nextCaptureTime`, `limitWarpForSoi`,
`stepCoastWithSoi`, `seedPowered`, `foldToCoast`, `stepPoweredSubstep`, `stepCoast`,
`advanceAttitudeCoast`, `stepAttitude`, `currentElements`.
Constants: `DT_PHYS = 1/64`, `MAX_SUBSTEPS = 4096`, `SAFE_WARP = 10`, `SOI_LEAD = 120`,
`CAPTURE_SAMPLES = 2000`.
Depends on: `types.ts`, `maneuver.ts` (`stateToElements`, `dvBudget`), `flight.ts` (most
of it), `constants.ts` (`defaultSystem`, `circularOrbit`, `deg`, `VESPER`), `system.ts`
(`Body`, `System`), `orbit.ts` (`propagate`, `nextEscapeTime`), `solvers.ts` (`bestTransfer`).

### `api.ts` (592 lines)
Owns: the one stable API surface used by HTTP routes, the AI tool layer, and (later)
routines — reads, writes, cargo trading, docking. Thin: nearly every function is a
translation from `World` + solver/maneuver calls into a plain-object response.
Reads: `getClock`, `getCentralBody`, `getSystem`, `getShip`, `getOrbit`, `getStateVector`,
`predictOrbit(w, t)`, `getTarget`, `listTargets`, `getCargo`, `getStation`, `getFlight`,
`getPendingManeuver`.
Target/dock: `selectTarget(w, index)`, `dock(w)`, `undock(w)`,
`transferCargo(w, direction: "load"|"unload", itemId: string, qty=1)`.
Planning (each parks a `ManeuverPlan` pending confirm): `planManeuver(w, input)`,
`planCircularize(w, at)`, `planSetApsis(w, which, targetAltitude)`,
`planHohmann(w, targetAltitude)`, `planIntercept(w, tofSeconds?, maxRevs?)`,
`planTransferWindow(w)`, `suggestIntercept(w, maxRevs?)`, `planMatchVelocity(w)`,
`cancelManeuver(w)`, `executeManeuver(w, confirm: boolean)` — the confirmation gate.
Direct flight: `setThrottle(w, x)`, `setAttitudeMode(w, mode)`, `setManualTorque(w, t)`,
`setExecutor(w, on)`, `jumpToNextNode(w)`, `clearNodes(w)`, `jumpToNextSoi(w)`.
Note: there is **no** `setWarp`/`setRate` function anywhere in `api.ts` — `World.rate`
is a bare public field, set directly by whatever owns the `World` (out of scope here).
Depends on: `world.ts`, `maneuver.ts`, `solvers.ts`, `types.ts`, `flight.ts`, `orbit.ts`.

### `legacy/web/scripts/check-sim.ts` (809 lines)
The numeric self-test suite (`npm run check`). Not part of the sim proper — a script
that imports the above modules and asserts on their outputs. See §4 for every check.

## 2. Data model

### `OrbitalElements` (types.ts) — the source of truth for a coast orbit
| field | unit | meaning |
|---|---|---|
| `a` | m | semi-major axis (negative for a hyperbola) |
| `e` | – | eccentricity (0 ≤ e < 1 closed; e > 1 hyperbolic) |
| `i` | rad | inclination |
| `raan` | rad | right ascension of ascending node (Ω) |
| `argp` | rad | argument of periapsis (ω) |
| `meanAnomalyAtEpoch` | rad | M0 |
| `epoch` | s | t0, sim-time |

### `CentralBody` (types.ts)
`name: string`, `mu` [m³/s², G·M], `radius` [m], `rotationPeriod` [s, or `null` if non-rotating].

### `Vec3` — `{x, y, z}`, all m or m/s depending on context. Plain object, not a class.

### `OrbitState` (types.ts) — the full telemetry `propagate()` returns
Echoes `a, e, i, raan, argp`; adds `trueAnomaly, eccentricAnomaly, meanAnomaly` (rad),
`period` (s, `Infinity` for a hyperbola), `meanMotion` (rad/s), `periapsisRadius/apoapsisRadius`
(m, apoapsis `Infinity` for hyperbola), `periapsisAltitude/apoapsisAltitude` (m),
`radius/altitude` (m), `speed` (m/s), `specificEnergy` (m²/s²), `specificAngularMomentum`
(m²/s), `flightPathAngle` (rad), `timeSincePeriapsis/timeToPeriapsis/timeToApoapsis` (s),
`latitude` (rad), `position`/`velocity` (`Vec3`, planet-centered inertial / PCI frame).

### `Body` (system.ts, extends `CentralBody`)
Adds `id: string`, `parentId: string | null` (null only for the root star),
`elements: OrbitalElements | null` (orbit about the parent; null for root),
`soiRadius: number | null` (m; null = infinite, root only).

### `BodyState` (system.ts) — `{ position: Vec3, velocity: Vec3 }` in some named frame.

### Ship (`ShipDef`, world.ts)
`dryMassKg`, `propellantKg` [kg]; `ispSeconds` [s]; `thrustN` [N, full throttle];
`inertia: Inertia` = `{ix,iy,iz}` [kg·m², diagonal/principal axes]; `maxTorqueNm`
[N·m per axis, reaction wheels]; `elements: OrbitalElements` (the coast conic, valid
while engine is off); `cargoCapacityKg`/`cargoCapacityM3` [kg, m³]; `cargo: CargoItem[]`
= `{id, name, massKg, volumeM3, qty, priceCr?}` — inert mass, folds into burnout mass.

Default ship ("Wayfarer"): dry 8000 kg, propellant 24000 kg, Isp 900 s, thrust 250 kN,
inertia `{14000, 107000, 107000}` kg·m², max torque 5500 N·m, starts at 400 km circular,
51.6° inclined, around Cradle. Δv budget ≈ 12.2 km/s.

### Powered-flight state (`RVMState`, flight.ts) — `{ r: Vec3 [m], v: Vec3 [m/s], m: number [kg] }`
### Attitude state (world.ts fields) — `orientation: Quat`, `angularVel: Vec3` [rad/s, body frame]
### `Quat` — `{w, x, y, z}`, unit, body→world.
### `Engine` (flight.ts) — `{ thrustN: number, ispSeconds: number }`

### Maneuver node (`ManeuverInput` / `ManeuverNode`, flight.ts + maneuver.ts)
`time` [s, absolute sim-time the burn is centered on]; `dvLocal: LocalDv` =
`{prograde, normal, radial}` [m/s, in the orbital frame AT the burn point];
`retarget?: Retarget` — discriminated union `{kind:"transfer", targetEl, arrivalTime,
maxRevs}` or `{kind:"match", targetEl}`, tells the executor to recompute `dvLocal` live
instead of flying the frozen value. `ManeuverNode` adds `id: string` (a queued/live copy
of a `ManeuverInput`).

### `NodePreview` / `PlanBurn` / `ManeuverPlan` (maneuver.ts)
Preview of one or many nodes: `dvMag` (m/s), `propellantKg` (kg), `massBeforeKg` (kg),
`feasible` (bool), `dvBudgetBefore/After` (m/s), `before/after: OrbitState`, `note?: string`.
`ManeuverPlan` adds `label`, `nodes: ManeuverInput[]`, `burns: PlanBurn[]` (per-node cost,
mass threaded across burns).

### `InterplanetaryWindow` (solvers.ts)
`departureTime, arrivalTime, tofSeconds` (s), `vInfOut, vInfIn: Vec3` (m/s, parent frame),
`vDepHelio: Vec3`, `dvEject, dvCapture, dvTotal` (m/s).

### `TargetDef` (world.ts) — rendezvous/transfer target
`name, kind: "station"|"depot"|"probe"|"planet", bodyId: string, transferBodyId?: string,
elements: OrbitalElements, inventory?: CargoItem[]`.

## 3. Algorithms

**Elliptical Kepler solver** — `solveKepler` (orbit.ts:27). Newton's method on
`f(E) = E − e·sin(E) − M`. Mean anomaly is wrapped to `[−π, π]` first (best convergence
near 0). Seed: `E0 = M` if `e < 0.8`, else `±π`. Up to **100 iterations**, breaks when
`|ΔE| < 1e-12`. No damping/bisection fallback — relies on Newton converging for all
`0 ≤ e < 1` (true in practice, but note if you ever push `e` toward 1 in testing).

**Hyperbolic Kepler solver** — `solveHyperKepler` (orbit.ts:42). Newton on
`f(H) = e·sinh(H) − H − M`. Seed: `asinh(M/e)` normally, `sign(M)·ln(2|M|/e + 1.8)` for
`|M| > 6`. Same 100-iteration cap, same `1e-12` tolerance on the step. `H` is never
wrapped (a hyperbola is flown once).

**SOI patched-conic handoff** — no numerical integration; two closed-form/semi-closed
pieces:
- **Escape** (`nextEscapeTime`, orbit.ts:83): analytic solve of `r(E or H) = soiRadius`
  for the outbound crossing (`E ∈ (0,π)` elliptical, `H > 0` hyperbolic); exact, no
  iteration beyond the Kepler-equation solves already used.
- **Capture** (`World.nextCaptureTime`, world.ts, private): a **sampled scan**, not
  closed-form — samples ship-vs-child distance at `CAPTURE_SAMPLES = 2000` points over
  the horizon, finds the first downward crossing of the SOI radius, then refines with
  **50 bisection iterations**. Horizon = time to next escape, or one orbital period for
  a bound orbit, or `5e8` s cap for an open arc (`captureHorizon()`).
- SOI radius itself: `soiRadius = a·(μ_body/μ_parent)^(2/5)` (system.ts:33, the Laplace/KSP
  formula) — closed-form, no iteration.

**Lambert's problem** — `lambert` (solvers.ts:107), universal-variable formulation
(Vallado) with Stumpff functions `c2(ψ), c3(ψ)`. Solves `TOF(ψ) = tof` for the universal
variable ψ by **bisection**, up to **100 iterations**, converged when
`|TOF(ψ) − tof| < 1e-5 · max(1, tof)`. Direct (`nrev=0`) window: `ψ ∈ [−4π², 4π²]`.
Multi-rev (`nrev ≥ 1`): window `((2nrev·π)², (2(nrev+1)·π)²)`, first found by a
**100-iteration ternary search** for the TOF-minimizing ψ (the low/high branch split),
then bisected within the requested branch. Returns `null` on non-convergence or an
unreachable geometry (no synthetic clamping — a real "no solution").

**Rendezvous / interplanetary layering** — `bestTransfer`/`solveIntercept`/
`suggestInterplanetaryWindow` are all **closed-form searches or grid scans over the
Lambert solver**, not independent numerical methods: porkchop grid is 48×40 coarse then
12×12 refine (solvers.ts, `suggestInterplanetaryWindow`); intercept TOF scan steps every
120 s from 1800–21600 s (`SUGGEST_TOF_MIN/MAX/STEP`).

**Finite-thrust integration** — `stepPowered` (flight.ts:262). Classic **4th-order
Runge-Kutta (RK4)** on `(r, v)` under `−μ·r̂/r² + thrust`; mass drops by the rocket
equation (`ṁ = F·throttle/(Isp·g0)`) applied as a simple `m − ṁ·dt` over the same step
(not itself RK4'd). Thrust direction/magnitude and mass are held constant across one
substep. **Fixed substep `DT_PHYS = 1/64 s`** (world.ts:29) — this is the load-bearing
constant for determinism (see §5, C2). `MAX_SUBSTEPS = 4096` per `advance()` call bounds
per-tick CPU; excess sim-time is carried in `physAccum` to the next call ("lazy catch-up").

**Attitude integration** — `integrateAttitude` (flight.ts:87): semi-implicit Euler on
Euler's rigid-body equation `I·ω̇ = τ − ω×(Iω)` (diagonal `I`), then quaternion kinematics
`q̇ = ½ q ⊗ (0,ω)` using the **updated** ω (semi-implicit, for stability), followed by
re-normalizing `q`. Same `DT_PHYS` grid as translation. Controller (`controlTorqueBody`,
flight.ts:125) is a phase-plane speed profile (`ω_cmd = min(rateCap, √(2·α_max·angle·0.85))`)
feeding a velocity-loop gain `KGAIN = 4`, torque clamped to `maxTorque`.

**Time-warp handling** — `World.advance(realDtSeconds)` (world.ts:296): `simDelta =
realDtSeconds * rate`. Fast path: pure coast with no live burn/pending burn-window
jumps straight via analytic `propagate` (`stepCoastWithSoi`, splitting only at SOI
boundaries, capped at **64 loop iterations** as a guard). Powered/burn-window path
accumulates `simDelta` into `physAccum` and drains it in fixed `DT_PHYS` chunks
(`MAX_SUBSTEPS` cap per call). `SAFE_WARP = 10` — warp is auto-clamped to 10× (not 1×)
within `SOI_LEAD = 120 s` of a handoff (`limitWarpForSoi`) or within
`max(20s, burnDuration)` of a node's burn window (`driveExecutor`); 10× is proven safe
because the coast lands exactly on the boundary and burns integrate on the fixed
`DT_PHYS` grid regardless of warp (legacy/web/docs/11 §4).

## 4. Verification numbers (`legacy/web/scripts/check-sim.ts`) — the GDScript test suite

Central-body constants first (`constants.ts`) — every numeric check below assumes these:

| Body | mu [m³/s²] | radius [m] | rotationPeriod | parentId | elements (a,e,i,raan,argp,M0,epoch) | soiRadius [m] |
|---|---|---|---|---|---|---|
| Sol | 1.32712440018e20 | 6.957e8 | null | null (root) | null | null (infinite) |
| Cradle | 3.986004418e14 | 6.371e6 | null | sol | a=1 AU=1.495978707e11, e=0,i=0,raan=0,argp=0,M0=0,epoch=0 | ≈9.2e8 (computed: `soiRadius(1AU, 3.986004418e14, 1.32712440018e20)`) |
| Vesper | 4.282837e13 | 3.3895e6 | null | sol | a=0.8 AU, e=0,i=0,raan=0,argp=0,M0=deg(40),epoch=0 | ≈3.0e8 |

Default ship fuel used across checks unless stated: `{dryMassKg: 8000, propellantKg: 4000,
ispSeconds: 320}` (a lighter test fuel than the in-game default ship). `body` = Cradle
throughout unless noted.

| # | Scenario | Inputs | Expected | Tolerance |
|---|---|---|---|---|
| 1 | 400 km circular, Cradle | `circularOrbit(body, 400e3)` @ t=0 | period 92.4 min; speed 7672 m/s; altitude/apo/peri altitude 400 km | 0.3 min; 5 m/s; 1e-3 km |
| 2 | Circular orbit stable over time | same orbit @ t=0,1000,2772,5544,12345 s | altitude 400 km at every t | 1e-3 km |
| 3 | Elliptical 400×800 km | a=(rp+ra)/2, e computed, M0=0 (periapsis) | peri alt 400 km; apo alt 800 km; period 96.5 min; speed peri>apo>circ | 0.5 km; 0.5 km; 0.5 min; n/a (boolean) |
| 4 | timeToPeriapsis wrap (H1 regression) | same ellipse | 0 at periapsis; period/2 at apoapsis; 1 s just before periapsis; timeTo+timeSince=period | 1e-6 s; 1e-3 s; 1e-3 s; 1e-6 s |
| 5 | Inclined 51.6° circular | `circularOrbit(body,400e3,deg(51.6))` | lat 0° @ node, +51.6° @ T/4, 0° @ T/2, −51.6° @ 3T/4; period/speed unchanged | 1e-3°; 0.3 min; 5 m/s |
| 6 | State↔elements round trip | propagate → stateToElements → propagate, t=1234 | position x/y/z match; speed match | 1 m; 1e-2 m/s |
| 7 | Prograde node raises apoapsis | dv=109.4 m/s prograde @ 400km circ 51.6°, fuel {8000,4000,320} | dvMag 109.4; new apo 800 km; new peri 400 km; propellant 411 kg; feasible | 0.1 m/s; 1 km; 1 km; 5 kg |
| 8 | Pure normal burn → inclination | dvN=500 m/s normal @ 400km circ equatorial | dvMag 500; Δi = atan2(500, vCirc) | 0.1 m/s; 0.05° |
| 9 | Burn beyond tanks flagged | dv=5000 m/s prograde, fuel {8000,4000,320} | infeasible=true, note is a string | n/a |
| 10 | Circularize at apoapsis | 400×800 ellipse, `solveCircularize(...,"apoapsis")` | apo/peri after = 800 km; e≈0; feasible | 1 km; 1 km; 1e-3 |
| 11 | Set periapsis via burn at apoapsis | 400×800 ellipse → periapsis 600 km | new peri 600 km; apo unchanged 800 km | 1 km; 1 km |
| 12 | Hohmann 400→800 km circular | `solveHohmann` | 2 burns; total Δv 217.9 m/s; final apo/peri 800 km | 3 m/s; 1 km; 1 km |
| 13 | Lambert reaches target position | tof=4800 s, 400km circ→450km circ (M0=20°), both 51.6° | arrival x/y/z match target | 0.2 km each axis |
| 14 | Guided intercept reaches dock envelope | target = Depot Six, guided `planIntercept` | range < 1 km; relSpeed < 5 m/s after ONE transfer | n/a (envelope, DOCK_RANGE=1000m, DOCK_REL_SPEED=5 m/s) |
| 15 | Determinism, same inputs | `propagate` twice, t=4242 | `JSON.stringify` identical | exact |
| 16 | Finite burn delivers rocket-eq Δv | thrust 50 kN, Isp 320s, dry 8000, m0=12000, μ=0 (isolated), T=20s, dt=1/64 | Δv = Isp·g0·ln(m0/m1); Δm = (F/(Isp·g0))·T | 0.5 m/s; 0.5 kg |
| 17 | 180° slew settles | I={14000,107000,107000}, τ=5500 N·m, rateCap=20°/s | settle time between 8–26 s (target ~16 s) | range check |
| 18 | Hybrid slew→burn→fold to coast | World, prograde hold, 6s burn, cut | apo raised >5000 m; continuous across fold (<2000 m jump); propellant spent >50 kg | boolean thresholds |
| 19 | Powered integration tick-size invariance | 2.0s burn as 128×(1/64s) vs 2×(1.0s) chunks | apoapsis altitude matches | 1e-3 km |
| 20 | Executor-flown node tick-chunking invariance | node dv=150 m/s @ t=0, chunk 1/64s vs 1.0s | apo Δ, peri Δ, propellant-burned Δ | 1e-3 m; 1e-3 m; 1e-6 kg |
| 21 | Executor flies planned node to preview | node dv=150 prograde | reached apo within 30 km of `previewNode`'s prediction; nodes drained | 30 km |
| 22 | Executor flies two sequential nodes | burn-1 @t=0 (60 m/s), burn-2 @t=600 (60 m/s) | both nodes consumed in order; propellant burned >50 kg | boolean |
| 23 | Chat-turn mutex (server concurrency, not physics) | two async "plan→execute" turns racing a shared pending slot | unserialized turns interleave (bug reproduced); chained turns each commit their own plan | n/a — not part of the physics port |
| 24 | Hyperbolic round trip (e>1) | v0 = 1.2× escape speed, tangential | e>1; position/velocity round-trip; apoapsisRadius=Infinity; energy conserved after coasting | Δr<1e-3 m; Δv<1e-6 m/s; ΔE<1e-3 |
| 25 | Heliocentric hierarchy resolves | `defaultSystem()`, t=12345/7777 | Sol at exact origin; Cradle at 1 AU from Sol; relativeState = difference of root states | Cradle dist ±1 m; rel pos <1e-3 m, rel vel <1e-6 m/s |
| 26 | Cross-SOI target gating | Vesper target from Cradle, then from Sol (heliocentric ship orbit) | range > 1e10 m and `sameFrame=false` @ Cradle; `planIntercept=null` @ Cradle; interceptable (dv>0) @ Sol with tof=4e6 s | n/a |
| 27 | SOI escape, tick-size independent | high ellipse, apoapsis = 2×SOI radius, ticks of 50s vs 20000s | both reach Sol; escape time matches; root position matches | time <1e-6 s; root pos <1 m |
| 28 | SOI capture | heliocentric approach into Vesper's SOI, closing speed 200 m/s, start at 1.5×SOI | predicted body = capturing body = "vesper"; final radius < SOI+1 m | 1 m |
| 29 | Full Cradle→Vesper transfer plan builds | 400 km parking orbit, `planTransferWindow` | feasible; total Δv < ship's Δv budget; exactly 4 nodes; departure ≤ 2400 days | n/a |
| 30 | Interplanetary window bounds | `suggestInterplanetaryWindow(Cradle, Vesper, ...)` | TOF ≤ 1.75×Hohmann-time+1; departure ≤ 2400 d; dvEject>0; dvCapture>0; dvTotal < 12200 m/s | as stated |
| 31 | Interplanetary window prefers sooner | wide margin (5×) vs tight margin (1.01×) | wide-margin departure time ≤ tight-margin departure time + 1 s | 1 s |
| 32 | Full transfer plan flies end-to-end | executed plan, advanced under warp | escapes Cradle; enters Vesper SOI; min range < Vesper SOI radius; propellant remains >0 | n/a |
| 33 | Ship can burn to escape with margin | sustained prograde burn from default ship | budget > 10000 m/s; reaches e≥1 within 1500 s; propellant remains | n/a |
| 34 | Cargo/market arithmetic (economy, not physics) | buy/sell ore/water/ballast at two stations, SELL_FACTOR=0.85 | exact credit arithmetic, stock clamping, rejection cases | exact integers — see script for values (not orbital mechanics, lower priority for the physics port) |

## 5. Known bugs / caveats to address during the port

**C2 — powered flight vs wall-clock dt** (already fixed in TS; the fix pattern must be
replicated, not re-broken). Before the fix (legacy/web/docs/08 D3, legacy/web/docs/10 §3), stepping powered
flight directly off the caller's per-frame wall-clock delta made the resulting trajectory
depend on how that delta happened to be chunked — non-deterministic across frame rates
or replay. The fix is a **fixed-step accumulator**: `World.advance()` (world.ts:296) adds
`simDelta` into a private `physAccum` and drains it in exact `DT_PHYS` (1/64 s)
increments, re-deciding control at each boundary, carrying any remainder to the next
call — enforced by checks #19 and #20 in §4. **Port requirement:** don't feed Godot's
`_process`/`_physics_process` `delta` straight into the RK4 stepper — replicate the
accumulate-and-drain pattern (a `float` accumulator, fixed `DT_PHYS` chunks, a
max-substeps-per-call cap), or the bug the TS code fixed comes back.

**The unguarded sim tick.** `World.advance(realDtSeconds: number)` and the public `rate`
field it multiplies by have no input validation: nothing clamps `realDtSeconds` to be
non-negative/finite, and there is no `setWarp`/`setRate` in `api.ts` at all — `rate` is a
bare mutable field any caller can set to zero, negative, `NaN`, or huge. `MAX_SUBSTEPS =
4096` bounds backlog drained per call (the rest defers via `physAccum`), but nothing
bounds `physAccum`'s growth, and nothing guards `World.time`/`World.rate` against a
nonsensical direct write. **Port requirement:** Godot's frame delta can spike more
visibly than a browser tab (alt-tab, a breakpoint, a scene-load stall) — add explicit
clamps on `delta` and `rate` at the call site; the original relies entirely on its
caller (outside `src/sim`) behaving well.

## 6. Porting notes for GDScript

**Float precision is the biggest trap.** Godot 4's built-in `Vector3` is **32-bit float**
per component (GDScript `float` is 64-bit, but `Vector3`/`Vector2` stay float32 unless
Godot is built with `precision=double`). Distances here run to `~9.2e8 m` (Cradle's SOI)
and `~1.5e11 m` (1 AU); float32's ~7 significant digits gives a `Vector3` at 1 AU ~10 km
of error before any physics runs, and RK4-integrated velocities near periapsis (~7-8 km/s)
will drift visibly. **Never store `position`/`velocity` (`RVMState.r/v`, `OrbitState.position/velocity`,
Lambert's `r1/r2/v1/v2`) in a native `Vector3`.** Keep them as three separate 64-bit
`float`s or a custom `Vector3d` struct all the way through the physics layer; convert to
a real `Vector3` only at the last step for rendering, after re-basing to a camera/ship-
local origin (floating-origin pattern) so rendered magnitudes stay small. Angles
(`i, raan, argp`, anomalies, `latitude`) and scalars (`a, e, mu, radius, period, speed`)
are fine as plain `float`. Quaternions are float32 in Godot too, but rotation doesn't
accumulate the same magnitude error as position — still, do `integrateAttitude`'s math in
raw floats/a custom quat if bit-for-bit parity with `check-sim` matters, converting to
`Quaternion`/`Basis` only for rendering.

**JS/TS-specific constructs to replace:**
- `Map<string, Body>` in `System` (system.ts:38) → GDScript `Dictionary` keyed by id
  string, or a linear-scan `Array` if the body count stays small.
- No `Date.now()`/`BigInt`/`performance.now()` anywhere in `src/sim` — a designed
  invariant ("pure and deterministic... no `Date.now()`", maneuver.ts:13, system.ts:9).
  **Preserve it**: the ported sim layer must never read `Time.get_ticks_msec()`; time is
  always an explicit parameter (`t`, `dt`, `realDtSeconds`).
- Discriminated unions (`Retarget`, the `AttitudeMode` string-literal union) have no
  GDScript equivalent — use an `enum` for mode tags, and a class/dictionary with optional
  fields (or two subclasses + a type-check) for `Retarget`.
- The `get body(): Body` getter on `World` — Godot 4 supports `var body: Body: get =
  _get_body`, or use a plain `get_body()` method; either way don't cache it, it must
  re-resolve `system.body(centralBodyId)` every access since that id changes on SOI handoff.
- Optional chaining (`?.`) / nullish coalescing (`??`), used throughout for
  `parentId`/`soiRadius`/etc. → explicit `if x != null:` guards. Watch `system.ts`
  (`b.parentId`) and `world.ts` (`nextSoi`, `poweredState`), where `null` means "root
  body" / "coasting" and is checked constantly.
- Per-file local closures for vector math (`add/sub/scale/dot/cross/len/norm/clampMag`,
  redefined separately in both `flight.ts` and `solvers.ts` — a JS-module-boundary
  artifact, not a design intent worth keeping) — port once as a shared `Vec3d` utility.
- `Math.hypot`/`acosh`/`asinh`/`atanh` (used in `solveHyperKepler`, RV2COE) have no
  GDScript builtin — implement `hypot(x,y,z)=sqrt(x*x+y*y+z*z)` and the inverse-hyperbolic
  identities (`asinh(x) = ln(x + sqrt(x*x+1))`, etc.) explicitly.
- `Infinity`/`NaN` are real sentinel values here (hyperbolic `period`/`apoapsisRadius`,
  candidate scoring via `Number.isFinite`) — GDScript's double `float` supports
  `INF`/`NAN`/`is_inf()`/`is_nan()` fine; just make sure every `=== Infinity` check
  (e.g. check #24) becomes `is_inf(x)`, not a fragile `== INF`.
- `class System`/`class World` → GDScript `class_name` extending `RefCounted`, not
  `Node` — nothing here touches the scene tree; drive `advance()` from a thin Node
  wrapper's `_physics_process`.

**Determinism discipline to preserve end-to-end:** every function in `orbit.ts`,
`system.ts`, `solvers.ts`, `maneuver.ts`, `flight.ts` is a pure function of its
arguments — no `World` reference, no hidden globals. Don't let these reach into a Godot
singleton/autoload for `mu`, `time`, or ship state; `World` (and its GDScript
equivalent) is the only place state should live. That boundary is what lets the
`check-sim` numeric checks in §4 port 1:1 into GDScript/GUT unit tests.
