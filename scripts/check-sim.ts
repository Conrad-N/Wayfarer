// Numeric self-test for the orbital sim — the M0 acceptance criteria (docs/07 §8)
// as runnable assertions. Run with `npm run check`.
import assert from "node:assert/strict";
import type { OrbitalElements } from "../src/sim/types";
import { CRADLE, circularOrbit, deg, defaultSystem } from "../src/sim/constants";
import { propagate } from "../src/sim/orbit";
import { previewNode, buildPlan, stateToElements } from "../src/sim/maneuver";
import { solveCircularize, solveSetApsis, solveHohmann, lambert } from "../src/sim/solvers";
import { World } from "../src/sim/world";
import { planManeuver, planIntercept, planTransferWindow, executeManeuver, selectTarget, getOrbit, getTarget, listTargets, getShip } from "../src/sim/api";
import {
  stepPowered,
  integrateAttitude,
  controlTorqueBody,
  thrustAxisWorld,
  IDENTITY_Q,
  G0,
} from "../src/sim/flight";

const body = CRADLE;
let failures = 0;

function approx(actual: number, expected: number, tol: number, label: string): void {
  const ok = Math.abs(actual - expected) <= tol;
  if (!ok) failures++;
  console.log(
    `${ok ? "PASS" : "FAIL"}  ${label.padEnd(28)} ${actual.toFixed(3)}  (expected ~${expected}, tol ${tol})`,
  );
}

console.log("== Canonical orbit: 400 km circular around Cradle ==");
const circ = propagate(circularOrbit(body, 400e3), body, 0);
approx(circ.period / 60, 92.4, 0.3, "period [min]");
approx(circ.speed, 7672, 5, "speed [m/s]");
approx(circ.altitude / 1000, 400, 1e-3, "altitude [km]");
approx(circ.apoapsisAltitude / 1000, 400, 1e-3, "apoapsis altitude [km]");
approx(circ.periapsisAltitude / 1000, 400, 1e-3, "periapsis altitude [km]");

console.log("\n== Circular orbit is stable as time advances ==");
for (const t of [0, 1000, 2772, 5544, 12345]) {
  const s = propagate(circularOrbit(body, 400e3), body, t);
  approx(s.altitude / 1000, 400, 1e-3, `altitude @ t=${t}s [km]`);
}

console.log("\n== Elliptical orbit: 400 x 800 km altitude ==");
const rp = body.radius + 400e3;
const ra = body.radius + 800e3;
const ell: OrbitalElements = {
  a: (rp + ra) / 2,
  e: (ra - rp) / (ra + rp),
  i: 0,
  raan: 0,
  argp: 0,
  meanAnomalyAtEpoch: 0, // M=0 -> at periapsis
  epoch: 0,
};
const peri = propagate(ell, body, 0);
const apo = propagate(ell, body, peri.period / 2);
approx(peri.altitude / 1000, 400, 0.5, "periapsis altitude [km]");
approx(apo.altitude / 1000, 800, 0.5, "apoapsis altitude [km]");
approx(peri.period / 60, 96.5, 0.5, "period [min]");
const fasterAtPeriapsis = peri.speed > apo.speed && peri.speed > circ.speed;
console.log(
  `${fasterAtPeriapsis ? "PASS" : "FAIL"}  vis-viva: faster at periapsis  ` +
    `peri=${peri.speed.toFixed(0)} m/s  apo=${apo.speed.toFixed(0)} m/s`,
);
if (!fasterAtPeriapsis) failures++;

console.log("\n== H1: timeToPeriapsis wraps to 0 at periapsis (no full-period jump) ==");
// At M=0 the old form returned a whole period instead of 0, and snapped
// discontinuously across periapsis. The wrapped form maps M=0 -> 0.
approx(peri.timeToPeriapsis, 0, 1e-6, "timeToPeri @ periapsis [s]");
approx(apo.timeToPeriapsis, peri.period / 2, 1e-3, "timeToPeri @ apoapsis [s]");
// And the countdown is continuous: just-before-periapsis is ~period, not a cliff.
const nearPeri = propagate(ell, body, peri.period - 1);
approx(nearPeri.timeToPeriapsis, 1, 1e-3, "timeToPeri 1s before peri [s]");
// Invariant: time-to + time-since = one full period at any mid-orbit phase.
const midPhase = propagate(ell, body, peri.period * 0.37);
approx(
  midPhase.timeToPeriapsis + midPhase.timeSincePeriapsis,
  peri.period,
  1e-6,
  "timeTo + timeSince = period",
);

