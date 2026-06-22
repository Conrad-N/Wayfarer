import type { CentralBody, OrbitalElements, OrbitState, Vec3 } from "./types";
import type { ManeuverPlan } from "./maneuver";
import { stateToElements, dvBudget as dvBudgetOf } from "./maneuver";
import {
  type Quat,
  type Inertia,
  type AttitudeMode,
  type RVMState,
  type ManeuverNode,
  IDENTITY_Q,
  integrateAttitude,
  controlTorqueBody,
  clampMagnitude,
  headingDir,
  thrustAxisWorld,
  stepPowered,
  dvMagnitude,
  nodeWorldDir,
  worldDvToLocal,
} from "./flight";
import { CRADLE, circularOrbit, deg } from "./constants";
import { propagate } from "./orbit";
import { bestTransfer } from "./solvers";

// Fixed integration substep for powered flight & rotation (docs/10 §3). Determinism
// comes from this being constant regardless of warp/frame pacing. The cap bounds
// per-tick work: under heavy warp a burn does a "lazy catch-up" across ticks.
const DT_PHYS = 1 / 64; // s
const MAX_SUBSTEPS = 4096; // per advance() call

// A rendezvous target: another object orbiting the same body (docs/05 §M2 — but single-
// body, so no patched conics). MVP keeps them co-planar + circular so the solvers are
// well-posed. `kind` is flavour for the target panel.
// A stack of fungible cargo: a name, a per-unit mass, and how many units. `id` is stable
// so transfers can merge a stack into a matching one on the other side. Cargo is INERT
// mass (not propellant): it rides in the structural mass, so loading it shrinks the Δv
// budget and unloading it grows it — the whole point of the docked transfer (docs/03 §M1).
export interface CargoItem {
  id: string;
  name: string;
  massKg: number; // per unit
  volumeM3: number; // per unit — what it takes up in the hold (a separate limit from mass)
  qty: number;
}

export interface TargetDef {
  name: string;
  kind: "station" | "depot" | "probe";
  elements: OrbitalElements;
  // What this target will trade across the dock. Stations/depots stock goods; a probe
  // has none (docking it offers no cargo services). Absent = no hold to transfer with.
  inventory?: CargoItem[];
}

export interface ShipDef {
  id: string;
  name: string;
  // Mass is split for the rocket equation (M1): total = dry + propellant. A burn
  // spends propellant, so total mass drops and the Δv budget shrinks with it.
  dryMassKg: number;
  propellantKg: number;
  ispSeconds: number; // specific impulse [s]
  thrustN: number; // engine thrust at full throttle [N] (finite burns, docs/10)
  inertia: Inertia; // principal moments of inertia [kg·m^2]
  maxTorqueNm: number; // reaction-wheel control authority per axis [N·m]
  elements: OrbitalElements; // the coast conic (valid while the engine is off)
  cargoCapacityKg: number; // most cargo mass the hold can carry [kg]
  cargoCapacityM3: number; // most cargo volume the hold can carry [m^3] — the other limit
  cargo: CargoItem[]; // what's currently in the hold (rides in the structural mass)
}

// The authoritative simulation (docs/03 — server-authoritative from M0). Truth is
// the ship's state + attitude; while coasting it's equivalently the orbital elements
// (propagated analytically), and while thrusting it's the integrated state vector
// (docs/10 — the hybrid). Clients never compute truth; they read telemetry.
export class World {
  body: CentralBody;
  ship: ShipDef;
  time: number; // sim-time [s]
  rate: number; // time multiplier (warp; full design in docs/08)

  // Attitude (rigid body, docs/10 §4): orientation + body-frame angular velocity.
  orientation: Quat;
  angularVel: Vec3; // body frame [rad/s]
  attitudeMode: AttitudeMode;
  manualTorque: Vec3; // body-frame command used in "manual" mode [N·m]
  rateCap: number; // max slew rate [rad/s]
  throttle: number; // commanded [0,1]

