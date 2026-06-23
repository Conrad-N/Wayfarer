import type { World, CargoItem } from "./world";
import type { ManeuverInput, ManeuverPlan } from "./maneuver";
import { buildPlan, dvBudget } from "./maneuver";
import {
  solveCircularize,
  solveSetApsis,
  solveHohmann,
  solveIntercept,
  solveMatchVelocity,
  suggestInterceptTof,
  suggestInterplanetaryWindow,
  solveInterplanetaryTransfer,
  type Apsis,
} from "./solvers";
import type { Vec3 } from "./types";
import type { AttitudeMode } from "./flight";
import { headingDir, thrustAxisWorld, dvMagnitude } from "./flight";
import { propagate } from "./orbit";

// THE SHIP API (docs/03 Keystone 1). One implementation, consumed by both the
// HTTP routes (panels) and the AI's tools. M0 was read-only; M1 adds the write
// actions (plan_maneuver / execute_maneuver) behind a confirmation gate — the read
// surface below is unchanged, exactly as docs/07 §5 promised.

export function getClock(w: World) {
  return { t: w.time, rate: w.rate };
}

export function getCentralBody(w: World) {
  const b = w.body;
  const parent = b.parentId ? w.system.body(b.parentId) : null;
  return {
    id: b.id,
    name: b.name,
    mu: b.mu,
    radius: b.radius,
    rotationPeriod: b.rotationPeriod,
    parentId: b.parentId,
    parentName: parent?.name ?? null,
    soiRadius: b.soiRadius, // null for the root star (infinite SOI)
  };
}

/** The whole body hierarchy for the scope/AI (patched conics, docs/05 §M2): every body with
 *  its physical parameters, SOI, parent, and current position in the root (heliocentric)
 *  frame; plus which body the ship currently orbits and the next SOI handoff ahead. */
export function getSystem(w: World) {
  const bodies = w.system.all().map((b) => {
    const root = w.system.bodyStateInRoot(b.id, w.time).position;
    return {
      id: b.id,
      name: b.name,
      mu: b.mu,
      radius: b.radius,
      parentId: b.parentId,
      soiRadius: b.soiRadius,
      orbitRadiusM: b.elements ? b.elements.a : null, // ring radius for the system map (null = root)
      rootPosition: [root.x, root.y, root.z] as [number, number, number],
    };
  });
  // The ship's own position in the root frame, so the map can plot the blip + draw its body.
  const sr = w.shipRootState().position;
  const ship = { bodyId: w.centralBodyId, rootPosition: [sr.x, sr.y, sr.z] as [number, number, number] };
  return { centralBodyId: w.centralBodyId, bodies, ship, nextSoi: w.nextSoi };
}

export function getShip(w: World) {
  const { dryMassKg, propellantKg, ispSeconds } = w.ship;
  const cargoKg = w.cargoMassKg();
  const structuralKg = w.structuralMassKg(); // dry + cargo — the burnout mass
  return {
    id: w.ship.id,
    name: w.ship.name,
    massKg: structuralKg + propellantKg,
    dryMassKg,
    cargoKg,
    propellantKg,
    ispSeconds,
    // Δv shrinks with cargo: the burnout mass is dry + cargo, not dry alone (the whole
    // reason loading the hold matters — Keystone 3, truth lives in the sim).
    dvBudget: dvBudget(propellantKg, structuralKg, ispSeconds), // Δv remaining [m/s]
  };
}

export function getOrbit(w: World) {
  return w.orbit();
}

export function getStateVector(w: World) {
  const o = w.orbit();
  return {
    r: [o.position.x, o.position.y, o.position.z],
    v: [o.velocity.x, o.velocity.y, o.velocity.z],
  };
}

export function predictOrbit(w: World, t: number) {
  return w.orbitAt(t);
}

// Docking envelope (MVP): you're "close enough" to dock when nearly co-located and nearly
// stationary relative to the station. Generous — reachable with a couple of intercept +
// match-velocity corrections.
const DOCK_RANGE = 1000; // m
const DOCK_REL_SPEED = 5; // m/s

/** The selected rendezvous target plus the relative state the operator flies by: range,
 *  closing speed (>0 = approaching), and the world-frame bearing toward it (for the nav
 *  ball). Also reports whether you're in the docking envelope and whether you're docked
 *  to it. The target it reports is whichever one is currently selected (selectTarget). */