console.log("\n== Inclined orbit: 51.6° circular, latitude sweeps ±i (docs/07 §8 crit. 5) ==");
const RAD = 180 / Math.PI;
const incl = circularOrbit(body, 400e3, deg(51.6));
const Ti = propagate(incl, body, 0).period;
// Starts at the ascending node; latitude reaches +i at T/4, 0 at T/2, −i at 3T/4.
approx(propagate(incl, body, 0).latitude * RAD, 0, 1e-3, "lat @ ascending node [deg]");
approx(propagate(incl, body, Ti / 4).latitude * RAD, 51.6, 1e-3, "lat @ T/4 = max north [deg]");
approx(propagate(incl, body, Ti / 2).latitude * RAD, 0, 1e-3, "lat @ T/2 [deg]");
approx(propagate(incl, body, (3 * Ti) / 4).latitude * RAD, -51.6, 1e-3, "lat @ 3T/4 = max south [deg]");
// Inclination must not perturb the canonical scalars.
approx(propagate(incl, body, 0).period / 60, 92.4, 0.3, "period unchanged [min]");
approx(propagate(incl, body, 0).speed, 7672, 5, "speed unchanged [m/s]");

console.log("\n== M1: state <-> elements round-trip (RV2COE inverts propagate) ==");
const rtEl = circularOrbit(body, 400e3, deg(51.6));
const sv = propagate(rtEl, body, 1234);
const sv2 = propagate(stateToElements(sv.position, sv.velocity, body, 1234), body, 1234);
approx(sv2.position.x, sv.position.x, 1, "round-trip pos.x [m]");
approx(sv2.position.y, sv.position.y, 1, "round-trip pos.y [m]");
approx(sv2.position.z, sv.position.z, 1, "round-trip pos.z [m]");
approx(sv2.speed, sv.speed, 1e-2, "round-trip speed [m/s]");

console.log("\n== Planner: prograde node raises apoapsis (forward primitive) ==");
const fuel = { dryMassKg: 8000, propellantKg: 4000, ispSeconds: 320 };
const raise = previewNode(circularOrbit(body, 400e3, deg(51.6)), body, fuel, {
  time: 0,
  dvLocal: { prograde: 109.4, normal: 0, radial: 0 },
});
approx(raise.dvMag, 109.4, 0.1, "Δv magnitude [m/s]");
approx(raise.after.apoapsisAltitude / 1000, 800, 1, "resulting apoapsis [km]");
approx(raise.after.periapsisAltitude / 1000, 400, 1, "resulting periapsis [km]");
approx(raise.propellantKg, 411, 5, "propellant burned [kg]");
console.log(
  `${raise.feasible ? "PASS" : "FAIL"}  feasible within Δv budget (${raise.dvBudgetBefore.toFixed(0)} m/s)`,
);
if (!raise.feasible) failures++;

console.log("\n== Planner: a pure NORMAL burn changes inclination (3-axis capability) ==");
const vCirc = propagate(circularOrbit(body, 400e3, 0), body, 0).speed;
const dvN = 500;
const plane = previewNode(circularOrbit(body, 400e3, 0), body, fuel, {
  time: 0,
  dvLocal: { prograde: 0, normal: dvN, radial: 0 },
});
const expectedI = Math.atan2(dvN, vCirc) * RAD;
approx(plane.dvMag, dvN, 0.1, "Δv is the normal component [m/s]");
approx(plane.after.i * RAD, expectedI, 0.05, "inclination after normal burn [deg]");
console.log(`${plane.feasible ? "PASS" : "FAIL"}  normal burn feasible (Δi ≈ ${expectedI.toFixed(2)}°)`);
if (!plane.feasible) failures++;

console.log("\n== Planner: a burn beyond the tanks is flagged infeasible ==");
const tooBig = previewNode(circularOrbit(body, 400e3, deg(51.6)), body, fuel, {
  time: 0,
  dvLocal: { prograde: 5000, normal: 0, radial: 0 },
});
const flagged = !tooBig.feasible && typeof tooBig.note === "string";
console.log(`${flagged ? "PASS" : "FAIL"}  infeasible flagged — ${tooBig.note}`);
if (!flagged) failures++;

console.log("\n== Solver: circularize at apoapsis (400×800 ellipse → circular) ==");
{
  const node = solveCircularize(ell, body, 0, "apoapsis");
  const plan = buildPlan(ell, body, fuel, "circ @ apo", [node]);
  approx(plan.after.apoapsisAltitude / 1000, 800, 1, "apo after circularize [km]");
  approx(plan.after.periapsisAltitude / 1000, 800, 1, "peri after circularize [km]");
  approx(plan.after.e, 0, 1e-3, "eccentricity ≈ 0");
  console.log(`${plan.feasible ? "PASS" : "FAIL"}  circularized (Δv ${plan.dvMag.toFixed(1)} m/s)`);
  if (!plan.feasible) failures++;
}

