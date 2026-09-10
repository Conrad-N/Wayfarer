import type { CentralBody, OrbitalElements, Vec3 } from "./types";

// Flight physics (docs/10). Pure and deterministic like the rest of src/sim — fixed
// `dt` in, new state out, no wall-clock. Two pieces:
//   • rigid-body ATTITUDE — the ship turns under reaction-wheel torque (Euler's
//     equations + quaternion kinematics), driven by a point-at controller.
//   • powered TRANSLATION — RK4 integration of (r,v,m) under gravity + thrust while
//     the engine is lit. (Coasting stays analytic; that lives in world.ts/orbit.ts.)

export const G0 = 9.80665; // standard gravity [m/s^2]

// --- vec3 helpers (local; orbit.ts keeps its own inline) --------------------
const add = (a: Vec3, b: Vec3): Vec3 => ({ x: a.x + b.x, y: a.y + b.y, z: a.z + b.z });
const sub = (a: Vec3, b: Vec3): Vec3 => ({ x: a.x - b.x, y: a.y - b.y, z: a.z - b.z });
const scale = (a: Vec3, s: number): Vec3 => ({ x: a.x * s, y: a.y * s, z: a.z * s });
const dot = (a: Vec3, b: Vec3): number => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a: Vec3, b: Vec3): Vec3 => ({
  x: a.y * b.z - a.z * b.y,
  y: a.z * b.x - a.x * b.z,
  z: a.x * b.y - a.y * b.x,
});
const len = (a: Vec3): number => Math.hypot(a.x, a.y, a.z);
const norm = (a: Vec3): Vec3 => {
  const l = len(a);
  return l > 0 ? scale(a, 1 / l) : { x: 0, y: 0, z: 0 };
};
const clampMag = (a: Vec3, max: number): Vec3 => {
  const l = len(a);
  return l > max ? scale(a, max / l) : a;
};
const clamp = (x: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, x));

/** Clamp a vector's magnitude to `max` (exported for body-frame torque limits). */
export const clampMagnitude = (a: Vec3, max: number): Vec3 => clampMag(a, max);

// --- quaternions (w, x, y, z); body→world, unit ------------------------------

export interface Quat {
  w: number;
  x: number;
  y: number;
  z: number;
}

export const IDENTITY_Q: Quat = { w: 1, x: 0, y: 0, z: 0 };

/** The ship's thrust axis in body coordinates: it points along +X (nose). */
export const BODY_THRUST_AXIS: Vec3 = { x: 1, y: 0, z: 0 };

function qMul(a: Quat, b: Quat): Quat {
  return {
    w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  };
}

function qNormalize(q: Quat): Quat {
  const l = Math.hypot(q.w, q.x, q.y, q.z) || 1;
  return { w: q.w / l, x: q.x / l, y: q.y / l, z: q.z / l };
}

const qConj = (q: Quat): Quat => ({ w: q.w, x: -q.x, y: -q.y, z: -q.z });

/** Rotate a vector by a unit quaternion: v' = v + 2·q_xyz × (q_xyz × v + w·v). */
export function rotate(q: Quat, v: Vec3): Vec3 {
  const u: Vec3 = { x: q.x, y: q.y, z: q.z };
  const t = scale(cross(u, v), 2);
  return add(add(v, scale(t, q.w)), cross(u, t));
}

/** The ship's thrust direction in world (PCI) coordinates. */
export const thrustAxisWorld = (q: Quat): Vec3 => rotate(q, BODY_THRUST_AXIS);

// --- rigid-body attitude integration ----------------------------------------

export interface Inertia {
  ix: number; // about +X (roll / thrust axis)
  iy: number; // transverse
  iz: number; // transverse
}

/** One fixed step of rigid-body rotation: Euler's equations for ω (body frame),
 *  then quaternion kinematics for orientation. Semi-implicit (uses the updated ω
 *  for the orientation step) for stability. `torque` is body-frame [N·m]. */
export function integrateAttitude(
  q: Quat,
  omega: Vec3,
  I: Inertia,
  torque: Vec3,
  dt: number,
): { q: Quat; omega: Vec3 } {
  // I·ω̇ = τ − ω × (I·ω)   (diagonal inertia)
  const Iw: Vec3 = { x: I.ix * omega.x, y: I.iy * omega.y, z: I.iz * omega.z };
  const gyro = cross(omega, Iw);
  const wdot: Vec3 = {
    x: (torque.x - gyro.x) / I.ix,
    y: (torque.y - gyro.y) / I.iy,
    z: (torque.z - gyro.z) / I.iz,
  };
  const omegaNew = add(omega, scale(wdot, dt));

  // q̇ = ½ q ⊗ (0, ω_body)
  const spin = qMul(q, { w: 0, x: omegaNew.x, y: omegaNew.y, z: omegaNew.z });
  const qNew = qNormalize({
    w: q.w + 0.5 * spin.w * dt,
    x: q.x + 0.5 * spin.x * dt,
    y: q.y + 0.5 * spin.y * dt,
    z: q.z + 0.5 * spin.z * dt,
  });
  return { q: qNew, omega: omegaNew };
}

