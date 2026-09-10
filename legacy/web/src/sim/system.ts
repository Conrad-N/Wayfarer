import type { CentralBody, OrbitalElements, Vec3 } from "./types";
import { propagate } from "./orbit";

// The body hierarchy (docs/05 §M2 — patched conics). A System is a tree of bodies: a
// root star with planets orbiting it (and, later, moons orbiting planets). Each non-root
// body carries its own Keplerian orbit ABOUT ITS PARENT, so the whole system's geometry
// is analytic: a body's state in the root frame is the sum of conics up the parent chain.
//
// Pure and deterministic like the rest of src/sim — no World, no Date.now, identical
// output for identical inputs. The ship is always bound to exactly ONE body's sphere of
// influence at a time (the patched-conic backbone, docs/08 Part A); `world.ts` owns which.

/** A gravitating body: a CentralBody (name/mu/radius) plus its place in the hierarchy and
 *  its sphere of influence. `parentId`/`elements` are null only for the root star; the root
 *  defines the inertial frame everything else is measured against. */
export interface Body extends CentralBody {
  id: string;
  parentId: string | null; // null = root star
  elements: OrbitalElements | null; // orbit about the parent; null for the root
  soiRadius: number | null; // sphere-of-influence radius [m]; null = root (infinite)
}

/** A body's Cartesian state in some frame. */
export interface BodyState {
  position: Vec3;
  velocity: Vec3;
}

const ZERO: BodyState = { position: { x: 0, y: 0, z: 0 }, velocity: { x: 0, y: 0, z: 0 } };

/** Sphere-of-influence radius for a body orbiting a parent: r_soi = a·(μ_body/μ_parent)^(2/5)
 *  (the Laplace SOI — the classic patched-conic boundary, KSP's model). */
export function soiRadius(semiMajorAxis: number, muBody: number, muParent: number): number {
  return semiMajorAxis * Math.pow(muBody / muParent, 2 / 5);
}

export class System {
  private readonly byId: Map<string, Body>;
  readonly rootId: string;

  constructor(bodies: Body[]) {
    this.byId = new Map(bodies.map((b) => [b.id, b]));
    const roots = bodies.filter((b) => b.parentId === null);
    if (roots.length !== 1) {
      throw new Error(`System needs exactly one root body (found ${roots.length})`);
    }
    this.rootId = roots[0].id;
  }

  has(id: string): boolean {
    return this.byId.has(id);
  }

  /** The body with this id (throws on an unknown id — a programming error, not a runtime one). */
  body(id: string): Body {
    const b = this.byId.get(id);
    if (!b) throw new Error(`no such body: ${id}`);
    return b;
  }

  root(): Body {
    return this.body(this.rootId);
  }

  all(): Body[] {
    return [...this.byId.values()];
  }

  /** The bodies whose immediate parent is `id` (e.g. the planets of a star). */
  children(id: string): Body[] {
    return this.all().filter((b) => b.parentId === id);
  }

  /** A body's state in the ROOT (inertial) frame at sim-time `t`, by summing the conic of
   *  every ancestor up the parent chain. Analytic — one `propagate` per level. The root is
   *  the origin (zero state). */
  bodyStateInRoot(id: string, t: number): BodyState {
    const b = this.body(id);
    if (b.parentId === null || b.elements === null) return ZERO;
    const parent = this.body(b.parentId);
    const up = this.bodyStateInRoot(b.parentId, t);
    const local = propagate(b.elements, parent, t); // state about the parent
    return {
      position: {
        x: up.position.x + local.position.x,
        y: up.position.y + local.position.y,
        z: up.position.z + local.position.z,
      },
      velocity: {
        x: up.velocity.x + local.velocity.x,
        y: up.velocity.y + local.velocity.y,
        z: up.velocity.z + local.velocity.z,
      },
    };
  }

  /** The state of `toId` expressed in `fromId`'s (non-rotating, translated) frame at `t`.
   *  Patched-conic frames are inertial translations, so this is just the difference of the
   *  two root-frame states — used for SOI handoffs and cross-frame target telemetry. */
  relativeState(fromId: string, toId: string, t: number): BodyState {
    const from = this.bodyStateInRoot(fromId, t);
    const to = this.bodyStateInRoot(toId, t);
    return {
      position: { x: to.position.x - from.position.x, y: to.position.y - from.position.y, z: to.position.z - from.position.z },
      velocity: { x: to.velocity.x - from.velocity.x, y: to.velocity.y - from.velocity.y, z: to.velocity.z - from.velocity.z },
    };
  }
}
