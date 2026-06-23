import type { CentralBody, OrbitalElements, OrbitState, Vec3 } from "./types";
import { TWO_PI } from "./constants";
import { propagate } from "./orbit";
import { type LocalDv, type Retarget, dvMagnitude, localDvToWorld } from "./flight";

// The maneuver layer, rebuilt around the maneuver NODE (docs/10 §6). The planner is now
// a deterministic FORWARD instrument: you choose a burn — when it fires and its Δv in the
// three orthonormal orbital-frame axes (prograde / normal / radial) — and it reports the
// cost and the resulting orbit. There is no target-seeking solver and no hidden judgment:
// the operator (human or AI) decides WHAT to burn; the tool only does the physics. Two
// intelligences, shared instruments (docs/01; Keystone 2 — the AI commands, never solves).
//
// Pure and deterministic like the rest of src/sim: no World, no Date.now, identical output
// for identical inputs. api.ts orchestrates these against the live World and owns the
// confirmation gate; these functions only do math.
//
// M0 propagates elements → state; we need the inverse (state → elements, RV2COE) so a burn
// — which changes the velocity vector at a point — folds back into a new set of elements.

const G0 = 9.80665; // standard gravity [m/s^2], for the rocket equation

function clamp(x: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, x));
}

function wrapTwoPi(x: number): number {
  const m = x % TWO_PI;
  return m < 0 ? m + TWO_PI : m;
}

/** Classical elements from a PCI state vector (the inverse of `propagate`'s
 *  element→state step). Standard RV→COE; degenerate cases (e→0 circular, i→0
 *  equatorial) fall back to the conventional substitute angle so this never NaNs. */
export function stateToElements(
  position: Vec3,
  velocity: Vec3,
  body: CentralBody,
  epoch: number,
): OrbitalElements {
  const mu = body.mu;
  const { x: rx, y: ry, z: rz } = position;
  const { x: vx, y: vy, z: vz } = velocity;
  const rMag = Math.hypot(rx, ry, rz);
  const vMag = Math.hypot(vx, vy, vz);

  // specific angular momentum  h = r × v
  const hx = ry * vz - rz * vy;
  const hy = rz * vx - rx * vz;
  const hz = rx * vy - ry * vx;
  const hMag = Math.hypot(hx, hy, hz);

  // node vector  n = ẑ × h = (−h_y, h_x, 0)
  const nx = -hy;
  const ny = hx;
  const nMag = Math.hypot(nx, ny, 0);

  // eccentricity vector  e = ((v² − μ/r)·r − (r·v)·v) / μ
  const rDotV = rx * vx + ry * vy + rz * vz;
  const c = vMag * vMag - mu / rMag;
  const ex = (c * rx - rDotV * vx) / mu;
  const ey = (c * ry - rDotV * vy) / mu;
  const ez = (c * rz - rDotV * vz) / mu;
  const e = Math.hypot(ex, ey, ez);

  // semi-major axis from specific energy (closed orbits, e < 1)
  const energy = (vMag * vMag) / 2 - mu / rMag;
  const a = -mu / (2 * energy);

  const i = Math.acos(clamp(hz / hMag, -1, 1));

  let raan = 0;
  if (nMag > 1e-9) {
    raan = Math.acos(clamp(nx / nMag, -1, 1));
    if (ny < 0) raan = TWO_PI - raan;
  }

  let argp = 0;
  let nu: number;
  if (e > 1e-9) {
    // argument of periapsis: angle from node to eccentricity vector
    if (nMag > 1e-9) {
      argp = Math.acos(clamp((nx * ex + ny * ey) / (nMag * e), -1, 1));
      if (ez < 0) argp = TWO_PI - argp;
    } else {
      // equatorial: measure periapsis longitude from +x
      argp = Math.acos(clamp(ex / e, -1, 1));
      if (ey < 0) argp = TWO_PI - argp;
    }
    // true anomaly: angle from periapsis to the ship
    nu = Math.acos(clamp((ex * rx + ey * ry + ez * rz) / (e * rMag), -1, 1));
    if (rDotV < 0) nu = TWO_PI - nu;
  } else if (nMag > 1e-9) {
    // circular inclined: use the argument of latitude (node → ship) as ν with argp=0
    nu = Math.acos(clamp((nx * rx + ny * ry) / (nMag * rMag), -1, 1));
    if (rz < 0) nu = TWO_PI - nu;
  } else {
    // circular equatorial: true longitude
    nu = Math.acos(clamp(rx / rMag, -1, 1));
    if (ry < 0) nu = TWO_PI - nu;
  }

  // ν → (eccentric / hyperbolic) anomaly → mean anomaly M, stored at this epoch so that
  // propagate(result, body, epoch) reproduces (position, velocity) exactly. Hyperbolic
  // states (e > 1, from an SOI escape or a fast approach) use the sinh form and don't wrap.
  let meanAnomalyAtEpoch: number;
  if (e < 1) {
    const E = 2 * Math.atan2(Math.sqrt(1 - e) * Math.sin(nu / 2), Math.sqrt(1 + e) * Math.cos(nu / 2));
    meanAnomalyAtEpoch = wrapTwoPi(E - e * Math.sin(E));
  } else {
    const H = 2 * Math.atanh(Math.sqrt((e - 1) / (e + 1)) * Math.tan(nu / 2));
    meanAnomalyAtEpoch = e * Math.sinh(H) - H; // unwrapped — a hyperbola is flown once
  }

  return { a, e, i, raan, argp, meanAnomalyAtEpoch, epoch };
}

