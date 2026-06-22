import type { CentralBody, OrbitalElements, Vec3 } from "./types";
import { propagate } from "./orbit";
import { worldDvToLocal, dvMagnitude } from "./flight";
import { stateToElements } from "./maneuver";
import type { ManeuverInput } from "./maneuver";

// Inverse solvers — deterministic, well-posed instruments that emit maneuver NODES into the
// planner pipeline (docs/10 §6 follow-up; the "library of well-posed solvers" from the design
// discussion). Each answers ONE question with a UNIQUE answer, so each is a calculation, not a
// judgment: the operator (human or AI) chooses WHICH solver and WHAT target; the math lives
// here (Keystone 2). All closed-form via vis-viva — no integration, no root-finding.
//
// They return node INPUTS (time + local Δv); api.ts wraps them in buildPlan so they flow
// through the same preview → confirm → execute gate as a hand-authored burn (Keystone 1).
//
// (Plane change is intentionally absent: the MVP target is co-planar, and a correct
// inclination-targeting burn needs node-crossing-time machinery not worth it until a target
// is actually inclined.)

export type Apsis = "apoapsis" | "periapsis";

/** Orbital speed at radius `r` on an orbit of semi-major axis `a` (vis-viva). */
const visViva = (mu: number, r: number, a: number) => Math.sqrt(mu * (2 / r - 1 / a));

/** Circularize at the next apoapsis or periapsis: one tangential burn matching circular
 *  speed there. Prograde at apoapsis (speed up), retrograde at periapsis (slow down). */
export function solveCircularize(
  el: OrbitalElements,
  body: CentralBody,
  tNow: number,
  at: Apsis,
): ManeuverInput {
  const s = propagate(el, body, tNow);
  const r = at === "apoapsis" ? s.apoapsisRadius : s.periapsisRadius;
  const tBurn = tNow + (at === "apoapsis" ? s.timeToApoapsis : s.timeToPeriapsis);
  const vAtApsis = visViva(body.mu, r, s.a); // tangential at an apsis
  const vCirc = Math.sqrt(body.mu / r);
  return { time: tBurn, dvLocal: { prograde: vCirc - vAtApsis, normal: 0, radial: 0 } };
}

/** Set one apsis to `targetRadius` by burning tangentially at the OPPOSITE apsis (which the
 *  burn leaves fixed). To move apoapsis, burn at periapsis; to move periapsis, burn at
 *  apoapsis. Closed-form via vis-viva. */
export function solveSetApsis(
  el: OrbitalElements,
  body: CentralBody,
  tNow: number,
  which: Apsis,
  targetRadius: number,
): ManeuverInput {
  const s = propagate(el, body, tNow);
  const burnAtApo = which === "periapsis";
  const rBurn = burnAtApo ? s.apoapsisRadius : s.periapsisRadius;
  const tBurn = tNow + (burnAtApo ? s.timeToApoapsis : s.timeToPeriapsis);
  const aNew = (rBurn + targetRadius) / 2;
  const vOld = visViva(body.mu, rBurn, s.a);
  const vNew = visViva(body.mu, rBurn, aNew);
  return { time: tBurn, dvLocal: { prograde: vNew - vOld, normal: 0, radial: 0 } };
}

/** Hohmann transfer to a CIRCULAR orbit at `targetRadius`. Departs NOW — assumes a near-
 *  circular start (true for the MVP) so the current radius/speed are the departure apsis —
 *  raising the opposite apsis to the target, then circularizes at the far apsis half a
 *  transfer ellipse later. Two prograde burns. */
export function solveHohmann(
  el: OrbitalElements,
  body: CentralBody,
  tNow: number,
  targetRadius: number,
): ManeuverInput[] {
  const s = propagate(el, body, tNow);
  const r0 = s.radius;
  const aTransfer = (r0 + targetRadius) / 2;
  const dvDepart = visViva(body.mu, r0, aTransfer) - s.speed;
  const tArrive = tNow + Math.PI * Math.sqrt((aTransfer * aTransfer * aTransfer) / body.mu);
  const dvArrive = Math.sqrt(body.mu / targetRadius) - visViva(body.mu, targetRadius, aTransfer);
  return [
    { time: tNow, dvLocal: { prograde: dvDepart, normal: 0, radial: 0 } },
    { time: tArrive, dvLocal: { prograde: dvArrive, normal: 0, radial: 0 } },
  ];
}

