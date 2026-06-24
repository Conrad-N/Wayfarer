import type { CentralBody, OrbitalElements, OrbitState, Vec3 } from "./types";
import { TWO_PI } from "./constants";

// Analytic two-body (Kepler) propagation. Closed-form: state at any time is one
// evaluation, no stepping — which is what makes time-warp and skip-resolution cheap
// (the shared event-clock, docs/08 Part B / Keystone 3). Patched conics + perturbations
// layer on top of this without changing the API (docs/03).

type Mat3 = [number, number, number, number, number, number, number, number, number];

function wrapTwoPi(x: number): number {
  const m = x % TWO_PI;
  return m < 0 ? m + TWO_PI : m;
}

function wrapToPi(x: number): number {
  let a = (x + Math.PI) % TWO_PI;
  if (a < 0) a += TWO_PI;
  return a - Math.PI;
}

function clamp(x: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, x));
}

/** Solve Kepler's equation M = E - e*sin(E) for the eccentric anomaly E. */
export function solveKepler(meanAnomaly: number, e: number): number {
  const M = wrapToPi(meanAnomaly); // best convergence near 0
  let E = e < 0.8 ? M : Math.PI * (M < 0 ? -1 : 1);
  for (let k = 0; k < 100; k++) {
    const f = E - e * Math.sin(E) - M;
    const fp = 1 - e * Math.cos(E);
    const dE = f / fp;
    E -= dE;
    if (Math.abs(dE) < 1e-12) break;
  }
  return E;
}

/** Solve the hyperbolic Kepler equation M = e·sinh(H) − H for the hyperbolic anomaly H
 *  (e > 1). Newton from a robust seed; H is unbounded (no wrap) — a hyperbola is flown once. */
export function solveHyperKepler(meanAnomaly: number, e: number): number {
  const M = meanAnomaly;
  // Seed: asinh(M/e) is well-behaved near periapsis; for large |M| a log seed converges faster.
  let H = Math.abs(M) > 6 ? Math.sign(M) * Math.log((2 * Math.abs(M)) / e + 1.8) : Math.asinh(M / e);
  for (let k = 0; k < 100; k++) {
    const f = e * Math.sinh(H) - H - M;
    const fp = e * Math.cosh(H) - 1;
    const dH = f / fp;
    H -= dH;
    if (Math.abs(dH) < 1e-12) break;
  }
  return H;
}

/** Rotation matrix from the perifocal frame to PCI via the 3-1-3 (Z-X-Z) sequence. */
function perifocalToInertial(raan: number, i: number, argp: number): Mat3 {
  const cO = Math.cos(raan);
  const sO = Math.sin(raan);
  const ci = Math.cos(i);
  const si = Math.sin(i);
  const cw = Math.cos(argp);
  const sw = Math.sin(argp);
  return [
    cO * cw - sO * sw * ci, -cO * sw - sO * cw * ci, sO * si,
    sO * cw + cO * sw * ci, -sO * sw + cO * cw * ci, -cO * si,
    sw * si, cw * si, ci,
  ];
}

function apply(m: Mat3, v: Vec3): Vec3 {
  return {
    x: m[0] * v.x + m[1] * v.y + m[2] * v.z,
    y: m[3] * v.x + m[4] * v.y + m[5] * v.z,
    z: m[6] * v.x + m[7] * v.y + m[8] * v.z,
  };
}

/** The next sim-time > `fromT` at which an orbit's radius crosses `soiRadius` OUTBOUND —
 *  i.e. when the ship leaves the current body's sphere of influence (an escape). Analytic:
 *  closed-form from the conic geometry (no stepping). Returns null if the orbit never
 *  reaches the boundary (a bound ellipse with apoapsis inside the SOI). */
export function nextEscapeTime(
  el: OrbitalElements,
  body: CentralBody,
  fromT: number,
  soiRadius: number,
): number | null {
  const { a, e } = el;
  const n = Math.sqrt(body.mu / Math.abs(a) ** 3); // mean motion (|a| handles hyperbola)
  const mNow = el.meanAnomalyAtEpoch + n * (fromT - el.epoch);

  if (e < 1) {
    if (a * (1 + e) <= soiRadius) return null; // apoapsis inside the SOI — never escapes
    // r = a(1 − e·cosE) = soiRadius  →  the outbound crossing is E ∈ (0, π).
    const cosE = (1 - soiRadius / a) / e;
    if (cosE < -1 || cosE > 1) return null;
    const Ecross = Math.acos(clamp(cosE, -1, 1));
    const Mcross = Ecross - e * Math.sin(Ecross); // ∈ (0, π)
    // Next unwrapped mean anomaly ≡ Mcross (mod 2π) strictly after now.
    const k = Math.ceil((mNow - Mcross) / TWO_PI - 1e-9);
    let Mtarget = Mcross + k * TWO_PI;
    if (Mtarget < mNow + 1e-9) Mtarget += TWO_PI;
    return fromT + (Mtarget - mNow) / n;
  }

  // Hyperbola: r = a(1 − e·coshH) = soiRadius (a < 0). Outbound crossing is H > 0.
  const coshH = (1 - soiRadius / a) / e;
  if (coshH < 1) return null;
  const Hcross = Math.acosh(coshH);
  const Mcross = e * Math.sinh(Hcross) - Hcross;
  if (Mcross <= mNow + 1e-9) return null; // already past the outbound crossing
  return fromT + (Mcross - mNow) / n;
}