// --- Fuel / mass (Tsiolkovsky) ----------------------------------------------

/** Total Δv available from `propellantKg` at exhaust velocity Isp·g0 [m/s]. */
export function dvBudget(propellantKg: number, dryMassKg: number, ispSeconds: number): number {
  return ispSeconds * G0 * Math.log((dryMassKg + propellantKg) / dryMassKg);
}

/** Propellant burned to produce |Δv| starting from total mass `massKg` [kg]. */
export function propellantForDv(massKg: number, dv: number, ispSeconds: number): number {
  return massKg * (1 - Math.exp(-Math.abs(dv) / (ispSeconds * G0)));
}

// --- the maneuver node: the forward primitive -------------------------------

/** Apply an impulsive local-frame Δv at sim-time `t` → resulting elements. The three
 *  components are along the orthonormal orbital frame at the burn point (prograde /
 *  normal / radial-out), so ANY burn is expressible — three numbers cover every
 *  direction. This is the inverse-free heart of the planner: you give it the burn, it
 *  gives you the orbit. */
export function applyBurn(el: OrbitalElements, body: CentralBody, t: number, dv: LocalDv): OrbitalElements {
  const s = propagate(el, body, t);
  const w = localDvToWorld(dv, s.position, s.velocity);
  const vNew: Vec3 = { x: s.velocity.x + w.x, y: s.velocity.y + w.y, z: s.velocity.z + w.z };
  return stateToElements(s.position, vNew, body, t);
}

export interface ShipFuel {
  dryMassKg: number;
  propellantKg: number;
  ispSeconds: number;
}

/** A burn to preview / commit: WHEN it fires and the Δv in the three orbital-frame axes. */
export interface ManeuverInput {
  time: number; // absolute sim-time the burn fires [s]
  dvLocal: LocalDv; // prograde / normal / radial Δv [m/s]
  retarget?: Retarget; // closed-loop guidance: recompute dvLocal from live state at fire time
}

/** The forward preview of one maneuver node — the planner's entire output. Reports the
 *  Δv magnitude, propellant cost, the Δv budget before/after, and the orbit at the burn
 *  (`before`) and immediately after it (`after` = the osculating conic in the current
 *  body's frame). `feasible` is false for a zero burn or one the tanks can't cover, with a
 *  `note` that seeds the operator's next try. (Trajectory through any SOI crossing
 *  downstream of `after` is the propagator's job, not the planner's — docs/10 §8; one body
 *  today, so `after` is the whole future.) */
export interface NodePreview {
  time: number;
  dvLocal: LocalDv;
  dvMag: number;
  propellantKg: number;
  massBeforeKg: number;
  feasible: boolean;
  dvBudgetBefore: number;
  dvBudgetAfter: number;
  before: OrbitState;
  after: OrbitState;
  note?: string;
}

/** Preview a single maneuver node against the ship's current orbit + fuel. With no
 *  earlier burns this slice, the ship's mass at the burn equals its mass now. */