console.log("\n== Solver: raise periapsis 400→600 on a 400×800 ellipse (burn at apo) ==");
{
  const node = solveSetApsis(ell, body, 0, "periapsis", body.radius + 600e3);
  const plan = buildPlan(ell, body, fuel, "set peri", [node]);
  approx(plan.after.periapsisAltitude / 1000, 600, 1, "new periapsis [km]");
  approx(plan.after.apoapsisAltitude / 1000, 800, 1, "apoapsis unchanged [km]");
  console.log(`${plan.feasible ? "PASS" : "FAIL"}  periapsis raised (Δv ${plan.dvMag.toFixed(1)} m/s)`);
  if (!plan.feasible) failures++;
}

console.log("\n== Solver: Hohmann 400 → 800 km circular (two burns) ==");
{
  const el = circularOrbit(body, 400e3, deg(51.6));
  const nodes = solveHohmann(el, body, 0, body.radius + 800e3);
  const plan = buildPlan(el, body, fuel, "hohmann", nodes);
  approx(plan.burns.length, 2, 0, "two burns");
  approx(plan.dvMag, 217.9, 3, "total Δv [m/s]");
  approx(plan.after.apoapsisAltitude / 1000, 800, 1, "final apoapsis [km]");
  approx(plan.after.periapsisAltitude / 1000, 800, 1, "final periapsis [km] (circular)");
  console.log(`${plan.feasible ? "PASS" : "FAIL"}  transfer feasible (${plan.propellantKg.toFixed(0)} kg)`);
  if (!plan.feasible) failures++;
}

console.log("\n== Lambert: the transfer reaches the target position in the flight time ==");
{
  const el1 = circularOrbit(body, 400e3, deg(51.6));
  const el2 = { a: body.radius + 450e3, e: 0, i: deg(51.6), raan: 0, argp: 0, meanAnomalyAtEpoch: deg(20), epoch: 0 };
  const tof = 4800; // 80 min
  const s1 = propagate(el1, body, 0);
  const s2 = propagate(el2, body, tof);
  const sol = lambert(s1.position, s2.position, tof, body.mu, true);
  if (!sol) {
    console.log("FAIL  lambert returned no solution");
    failures++;
  } else {
    // Fly the transfer from (r1, v1) for the flight time; it must land on the target's r2.
    const arrived = propagate(stateToElements(s1.position, sol.v1, body, 0), body, tof);
    approx(arrived.position.x / 1000, s2.position.x / 1000, 0.2, "arrival x [km]");
    approx(arrived.position.y / 1000, s2.position.y / 1000, 0.2, "arrival y [km]");
    approx(arrived.position.z / 1000, s2.position.z / 1000, 0.2, "arrival z [km]");
  }
}

console.log("\n== Rendezvous: ONE guided intercept reaches the dock envelope (midcourse correction) ==");
{
  // Depot Six is far + poorly phased — its only affordable transfer is long and hyper-sensitive,
  // so an open-loop intercept misses by hundreds of km and needs re-flying. The guided intercept
  // (midcourse trims recomputed in flight) must close it to the dock envelope in a SINGLE transfer.
  const sim = new World();
  selectTarget(sim, 1); // Depot Six
  const before = getTarget(sim).range / 1000;

  // Warp to each pending burn and let the executor slew + fire it (drops the node count).
  const flyAllNodes = () => {
    let guard = 0;
    while (sim.nodes.length > 0 && guard++ < 50) {
      const n0 = sim.nodes.length;
      sim.jumpToNextNode();
      let g = 0;
      while (sim.nodes.length === n0 && g < 1200) {
        sim.advance(0.05); // fine steps ⇒ crisp burn cutoff (real play steps per frame, finer still)
        g += 0.05;
      }
    }
  };

  const plan = planIntercept(sim); // guided: departure + midcourse trims + live match
  const fired = !!plan && executeManeuver(sim, true).ok;
  if (fired) flyAllNodes();

  const range = getTarget(sim).range / 1000;
  const rel = getTarget(sim).relSpeed;
  const ok = fired && range < 1 && rel < 5; // the dock envelope (DOCK_RANGE 1 km, DOCK_REL_SPEED 5 m/s)
  console.log(
    `${ok ? "PASS" : "FAIL"}  Depot Six range ${before.toFixed(0)}→${range.toFixed(2)} km; rel vel ${rel.toFixed(2)} m/s in one transfer`,
  );
  if (!ok) failures++;
}

console.log("\n== Determinism: same inputs -> same state ==");
const aState = propagate(circularOrbit(body, 400e3), body, 4242);
const bState = propagate(circularOrbit(body, 400e3), body, 4242);
const identical = JSON.stringify(aState) === JSON.stringify(bState);
console.log(`${identical ? "PASS" : "FAIL"}  reproducible`);
if (!identical) failures++;

