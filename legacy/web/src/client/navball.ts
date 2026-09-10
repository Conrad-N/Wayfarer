import { rotate } from "../sim/flight";
import type { FlightState, TargetState, V3 } from "./types";

// The nav ball (docs/10 §7): a functional 2D attitude display. It's a thin client —
// it draws only world-frame unit vectors the API already computed (the orbital-frame
// markers, the ship's facing, its angular velocity). No physics here, just projection.
//
// Projection: BORESIGHT-CENTERED azimuthal-equidistant. The ship's nose sits at the
// centre crosshair; every marker is plotted by its ANGLE off the nose. The front
// hemisphere fills the disc (0°→centre, 90°→rim); markers behind the ship clamp to
// the rim, dimmed. So aligning to prograde = watching the prograde marker spiral into
// the bullseye, which is exactly the "watch it flip and align" payoff.

const DEG = 180 / Math.PI;
const HALF_PI = Math.PI / 2;

// Marker colour language mirrors KSP so it reads instantly: prograde yellow, normal
// magenta, radial cyan, the maneuver node blue. The ship reticle is near-white.
const COL = {
  prograde: "#ffd23f",
  normal: "#d472ff",
  radial: "#36d6ff",
  node: "#5ab0ff",
  target: "#ff7ec9", // rose — the rendezvous target (KSP-ish target colour)
  ship: "#eaf6ff",
  ringFaint: "rgba(120,160,200,0.18)",
  ringRim: "rgba(120,170,210,0.45)",
  back: "#0a1018",
};

const clamp = (x: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, x));
const dot = (a: V3, b: V3) => a.x * b.x + a.y * b.y + a.z * b.z;
const cross = (a: V3, b: V3): V3 => ({
  x: a.y * b.z - a.z * b.y,
  y: a.z * b.x - a.x * b.z,
  z: a.x * b.y - a.y * b.x,
});

interface Basis {
  fwd: V3; // ship nose (out of the screen, toward the viewer)
  right: V3; // screen +x
  up: V3; // screen +y
}

interface Plot {
  x: number; // screen offset from centre (+x right)
  y: number; // screen offset from centre (+y up)
  front: boolean; // in the forward hemisphere?
}

/** Project a world unit direction onto the disc (boresight-centred, equidistant). */
function project(d: V3, b: Basis, R: number): Plot {
  const theta = Math.acos(clamp(dot(d, b.fwd), -1, 1)); // 0..π off the nose
  let sx = dot(d, b.right);
  let sy = dot(d, b.up);
  const planar = Math.hypot(sx, sy);
  const front = theta <= HALF_PI + 1e-6;
  const rr = Math.min(theta / HALF_PI, 1) * R; // front fills disc; back clamps to rim
  if (planar < 1e-6) {
    // dead-ahead (centre) or dead-astern (park at the bottom rim)
    return { x: 0, y: theta < HALF_PI ? 0 : -R, front };
  }
  return { x: (sx / planar) * rr, y: (sy / planar) * rr, front };
}

interface Marker {
  dir: V3;
  color: string;
  kind: "prograde" | "retrograde" | "normalUp" | "normalDn" | "radialOut" | "radialIn" | "node" | "target" | "antiTarget";
  label?: string;
}

