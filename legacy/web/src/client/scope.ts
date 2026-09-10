import type { OrbitState } from "../sim/types";

// A vector "orbit scope" (docs/04): the conic drawn as a glowing line, the planet
// at the focus, the ship as a blip. A 2D schematic in the orbital plane (perifocal
// projection) — period-honest and cheap, exactly what the aesthetic calls for. A
// co-planar `target` orbit is drawn alongside (same plane → same projection).
const TARGET_COL = "#ff7ec9";

export function drawScope(
  canvas: HTMLCanvasElement,
  o: OrbitState,
  bodyRadius: number,
  target?: OrbitState | null,
  soiRadius?: number | null,
): void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const W = canvas.width;
  const H = canvas.height;
  ctx.clearRect(0, 0, W, H);

  const phos = getComputedStyle(canvas).color || "#ffb000";
  const pad = 20;
  const hyperbolic = o.e >= 1 || !Number.isFinite(o.apoapsisRadius);
  // Draw the SOI ring once the orbit reaches out toward the boundary (escape regime) — keeps
  // the everyday low-orbit view unchanged, but makes an approaching handoff visible.
  const drawSoi = soiRadius != null && (hyperbolic || o.apoapsisRadius > 0.15 * soiRadius);
  // Scale so everything finite fits. A hyperbola has no apoapsis — bound its extent by the SOI.
  const orbitExtent = Number.isFinite(o.apoapsisRadius) ? o.apoapsisRadius : (soiRadius ?? o.radius * 2);
  const maxR = Math.max(orbitExtent, target ? target.apoapsisRadius : 0, drawSoi ? (soiRadius as number) : 0);
  const scale = maxR > 0 ? (Math.min(W, H) / 2 - pad) / maxR : 1;

  const a = o.a;
  const e = o.e;
  const c = a * e; // focus offset; periapsis lies along +x

  ctx.save();
  ctx.translate(W / 2, H / 2);
  ctx.strokeStyle = phos;
  ctx.fillStyle = phos;
  ctx.lineWidth = 1.5;

  // The ship's conic. An ellipse draws directly; a hyperbola (an escape/approach arc) is
  // sampled in polar form r(ν)=p/(1+e·cosν) so the canvas never sees a negative radius.
  ctx.globalAlpha = 0.9;
  if (!hyperbolic) {
    const b = a * Math.sqrt(Math.max(0, 1 - e * e));
    ctx.beginPath();
    ctx.ellipse(-c * scale, 0, a * scale, b * scale, 0, 0, Math.PI * 2);
    ctx.stroke();
  } else {
    drawConicArc(ctx, o, scale);
  }

  // SOI ring (the boundary the ship hands off at) — faint, dashed.
  if (drawSoi) {
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.arc(0, 0, (soiRadius as number) * scale, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  // planet at the focus (origin)
  ctx.globalAlpha = 0.45;
  ctx.beginPath();
  ctx.arc(0, 0, Math.max(2, bodyRadius * scale), 0, Math.PI * 2);
  ctx.stroke();
  ctx.globalAlpha = 0.12;
  ctx.fill();

  // periapsis (+x) and apoapsis (-x) markers (apoapsis only exists for a bound orbit)
  ctx.globalAlpha = 0.6;
  tick(ctx, o.periapsisRadius * scale, 0);
  if (Number.isFinite(o.apoapsisRadius)) tick(ctx, -o.apoapsisRadius * scale, 0);

  // The co-planar target orbit + station blip, in the SHIP's perifocal frame. Both share
  // the plane (same inclination/node), so the only correction is the difference in argp;
  // the target's angle-from-periapsis-axis is (argp_t + ν_t) − argp_ship.
  if (target) {
    ctx.strokeStyle = TARGET_COL;
    ctx.fillStyle = TARGET_COL;
    const at = target.a;
    const et = target.e;
    const bt = at * Math.sqrt(Math.max(0, 1 - et * et));
    const dArgp = target.argp - o.argp;
    ctx.globalAlpha = 0.55;
    ctx.beginPath();
    // ellipse centre offset from the focus by c along the target's periapsis axis (rotated
    // by dArgp); for the MVP circular target this is just a circle at the origin.
    const ct = at * et;
    ctx.ellipse(-ct * Math.cos(dArgp) * scale, ct * Math.sin(dArgp) * scale, at * scale, bt * scale, -dArgp, 0, Math.PI * 2);
    ctx.stroke();

    const ang = target.argp + target.trueAnomaly - o.argp;
    const tr = target.radius * scale;
    const txp = tr * Math.cos(ang);
    const typ = -tr * Math.sin(ang);
    ctx.globalAlpha = 1;
    ctx.beginPath();
    ctx.arc(txp, typ, 3.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 0.4;
    ctx.beginPath();
    ctx.arc(txp, typ, 7, 0, Math.PI * 2);
    ctx.stroke();
    ctx.strokeStyle = phos;
    ctx.fillStyle = phos;
  }

  // ship blip at the current true anomaly (y flipped so prograde reads CCW)
  const r = o.radius * scale;
  const sx = r * Math.cos(o.trueAnomaly);
  const sy = -r * Math.sin(o.trueAnomaly);
  ctx.globalAlpha = 1;
  ctx.beginPath();
  ctx.arc(sx, sy, 3.5, 0, Math.PI * 2);
  ctx.fill();
  ctx.globalAlpha = 0.5;
  ctx.beginPath();
  ctx.arc(sx, sy, 7, 0, Math.PI * 2);
  ctx.stroke();

  ctx.restore();
}

function tick(ctx: CanvasRenderingContext2D, x: number, y: number): void {
  ctx.beginPath();
  ctx.arc(x, y, 2, 0, Math.PI * 2);
  ctx.stroke();
}

/** Sample a (hyperbolic) conic in the perifocal plane as a polyline. r(ν)=p/(1+e·cosν) is
 *  finite only for ν within the asymptote ±acos(−1/e); we sweep just inside that range so the
 *  escape/approach branch reads correctly (y flipped to match the ship blip's CCW convention). */
function drawConicArc(ctx: CanvasRenderingContext2D, o: OrbitState, scale: number): void {
  const e = o.e;
  const p = o.a * (1 - e * e); // semi-latus rectum (>0 for a hyperbola: a<0, 1−e²<0)
  const nuInf = Math.acos(Math.max(-1, Math.min(1, -1 / e)));
  const lim = nuInf - 1e-3; // stay just inside the asymptotes
  const N = 128;
  ctx.beginPath();
  for (let k = 0; k <= N; k++) {
    const nu = -lim + (2 * lim * k) / N;
    const r = p / (1 + e * Math.cos(nu));
    const x = r * Math.cos(nu) * scale;
    const y = -r * Math.sin(nu) * scale;
    if (k === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();
}