export function previewNode(
  el: OrbitalElements,
  body: CentralBody,
  fuel: ShipFuel,
  input: ManeuverInput,
): NodePreview {
  const { dvLocal, time } = input;
  const dvMag = dvMagnitude(dvLocal);
  const m0 = fuel.dryMassKg + fuel.propellantKg;
  const budgetBefore = dvBudget(fuel.propellantKg, fuel.dryMassKg, fuel.ispSeconds);
  const propellantKg = propellantForDv(m0, dvMag, fuel.ispSeconds);
  const affordable = propellantKg <= fuel.propellantKg + 1e-6;
  const feasible = dvMag > 0 && affordable;
  const before = propagate(el, body, time);
  const after = propagate(applyBurn(el, body, time, dvLocal), body, time);
  const note =
    dvMag === 0
      ? "no Δv — set a prograde, normal or radial component"
      : affordable
        ? undefined
        : `needs ${propellantKg.toFixed(0)} kg but only ${fuel.propellantKg.toFixed(0)} kg aboard ` +
          `(Δv budget ${budgetBefore.toFixed(0)} m/s)`;

  return {
    time,
    dvLocal,
    dvMag,
    propellantKg,
    massBeforeKg: m0,
    feasible,
    dvBudgetBefore: budgetBefore,
    dvBudgetAfter: feasible ? dvBudget(fuel.propellantKg - propellantKg, fuel.dryMassKg, fuel.ispSeconds) : 0,
    before,
    after,
    note,
  };
}

// --- planned maneuvers: one OR more nodes, reviewed and flown as a unit ------
// A simple burn is one node; a transfer or an intercept is two. The hand planner builds a
// one-node plan; every inverse solver (solvers.ts) builds one too. This is the unit the
// confirmation gate reviews and the executor flies — NOT an editable timeline (that's the
// deferred sequence planner), just the atomic output of a single planning action.

export interface PlanBurn {
  time: number;
  dvLocal: LocalDv;
  dvMag: number;
  propellantKg: number;
  live?: boolean; // computed in flight from live state (a midcourse trim / live velocity match)
}

export interface ManeuverPlan {
  label: string; // human tag: "manual burn", "circularize @ apoapsis", "hohmann → 600 km"…
  nodes: ManeuverInput[]; // ordered by time — what the executor lays and flies
  burns: PlanBurn[]; // per-node cost breakdown (mass threaded across burns)
  dvMag: number; // total |Δv| [m/s]
  propellantKg: number; // total propellant [kg]
  feasible: boolean;
  dvBudgetBefore: number;
  dvBudgetAfter: number;
  after: OrbitState; // osculating orbit just after the LAST burn (the coast between is analytic)
  note?: string;
}

/** Forward-preview an ordered list of nodes as one plan: chain the burns through the
 *  analytic coast, threading mass (so burn 2 starts lighter), and report the totals and the
 *  final orbit. Deterministic; no judgment — the solver/operator chose the nodes. */
export function buildPlan(
  el: OrbitalElements,
  body: CentralBody,
  fuel: ShipFuel,
  label: string,
  nodes: ManeuverInput[],
): ManeuverPlan {
  const budgetBefore = dvBudget(fuel.propellantKg, fuel.dryMassKg, fuel.ispSeconds);
  let curEl = el;
  let mass = fuel.dryMassKg + fuel.propellantKg;
  let propLeft = fuel.propellantKg;
  let totalDv = 0;
  let totalProp = 0;
  let affordable = true;
  const burns: PlanBurn[] = [];
  let after = propagate(el, body, nodes.length ? nodes[0].time : 0);

  for (const n of nodes) {
    const dvMag = dvMagnitude(n.dvLocal);
    const propellantKg = propellantForDv(mass, dvMag, fuel.ispSeconds);
    if (propellantKg > propLeft + 1e-6) affordable = false;
    burns.push({ time: n.time, dvLocal: n.dvLocal, dvMag, propellantKg, live: !!n.retarget });
    totalDv += dvMag;
    totalProp += propellantKg;
    curEl = applyBurn(curEl, body, n.time, n.dvLocal); // coast (analytic) + impulse
    after = propagate(curEl, body, n.time);
    mass -= propellantKg;
    propLeft -= propellantKg;
  }

  const feasible = totalDv > 1e-3 && affordable; // ignore sub-mm/s dust (e.g. circularizing a circle)
  const note =
    totalDv <= 1e-3
      ? "no Δv — nothing to do"
      : affordable
        ? undefined
        : `needs ${totalProp.toFixed(0)} kg but only ${fuel.propellantKg.toFixed(0)} kg aboard ` +
          `(Δv budget ${budgetBefore.toFixed(0)} m/s)`;

  return {
    label,
    nodes,
    burns,
    dvMag: totalDv,
    propellantKg: totalProp,
    feasible,
    dvBudgetBefore: budgetBefore,
    dvBudgetAfter: feasible ? dvBudget(propLeft, fuel.dryMassKg, fuel.ispSeconds) : 0,
    after,
    note,
  };
}