// --- Lambert intercept + rendezvous -----------------------------------------
// The general rendezvous workhorse. Lambert's problem: given two positions and a time of
// flight, find the connecting conic. We use it to MEET a target — go to where it WILL be,
// then match its velocity — which handles phasing automatically (docs/05 §M2).

const sub = (a: Vec3, b: Vec3): Vec3 => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z });
const dot3 = (a: Vec3, b: Vec3) => a.x * b.x + a.y * b.y + a.z * b.z;
const mag = (a: Vec3) => Math.hypot(a.x, a.y, a.z);
const clampN = (x: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, x));

/** Stumpff functions c2(ψ), c3(ψ) for the universal-variable formulation. */
function stumpff(psi: number): { c2: number; c3: number } {
  if (psi > 1e-6) {
    const s = Math.sqrt(psi);
    return { c2: (1 - Math.cos(s)) / psi, c3: (s - Math.sin(s)) / (s * s * s) };
  }
  if (psi < -1e-6) {
    const s = Math.sqrt(-psi);
    return { c2: (1 - Math.cosh(s)) / psi, c3: (Math.sinh(s) - s) / (s * s * s) };
  }
  return { c2: 1 / 2, c3: 1 / 6 };
}

/** Lambert's problem (universal variables, Vallado). Find the velocities at r1 and r2 on a
 *  conic connecting them in time `tof`. `prograde` picks the short way for prograde motion.
 *
 *  `nrev` is the number of FULL revolutions the transfer makes (0 = direct, the usual case).
 *  Each `nrev ≥ 1` admits two transfers of different energy for the same `tof`; `branch`
 *  selects the low-ψ ("low") or high-ψ ("high") one. Multi-rev solutions are what let a long
 *  time of flight resolve to a sane, near-circular transfer instead of one wild ellipse.
 *
 *  Returns null if there's no usable solution (e.g. `tof` shorter than the N-rev minimum). */
