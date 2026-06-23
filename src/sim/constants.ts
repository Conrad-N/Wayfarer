import type { CentralBody, OrbitalElements } from "./types";
import { type Body, System, soiRadius } from "./system";

export const TWO_PI = Math.PI * 2;

/** Degrees → radians, for writing orbital angles readably at call sites. */
export function deg(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

const AU = 1.495978707e11; // m

// The root star — the heliocentric frame everything is measured against (docs/05 §M2).
export const SOL: Body = {
  id: "sol",
  name: "Sol",
  mu: 1.32712440018e20, // m^3/s^2
  radius: 6.957e8, // m
  rotationPeriod: null,
  parentId: null, // root
  elements: null,
  soiRadius: null, // infinite — the outermost frame
};

// Earth-like home planet (docs/07 §2). Its μ and radius are UNCHANGED from M0 so every
// existing acceptance number holds (a 400 km circular orbit still reads ~92.4 min,
// ~7.67 km/s); it now also orbits Sol at ~1 AU, which only matters once you leave its SOI.
export const CRADLE: Body = {
  id: "cradle",
  name: "Cradle",
  mu: 3.986004418e14, // m^3/s^2
  radius: 6.371e6, // m
  rotationPeriod: null, // non-rotating
  parentId: "sol",
  elements: { a: AU, e: 0, i: 0, raan: 0, argp: 0, meanAnomalyAtEpoch: 0, epoch: 0 },
  soiRadius: soiRadius(AU, 3.986004418e14, 1.32712440018e20), // ≈ 9.2e8 m
};

// A second planet — Mars-like, slightly inside Cradle's orbit and phased ahead, so a
// heliocentric Lambert transfer to it is well-posed (coplanar, modest Δv). The interplanetary
// destination for the patched-conic slice.
const VESPER_A = 0.8 * AU;
export const VESPER: Body = {
  id: "vesper",
  name: "Vesper",
  mu: 4.282837e13, // m^3/s^2
  radius: 3.3895e6, // m
  rotationPeriod: null,
  parentId: "sol",
  elements: { a: VESPER_A, e: 0, i: 0, raan: 0, argp: 0, meanAnomalyAtEpoch: deg(40), epoch: 0 },
  soiRadius: soiRadius(VESPER_A, 4.282837e13, 1.32712440018e20), // ≈ 3.0e8 m
};

/** The default solar system: Sol with Cradle and Vesper orbiting it. The ship starts in
 *  low orbit around Cradle. Built fresh (a function, not a const) to avoid any module
 *  load-order coupling with `orbit.ts`. */
export function defaultSystem(): System {
  return new System([SOL, CRADLE, VESPER]);
}

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