export function getTarget(w: World) {
  const def = w.selectedTargetDef();
  const ts = w.targetState(); // the target's own orbit (about its body) — altitude/period/scope
  // Relative state in the root (heliocentric) frame so it's correct even when the target
  // orbits a DIFFERENT body than the ship. Relative vectors (range/closing/bearing) are
  // translation-invariant, so for a co-frame target this matches the old PCI computation.
  const shipR = w.shipRootState();
  const tgtR = w.targetRootState(def);
  const rel: Vec3 = { x: tgtR.position.x - shipR.position.x, y: tgtR.position.y - shipR.position.y, z: tgtR.position.z - shipR.position.z };
  const range = Math.hypot(rel.x, rel.y, rel.z);
  const relVel: Vec3 = { x: tgtR.velocity.x - shipR.velocity.x, y: tgtR.velocity.y - shipR.velocity.y, z: tgtR.velocity.z - shipR.velocity.z };
  const relSpeed = Math.hypot(relVel.x, relVel.y, relVel.z);
  // closing speed = −d(range)/dt = −(r̂_rel · v_rel); positive means the gap is shrinking.
  const closingSpeed = range > 1 ? -(rel.x * relVel.x + rel.y * relVel.y + rel.z * relVel.z) / range : 0;
  const direction: Vec3 =
    range > 1 ? { x: rel.x / range, y: rel.y / range, z: rel.z / range } : { x: 0, y: 0, z: 0 };
  // A Lambert intercept is only well-posed when the ship and target share a central body
  // (their elements are in the same frame). A cross-frame planet needs an escape burn first.
  const sameFrame = def.bodyId === w.centralBodyId;
  return {
    index: w.selectedTarget,
    name: def.name,
    kind: def.kind,
    bodyId: def.bodyId,
    sameFrame, // intercept/match available only when true (docs/05 §M2 — two-step transfer)
    range,
    relSpeed,
    closingSpeed,
    direction, // unit vector toward the target, world frame
    altitude: ts.altitude,
    period: ts.period,
    orbit: ts, // the target's own orbital state (for the scope)
    canDock: sameFrame && range < DOCK_RANGE && relSpeed < DOCK_REL_SPEED,
    docked: w.dockedTo === w.selectedTarget,
  };
}

/** The roster for the TARGET selector: every target with a snapshot of its altitude,
 *  period, and current range from the ship, plus which one is selected. */
export function listTargets(w: World) {
  const shipR = w.shipRootState();
  return w.targets.map((def, index) => {
    const s = propagate(def.elements, w.system.body(def.bodyId), w.time); // about its own body
    const tgtR = w.targetRootState(def);
    const range = Math.hypot(tgtR.position.x - shipR.position.x, tgtR.position.y - shipR.position.y, tgtR.position.z - shipR.position.z);
    return {
      index,
      name: def.name,
      kind: def.kind,
      bodyId: def.bodyId,
      sameFrame: def.bodyId === w.centralBodyId,
      altitude: s.altitude,
      period: s.period,
      range,
      selected: index === w.selectedTarget,
      docked: w.dockedTo === index,
    };
  });
}

/** Select which target the telemetry, solvers and dock affordance follow. */
export function selectTarget(w: World, index: number) {
  if (!Number.isInteger(index) || index < 0 || index >= w.targets.length) {
    return { ok: false as const, error: `no such target (0..${w.targets.length - 1})` };
  }
  w.selectedTarget = index;
  return { ok: true as const, target: getTarget(w), targets: listTargets(w) };
}

/** Dock with the selected target — MVP stub. Allowed only inside the envelope; latches
 *  the docked index (no mechanics yet). Firing the engine again casts off. */
export function dock(w: World) {
  const t = getTarget(w);
  if (t.docked) return { ok: true as const, docked: true };
  if (!t.canDock) {
    return {
      ok: false as const,
      error: `not in the docking envelope (range ${(t.range / 1000).toFixed(2)} km, rel ${t.relSpeed.toFixed(1)} m/s)`,
    };
  }
  w.dockedTo = w.selectedTarget;
  return { ok: true as const, docked: true };
}

export function undock(w: World) {
  w.dockedTo = null;
  return { ok: true as const, docked: false };
}