  // While the engine is lit, the integrated state vector is the truth; null when
  // coasting (the elements are). The hybrid switches between the two seamlessly.
  poweredState: RVMState | null;
  private physAccum = 0; // un-integrated sim-time carried between ticks (fixed DT_PHYS grid)
  private inBurnWindow = false; // executor is in a node's burn window → step on the fixed grid

  // Maneuver nodes + the node-executor autopilot (docs/10 §6).
  nodes: ManeuverNode[];
  executorOn: boolean;
  burnTargetDir: Vec3 | null; // world dir the executor is pointing/burning along
  burnDelivered: number; // Δv applied so far in the current node's burn [m/s]
  warpAutoLimited: boolean; // executor forced warp down for a burn (telemetry)

  pendingManeuver: ManeuverPlan | null;

  // Rendezvous targets: a few co-planar objects to choose between (the TARGET panel's
  // selector). `selectedTarget` indexes the active one — what the telemetry, the solvers
  // and the dock affordance all follow. `dockedTo` is the index we're latched to (MVP
  // stub — no mechanics yet), or null.
  targets: TargetDef[];
  selectedTarget: number;
  dockedTo: number | null;

  constructor() {
    this.body = CRADLE;
    this.ship = {
      id: "SHIP-01",
      name: "Wayfarer",
      dryMassKg: 8000,
      propellantKg: 4000, // ~1.27 km/s of Δv at Isp 320 s
      ispSeconds: 320,
      thrustN: 50_000, // ~26 s for a 109 m/s burn at 12 t (docs/10 §11)
      inertia: { ix: 14_000, iy: 107_000, iz: 107_000 }, // ≈10 m × 3 m, 12 t cylinder
      maxTorqueNm: 5_500, // ~16 s for a 180° flip
      // Canonical 400 km circular orbit, inclined 51.6° (ISS-like) so the sub-ship
      // latitude sweeps ±51.6° and the AI can answer "when am I next over the pole?"
      // (docs/07 §8, criterion 5). Inclination leaves period, speed, altitude alone.
      elements: circularOrbit(CRADLE, 400e3, deg(51.6)),
      // Starts EMPTY on purpose: cargo 0 ⇒ structural mass = dry mass, so the tuned
      // Δv budget and the check-sim rendezvous margins are unchanged. Load at a station.
      cargoCapacityKg: 8000,
      cargoCapacityM3: 40, // ~10 m × 3 m hull's usable internal volume; bulky goods bind here first
      cargo: [],
    };
    this.time = 0;
    this.rate = 1;
    this.orientation = IDENTITY_Q;
    this.angularVel = { x: 0, y: 0, z: 0 };
    this.attitudeMode = "manual";
    this.manualTorque = { x: 0, y: 0, z: 0 };
    this.rateCap = deg(20); // 20°/s
    this.throttle = 0;
    this.poweredState = null;
    this.nodes = [];
    this.executorOn = false;
    this.burnTargetDir = null;
    this.burnDelivered = 0;
    this.warpAutoLimited = false;
    this.pendingManeuver = null;
    // All co-planar with the ship (i 51.6°, same node), differing in altitude + phase — real
    // rendezvous targets without leaving the single-body sim. The default (Kestrel, 450 km,
    // ~20° ahead) is tuned so a Lambert intercept (~360 m/s @ ~80 min) leaves comfortable Δv
    // margin under the ~1272 m/s budget. The others are reachable but cost more.
    const R = this.body.radius;
    const ring = (altKm: number, phaseDeg: number): OrbitalElements => ({
      a: R + altKm * 1e3,
      e: 0,
      i: deg(51.6),
      raan: 0,
      argp: 0,
      meanAnomalyAtEpoch: deg(phaseDeg),
      epoch: 0,
    });
    this.targets = [
      {
        name: "Kestrel Station",
        kind: "station",
        elements: ring(450, 20),
        inventory: [
          { id: "water", name: "Water", massKg: 250, volumeM3: 0.3, qty: 8 },
          { id: "rations", name: "Rations", massKg: 50, volumeM3: 0.35, qty: 20 },
          { id: "parts", name: "Spare Parts", massKg: 120, volumeM3: 0.5, qty: 6 },
          { id: "alloy", name: "Alloy Plate", massKg: 300, volumeM3: 0.12, qty: 4 },
        ],
      },
      {
        name: "Depot Six",
        kind: "depot",
        elements: ring(520, 75),
        inventory: [
          { id: "ore", name: "Ore", massKg: 500, volumeM3: 0.22, qty: 10 },
          { id: "machinery", name: "Machinery", massKg: 400, volumeM3: 1.5, qty: 3 },
          { id: "ballast", name: "Ballast", massKg: 250, volumeM3: 0.08, qty: 12 },
        ],
      },
      // A probe has no hold — docking it offers no cargo services (a deliberate edge case).
      { name: "Probe Ariel", kind: "probe", elements: ring(360, 325) },
    ];
    this.selectedTarget = 0;
    this.dockedTo = null;
  }