console.log("\n== Flight: finite burn delivers the rocket-equation Δv (RK4 integrator) ==");
{
  const freeSpace = { ...CRADLE, mu: 0 }; // isolate thrust from gravity
  const engine = { thrustN: 50_000, ispSeconds: 320 };
  const dry = 8000;
  const dir = { x: 0, y: 1, z: 0 }; // thrust along +y = along velocity
  let s = { r: { x: 7e6, y: 0, z: 0 }, v: { x: 0, y: 7000, z: 0 }, m: 12000 };
  const T = 20;
  const dtp = 1 / 64;
  for (let t = 0; t + dtp <= T + 1e-9; t += dtp) s = stepPowered(s, freeSpace, dir, 1, engine, dry, dtp);
  approx(s.v.y - 7000, engine.ispSeconds * G0 * Math.log(12000 / s.m), 0.5, "delivered Δv [m/s]");
  approx(12000 - s.m, (engine.thrustN / (engine.ispSeconds * G0)) * T, 0.5, "propellant burned [kg]");
}

console.log("\n== Flight: 180° slew completes & settles (rigid body + reaction wheels) ==");
{
  const I = { ix: 14_000, iy: 107_000, iz: 107_000 };
  const tau = 5500;
  const rateCap = deg(20);
  const dtp = 1 / 64;
  const target = { x: -1, y: 0, z: 0 }; // 180° from the initial +X pointing
  let q = IDENTITY_Q;
  let omega = { x: 0, y: 0, z: 0 };
  let settledAt = -1;
  for (let t = 0; t < 60 && settledAt < 0; t += dtp) {
    const torque = controlTorqueBody(q, omega, target, I, tau, rateCap);
    const next = integrateAttitude(q, omega, I, torque, dtp);
    q = next.q;
    omega = next.omega;
    const a = thrustAxisWorld(q);
    const err = Math.acos(Math.max(-1, Math.min(1, a.x * target.x + a.y * target.y + a.z * target.z)));
    if (err < deg(1) && Math.hypot(omega.x, omega.y, omega.z) < deg(1)) settledAt = t;
  }
  const ok = settledAt > 8 && settledAt < 26;
  console.log(`${ok ? "PASS" : "FAIL"}  180° flip settled in ${settledAt.toFixed(1)} s (target ~16 s)`);
  if (!ok) failures++;
}

console.log("\n== Flight: hybrid — slew to prograde, finite burn raises orbit, fold to coast ==");
{
  const sim = new World();
  sim.attitudeMode = "prograde";
  for (let t = 0; t < 40; t += 0.1) sim.advance(0.1); // slew to prograde, engine off
  const apoBefore = sim.orbit().apoapsisAltitude;
  const propBefore = sim.ship.propellantKg;
  sim.throttle = 1;
  for (let t = 0; t < 6; t += 0.1) sim.advance(0.1); // ~6 s prograde burn
  const apoMidBurn = sim.orbit().apoapsisAltitude;
  sim.throttle = 0;
  sim.advance(1); // engine cut → fold to coast conic
  const apoAfter = sim.orbit().apoapsisAltitude;
  const raised = apoAfter > apoBefore + 5000;
  const continuous = Math.abs(apoAfter - apoMidBurn) < 2000; // no jump across the fold
  const spent = sim.ship.propellantKg < propBefore - 50;
  console.log(
    `${raised && continuous && spent ? "PASS" : "FAIL"}  apo ${(apoBefore / 1000).toFixed(0)}→${(apoAfter / 1000).toFixed(0)} km, burned ${(propBefore - sim.ship.propellantKg).toFixed(0)} kg`,
  );
  if (!(raised && continuous && spent)) failures++;
}

console.log("\n== Flight: powered integration is identical regardless of tick size ==");
{
  const DT = 1 / 64;
  // Burn the same whole-substep total (2.0 s = 128 substeps) but grouped very
  // differently: 1 substep per call vs 64 per call. Determinism holds at the
  // DT_PHYS grid, so the end states must match (any sub-step remainder is what the
  // lazy catch-up defers — avoided here by using exact multiples).
  function burnRun(chunk: number) {
    const sim = new World();
    sim.attitudeMode = "prograde";
    for (let t = 0; t < 40; t += 0.1) sim.advance(0.1); // identical alignment
    sim.throttle = 1;
    const n = Math.round(2.0 / chunk);
    for (let i = 0; i < n; i++) sim.advance(chunk);
    return sim.orbit();
  }
  const a = burnRun(DT); // 128 calls, 1 substep each
  const b = burnRun(1.0); // 2 calls, 64 substeps each
  const same = Math.abs(a.apoapsisAltitude - b.apoapsisAltitude) < 1e-3;
  console.log(
    `${same ? "PASS" : "FAIL"}  apo ${(a.apoapsisAltitude / 1000).toFixed(4)} vs ${(b.apoapsisAltitude / 1000).toFixed(4)} km`,
  );
  if (!same) failures++;
}