// --- CARGO (docs/03 §M1 — docked transfer; docking itself is still an MVP stub) --------
// Cargo is inert mass: getShip already folds it into the burnout mass, so loading/unloading
// here is what makes the Δv budget move. Transfers are only legal while docked to a target
// that has a hold (a probe doesn't). All three clients call these the same way (Keystone 1).

const cargoView = (c: CargoItem) => ({
  id: c.id,
  name: c.name,
  massKg: c.massKg,
  volumeM3: c.volumeM3,
  qty: c.qty,
  totalKg: c.massKg * c.qty,
  totalM3: c.volumeM3 * c.qty,
});

/** The ship's hold: its stacks, plus the two limits it fills against — mass and volume —
 *  each with used / capacity / free. A load stops at whichever runs out first. */
export function getCargo(w: World) {
  const usedKg = w.cargoMassKg();
  const usedM3 = w.cargoVolumeM3();
  return {
    items: w.ship.cargo.map(cargoView),
    usedKg,
    capacityKg: w.ship.cargoCapacityKg,
    freeKg: Math.max(0, w.ship.cargoCapacityKg - usedKg),
    usedM3,
    capacityM3: w.ship.cargoCapacityM3,
    freeM3: Math.max(0, w.ship.cargoCapacityM3 - usedM3),
  };
}

/** The docked target's trading surface — its inventory, or `docked:false` when adrift.
 *  A target with no hold (a probe) reports docked but an empty inventory + a reason. */
export function getStation(w: World) {
  const idx = w.dockedTo;
  if (idx === null) {
    return { docked: false as const, index: null, name: null, kind: null, hasHold: false, inventory: [] as ReturnType<typeof cargoView>[] };
  }
  const def = w.targets[idx];
  const hasHold = Array.isArray(def.inventory);
  return {
    docked: true as const,
    index: idx,
    name: def.name,
    kind: def.kind,
    hasHold,
    inventory: (def.inventory ?? []).map(cargoView),
  };
}

/** Merge `qty` units of a stack into a hold, stacking onto a matching id or appending. */
function addToHold(hold: CargoItem[], item: CargoItem, qty: number): void {
  const existing = hold.find((c) => c.id === item.id);
  if (existing) existing.qty += qty;
  else hold.push({ id: item.id, name: item.name, massKg: item.massKg, volumeM3: item.volumeM3, qty });
}

/** Remove `qty` units of `id` from a hold (dropping the stack when it empties). */
function removeFromHold(hold: CargoItem[], id: string, qty: number): void {
  const i = hold.findIndex((c) => c.id === id);
  if (i < 0) return;
  hold[i].qty -= qty;
  if (hold[i].qty <= 0) hold.splice(i, 1);
}

type TransferDir = "load" | "unload"; // load = station→ship, unload = ship→station

/** Move cargo across the dock. Validates: docked, the target has a hold, the source stocks
 *  the item, and (on load) the ship's hold has room. Returns the updated holds + Δv so a
 *  caller sees the mass/Δv move in one round-trip. */
export function transferCargo(w: World, direction: TransferDir, itemId: string, qty = 1) {
  const idx = w.dockedTo;
  if (idx === null) return { ok: false as const, error: "not docked — cargo transfer needs a dock" };
  const def = w.targets[idx];
  if (!def.inventory) return { ok: false as const, error: `${def.name} has no cargo hold` };
  const want = Math.max(1, Math.floor(qty));

  const station = def.inventory;
  const ship = w.ship.cargo;
  const source = direction === "load" ? station : ship;
  const item = source.find((c) => c.id === itemId);
  if (!item) return { ok: false as const, error: `no "${itemId}" available to ${direction}` };

  let move = Math.min(want, item.qty);
  if (direction === "load") {
    // The load stops at whichever limit fills first: mass OR volume. A dense item runs out
    // of kg; a bulky one runs out of m^3. (A weightless or volumeless item ignores its limit.)
    const fitsByMass = item.massKg > 0 ? Math.floor((w.ship.cargoCapacityKg - w.cargoMassKg()) / item.massKg) : Infinity;
    const fitsByVolume = item.volumeM3 > 0 ? Math.floor((w.ship.cargoCapacityM3 - w.cargoVolumeM3()) / item.volumeM3) : Infinity;
    move = Math.min(move, fitsByMass, fitsByVolume);
    if (move <= 0) {
      const limit = fitsByVolume < fitsByMass ? "out of volume" : "out of mass capacity";
      return { ok: false as const, error: `hold full — ${limit}` };
    }
  }

  if (direction === "load") {
    removeFromHold(station, itemId, move);
    addToHold(ship, item, move);
  } else {
    removeFromHold(ship, itemId, move);
    addToHold(station, item, move);
  }
  return { ok: true as const, moved: move, cargo: getCargo(w), station: getStation(w), ship: getShip(w) };
}