  /** The active target's definition (name/kind/elements). */
  selectedTargetDef(): TargetDef {
    return this.targets[this.selectedTarget] ?? this.targets[0];
  }

  /** The active rendezvous target's orbital state right now. */
  targetState(): OrbitState {
    return propagate(this.selectedTargetDef().elements, this.body, this.time);
  }

  /** Advance sim-time by `realDtSeconds` of wall-clock × warp. The executor (if on)
   *  sets throttle/attitude first; powered flight then integrates at a fixed substep
   *  (docs/10 §3), while coasting stays analytic. */
  advance(realDtSeconds: number): void {
    // Let the executor (if on) decide throttle/attitude/warp-clamp from the CURRENT
    // sim-time before we pick a stepping regime.
    if (this.executorOn) this.driveExecutor();
    const simDelta = realDtSeconds * this.rate;

    // Fast path: pure coast with nothing time-critical pending (no live burn, and the
    // executor isn't inside a node's burn window). Orbit propagation is analytic, so this
    // is one exact jump — it's what keeps warp cheap.
    const poweredNow = this.throttle > 0 && this.ship.propellantKg > 0;
    if (!poweredNow && !this.poweredState && !this.inBurnWindow) {
      this.stepCoast(simDelta);
      return;
    }

    // Quantized path (docs/10 §3): powered flight and the run-up/run-down around a burn
    // advance on a FIXED DT_PHYS sim-time grid, re-deciding control at each substep
    // boundary. This makes the burn a pure function of elapsed sim-time — independent of
    // how the wall-clock delta was chunked — which is what determinism (multiplayer and
    // the away-game, docs/10 §3) requires.
    this.physAccum += simDelta;
    let steps = 0;
    while (this.physAccum >= DT_PHYS && steps < MAX_SUBSTEPS) {
      // Re-decide control at THIS substep's sim-time (step 0 used the decision above).
      if (steps > 0 && this.executorOn) this.driveExecutor();
      const powered = this.throttle > 0 && this.ship.propellantKg > 0;
      if (powered) {
        if (!this.poweredState) this.seedPowered();
        this.stepPoweredSubstep();
      } else {
        if (this.poweredState) this.foldToCoast();
        this.stepCoast(DT_PHYS);
      }
      this.physAccum -= DT_PHYS;
      steps++;
      if (powered && this.ship.propellantKg <= 0) break; // flame-out
    }

    // Sub-DT_PHYS remainder: while coasting it's exact to apply analytically; while a burn
    // is still live, leave it in physAccum so the next tick continues the same grid.
    if (this.physAccum > 0 && !(this.throttle > 0 && this.ship.propellantKg > 0)) {
      if (this.poweredState) this.foldToCoast(); // e.g. flame-out mid-loop
      this.stepCoast(this.physAccum);
      this.physAccum = 0;
    }
  }

  // --- flight commands (the three clients all call these via the API) --------