export function lambert(
  r1: Vec3,
  r2: Vec3,
  tof: number,
  mu: number,
  prograde = true,
  nrev = 0,
  branch: "low" | "high" = "low",
): { v1: Vec3; v2: Vec3 } | null {
  const r1m = mag(r1);
  const r2m = mag(r2);
  const cosDnu = clampN(dot3(r1, r2) / (r1m * r2m), -1, 1);
  const crossZ = r1.x * r2.y - r1.y * r2.x; // z-component of r1 × r2 (direction of motion)
  let dnu = Math.acos(cosDnu);
  const longWay = prograde ? crossZ < 0 : crossZ > 0;
  if (longWay) dnu = 2 * Math.PI - dnu;

  const A = Math.sin(dnu) * Math.sqrt((r1m * r2m) / (1 - Math.cos(dnu)));
  if (Math.abs(A) < 1e-9) return null;

  const sqrtMu = Math.sqrt(mu);

  // Time of flight as a function of the universal variable ψ. NaN where y < 0 (the conic dips
  // below the focus and the parameters are unusable at this ψ).
  const tofOf = (psi: number): number => {
    const { c2, c3 } = stumpff(psi);
    const y = r1m + r2m + (A * (psi * c3 - 1)) / Math.sqrt(c2);
    if (y < 0) return NaN;
    const chi = Math.sqrt(y / c2);
    return (chi * chi * chi * c3 + A * Math.sqrt(y)) / sqrtMu;
  };

  // ψ search window. Direct transfers (nrev 0) span hyperbolic → one rev with TOF monotonically
  // increasing in ψ, so a plain bisection converges. Each multi-rev count N lives in
  // ψ ∈ ((2Nπ)², (2(N+1)π)²) where TOF is U-shaped: a minimum splits it into a low-ψ and a
  // high-ψ branch (two transfers of different energy for the same TOF). We pick the requested
  // branch, then bisect its monotonic half.
  let lo: number;
  let hi: number;
  if (nrev <= 0) {
    lo = -4 * Math.PI * Math.PI;
    hi = 4 * Math.PI * Math.PI;
  } else {
    const inner = (2 * nrev * Math.PI) ** 2;
    const outer = (2 * (nrev + 1) * Math.PI) ** 2;
    const span = outer - inner;
    const a = inner + span * 1e-6; // nudge off the singular endpoints (c2 → 0 there)
    const b = outer - span * 1e-6;
    const T = (p: number): number => {
      const t = tofOf(p);
      return Number.isFinite(t) ? t : Infinity;
    };
    // Ternary search for the TOF minimum (unimodal on the interval).
    let ta = a;
    let tb = b;
    for (let i = 0; i < 100; i++) {
      const m1 = ta + (tb - ta) / 3;
      const m2 = tb - (tb - ta) / 3;
      if (T(m1) < T(m2)) tb = m2;
      else ta = m1;
    }
    const psiMin = (ta + tb) / 2;
    if (!(tof >= T(psiMin))) return null; // requested TOF is faster than the N-rev minimum
    if (branch === "low") {
      lo = a;
      hi = psiMin;
    } else {
      lo = psiMin;
      hi = b;
    }
  }

  // Detect the monotonicity of TOF(ψ) on the window so one bisection serves the direct case and
  // both multi-rev branches. Direct & the high branch increase with ψ; the low branch decreases.
  const tl = tofOf(lo + (hi - lo) * 1e-3);
  const th = tofOf(hi - (hi - lo) * 1e-3);
  const decreasing = Number.isFinite(tl) && Number.isFinite(th) ? tl > th : false;

  let psi = (lo + hi) / 2;
  let y = r1m + r2m;
  let converged = false;

  for (let i = 0; i < 100; i++) {
    const { c2, c3 } = stumpff(psi);
    y = r1m + r2m + (A * (psi * c3 - 1)) / Math.sqrt(c2);
    if (A > 0 && y < 0) {
      // push ψ up until y ≥ 0 (the transfer is too "low")
      lo = psi;
      psi = (lo + hi) / 2;
      continue;
    }
    const chi = Math.sqrt(y / c2);
    const tofPsi = (chi * chi * chi * c3 + A * Math.sqrt(y)) / sqrtMu;
    if (Math.abs(tofPsi - tof) < 1e-5 * Math.max(1, tof)) {
      converged = true;
      break;
    }
    // decreasing: larger ψ ⇒ smaller TOF; increasing: larger ψ ⇒ larger TOF.
    if (decreasing === tofPsi > tof) lo = psi;
    else hi = psi;
    psi = (lo + hi) / 2;
  }
  if (!converged) return null;

  const f = 1 - y / r1m;
  const g = A * Math.sqrt(y / mu);
  const gdot = 1 - y / r2m;
  if (Math.abs(g) < 1e-9) return null;

  return {
    v1: { x: (r2.x - f * r1.x) / g, y: (r2.y - f * r1.y) / g, z: (r2.z - f * r1.z) / g },
    v2: { x: (gdot * r2.x - r1.x) / g, y: (gdot * r2.y - r1.y) / g, z: (gdot * r2.z - r1.z) / g },
  };
}

/** Rendezvous via Lambert: an intercept burn that puts the ship on a transfer arriving at
 *  the target's FUTURE position after `tof` seconds, then a match-velocity burn on arrival.
 *  Two nodes. The first fires after a short LEAD so the ship has time to review + slew (and
 *  the burn point is one the ship will actually reach). Returns null if Lambert fails. */
const INTERCEPT_LEAD = 60; // s — slew/settle margin before the intercept burn
const DEGENERATE_ANGLE = (1.5 * Math.PI) / 180; // rad — single-rev Lambert is ill-conditioned this close to 0/π
const MAX_INTERCEPT_DV = 50_000; // m/s — beyond this the "transfer" is a degenerate near-rectilinear conic, not a plan
export const DEFAULT_INTERCEPT_REVS = 4; // try up to this many full loops — long TOFs want a near-circular (low-rev-energy) arc
const TRANSFER_CLEARANCE = 10_000; // m — the transfer arc must stay this far above the surface (no flying through the planet)
const ARC_SAMPLES = 64; // points along the transfer to check for a sub-surface dip the periapsis test can miss

/** Does the transfer conic departing (r1, v1) stay clear of the body for the whole flight? The
 *  cheapest Lambert arc is often a wildly eccentric ellipse whose periapsis is underground — a
 *  trajectory through the planet. If the conic's periapsis already clears, the whole orbit does;
 *  otherwise we sample the actually-traversed arc (which may or may not reach that low periapsis). */
