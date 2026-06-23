import type { StateResponse, SystemState, ViewInstance } from "./types";
import { h } from "./dom";

// The SYSTEM MAP view — the far view (docs/05 §M2). A top-down heliocentric schematic of the
// whole system: the star at centre, each planet on its orbit ring with a faint sphere-of-
// influence circle, and the ship as a blip at its real heliocentric position. The orbit scope
// (NAV) is the close-in view around the current body; this is what makes an interplanetary
// trajectory legible. A pure API client — it plots server-provided positions, computes nothing.

const SHIP_COL = "#ff7ec9"; // rose, matches the ship/target language elsewhere
const MIN_SOI_PX = 3;

function hms(seconds: number): string {
  if (!Number.isFinite(seconds)) return "--:--:--";
  const s = Math.max(0, Math.floor(seconds));
  return `${String(Math.floor(s / 3600)).padStart(2, "0")}:${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

function draw(canvas: HTMLCanvasElement, sys: SystemState, tNow: number): void {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  const W = canvas.width;
  const H = canvas.height;
  ctx.clearRect(0, 0, W, H);
  const phos = getComputedStyle(canvas).color || "#ffb000";
  const pad = 24;

  // Scale to fit the outermost orbit (and the ship, in case it's flung beyond every planet).
  const shipR = Math.hypot(sys.ship.rootPosition[0], sys.ship.rootPosition[1]);
  const maxR = Math.max(shipR, ...sys.bodies.map((b) => b.orbitRadiusM ?? 0), 1);
  const scale = (Math.min(W, H) / 2 - pad) / maxR;

  ctx.save();
  ctx.translate(W / 2, H / 2); // root (star) at centre; +y up (screen y flipped)
  ctx.strokeStyle = phos;
  ctx.fillStyle = phos;
  ctx.font = "10px ui-monospace, monospace";

  // Orbit rings (circles about the star — heliocentric semi-major axes).
  for (const b of sys.bodies) {
    if (b.orbitRadiusM == null) continue;
    ctx.globalAlpha = 0.3;
    ctx.beginPath();
    ctx.arc(0, 0, b.orbitRadiusM * scale, 0, Math.PI * 2);
    ctx.stroke();
  }

  // Bodies: a dot at the real heliocentric position, an SOI circle, and a label. The root
  // (star) sits at the origin with no orbit/SOI.
  for (const b of sys.bodies) {
    const x = b.rootPosition[0] * scale;
    const y = -b.rootPosition[1] * scale;
    const isCurrent = b.id === sys.centralBodyId;
    const dot = b.parentId == null ? 6 : 4; // the star reads a touch larger
    ctx.globalAlpha = 1;
    ctx.beginPath();
    ctx.arc(x, y, dot, 0, Math.PI * 2);
    ctx.fill();
    if (b.soiRadius != null) {
      ctx.globalAlpha = isCurrent ? 0.55 : 0.25;
      ctx.beginPath();
      ctx.arc(x, y, Math.max(MIN_SOI_PX, b.soiRadius * scale), 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = 0.85;
    ctx.fillText(b.name, x + dot + 3, y + 3);
  }

  // The ship blip (rose), at its heliocentric position.
  const sx = sys.ship.rootPosition[0] * scale;
  const sy = -sys.ship.rootPosition[1] * scale;
  ctx.strokeStyle = SHIP_COL;
  ctx.fillStyle = SHIP_COL;
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

export function createSystemMapView(): ViewInstance {
  const canvas = h("canvas", { class: "scope", width: 320, height: 320 }) as HTMLCanvasElement;
  const caption = h("div", { class: "readout" });
  const root = h("div", { class: "view" }, h("div", { class: "scrollarea" }, h("div", { class: "scope-wrap" }, canvas), caption));

  function render(state: StateResponse): void {
    const sys = state.system;
    draw(canvas, sys, state.clock.t);
    const cur = sys.bodies.find((b) => b.id === sys.centralBodyId)?.name ?? sys.centralBodyId;
    const soi = sys.nextSoi;
    const soiName = soi ? (sys.bodies.find((b) => b.id === soi.toBodyId)?.name ?? soi.toBodyId) : null;
    const handoff = soi && soiName ? `next SOI → ${soiName} in ${hms(soi.time - state.clock.t)}` : "no SOI handoff ahead";
    caption.innerHTML =
      `<div class="row"><span class="k">FRAME</span><span class="v">${cur}</span></div>` +
      `<div class="row"><span class="k">HANDOFF</span><span class="v">${handoff}</span></div>`;
  }

  return { root, render };
}