export function drawNavball(canvas: HTMLCanvasElement, f: FlightState, target?: TargetState | null): void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  const W = canvas.width;
  const H = canvas.height;
  const cx = W / 2;
  const cy = H / 2;
  const R = Math.min(W, H) / 2 - 16;
  ctx.clearRect(0, 0, W, H);

  // Screen basis from the ship's orientation: nose toward the viewer, body +Y to the
  // right, body +Z up. Roll about the nose rolls the whole ball — correct and free.
  const q = f.orientation;
  const b: Basis = {
    fwd: rotate(q, { x: 1, y: 0, z: 0 }),
    right: rotate(q, { x: 0, y: 1, z: 0 }),
    up: rotate(q, { x: 0, y: 0, z: 1 }),
  };

  drawBackdrop(ctx, cx, cy, R);

  // Markers, back-hemisphere first so the forward ones draw on top.
  const markers: Marker[] = [
    { dir: f.frame.prograde, color: COL.prograde, kind: "prograde", label: "PG" },
    { dir: f.frame.retrograde, color: COL.prograde, kind: "retrograde", label: "RG" },
    { dir: f.frame.normal, color: COL.normal, kind: "normalUp" },
    { dir: f.frame.antinormal, color: COL.normal, kind: "normalDn" },
    { dir: f.frame.radialOut, color: COL.radial, kind: "radialOut" },
    { dir: f.frame.radialIn, color: COL.radial, kind: "radialIn" },
  ];
  if (f.burnTargetDir) {
    markers.push({ dir: f.burnTargetDir, color: COL.node, kind: "node", label: "BURN" });
  }
  // The rendezvous target: where to point to fly straight at it, and its opposite.
  if (target && (target.direction.x || target.direction.y || target.direction.z)) {
    const d = target.direction;
    markers.push({ dir: d, color: COL.target, kind: "target", label: "TGT" });
    markers.push({ dir: { x: -d.x, y: -d.y, z: -d.z }, color: COL.target, kind: "antiTarget" });
  }
  const plotted = markers.map((m) => ({ m, p: project(m.dir, b, R) }));

  // A guide line from the nose to the burn target, so you can see where to point.
  const node = plotted.find((x) => x.m.kind === "node");
  if (node) {
    ctx.save();
    ctx.strokeStyle = COL.node;
    ctx.globalAlpha = 0.35;
    ctx.setLineDash([3, 4]);
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + node.p.x, cy - node.p.y);
    ctx.stroke();
    ctx.restore();
  }

  for (const { m, p } of plotted.filter((x) => !x.p.front)) drawMarker(ctx, cx + p.x, cy - p.y, m, false);
  for (const { m, p } of plotted.filter((x) => x.p.front)) drawMarker(ctx, cx + p.x, cy - p.y, m, true);

  drawRateArrow(ctx, cx, cy, R, q, f.angularVel, b);
  drawReticle(ctx, cx, cy);
}

function drawBackdrop(ctx: CanvasRenderingContext2D, cx: number, cy: number, R: number): void {
  ctx.save();
  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, R);
  g.addColorStop(0, "#0d1622");
  g.addColorStop(1, COL.back);
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.fill();

  // concentric rings at 30° and 60° off-nose, plus the 90° rim
  ctx.strokeStyle = COL.ringFaint;
  ctx.lineWidth = 1;
  for (const frac of [1 / 3, 2 / 3]) {
    ctx.beginPath();
    ctx.arc(cx, cy, R * frac, 0, Math.PI * 2);
    ctx.stroke();
  }
  // crosshair axes
  ctx.beginPath();
  ctx.moveTo(cx - R, cy);
  ctx.lineTo(cx + R, cy);
  ctx.moveTo(cx, cy - R);
  ctx.lineTo(cx, cy + R);
  ctx.stroke();

  ctx.strokeStyle = COL.ringRim;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.arc(cx, cy, R, 0, Math.PI * 2);
  ctx.stroke();
  ctx.restore();
}

function drawMarker(ctx: CanvasRenderingContext2D, x: number, y: number, m: Marker, front: boolean): void {
  ctx.save();
  ctx.translate(x, y);
  ctx.globalAlpha = front ? 1 : 0.4;
  ctx.strokeStyle = m.color;
  ctx.fillStyle = m.color;
  ctx.lineWidth = 1.5;
  ctx.shadowColor = m.color;
  ctx.shadowBlur = front ? 5 : 0;
  const r = 6;

  switch (m.kind) {
    case "prograde": {
      ring(ctx, r);
      ctx.beginPath();
      ctx.arc(0, 0, 1.5, 0, Math.PI * 2);
      ctx.fill();
      // three legs (up, left, right) — the classic prograde glyph
      for (const a of [-Math.PI / 2, Math.PI, 0]) leg(ctx, a, r, r + 3);
      break;
    }
    case "retrograde": {
      ring(ctx, r);
      const k = r * 0.62;
      ctx.beginPath();
      ctx.moveTo(-k, -k);
      ctx.lineTo(k, k);
      ctx.moveTo(-k, k);
      ctx.lineTo(k, -k);
      ctx.stroke();
      for (const a of [-Math.PI / 2, Math.PI, 0]) leg(ctx, a, r, r + 3);
      break;
    }
    case "normalUp":
      triangle(ctx, r, true);
      break;
    case "normalDn":
      triangle(ctx, r, false);
      break;
    case "radialOut":
      square(ctx, r - 1, false);
      break;
    case "radialIn":
      square(ctx, r - 1, true);
      break;
    case "node":
      diamond(ctx, r + 1);
      break;
    case "target": {
      // gun-sight: ring + center dot + four ticks
      ring(ctx, r);
      ctx.beginPath();
      ctx.arc(0, 0, 1.6, 0, Math.PI * 2);
      ctx.fill();
      for (const a of [-Math.PI / 2, Math.PI / 2, 0, Math.PI]) leg(ctx, a, r, r + 3);
      break;
    }
    case "antiTarget": {
      ring(ctx, r);
      const k = r * 0.6;
      ctx.beginPath();
      ctx.moveTo(-k, -k);
      ctx.lineTo(k, k);
      ctx.moveTo(-k, k);
      ctx.lineTo(k, -k);
      ctx.stroke();
      break;
    }
  }

  if (m.label) {
    ctx.shadowBlur = 0;
    ctx.globalAlpha = front ? 0.95 : 0.4;
    ctx.font = "8px Consolas, monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    ctx.fillText(m.label, 0, r + 4);
  }
  ctx.restore();
}