  setThrottle(x: number): void {
    this.throttle = Math.max(0, Math.min(1, x));
  }

  setAttitudeMode(mode: AttitudeMode): void {
    this.attitudeMode = mode;
  }

  /** Manual reaction-wheel command in body axes (pitch/yaw/roll), used in manual mode. */
  setManualTorque(t: Vec3): void {
    this.manualTorque = t;
  }

  setExecutor(on: boolean): void {
    this.executorOn = on;
    if (!on) {
      this.throttle = 0;
      this.warpAutoLimited = false;
      this.inBurnWindow = false;
    } else {
      this.burnDelivered = 0;
    }
  }

  // --- node-executor autopilot (docs/10 §6) ----------------------------------

  /** Resolve a retarget node's Δv from the ship's live coasted state (valid only between burns,
   *  when the orbit is analytic). `transfer` re-solves the Lambert leg to the target's arrival
   *  position — a midcourse trim that cancels accumulated error; `match` nulls relative velocity.
   *  Clears the retarget afterwards so the frozen value flies. A non-physical or unaffordable
   *  trim is dropped to zero (skipped) rather than risking a propellant-starving burn. */
  private resolveRetarget(node: ManeuverNode): void {
    const rt = node.retarget;
    if (!rt) return;
    const s = propagate(this.ship.elements, this.body, node.time); // burn-point state (analytic coast)
    let dvWorld: Vec3 = { x: 0, y: 0, z: 0 };
    if (rt.kind === "match") {
      const tgt = propagate(rt.targetEl, this.body, node.time);
      dvWorld = { x: tgt.velocity.x - s.velocity.x, y: tgt.velocity.y - s.velocity.y, z: tgt.velocity.z - s.velocity.z };
    } else {
      const tof = rt.arrivalTime - node.time;
      const arr = propagate(rt.targetEl, this.body, rt.arrivalTime);
      const sol = tof > 0 ? bestTransfer(s.position, arr.position, tof, this.body.mu, s.velocity, arr.velocity, rt.maxRevs) : null;
      if (sol) dvWorld = { x: sol.v1.x - s.velocity.x, y: sol.v1.y - s.velocity.y, z: sol.v1.z - s.velocity.z };
    }
    const dvMag = Math.hypot(dvWorld.x, dvWorld.y, dvWorld.z);
    const budget = dvBudgetOf(this.ship.propellantKg, this.structuralMassKg(), this.ship.ispSeconds);
    node.dvLocal =
      Number.isFinite(dvMag) && dvMag <= budget
        ? worldDvToLocal(dvWorld, s.position, s.velocity)
        : { prograde: 0, normal: 0, radial: 0 }; // non-physical / unaffordable trim — skip rather than starve
    node.retarget = undefined; // resolved — fly the frozen value
  }

  /** Each tick before stepping: aim the ship at the next node's burn vector, drop
   *  out of warp near the burn, throttle up once aligned & in-window, and cut off
   *  when the planned Δv has been delivered. Closed-loop for retarget nodes (midcourse
   *  trims + live match); otherwise open-loop on the planned Δv (docs/10 §6). */
  private driveExecutor(): void {
    const node = this.nodes[0];
    if (!node) {
      this.executorOn = false;
      this.throttle = 0;
      this.warpAutoLimited = false;
      this.inBurnWindow = false;
      return;
    }
    // Closed-loop guidance: resolve a retarget node's Δv from the ship's ACTUAL coasted state
    // the moment it becomes active (coast is analytic, so this is stable once the prior burn
    // has folded). A midcourse trim / live match cancels the open-loop error of a long transfer.
    if (node.retarget && !this.poweredState) this.resolveRetarget(node);
    const dvMag = dvMagnitude(node.dvLocal);
    const accel = this.ship.thrustN / this.currentMass();
    const burnDur = accel > 0 ? dvMag / accel : 0;
    const burnStart = node.time - burnDur / 2;

    const { r, v } = this.currentRV();
    this.burnTargetDir = nodeWorldDir(node.dvLocal, r, v);
    this.attitudeMode = "node";

    // Auto-limit warp as the burn window approaches (docs/08).
    const lead = Math.max(20, burnDur);
    const inWindow = this.time >= burnStart - lead;
    this.inBurnWindow = inWindow; // tells advance() to step on the fixed DT_PHYS grid
    this.warpAutoLimited = inWindow && this.rate > 1;
    if (inWindow && this.rate > 1) this.rate = 1;

    const aligned = this.pointingError(this.burnTargetDir) < deg(2);
    if (this.time >= burnStart && this.burnDelivered >= dvMag) {
      // burn complete — retire the node
      this.nodes.shift();
      this.burnDelivered = 0;
      this.throttle = 0;
      this.burnTargetDir = null;
      if (this.nodes.length === 0) {
        this.executorOn = false;
        this.attitudeMode = "kill";
        this.inBurnWindow = false; // burn done → let advance() return to the analytic coast fast-path
      }
      return;
    }
    this.throttle = this.time >= burnStart && aligned && this.burnDelivered < dvMag ? 1 : 0;
  }