// --- THE WRITE API (docs/05 §M1, docs/07 §5 + §6.3; docs/10 §6) -------------
// plan_maneuver PREVIEWS a node (when + Δv components) and parks it pending — it never
// touches the orbit. execute_maneuver commits the pending node, and ONLY with an explicit
// confirm: that is the confirmation gate. The planner makes no judgment — it's a forward
// calculator; the operator (human or AI) chooses the burn. Panels and the AI call these
// the same way (Keystone 1 parity).

function fuelOf(w: World) {
  return {
    // Burnout mass includes cargo, so every planned burn's feasibility + cost reflect
    // the loaded hold (the planner sees the same heavy ship the executor will fly).
    dryMassKg: w.structuralMassKg(),
    propellantKg: w.ship.propellantKg,
    ispSeconds: w.ship.ispSeconds,
  };
}

function parkPlan(w: World, plan: ManeuverPlan): ManeuverPlan {
  w.pendingManeuver = plan;
  return plan;
}

/** Hand-authored burn: one node (when + Δv components) → a one-burn plan. */
export function planManeuver(w: World, input: ManeuverInput): ManeuverPlan {
  return parkPlan(w, buildPlan(w.ship.elements, w.body, fuelOf(w), "manual burn", [input]));
}

// Inverse solvers as planning actions: each computes its node(s) and parks the plan, which
// then flows through the same review → execute gate as a hand burn (Keystone 1).
export function planCircularize(w: World, at: Apsis): ManeuverPlan {
  const node = solveCircularize(w.ship.elements, w.body, w.time, at);
  return parkPlan(w, buildPlan(w.ship.elements, w.body, fuelOf(w), `circularize @ ${at}`, [node]));
}

export function planSetApsis(w: World, which: Apsis, targetAltitude: number): ManeuverPlan {
  const targetRadius = w.body.radius + targetAltitude;
  const node = solveSetApsis(w.ship.elements, w.body, w.time, which, targetRadius);
  const label = `set ${which} → ${(targetAltitude / 1000).toFixed(0)} km`;
  return parkPlan(w, buildPlan(w.ship.elements, w.body, fuelOf(w), label, [node]));
}

export function planHohmann(w: World, targetAltitude: number): ManeuverPlan {
  const targetRadius = w.body.radius + targetAltitude;
  const nodes = solveHohmann(w.ship.elements, w.body, w.time, targetRadius);
  const label = `hohmann → ${(targetAltitude / 1000).toFixed(0)} km`;
  return parkPlan(w, buildPlan(w.ship.elements, w.body, fuelOf(w), label, nodes));
}

/** Lambert rendezvous with the target: intercept + match-velocity. Pass a time of flight
 *  (seconds); omit it (or pass ≤ 0) to auto-pick the cheapest TOF for this target's phasing.
 *  `maxRevs` caps how many full revolutions the transfer may make (0 forces a direct arc; more
 *  loops let a poorly-phased target find a cheaper transfer). Returns null if no solution. */
/** True when the selected target shares the ship's central body — the precondition for a
 *  Lambert intercept/match (their elements are in the same frame). A cross-frame planet
 *  needs an escape burn first (the two-step interplanetary transfer, docs/05 §M2). */
function targetCoFrame(w: World): boolean {
  return w.selectedTargetDef().bodyId === w.centralBodyId;
}

export function planIntercept(w: World, tofSeconds?: number, maxRevs?: number): ManeuverPlan | null {
  if (!targetCoFrame(w)) return null; // cross-frame target — escape your SOI first
  const tof =
    tofSeconds && tofSeconds > 0
      ? tofSeconds
      : suggestInterceptTof(w.ship.elements, w.body, w.time, w.selectedTargetDef().elements, maxRevs)?.tofSeconds;
  if (!tof) return null;
  // guided = closed-loop: midcourse trims + a live velocity match, recomputed in flight.
  const nodes = solveIntercept(w.ship.elements, w.body, w.time, w.selectedTargetDef().elements, tof, maxRevs, true);
  if (!nodes) return null;
  const label = `intercept (${(tof / 60).toFixed(0)} min TOF)`;
  return parkPlan(w, buildPlan(w.ship.elements, w.body, fuelOf(w), label, nodes));
}

