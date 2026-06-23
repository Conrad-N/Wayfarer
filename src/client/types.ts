import type { OrbitState } from "../sim/types";
import type { ManeuverPlan } from "../sim/maneuver";

/** The current central body — getCentralBody (patched conics). Adds the hierarchy + SOI
 *  to the M0 CentralBody fields, since which body you orbit now changes at SOI handoffs. */
export interface CentralBodyView {
  id: string;
  name: string;
  mu: number;
  radius: number;
  rotationPeriod: number | null;
  parentId: string | null;
  parentName: string | null;
  soiRadius: number | null; // null for the root star
}

/** One body in the system map — getSystem. */
export interface SystemBody {
  id: string;
  name: string;
  mu: number;
  radius: number;
  parentId: string | null;
  soiRadius: number | null;
  orbitRadiusM: number | null; // semi-major axis about its parent (null = root)
  rootPosition: [number, number, number]; // heliocentric position [m]
}

/** The whole hierarchy + the ship's root-frame position + the next SOI handoff — getSystem. */
export interface SystemState {
  centralBodyId: string;
  bodies: SystemBody[];
  ship: { bodyId: string; rootPosition: [number, number, number] };
  nextSoi: { time: number; toBodyId: string } | null;
}

// Shared client types. These mirror the API's serialised payloads (world frame, SI)
// and the view/slot contracts. Kept in one place so views, the canvas renderers, and
// the slot system all import from here rather than from each other.

/** A 3-vector / quaternion as the API serialises them (world frame, SI). */
export interface V3 {
  x: number;
  y: number;
  z: number;
}
export interface Quat {
  w: number;
  x: number;
  y: number;
  z: number;
}

/** The orbital-frame markers the nav ball draws, as world-frame unit directions. */
export interface NavFrame {
  prograde: V3;
  retrograde: V3;
  normal: V3;
  antinormal: V3;
  radialIn: V3;
  radialOut: V3;
}

/** Live flight telemetry — the full getFlight payload (docs/10 §8). */
export interface FlightState {
  orientation: Quat;
  angularVel: V3;
  facing: V3;
  throttle: number;
  thrustN: number;
  attitudeMode: string;
  executorOn: boolean;
  warpAutoLimited: boolean;
  pointingErrorDeg: number;
  frame: NavFrame;
  burnTargetDir: V3 | null;
  nodes: { id: string; time: number; dvLocal: { prograde: number; normal: number; radial: number }; dvMag: number }[];
  nextNode: { id: string; time: number; dvMag: number; dvRemaining: number } | null;
}

/** The selected rendezvous target + the relative state the operator flies by. */
export interface TargetState {
  index: number;
  name: string;
  kind: string;
  bodyId: string; // which body it orbits
  sameFrame: boolean; // shares the ship's central body → intercept/match available
  range: number; // m
  relSpeed: number; // m/s
  closingSpeed: number; // m/s (>0 = approaching)
  direction: V3; // world unit vector toward the target
  altitude: number; // target orbit altitude [m]
  period: number; // target orbit period [s]
  orbit: OrbitState; // the target's own orbital state (for the scope)
  canDock: boolean; // inside the docking envelope (close + slow)
  docked: boolean;
}

/** One row of the TARGET selector roster. */
export interface TargetSummary {
  index: number;
  name: string;
  kind: string;
  bodyId: string;
  sameFrame: boolean;
  altitude: number; // m
  period: number; // s
  range: number; // m, from the ship
  selected: boolean;
  docked: boolean;
}

/** One cargo stack as the API serialises it (a fungible lot of identical units). */
export interface CargoItemSummary {
  id: string;
  name: string;
  massKg: number; // per unit
  volumeM3: number; // per unit
  qty: number;
  totalKg: number; // massKg * qty
  totalM3: number; // volumeM3 * qty
}

/** The ship's hold — getCargo. Two limits: mass (kg) and volume (m^3). */
export interface CargoState {
  items: CargoItemSummary[];
  usedKg: number;
  capacityKg: number;
  freeKg: number;
  usedM3: number;
  capacityM3: number;
  freeM3: number;
}

/** The docked target's trading surface — getStation. `docked:false` when adrift; a
 *  target with no hold (a probe) reports docked with hasHold:false + empty inventory. */
export interface StationState {
  docked: boolean;
  index: number | null;
  name: string | null;
  kind: string | null;
  hasHold: boolean;
  inventory: CargoItemSummary[];
}

export interface StateResponse {
  clock: { t: number; rate: number };
  body: CentralBodyView;
  system: SystemState;
  ship: {
    id: string;
    name: string;
    massKg: number;
    dryMassKg: number;
    cargoKg: number;
    propellantKg: number;
    ispSeconds: number;
    dvBudget: number;
  };
  orbit: OrbitState;
  pendingManeuver: ManeuverPlan | null;
  flight: FlightState;
  target: TargetState;
  targets: TargetSummary[];
  cargo: CargoState;
  station: StationState;
}

// --- the view / slot contract ------------------------------------------------
// A display is a self-contained VIEW: it builds its own DOM (no shared ids, so the
// same view can live in two slots at once) and exposes render/destroy. A SLOT is one
// of the fixed panel frames; it can mount any view via its switcher (the "any display
// in any panel" system the operator asked for).

export type PanelColor = "amber" | "cyan" | "violet" | "green" | "rose" | "steel";

export interface ViewInstance {
  /** The content below the panel header — a flex column filling the slot body. */
  root: HTMLElement;
  /** Called every poll tick with the latest world state. */
  render(state: StateResponse): void;
  /** Tear down (remove document-level listeners, etc.) when swapped out. */
  destroy?(): void;
}

export interface ViewDef {
  id: string;
  label: string; // shown in the switcher menu and the panel title
  color: PanelColor;
  create(): ViewInstance;
}