console.log("\n== Determinism: an EXECUTOR-flown node is identical regardless of tick chunking ==");
{
  // The real determinism guarantee (docs/10 §3): a burn the autopilot flies must be a pure
  // function of elapsed sim-time, not of how the wall-clock delta was chunked. The node is at
  // t=0 so the executor is in the burn window from the first tick (no analytic-coast run-up to
  // phase-shift the grid), then control is re-decided at each fixed DT_PHYS substep boundary.
  function execRun(chunk: number) {
    const sim = new World();
    sim.nodes.push({ id: "det", time: 0, dvLocal: { prograde: 150, normal: 0, radial: 0 } });
    const propBefore = sim.ship.propellantKg;
    sim.setExecutor(true);
    let t = 0;
    while ((sim.executorOn || sim.nodes.length > 0) && t < 600) {
      sim.advance(chunk);
      t += chunk;
    }
    const o = sim.orbit();
    return { apo: o.apoapsisAltitude, peri: o.periapsisAltitude, burned: propBefore - sim.ship.propellantKg };
  }
  const fine = execRun(1 / 64); // 1 substep per advance()
  const coarse = execRun(1.0); //  64 substeps per advance()
  const dApo = Math.abs(fine.apo - coarse.apo);
  const dPeri = Math.abs(fine.peri - coarse.peri);
  const dBurn = Math.abs(fine.burned - coarse.burned);
  const ok = dApo < 1e-3 && dPeri < 1e-3 && dBurn < 1e-6;
  console.log(
    `${ok ? "PASS" : "FAIL"}  apo Δ${dApo.toExponential(1)} m, peri Δ${dPeri.toExponential(1)} m, ` +
      `burned Δ${dBurn.toExponential(1)} kg (apo ${(fine.apo / 1000).toFixed(2)} km, ${fine.burned.toFixed(1)} kg)`,
  );
  if (!ok) failures++;
}

console.log("\n== Executor: autopilot flies a planned node to the previewed orbit ==");
{
  const sim = new World();
  const fuelNow = { dryMassKg: sim.ship.dryMassKg, propellantKg: sim.ship.propellantKg, ispSeconds: sim.ship.ispSeconds };
  const node = { time: 0, dvLocal: { prograde: 150, normal: 0, radial: 0 } };
  // The planner is a forward calculator: it predicts the orbit; the executor should fly to it.
  const predicted = previewNode(sim.ship.elements, sim.body, fuelNow, node).after.apoapsisAltitude / 1000;
  planManeuver(sim, node);
  executeManeuver(sim, true); // lays the node + arms the executor
  let t = 0;
  while ((sim.executorOn || sim.nodes.length > 0) && t < 600) {
    sim.advance(0.1);
    t += 0.1;
  }
  const apo = getOrbit(sim).apoapsisAltitude / 1000;
  const ok = !sim.executorOn && sim.nodes.length === 0 && Math.abs(apo - predicted) < 30;
  console.log(
    `${ok ? "PASS" : "FAIL"}  autopilot reached apo ${apo.toFixed(0)} km (planner predicted ${predicted.toFixed(0)}) in ${t.toFixed(0)} s`,
  );
  if (!ok) failures++;
}

console.log("\n== Executor: flies two separately-authored nodes in sequence ==");
{
  const sim = new World();
  const propBefore = sim.ship.propellantKg;
  // Two independent prograde nodes — burn now, then again ~600 s later (no recipe; the
  // operator composes a sequence from single nodes).
  sim.nodes.push({ id: "burn-1", time: 0, dvLocal: { prograde: 60, normal: 0, radial: 0 } });
  sim.nodes.push({ id: "burn-2", time: 600, dvLocal: { prograde: 60, normal: 0, radial: 0 } });
  sim.setExecutor(true);
  let t = 0;
  while (sim.nodes.length === 2 && t < 400) {
    sim.advance(0.1); // fly node 1
    t += 0.1;
  }
  const afterFirst = sim.nodes.length;
  sim.jumpToNextNode(); // warp to node 2
  while ((sim.executorOn || sim.nodes.length > 0) && t < 1400) {
    sim.advance(0.1);
    t += 0.1;
  }
  const ok =
    afterFirst === 1 && sim.nodes.length === 0 && !sim.executorOn && sim.ship.propellantKg < propBefore - 50;
  console.log(`${ok ? "PASS" : "FAIL"}  both nodes consumed; burned ${(propBefore - sim.ship.propellantKg).toFixed(0)} kg`);
  if (!ok) failures++;
}