function transferClears(r1: Vec3, v1: Vec3, body: CentralBody, tBurn: number, tof: number): boolean {
  const safeR = body.radius + TRANSFER_CLEARANCE;
  const el = stateToElements(r1, v1, body, tBurn);
  if (el.e < 1 && el.a * (1 - el.e) >= safeR) return true; // periapsis = min radius of the conic
  for (let k = 0; k <= ARC_SAMPLES; k++) {
    if (mag(propagate(el, body, tBurn + (tof * k) / ARC_SAMPLES).position) < safeR) return false;
  }
  return true;
}

/** Fractions of the time-of-flight at which a guided intercept drops a midcourse-correction
 *  checkpoint. Two trims (mid-coast and late) take a long, error-sensitive transfer from a
 *  hundreds-of-km miss to sub-km — see docs/10 §6. */
const CORRECTION_FRACTIONS = [0.5, 0.8, 0.93];

/** Cheapest Lambert transfer (over rev counts + branches) from r1 to r2 in `tof`, scored by
 *  the Δv to depart from `vNow` and arrive matching `vArr`. No surface-clearance filter — this
 *  is the executor's midcourse-trim workhorse, nudging a transfer the ship is already flying. */
export function bestTransfer(
  r1: Vec3,
  r2: Vec3,
  tof: number,
  mu: number,
  vNow: Vec3,
  vArr: Vec3,
  maxRevs = DEFAULT_INTERCEPT_REVS,
): { v1: Vec3; v2: Vec3 } | null {
  let best: { v1: Vec3; v2: Vec3 } | null = null;
  let bestDv = Infinity;
  const consider = (sol: { v1: Vec3; v2: Vec3 } | null) => {
    if (!sol) return;
    const dv = mag(sub(sol.v1, vNow)) + mag(sub(vArr, sol.v2));
    if (Number.isFinite(dv) && dv < bestDv) {
      bestDv = dv;
      best = sol;
    }
  };
  consider(lambert(r1, r2, tof, mu, true, 0));
  for (let n = 1; n <= Math.max(0, Math.floor(maxRevs)); n++) {
    consider(lambert(r1, r2, tof, mu, true, n, "low"));
    consider(lambert(r1, r2, tof, mu, true, n, "high"));
  }
  return best;
}