/** Propagate elements to sim-time `t` and return the full telemetry catalog. Handles both
 *  closed (0 ≤ e < 1) and hyperbolic (e > 1) conics — the latter arises on SOI escape and
 *  on a fast approach into another body (patched conics, docs/08). For a hyperbola, period
 *  and apoapsis are undefined and reported as Infinity (the telemetry formatters dash them). */
export function propagate(el: OrbitalElements, body: CentralBody, t: number): OrbitState {
  const { a, e, i, raan, argp } = el;
  const mu = body.mu;

  // Branch on the conic: the elliptic path is unchanged from M0; the hyperbolic path uses
  // |a|, the hyperbolic anomaly H, and cosh/sinh in place of cos/sin.
  let meanMotion: number;
  let period: number;
  let meanAnomaly: number; // wrapped (elliptic) or raw (hyperbolic — no wrap)
  let eccentricAnomalyOut: number; // E (elliptic) or H (hyperbolic)
  let trueAnomaly: number;
  let radius: number;
  let periapsisRadius: number;
  let apoapsisRadius: number;
  let timeToApoapsis: number;
  let timeSincePeriapsis: number;
  let timeToPeriapsis: number;

  if (e < 1) {
    meanMotion = Math.sqrt(mu / (a * a * a)); // n [rad/s]
    period = TWO_PI / meanMotion;
    meanAnomaly = wrapTwoPi(el.meanAnomalyAtEpoch + meanMotion * (t - el.epoch));

    const E = solveKepler(meanAnomaly, e);
    trueAnomaly = wrapTwoPi(
      2 *
        Math.atan2(
          Math.sqrt(1 + e) * Math.sin(E / 2),
          Math.sqrt(1 - e) * Math.cos(E / 2),
        ),
    );
    eccentricAnomalyOut = wrapTwoPi(E);
    radius = a * (1 - e * Math.cos(E));
    periapsisRadius = a * (1 - e);
    apoapsisRadius = a * (1 + e);
    timeToApoapsis = wrapTwoPi(Math.PI - meanAnomaly) / meanMotion;
    timeSincePeriapsis = meanAnomaly / meanMotion;
    timeToPeriapsis = wrapTwoPi(TWO_PI - meanAnomaly) / meanMotion;
  } else {
    const absA = -a; // a < 0 for a hyperbola
    meanMotion = Math.sqrt(mu / (absA * absA * absA));
    period = Infinity; // open orbit — no period
    meanAnomaly = el.meanAnomalyAtEpoch + meanMotion * (t - el.epoch); // no wrap

    const H = solveHyperKepler(meanAnomaly, e);
    trueAnomaly = wrapTwoPi(
      2 *
        Math.atan2(
          Math.sqrt(e + 1) * Math.sinh(H / 2),
          Math.sqrt(e - 1) * Math.cosh(H / 2),
        ),
    );
    eccentricAnomalyOut = H;
    radius = a * (1 - e * Math.cosh(H)); // = absA·(e·coshH − 1) ≥ periapsis
    periapsisRadius = a * (1 - e); // = absA·(e − 1) > 0
    apoapsisRadius = Infinity; // unbounded
    timeToApoapsis = Infinity;
    timeSincePeriapsis = meanAnomaly / meanMotion; // signed: <0 before periapsis
    timeToPeriapsis = meanAnomaly <= 0 ? -meanAnomaly / meanMotion : Infinity; // periapsis flown once
  }

  const speed = Math.sqrt(mu * (2 / radius - 1 / a)); // vis-viva (a<0 ⇒ +energy for hyperbola)
  const h = Math.sqrt(mu * a * (1 - e * e)); // specific angular momentum (a<0 & e>1 ⇒ +)

  // Perifocal position/velocity, then rotate to PCI.
  const cosNu = Math.cos(trueAnomaly);
  const sinNu = Math.sin(trueAnomaly);
  const rPf: Vec3 = { x: radius * cosNu, y: radius * sinNu, z: 0 };
  const vPf: Vec3 = { x: (mu / h) * -sinNu, y: (mu / h) * (e + cosNu), z: 0 };
  const Q = perifocalToInertial(raan, i, argp);
  const position = apply(Q, rPf);
  const velocity = apply(Q, vPf);

  return {
    a,
    e,
    i,
    raan,
    argp,
    trueAnomaly,
    eccentricAnomaly: eccentricAnomalyOut,
    meanAnomaly,
    period,
    meanMotion,
    periapsisRadius,
    apoapsisRadius,
    periapsisAltitude: periapsisRadius - body.radius,
    apoapsisAltitude: apoapsisRadius - body.radius,
    radius,
    altitude: radius - body.radius,
    speed,
    specificEnergy: -mu / (2 * a),
    specificAngularMomentum: h,
    flightPathAngle: Math.atan2(e * sinNu, 1 + e * cosNu),
    timeSincePeriapsis,
    timeToPeriapsis,
    timeToApoapsis,
    latitude: Math.asin(clamp(position.z / radius, -1, 1)),
    position,
    velocity,
  };
}