function anyPerpendicular(v: Vec3): Vec3 {
  const a: Vec3 = Math.abs(v.x) < 0.9 ? { x: 1, y: 0, z: 0 } : { x: 0, y: 1, z: 0 };
  return norm(cross(v, a));
}

/** Reaction-wheel point-at controller: body-frame torque (clamped to τ_max) that
 *  slews the thrust axis toward `targetDirWorld` and damps rotation. A phase-plane
 *  (√) speed profile gives a near time-optimal slew that brakes into the target
 *  without big overshoot; an unreachable 180° flip is kicked off about a transverse
 *  axis. `target === null` (manual) yields zero torque. */
export function controlTorqueBody(
  q: Quat,
  omega: Vec3,
  targetDirWorld: Vec3 | null,
  I: Inertia,
  maxTorque: number,
  rateCap: number,
): Vec3 {
  if (!targetDirWorld) return { x: 0, y: 0, z: 0 };

  const axisW = thrustAxisWorld(q);
  const target = norm(targetDirWorld);
  const angle = Math.acos(clamp(dot(axisW, target), -1, 1)); // 0..π
  const e = cross(axisW, target);
  const eLen = len(e);
  const errAxisW = eLen > 1e-9 ? scale(e, 1 / eLen) : angle > 1e-6 ? anyPerpendicular(axisW) : { x: 0, y: 0, z: 0 };

  const alphaMax = maxTorque / I.iy; // transverse angular accel limit
  const omegaMag = Math.min(rateCap, Math.sqrt(2 * alphaMax * angle * 0.85)); // brake a touch early
  const omegaCmdW = scale(errAxisW, omegaMag);

  const omegaW = rotate(q, omega); // body ω → world
  const KGAIN = 4; // velocity-loop gain [1/s]; saturates torque while the error is large
  const torqueW = clampMag(scale(sub(omegaCmdW, omegaW), I.iy * KGAIN), maxTorque);
  return rotate(qConj(q), torqueW); // world → body
}

export type AttitudeMode =
  | "prograde"
  | "retrograde"
  | "normal"
  | "antinormal"
  | "radialIn"
  | "radialOut"
  | "target" // point at the selected target (relative position; resolved in world.ts)
  | "antiTarget" // point directly away from the selected target
  | "node" // point at the active maneuver node's burn vector (set by the executor)
  | "kill"
  | "manual";

/** The orthonormal orbital frame at (r, v): prograde = v̂, normal = ĥ = (r×v)̂, and
 *  radial-out = prograde × normal — a right-handed orthonormal set (radial-out equals r̂
 *  for a circular orbit and tilts by the flight-path angle when eccentric). Because the
 *  three axes are mutually perpendicular, any Δv decomposes UNIQUELY into
 *  (prograde, normal, radial) — this is the basis the maneuver planner edits and the nav
 *  ball draws, so "burn radial" and "point radial" always agree. */
export interface OrbitalFrame {
  prograde: Vec3;
  normal: Vec3;
  radialOut: Vec3;
}

export function orbitalFrame(r: Vec3, v: Vec3): OrbitalFrame {
  const prograde = norm(v);
  const normal = norm(cross(r, v));
  const radialOut = norm(cross(prograde, normal)); // v̂ × ĥ — outward, ⊥ to both
  return { prograde, normal, radialOut };
}

/** Unit world direction for a directional hold mode, from the orbital frame at the
 *  ship's current state. (kill/manual are handled by the caller.) */
export function headingDir(mode: AttitudeMode, r: Vec3, v: Vec3): Vec3 {
  const f = orbitalFrame(r, v);
  switch (mode) {
    case "prograde": return f.prograde;
    case "retrograde": return scale(f.prograde, -1);
    case "normal": return f.normal;
    case "antinormal": return scale(f.normal, -1);
    case "radialOut": return f.radialOut;
    case "radialIn": return scale(f.radialOut, -1);
    default: return f.prograde;
  }
}

// --- maneuver nodes (docs/10 §6) --------------------------------------------