export function solveIntercept(
  shipEl: OrbitalElements,
  body: CentralBody,
  tNow: number,
  targetEl: OrbitalElements,
  tof: number,
  maxRevs = DEFAULT_INTERCEPT_REVS,
  guided = false,
): ManeuverInput[] | null {
  const tBurn = tNow + INTERCEPT_LEAD;
  const tArrive = tBurn + tof;
  const s1 = propagate(shipEl, body, tBurn); // ship state at the burn point it will reach
  const s2 = propagate(targetEl, body, tArrive); // where the target will be on arrival

  // Transfer angle between departure and arrival radii. Within ~1.5° of 0 or π the single-rev
  // Lambert is degenerate (no well-defined transfer plane) and returns an absurd, near-
  // rectilinear conic — so there we skip the direct branch and lean on the multi-rev ones.
  const cosTheta = clampN(dot3(s1.position, s2.position) / (mag(s1.position) * mag(s2.position)), -1, 1);
  const theta = Math.acos(cosTheta);
  const degenerate = theta < DEGENERATE_ANGLE || Math.PI - theta < DEGENERATE_ANGLE;

  // Enumerate candidate transfers and keep the cheapest physical one. The direct short way is
  // the usual winner for well-phased targets; the multi-rev branches rescue long times of
  // flight, where a direct transfer would fling out on a wild, ruinously expensive ellipse.
  const candidates: { sol: { v1: Vec3; v2: Vec3 }; dv: number }[] = [];
  const consider = (sol: { v1: Vec3; v2: Vec3 } | null) => {
    if (!sol) return;
    const dv = mag(sub(sol.v1, s1.velocity)) + mag(sub(s2.velocity, sol.v2));
    if (!Number.isFinite(dv)) return;
    if (!transferClears(s1.position, sol.v1, body, tBurn, tof)) return; // no flying through the planet
    candidates.push({ sol, dv });
  };

  if (!degenerate) consider(lambert(s1.position, s2.position, tof, body.mu, true, 0));
  for (let n = 1; n <= Math.max(0, Math.floor(maxRevs)); n++) {
    consider(lambert(s1.position, s2.position, tof, body.mu, true, n, "low"));
    consider(lambert(s1.position, s2.position, tof, body.mu, true, n, "high"));
  }
  if (candidates.length === 0) return null;
  const best = candidates.reduce((a, b) => (b.dv < a.dv ? b : a));
  if (best.dv > MAX_INTERCEPT_DV) return null; // even the cheapest transfer is non-physical

  const dvIntercept = sub(best.sol.v1, s1.velocity); // current velocity → transfer departure
  const dvMatch = sub(s2.velocity, best.sol.v2); // transfer arrival → target's velocity
  const departure: ManeuverInput = { time: tBurn, dvLocal: worldDvToLocal(dvIntercept, s1.position, s1.velocity) };
  const match: ManeuverInput = {
    time: tArrive,
    dvLocal: worldDvToLocal(dvMatch, s2.position, best.sol.v2),
    ...(guided ? { retarget: { kind: "match", targetEl } } : {}),
  };
  if (!guided) return [departure, match];

  // Closed-loop guidance: midcourse trims, recomputed in flight from the ship's actual state,
  // cancel the open-loop error a long/sensitive transfer accumulates — which otherwise forces
  // the operator to re-intercept several times (each a full transfer). The trims are nominally
  // zero (the planned transfer is exact), so they cost nothing here and resolve live (docs/10 §6).
  const corrections: ManeuverInput[] = CORRECTION_FRACTIONS.map((f) => ({
    time: tBurn + f * tof,
    dvLocal: { prograde: 0, normal: 0, radial: 0 },
    retarget: { kind: "transfer", targetEl, arrivalTime: tArrive, maxRevs },
  }));
  return [departure, ...corrections, match];
}

/** Scan times of flight for the cheapest intercept of `targetEl` from the ship's current
 *  state — the sensible default TOF for a target (its phasing differs from every other's, so
 *  one fixed TOF can't serve them all). Returns the best {tofSeconds, dvMag}, or null if no
 *  transfer solves anywhere in the window. */
const SUGGEST_TOF_MIN = 30 * 60; // s
const SUGGEST_TOF_MAX = 360 * 60; // s — wide enough to catch the cheap phasing window of a poorly-phased target
const SUGGEST_TOF_STEP = 2 * 60; // s — fine enough not to step over the narrow low-Δv valleys

export function suggestInterceptTof(
  shipEl: OrbitalElements,
  body: CentralBody,
  tNow: number,
  targetEl: OrbitalElements,
  maxRevs = DEFAULT_INTERCEPT_REVS,
): { tofSeconds: number; dvMag: number } | null {
  let best: { tofSeconds: number; dvMag: number } | null = null;
  for (let tof = SUGGEST_TOF_MIN; tof <= SUGGEST_TOF_MAX; tof += SUGGEST_TOF_STEP) {
    const nodes = solveIntercept(shipEl, body, tNow, targetEl, tof, maxRevs);
    if (!nodes) continue;
    const dv = nodes.reduce((s, n) => s + dvMagnitude(n.dvLocal), 0);
    if (!best || dv < best.dvMag) best = { tofSeconds: tof, dvMag: dv };
  }
  return best;
}

/** Match the target's velocity NOW — kill the relative velocity in one burn. Computed live
 *  from the current states, so it's exact: Δv = v_target − v_ship. The terminal-approach
 *  instrument — after an intercept gets you close, this stops you alongside (then trim the
 *  remaining range with a short intercept; open-loop intercepts converge by iteration). */
export function solveMatchVelocity(
  shipEl: OrbitalElements,
  body: CentralBody,
  tNow: number,
  targetEl: OrbitalElements,
): ManeuverInput {
  const s = propagate(shipEl, body, tNow);
  const tgt = propagate(targetEl, body, tNow);
  const dvWorld = sub(tgt.velocity, s.velocity);
  return { time: tNow, dvLocal: worldDvToLocal(dvWorld, s.position, s.velocity) };
}
