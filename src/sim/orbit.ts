import type { CentralBody, OrbitalElements, OrbitState, Vec3 } from "./types";
import { TWO_PI } from "./constants";

// Analytic two-body (Kepler) propagation. Closed-form: state at any time is one
// evaluation, no stepping — which is what makes time-warp and the away-game cheap
// later (docs/08, Keystone 3). Patched conics + perturbations layer on top of this
// without changing the API (docs/03).

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

/** Propagate elements to sim-time `t` and return the full telemetry catalog. */
export function propagate(el: OrbitalElements, body: CentralBody, t: number): OrbitState {
  const { a, e, i, raan, argp } = el;
  const mu = body.mu;

  const meanMotion = Math.sqrt(mu / (a * a * a)); // n [rad/s]
  const period = TWO_PI / meanMotion;
  const meanAnomaly = wrapTwoPi(el.meanAnomalyAtEpoch + meanMotion * (t - el.epoch));

  const E = solveKepler(meanAnomaly, e);
  const trueAnomaly = wrapTwoPi(
    2 *
      Math.atan2(
        Math.sqrt(1 + e) * Math.sin(E / 2),
        Math.sqrt(1 - e) * Math.cos(E / 2),
      ),
  );

  const radius = a * (1 - e * Math.cos(E));
  const speed = Math.sqrt(mu * (2 / radius - 1 / a)); // vis-viva
  const h = Math.sqrt(mu * a * (1 - e * e)); // specific angular momentum

  const periapsisRadius = a * (1 - e);
  const apoapsisRadius = a * (1 + e);

  // Perifocal position/velocity, then rotate to PCI.
  const cosNu = Math.cos(trueAnomaly);
  const sinNu = Math.sin(trueAnomaly);
  const rPf: Vec3 = { x: radius * cosNu, y: radius * sinNu, z: 0 };
  const vPf: Vec3 = { x: (mu / h) * -sinNu, y: (mu / h) * (e + cosNu), z: 0 };
  const Q = perifocalToInertial(raan, i, argp);
  const position = apply(Q, rPf);
  const velocity = apply(Q, vPf);

  const timeToApoapsis = wrapTwoPi(Math.PI - meanAnomaly) / meanMotion;

  return {
    a,
    e,
    i,
    raan,
    argp,
    trueAnomaly,
    eccentricAnomaly: wrapTwoPi(E),
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
    timeSincePeriapsis: meanAnomaly / meanMotion,
    timeToPeriapsis: (TWO_PI - meanAnomaly) / meanMotion,
    timeToApoapsis,
    latitude: Math.asin(clamp(position.z / radius, -1, 1)),
    position,
    velocity,
  };
}