/** A burn Δv expressed in the orbital frame at the node's position [m/s]. */
export interface LocalDv {
  prograde: number;
  normal: number;
  radial: number;
}

/** Tells the executor to RECOMPUTE a node's Δv from the live state when its burn window opens,
 *  instead of flying the precomputed `dvLocal` — closed-loop guidance for an open-loop transfer.
 *  • `transfer`: re-solve the Lambert leg from where the ship actually is now to where the target
 *    will be at `arrivalTime` — a midcourse trim that cancels accumulated error (and the
 *    departure burn itself). • `match`: null the relative velocity to the target right now.
 *  The target is carried as its orbital elements so the executor stays self-contained and
 *  deterministic (the target coasts on its own Keplerian orbit). */
export type Retarget =
  | { kind: "transfer"; targetEl: OrbitalElements; arrivalTime: number; maxRevs: number }
  | { kind: "match"; targetEl: OrbitalElements };

export interface ManeuverNode {
  id: string;
  time: number; // sim-time the node sits at (the burn is centered here) [s]
  dvLocal: LocalDv; // the burn (or, for a retarget node, the nominal/last-resolved value)
  retarget?: Retarget; // if set, the executor re-solves dvLocal from live state at fire time
}

export const dvMagnitude = (d: LocalDv): number => Math.hypot(d.prograde, d.normal, d.radial);

/** Full world-frame Δv vector [m/s] of a local Δv in the orbital frame at (r, v). */
export function localDvToWorld(d: LocalDv, r: Vec3, v: Vec3): Vec3 {
  const f = orbitalFrame(r, v);
  return add(add(scale(f.prograde, d.prograde), scale(f.normal, d.normal)), scale(f.radialOut, d.radial));
}

/** World-frame unit direction of a local Δv (for pointing the ship at the burn). */
export function nodeWorldDir(d: LocalDv, r: Vec3, v: Vec3): Vec3 {
  return norm(localDvToWorld(d, r, v));
}

/** Decompose a world-frame Δv into orbital-frame components at (r, v) — the inverse of
 *  localDvToWorld. Lets a solver that works in world vectors (e.g. Lambert) emit a node. */
export function worldDvToLocal(dvWorld: Vec3, r: Vec3, v: Vec3): LocalDv {
  const f = orbitalFrame(r, v);
  return { prograde: dot(dvWorld, f.prograde), normal: dot(dvWorld, f.normal), radial: dot(dvWorld, f.radialOut) };
}

// --- powered translation (RK4) ----------------------------------------------

export interface RVMState {
  r: Vec3; // position [m, PCI]
  v: Vec3; // velocity [m/s]
  m: number; // total mass [kg]
}

export interface Engine {
  thrustN: number;
  ispSeconds: number;
}

/** One fixed RK4 step of powered flight: gravity + thrust along `thrustDirWorld`,
 *  with mass dropping by the rocket equation. Thrust direction and mass are held
 *  constant across the (small) step — attitude is stepped separately per substep. */
export function stepPowered(
  s: RVMState,
  body: CentralBody,
  thrustDirWorld: Vec3,
  throttle: number,
  engine: Engine,
  dryMassKg: number,
  dt: number,
): RVMState {
  const mu = body.mu;
  const burning = throttle > 0 && s.m > dryMassKg;
  const thrustAcc = burning ? (engine.thrustN * throttle) / s.m : 0; // magnitude
  const thrust = scale(thrustDirWorld, thrustAcc);

  const accel = (r: Vec3): Vec3 => {
    const rl = len(r);
    return add(scale(r, -mu / (rl * rl * rl)), thrust);
  };

  // classic RK4 on (r, v)
  const k1v = accel(s.r), k1r = s.v;
  const k2v = accel(add(s.r, scale(k1r, dt / 2))), k2r = add(s.v, scale(k1v, dt / 2));
  const k3v = accel(add(s.r, scale(k2r, dt / 2))), k3r = add(s.v, scale(k2v, dt / 2));
  const k4v = accel(add(s.r, scale(k3r, dt))), k4r = add(s.v, scale(k3v, dt));

  const r = add(s.r, scale(add(add(k1r, scale(k2r, 2)), add(scale(k3r, 2), k4r)), dt / 6));
  const v = add(s.v, scale(add(add(k1v, scale(k2v, 2)), add(scale(k3v, 2), k4v)), dt / 6));

  const mdot = burning ? (engine.thrustN * throttle) / (engine.ispSeconds * G0) : 0;
  const m = Math.max(dryMassKg, s.m - mdot * dt);
  return { r, v, m };
}