  /** Jump-to-event: coast (analytically) to just before the next node's burn window
   *  so the executor can fly it. Returns false if no node is queued. */
  jumpToNextNode(): boolean {
    const node = this.nodes[0];
    if (!node) return false;
    if (node.retarget && !this.poweredState) this.resolveRetarget(node); // size the window from the real trim
    const burnDur = dvMagnitude(node.dvLocal) / Math.max(1e-9, this.ship.thrustN / this.currentMass());
    const arrive = node.time - burnDur / 2 - 25; // 25 s lead to settle + slew
    if (arrive > this.time) this.time = arrive; // instant coast (orbit is analytic)
    this.executorOn = true;
    return true;
  }

  // --- hybrid plumbing -------------------------------------------------------

  private seedPowered(): void {
    const s = propagate(this.ship.elements, this.body, this.time);
    this.poweredState = {
      r: { ...s.position },
      v: { ...s.velocity },
      m: this.structuralMassKg() + this.ship.propellantKg,
    };
  }

  private foldToCoast(): void {
    const ps = this.poweredState!;
    this.ship.elements = stateToElements(ps.r, ps.v, this.body, this.time);
    this.poweredState = null;
    // Any un-integrated sim-time stays in physAccum and is consumed as coast by advance()'s
    // loop / remainder drain — no separate carry needed.
  }

  /** Exactly one DT_PHYS of powered integration, anchored to the fixed grid. advance()
   *  owns physAccum and the per-substep control decision; this just integrates one step. */
  private stepPoweredSubstep(): void {
    this.stepAttitude(DT_PHYS);
    const dir = thrustAxisWorld(this.orientation);
    const mPre = this.poweredState!.m;
    const structural = this.structuralMassKg(); // cargo can't change mid-burn (docked casts off)
    this.poweredState = stepPowered(
      this.poweredState!,
      this.body,
      dir,
      this.throttle,
      { thrustN: this.ship.thrustN, ispSeconds: this.ship.ispSeconds },
      structural,
      DT_PHYS,
    );
    this.burnDelivered += ((this.ship.thrustN * this.throttle) / mPre) * DT_PHYS;
    this.ship.propellantKg = Math.max(0, this.poweredState.m - structural);
    this.time += DT_PHYS;
  }

  private stepCoast(simDelta: number): void {
    this.advanceAttitudeCoast(simDelta);
    this.time += simDelta;
  }

  private advanceAttitudeCoast(delta: number): void {
    // Nothing to integrate if the ship is inert and not commanded to turn.
    const still = Math.hypot(this.angularVel.x, this.angularVel.y, this.angularVel.z) < 1e-9;
    if (still && this.attitudeMode === "manual") return;
    let remaining = delta;
    let steps = 0;
    while (remaining > 1e-9 && steps < MAX_SUBSTEPS) {
      const dt = Math.min(DT_PHYS, remaining);
      this.stepAttitude(dt);
      remaining -= dt;
      steps++;
    }
  }