function ring(ctx: CanvasRenderingContext2D, r: number): void {
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, Math.PI * 2);
  ctx.stroke();
}

function leg(ctx: CanvasRenderingContext2D, ang: number, r0: number, r1: number): void {
  ctx.beginPath();
  ctx.moveTo(Math.cos(ang) * r0, Math.sin(ang) * r0);
  ctx.lineTo(Math.cos(ang) * r1, Math.sin(ang) * r1);
  ctx.stroke();
}

function triangle(ctx: CanvasRenderingContext2D, r: number, up: boolean): void {
  const s = up ? 1 : -1;
  ctx.beginPath();
  ctx.moveTo(0, -r * s);
  ctx.lineTo(r * 0.9, r * 0.7 * s);
  ctx.lineTo(-r * 0.9, r * 0.7 * s);
  ctx.closePath();
  ctx.fill();
}

function square(ctx: CanvasRenderingContext2D, r: number, filled: boolean): void {
  ctx.beginPath();
  ctx.rect(-r, -r, r * 2, r * 2);
  if (filled) ctx.fill();
  else ctx.stroke();
}

function diamond(ctx: CanvasRenderingContext2D, r: number): void {
  ctx.beginPath();
  ctx.moveTo(0, -r);
  ctx.lineTo(r, 0);
  ctx.lineTo(0, r);
  ctx.lineTo(-r, 0);
  ctx.closePath();
  ctx.lineWidth = 2;
  ctx.stroke();
}

/** A short arrow from centre showing which way the nose is swinging, and how fast. */
function drawRateArrow(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  R: number,
  q: FlightState["orientation"],
  omegaBody: V3,
  b: Basis,
): void {
  const omegaW = rotate(q, omegaBody);
  const df = cross(omegaW, b.fwd); // world velocity of the nose tip
  const ax = dot(df, b.right);
  const ay = dot(df, b.up);
  const rate = Math.hypot(ax, ay); // transverse angular rate [rad/s]

  ctx.save();
  ctx.font = "9px Consolas, monospace";
  ctx.fillStyle = COL.ship;
  ctx.globalAlpha = 0.6;
  ctx.textAlign = "left";
  ctx.textBaseline = "bottom";
  ctx.fillText(`w ${(rate * DEG).toFixed(0)} deg/s`, 6, cy + R + 14);
  ctx.restore();

  if (rate < 2e-3) return;
  const L = clamp(rate / 0.4, 0.08, 1) * R * 0.7; // ~0.4 rad/s saturates the arrow
  const ux = ax / rate;
  const uy = ay / rate;
  const ex = cx + ux * L;
  const ey = cy - uy * L;
  ctx.save();
  ctx.strokeStyle = COL.ship;
  ctx.fillStyle = COL.ship;
  ctx.globalAlpha = 0.7;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(ex, ey);
  ctx.stroke();
  // arrowhead
  const a = Math.atan2(-uy, ux);
  ctx.beginPath();
  ctx.moveTo(ex, ey);
  ctx.lineTo(ex - 6 * Math.cos(a - 0.4), ey - 6 * Math.sin(a - 0.4));
  ctx.lineTo(ex - 6 * Math.cos(a + 0.4), ey - 6 * Math.sin(a + 0.4));
  ctx.closePath();
  ctx.fill();
  ctx.restore();
}

/** The fixed boresight reticle — where the ship's nose (and thrust) points. */
function drawReticle(ctx: CanvasRenderingContext2D, cx: number, cy: number): void {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.strokeStyle = COL.ship;
  ctx.fillStyle = COL.ship;
  ctx.lineWidth = 2;
  ctx.shadowColor = COL.ship;
  ctx.shadowBlur = 6;
  ctx.beginPath();
  ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
  ctx.fill();
  // waterline wings
  ctx.beginPath();
  ctx.moveTo(-12, 0);
  ctx.lineTo(-5, 0);
  ctx.moveTo(5, 0);
  ctx.lineTo(12, 0);
  ctx.moveTo(0, -5);
  ctx.lineTo(0, -10);
  ctx.stroke();
  ctx.restore();
}