console.log("\n== H3: chat-turn mutex serializes plan→execute over the shared world ==");
// /api/ai/chat runs the AI tool-loop async over one shared `world`, and the
// pending burn is a single global slot. A turn = plan (write the slot) then,
// after an await, execute (commit whatever the slot holds). Two overlapping
// turns can interleave so one turn commits the OTHER's reviewed-but-
// unconfirmed plan (Keystone 2's gate defeated). The fix is the index.ts
// `chatChain` mutex; this models it and the race it closes, no AI needed.
{
  // One async turn: stamp the shared slot, yield (simulating tool-loop awaits),
  // then commit whatever the slot now holds — the execute step reads the global.
  const makeTurn = (slot: { pending: string | null }, committed: string[]) =>
    async (id: string) => {
      slot.pending = id; // plan_maneuver
      await Promise.resolve();
      await Promise.resolve(); // tool-loop / network round-trips
      committed.push(slot.pending ?? "none"); // execute_maneuver(confirm:true)
    };

  // Unserialized (the bug): fire two turns concurrently. A sets pending=A, B
  // overwrites with B before either commits, so both commit B — A committed a
  // plan no one in A's turn authored.
  {
    const slot = { pending: null as string | null };
    const committed: string[] = [];
    const turn = makeTurn(slot, committed);
    await Promise.all([turn("A"), turn("B")]);
    const crossCommit = committed[0] !== "A"; // A's turn did NOT commit A's own plan
    console.log(`${crossCommit ? "PASS" : "FAIL"}  unserialized turns DO interleave (commits=${committed.join(",")})`);
    if (!crossCommit) failures++;
  }

  // Serialized (the fix): chain turns through `chatChain` exactly as index.ts
  // does. Turn B can't start until turn A fully resolves, so each turn commits
  // its own plan.
  {
    const slot = { pending: null as string | null };
    const committed: string[] = [];
    const turn = makeTurn(slot, committed);
    let chatChain: Promise<unknown> = Promise.resolve();
    const runA = chatChain.then(() => turn("A"));
    chatChain = runA.catch(() => {});
    const runB = chatChain.then(() => turn("B"));
    chatChain = runB.catch(() => {});
    await Promise.all([runA, runB]);
    const ok = committed.length === 2 && committed[0] === "A" && committed[1] === "B";
    console.log(`${ok ? "PASS" : "FAIL"}  mutex: each turn commits its own plan (commits=${committed.join(",")})`);
    if (!ok) failures++;
  }
}

console.log("\n== Hyperbolic: a state above escape speed round-trips through elements (e > 1) ==");
{
  // Around Cradle, a tangential velocity 1.2× escape → an open (hyperbolic) trajectory.
  const r0 = { x: 7e6, y: 0, z: 0 };
  const vEsc = Math.sqrt((2 * body.mu) / 7e6);
  const v0 = { x: 0, y: 1.2 * vEsc, z: 0 };
  const el = stateToElements(r0, v0, body, 0);
  const back = propagate(el, body, 0); // same epoch — must reproduce r,v
  const dR = Math.hypot(back.position.x - r0.x, back.position.y - r0.y, back.position.z - r0.z);
  const dV = Math.hypot(back.velocity.x - v0.x, back.velocity.y - v0.y, back.velocity.z - v0.z);
  // Energy is conserved as it coasts outward; period/apoapsis are Infinity (open orbit).
  const later = propagate(el, body, 500);
  const energy0 = back.speed * back.speed / 2 - body.mu / back.radius;
  const energy1 = later.speed * later.speed / 2 - body.mu / later.radius;
  const ok =
    el.e > 1 &&
    dR < 1e-3 &&
    dV < 1e-6 &&
    back.apoapsisRadius === Infinity &&
    later.radius > back.radius &&
    Math.abs(energy0 - energy1) < 1e-3;
  console.log(
    `${ok ? "PASS" : "FAIL"}  e=${el.e.toFixed(3)}, round-trip Δr=${dR.toExponential(1)} m Δv=${dV.toExponential(1)} m/s, energy conserved`,
  );
  if (!ok) failures++;
}

