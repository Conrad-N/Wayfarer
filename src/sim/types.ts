// Shared sim types. SI units throughout (meters, seconds, radians, kg) — see
// docs/07-milestone-0-spec.md §1. Unit-friendliness is a presentation concern,
// handled at the client edge, never here.

/** Classical orbital elements at an epoch — the source of truth for an orbit. */
export interface OrbitalElements {
  a: number; // semi-major axis [m]
  e: number; // eccentricity [-]  (0 <= e < 1 for closed orbits)
  i: number; // inclination [rad]
  raan: number; // right ascension of ascending node, Omega [rad]
  argp: number; // argument of periapsis, omega [rad]
  meanAnomalyAtEpoch: number; // M0 [rad]
  epoch: number; // t0 [s, sim-time]
}

export interface CentralBody {
  name: string;
  mu: number; // standard gravitational parameter G*M [m^3/s^2]
  radius: number; // mean radius [m]
  rotationPeriod: number | null; // [s], or null if non-rotating (M0)
}

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

/** The full derived telemetry catalog (docs/07 §4), all SI. */
export interface OrbitState {
  // stored elements (echoed for convenience)
  a: number;
  e: number;
  i: number;
  raan: number;
  argp: number;
  // anomalies
  trueAnomaly: number;
  eccentricAnomaly: number;
  meanAnomaly: number;
  // derived scalars
  period: number;
  meanMotion: number;
  periapsisRadius: number;
  apoapsisRadius: number;
  periapsisAltitude: number;
  apoapsisAltitude: number;
  radius: number;
  altitude: number;
  speed: number;
  specificEnergy: number;
  specificAngularMomentum: number;
  flightPathAngle: number;
  timeSincePeriapsis: number;
  timeToPeriapsis: number;
  timeToApoapsis: number;
  latitude: number;
  // Cartesian state in the planet-centered inertial (PCI) frame
  position: Vec3;
  velocity: Vec3;
}