/** Plan a full INTERPLANETARY transfer to the selected planet — from INSIDE the current body's
 *  SOI (no need to escape first). A heliocentric porkchop picks the soonest cheap window and the
 *  planner sizes the ejection burn itself, so a manual escape can't overshoot (docs/11). Returns
 *  the parked plan, or a reason it couldn't (wrong target / not a sibling / no window). The result
 *  is a guided plan: one real ejection burn, then live heliocentric trims + an arrival match. */
export function planTransferWindow(w: World): { ok: true; plan: ManeuverPlan } | { ok: false; error: string } {
  const def = w.selectedTargetDef();
  if (!def.transferBodyId) {
    return { ok: false, error: `${def.name} isn't an interplanetary destination — select a planet (a sibling of your current body)` };
  }
  if (!w.system.has(def.transferBodyId)) {
    return { ok: false, error: `unknown destination body "${def.transferBodyId}"` };
  }
  const A = w.body;
  const B = w.system.body(def.transferBodyId);
  if (A.id === B.id) return { ok: false, error: `you're already orbiting ${B.name}` };
  if (A.parentId == null) {
    return { ok: false, error: `you're in the ${A.name} frame — drop into a planet's SOI before planning a sibling transfer` };
  }
  if (A.parentId !== B.parentId) {
    return { ok: false, error: `${B.name} isn't a sibling of ${A.name} — no direct transfer between them` };
  }
  const p = propagate(w.ship.elements, A, w.time).position;
  const r0 = Math.hypot(p.x, p.y, p.z); // ship's current orbital radius about A — the ejection is sized from here
  const win = suggestInterplanetaryWindow(A, B, w.system, w.time, r0);
  if (!win) return { ok: false, error: `no transfer window to ${B.name} found within the search horizon` };
  const nodes = solveInterplanetaryTransfer(w.ship.elements, A, w.time, B, win);
  if (!nodes) return { ok: false, error: `couldn't lay a transfer plan to ${B.name} (degenerate window)` };
  const departDays = (win.departureTime - w.time) / 86400;
  const arriveDays = (win.arrivalTime - w.time) / 86400;
  const label = `transfer → ${B.name} (depart +${departDays.toFixed(0)} d, arrive +${arriveDays.toFixed(0)} d)`;
  return { ok: true, plan: parkPlan(w, buildPlan(w.ship.elements, A, fuelOf(w), label, nodes)) };
}

/** The cheapest intercept TOF for the selected target right now — the panel uses it to seed a
 *  sensible TOF when the operator switches targets (every target's phasing is different).
 *  `maxRevs` matches the cap the panel will solve with, so the seed reflects the same setting. */
export function suggestIntercept(w: World, maxRevs?: number) {
  if (!targetCoFrame(w)) return null; // cross-frame — no in-frame Lambert to suggest
  return suggestInterceptTof(w.ship.elements, w.body, w.time, w.selectedTargetDef().elements, maxRevs);
}

/** Kill the relative velocity to the target (terminal approach): one live, exact burn. Null
 *  when the target is in another body's SOI (no shared frame to match velocity in). */
export function planMatchVelocity(w: World): ManeuverPlan | null {
  if (!targetCoFrame(w)) return null;
  const node = solveMatchVelocity(w.ship.elements, w.body, w.time, w.selectedTargetDef().elements);
  return parkPlan(w, buildPlan(w.ship.elements, w.body, fuelOf(w), "match target velocity", [node]));
}

export function getPendingManeuver(w: World): ManeuverPlan | null {
  return w.pendingManeuver;
}

export function cancelManeuver(w: World) {
  w.pendingManeuver = null;
  w.nodes = [];
  w.setExecutor(false);
  return { ok: true as const };
}

/** Commit the planned maneuver: lay its node(s) and arm the executor to fly them with
 *  finite thrust. The confirmation gate is unchanged. */