console.log("\n== System: heliocentric hierarchy resolves analytically (patched-conic frame) ==");
{
  const sys = defaultSystem();
  const AU = 1.495978707e11;
  // The root star is the origin of the inertial frame.
  const sol = sys.bodyStateInRoot("sol", 12345);
  const solAtOrigin = Math.hypot(sol.position.x, sol.position.y, sol.position.z) === 0;
  // Cradle orbits Sol at ~1 AU; its heliocentric distance holds (circular orbit) across time.
  const cr = sys.bodyStateInRoot("cradle", 7777);
  const cradleDist = Math.hypot(cr.position.x, cr.position.y, cr.position.z);
  // Vesper's state seen from Cradle equals (Vesper − Cradle) in the root frame.
  const rel = sys.relativeState("cradle", "vesper", 7777);
  const ve = sys.bodyStateInRoot("vesper", 7777);
  const relConsistent =
    Math.abs(rel.position.x - (ve.position.x - cr.position.x)) < 1e-3 &&
    Math.abs(rel.velocity.y - (ve.velocity.y - cr.velocity.y)) < 1e-6;
  const ok = solAtOrigin && Math.abs(cradleDist - AU) < 1 && relConsistent;
  console.log(
    `${ok ? "PASS" : "FAIL"}  Sol@origin=${solAtOrigin}, Cradle ${(cradleDist / AU).toFixed(4)} AU from Sol, relativeState consistent=${relConsistent}`,
  );
  if (!ok) failures++;
}

console.log("\n== Targets: a cross-SOI planet is visible but its intercept is gated until co-frame ==");
{
  const sim = new World();
  // Vesper is in the roster (it orbits Sol, not Cradle) and shows a real heliocentric range.
  const list = listTargets(sim);
  const vesperIdx = list.findIndex((t) => t.name === "Vesper");
  const vesper = list[vesperIdx];
  const visibleFarAway = vesper && !vesper.sameFrame && vesper.range > 1e10; // ~0.2 AU away, cross-frame
  // Selecting it while around Cradle: intercept is unavailable (no shared frame).
  selectTarget(sim, vesperIdx);
  const blockedWhileAtCradle = getTarget(sim).sameFrame === false && planIntercept(sim) === null;
  // Once we're in the Sol frame (escaped Cradle), the SAME target becomes interceptable.
  sim.centralBodyId = "sol";
  sim.ship.elements = { a: 1.0e11, e: 0.05, i: 0, raan: 0, argp: 0, meanAnomalyAtEpoch: 0, epoch: 0 }; // a heliocentric orbit
  sim.recomputeNextSoi();
  const coFrameNow = getTarget(sim).sameFrame === true;
  const plan = planIntercept(sim, 4e6); // explicit-TOF heliocentric Lambert to Vesper (~46 days)
  const interceptable = coFrameNow && plan != null && plan.dvMag > 0;
  const ok = visibleFarAway && blockedWhileAtCradle && interceptable;
  console.log(
    `${ok ? "PASS" : "FAIL"}  Vesper range ${(vesper.range / 1.496e11).toFixed(2)} AU; gated@Cradle=${blockedWhileAtCradle}; interceptable@Sol=${interceptable}`,
  );
  if (!ok) failures++;
}

// Ship position in the root (heliocentric) frame — for checking continuity across handoffs.
function shipRootPos(sim: World) {
  const s = propagate(sim.ship.elements, sim.body, sim.time);
  const base = sim.system.bodyStateInRoot(sim.centralBodyId, sim.time);
  return { x: base.position.x + s.position.x, y: base.position.y + s.position.y, z: base.position.z + s.position.z };
}

console.log("\n== SOI: escape — a high ellipse leaves Cradle's SOI and hands off to Sol ==");
{
  function runEscape(chunk: number) {
    const sim = new World();
    const cradle = sim.body;
    const rp = cradle.radius + 400e3;
    const ra = 2 * (cradle.soiRadius as number); // apoapsis well beyond the SOI
    sim.ship.elements = {
      a: (rp + ra) / 2,
      e: (ra - rp) / (ra + rp),
      i: deg(51.6),
      raan: 0,
      argp: 0,
      meanAnomalyAtEpoch: 0, // start at periapsis
      epoch: 0,
    };
    sim.recomputeNextSoi();
    const total = (sim.nextSoi?.time ?? 0) + 50_000; // enough to cross the boundary
    let elapsed = 0;
    while (elapsed < total) {
      const c = Math.min(chunk, total - elapsed);
      sim.advance(c); // rate = 1 ⇒ simDelta = c
      elapsed += c;
    }
    return { body: sim.centralBodyId, time: sim.time, root: shipRootPos(sim) };
  }
  const fine = runEscape(50); // many small ticks
  const coarse = runEscape(20_000); // few huge ticks — must reach the SAME boundary
  const escaped = fine.body === "sol" && coarse.body === "sol";
  const dRoot = Math.hypot(fine.root.x - coarse.root.x, fine.root.y - coarse.root.y, fine.root.z - coarse.root.z);
  const ok = escaped && Math.abs(fine.time - coarse.time) < 1e-6 && dRoot < 1; // boundary crossing is chunk-independent
  console.log(
    `${ok ? "PASS" : "FAIL"}  Cradle→${fine.body}; crossing deterministic across tick size (Δroot ${dRoot.toExponential(1)} m)`,
  );
  if (!ok) failures++;
}

