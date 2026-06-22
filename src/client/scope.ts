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
): void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;

  const W = canvas.width;
  const H = canvas.height;
  ctx.clearRect(0, 0, W, H);

  const phos = getComputedStyle(canvas).color || "#ffb000";
  const pad = 20;
  // Scale so both orbits fit (the target may sit higher than the ship's apoapsis).
  const maxR = Math.max(o.apoapsisRadius, target ? target.apoapsisRadius : 0);
  const scale = (Math.min(W, H) / 2 - pad) / maxR;

  const a = o.a;
  const e = o.e;
  const b = a * Math.sqrt(Math.max(0, 1 - e * e));
  const c = a * e; // focus offset; periapsis lies along +x

  ctx.save();
  ctx.translate(W / 2, H / 2);
  ctx.strokeStyle = phos;
  ctx.fillStyle = phos;
  ctx.lineWidth = 1.5;

  // orbit ellipse (centered at -c from the focus)
  ctx.globalAlpha = 0.9;
  ctx.beginPath();
  ctx.ellipse(-c * scale, 0, a * scale, b * scale, 0, 0, Math.PI * 2);
  ctx.stroke();

  // planet at the focus (origin)
  ctx.globalAlpha = 0.45;
  ctx.beginPath();
  ctx.arc(0, 0, Math.max(2, bodyRadius * scale), 0, Math.PI * 2);
  ctx.stroke();
  ctx.globalAlpha = 0.12;
  ctx.fill();

  // periapsis (+x) and apoapsis (-x) markers
  ctx.globalAlpha = 0.6;
  tick(ctx, o.periapsisRadius * scale, 0);
  tick(ctx, -o.apoapsisRadius * scale, 0);

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