  /** One attitude substep: manual torque in manual mode, else the point-at controller. */
  private stepAttitude(dt: number): void {
    const torque =
      this.attitudeMode === "manual"
        ? clampMagnitude(this.manualTorque, this.ship.maxTorqueNm)
        : controlTorqueBody(
            this.orientation,
            this.angularVel,
            this.attitudeTargetDir(),
            this.ship.inertia,
            this.ship.maxTorqueNm,
            this.rateCap,
          );
    const next = integrateAttitude(this.orientation, this.angularVel, this.ship.inertia, torque, dt);
    this.orientation = next.q;
    this.angularVel = next.omega;
  }

  /** Commanded thrust-axis direction (world) for the current mode. `node` follows
   *  the executor's burn vector; `kill` targets the current axis (damps rotation);
   *  `manual` returns null (handled upstream). */
  attitudeTargetDir(): Vec3 | null {
    const mode = this.attitudeMode;
    if (mode === "manual") return null;
    if (mode === "node") return this.burnTargetDir;
    if (mode === "kill") return thrustAxisWorld(this.orientation);
    const { r, v } = this.currentRV();
    if (mode === "target" || mode === "antiTarget") {
      // Line-of-sight to the selected target (relative position), not an orbital axis.
      const tp = this.targetState().position;
      const los = { x: tp.x - r.x, y: tp.y - r.y, z: tp.z - r.z };
      const m = Math.hypot(los.x, los.y, los.z);
      if (m < 1e-6) return null; // coincident — nothing to point at
      const s = (mode === "antiTarget" ? -1 : 1) / m;
      return { x: los.x * s, y: los.y * s, z: los.z * s };
    }
    return headingDir(mode, r, v);
  }

  pointingError(target: Vec3 | null): number {
    if (!target) return 0;
    const axis = thrustAxisWorld(this.orientation);
    return Math.acos(Math.max(-1, Math.min(1, axis.x * target.x + axis.y * target.y + axis.z * target.z)));
  }

  /** Total cargo mass in the hold [kg]. */
  cargoMassKg(): number {
    return this.ship.cargo.reduce((sum, c) => sum + c.massKg * c.qty, 0);
  }

  /** Total cargo volume in the hold [m^3]. A load can be capped by this even with mass to spare. */
  cargoVolumeM3(): number {
    return this.ship.cargo.reduce((sum, c) => sum + c.volumeM3 * c.qty, 0);
  }

  /** The mass that ISN'T propellant — dry structure plus cargo [kg]. This is the burnout
   *  mass the rocket equation uses, and the floor propellant depletion can't go below. */
  structuralMassKg(): number {
    return this.ship.dryMassKg + this.cargoMassKg();
  }

  currentMass(): number {
    return this.poweredState ? this.poweredState.m : this.structuralMassKg() + this.ship.propellantKg;
  }

  currentRV(): { r: Vec3; v: Vec3 } {
    if (this.poweredState) return { r: this.poweredState.r, v: this.poweredState.v };
    const s = propagate(this.ship.elements, this.body, this.time);
    return { r: s.position, v: s.velocity };
  }

  // --- reads -----------------------------------------------------------------

  /** Current orbital state — from the live integrated state while thrusting (the
   *  osculating conic), else from the coast elements. */
  orbit(): OrbitState {
    return propagate(this.currentElements(), this.body, this.time);
  }

  orbitAt(t: number): OrbitState {
    return propagate(this.currentElements(), this.body, t);
  }

  /** The osculating elements right now: derived from the integrated state under
   *  power, otherwise the stored coast conic. */
  private currentElements(): OrbitalElements {
    if (this.poweredState) {
      return stateToElements(this.poweredState.r, this.poweredState.v, this.body, this.time);
    }
    return this.ship.elements;
  }
}