console.log("\n== SOI: capture — a heliocentric approach is caught by Vesper's SOI ==");
{
  const sim = new World();
  sim.centralBodyId = "sol"; // pretend we've already escaped Cradle and are cruising
  const vesper = sim.system.body("vesper");
  const vState = sim.system.bodyStateInRoot("vesper", 0);
  const vp = vState.position;
  const vpMag = Math.hypot(vp.x, vp.y, vp.z);
  const u = { x: vp.x / vpMag, y: vp.y / vpMag, z: vp.z / vpMag }; // Sun→Vesper direction
  const off = (vesper.soiRadius as number) * 1.5; // start just outside the SOI
  const shipPos = { x: vp.x + u.x * off, y: vp.y + u.y * off, z: vp.z + u.z * off };
  const vIn = 200; // m/s closing toward Vesper
  const shipVel = { x: vState.velocity.x - u.x * vIn, y: vState.velocity.y - u.y * vIn, z: vState.velocity.z - u.z * vIn };
  sim.ship.elements = stateToElements(shipPos, shipVel, sim.body, 0);
  sim.time = 0;
  sim.recomputeNextSoi();
  const predicted = sim.nextSoi?.toBodyId;
  let t = 0;
  while (sim.centralBodyId === "sol" && t < 1e7) {
    sim.advance(500);
    t += 500;
  }
  // After capture the ship is bound to Vesper, inside its SOI.
  const inSoi = propagate(sim.ship.elements, sim.body, sim.time).radius < (vesper.soiRadius as number) + 1;
  const ok = predicted === "vesper" && sim.centralBodyId === "vesper" && inSoi;
  console.log(`${ok ? "PASS" : "FAIL"}  Sol→${sim.centralBodyId} (predicted ${predicted}); inside SOI=${inSoi}`);
  if (!ok) failures++;
}

console.log("\n== Porkchop: an interplanetary transfer window to Vesper is found and is feasible ==");
{
  const sim = new World();
  sim.centralBodyId = "sol"; // as if we've escaped Cradle and are heliocentric
  sim.ship.elements = { a: 1.496e11, e: 0.02, i: 0, raan: 0, argp: 0, meanAnomalyAtEpoch: 0, epoch: 0 }; // ~1 AU
  sim.recomputeNextSoi();
  const vesperIdx = listTargets(sim).findIndex((t) => t.name === "Vesper");
  selectTarget(sim, vesperIdx);
  const plan = planTransferWindow(sim); // porkchop search over departure × TOF
  const budget = getShip(sim).dvBudget;
  const ok = plan != null && plan.feasible && plan.dvMag < budget && plan.nodes.length >= 2;
  console.log(
    plan
      ? `${ok ? "PASS" : "FAIL"}  window: Δv ${(plan.dvMag / 1000).toFixed(2)} km/s (budget ${(budget / 1000).toFixed(1)}), depart +${((plan.nodes[0].time - sim.time) / 86400).toFixed(0)} d, feasible=${plan.feasible}`
      : "FAIL  no transfer window found",
  );
  if (!ok) failures++;
}

console.log("\n== Δv: the interplanetary-class ship can burn to escape velocity with fuel to spare ==");
{
  const sim = new World();
  const budget = getShip(sim).dvBudget; // remaining Δv budget [m/s]
  sim.attitudeMode = "prograde";
  for (let t = 0; t < 40; t += 0.5) sim.advance(0.5); // settle pointing prograde
  sim.throttle = 1; // sustained prograde burn raises the orbit until it goes hyperbolic
  let t = 0;
  while (t < 1500 && getOrbit(sim).e < 1) {
    sim.advance(0.5);
    t += 0.5;
  }
  const e = getOrbit(sim).e;
  const ok = budget > 10_000 && e >= 1 && sim.ship.propellantKg > 0; // escaped, didn't run dry
  console.log(
    `${ok ? "PASS" : "FAIL"}  budget ${(budget / 1000).toFixed(1)} km/s; burned to e=${e.toFixed(2)} (escape) with ${(sim.ship.propellantKg / 1000).toFixed(1)} t left`,
  );
  if (!ok) failures++;
}

console.log(failures === 0 ? "\nAll checks passed." : `\n${failures} check(s) FAILED.`);
assert(failures === 0, `${failures} check(s) failed`);