export function executeManeuver(w: World, confirm: boolean) {
  if (w.nodes.length || w.executorOn) {
    return { ok: false as const, error: "a maneuver is already in progress — cancel it first" };
  }
  const pending = w.pendingManeuver;
  if (!pending) return { ok: false as const, error: "no maneuver planned" };
  if (!confirm) return { ok: false as const, error: "execution requires explicit confirmation" };

  // Re-build against the live orbit/fuel so a stale proposal can't fire an infeasible burn.
  const plan = buildPlan(w.ship.elements, w.body, fuelOf(w), pending.label, pending.nodes);
  if (!plan.feasible) {
    return { ok: false as const, error: plan.note ?? "maneuver is not feasible" };
  }

  const multi = plan.nodes.length > 1;
  plan.nodes.forEach((n, k) => {
    w.nodes.push({ id: multi ? `burn ${k + 1}` : "burn", time: n.time, dvLocal: n.dvLocal, retarget: n.retarget });
  });
  w.nodes.sort((a, b) => a.time - b.time);
  w.setExecutor(true); // fly it
  w.dockedTo = null; // committing a burn casts off
  w.pendingManeuver = null;
  return { ok: true as const, ...getFlight(w) };
}

// --- direct flight commands (throttle / attitude / executor / nodes) --------

export function setThrottle(w: World, x: number) {
  w.setExecutor(false); // grabbing the throttle releases the autopilot
  if (x > 0) w.dockedTo = null; // thrusting casts off
  w.setThrottle(x);
  return getFlight(w);
}

export function setAttitudeMode(w: World, mode: AttitudeMode) {
  w.setExecutor(false); // hand-flying attitude releases the autopilot
  w.setAttitudeMode(mode);
  return getFlight(w);
}

export function setManualTorque(w: World, t: Vec3) {
  w.setManualTorque(t);
  return getFlight(w);
}

export function setExecutor(w: World, on: boolean) {
  w.setExecutor(on);
  return getFlight(w);
}

/** Jump-to-event: warp to the next node's burn window and let the executor fly it. */
export function jumpToNextNode(w: World) {
  if (!w.jumpToNextNode()) return { ok: false as const, error: "no maneuver node queued" };
  return { ok: true as const, orbit: getOrbit(w), ...getFlight(w) };
}

export function clearNodes(w: World) {
  w.nodes = [];
  w.setExecutor(false);
  return { ok: true as const };
}

/** Jump-to-event: warp to just before the next sphere-of-influence handoff (escape/capture)
 *  so it's crossed under control. Returns the orbit + the (possibly new) central body. */
export function jumpToNextSoi(w: World) {
  if (!w.jumpToNextSoi()) return { ok: false as const, error: "no SOI handoff ahead on the current orbit" };
  return { ok: true as const, orbit: getOrbit(w), centralBody: getCentralBody(w), nextSoi: w.nextSoi };
}

/** Flight telemetry: attitude, throttle, executor state, the orbital-frame markers
 *  (for the nav ball), and the node queue with Δv-remaining. */
export function getFlight(w: World) {
  const { r, v } = w.currentRV();
  const node = w.nodes[0];
  return {
    orientation: w.orientation,
    angularVel: w.angularVel,
    facing: thrustAxisWorld(w.orientation), // world-frame thrust axis (the reticle)
    throttle: w.throttle,
    thrustN: w.ship.thrustN,
    attitudeMode: w.attitudeMode,
    executorOn: w.executorOn,
    warpAutoLimited: w.warpAutoLimited,
    pointingErrorDeg: (w.pointingError(w.burnTargetDir ?? w.attitudeTargetDir()) * 180) / Math.PI,
    frame: {
      // orbital-frame markers in world coords — what the nav ball draws
      prograde: headingDir("prograde", r, v),
      retrograde: headingDir("retrograde", r, v),
      normal: headingDir("normal", r, v),
      antinormal: headingDir("antinormal", r, v),
      radialIn: headingDir("radialIn", r, v),
      radialOut: headingDir("radialOut", r, v),
    },
    burnTargetDir: w.burnTargetDir,
    nodes: w.nodes.map((n) => ({ id: n.id, time: n.time, dvLocal: n.dvLocal, dvMag: dvMagnitude(n.dvLocal) })),
    nextNode: node
      ? {
          id: node.id,
          time: node.time,
          dvMag: dvMagnitude(node.dvLocal),
          dvRemaining: Math.max(0, dvMagnitude(node.dvLocal) - w.burnDelivered),
        }
      : null,
  };
}
