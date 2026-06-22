import type { CentralBody, OrbitalElements } from "./types";

export const TWO_PI = Math.PI * 2;

/** Degrees → radians, for writing orbital angles readably at call sites. */
export function deg(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

// Earth-like default body (docs/07 §2). Values chosen so the readout can be
// checked against reality: a 400 km circular orbit reads ~92.4 min, ~7.67 km/s.
export const CRADLE: CentralBody = {
  name: "Cradle",
  mu: 3.986004418e14, // m^3/s^2
  radius: 6.371e6, // m
  rotationPeriod: null, // non-rotating in M0
};

/** A circular parking orbit at `altitude` meters, inclined `inclination` radians
 *  from the equator (default equatorial), epoch at t=0. Starts at the ascending
 *  node (M0 = 0), so the sub-ship latitude sweeps 0 → +i → 0 → −i over one period. */
export function circularOrbit(
  body: CentralBody,
  altitude: number,
  inclination = 0,
): OrbitalElements {
  return {
    a: body.radius + altitude,
    e: 0,
    i: inclination,
    raan: 0,
    argp: 0,
    meanAnomalyAtEpoch: 0,
    epoch: 0,
  };
}
