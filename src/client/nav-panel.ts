import type { OrbitState } from "../sim/types";
import type { StateResponse, ViewInstance } from "./types";
import { h, post, esc } from "./dom";
import { drawScope } from "./scope";
import { isViewOpen } from "./mounted";

// The NAV view — the orbit scope + telemetry readout + the time-warp selector. A thin
// client of the read API: it polls and renders, never computes truth (docs/03). The warp
// selector is reconciled from the SERVER rate each tick (the executor can force it down
// during a burn), so it shows a red ⚠ HELD badge when that happens.

const DEG = 180 / Math.PI;

function pad(s: string, n: number): string {
  return s.padStart(n, " ");
}
function num(v: number, dp: number, width = 9): string {
  // Dash placeholder for a non-finite field — keeps the fixed-width column intact and reads
  // as a "dead segment" instead of throwing or printing "NaN" (docs/FIX-SPECS H8).
  return pad(Number.isFinite(v) ? v.toFixed(dp) : "---", width);
}
function hms(seconds: number): string {
  if (!Number.isFinite(seconds)) return "--:--:--";
  const s = Math.max(0, Math.floor(seconds));
  const h2 = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return `${String(h2).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
}

// Conversion from SI to operator-friendly units happens here, at the presentation edge —
// never in the sim (docs/07 §1).
const ROWS: Array<[string, (o: OrbitState) => string]> = [
  ["ALTITUDE", (o) => `${num(o.altitude / 1000, 2)} km`],
  ["SPEED", (o) => `${num(o.speed, 1)} m/s`],
  ["PERIOD", (o) => `${num(o.period / 60, 2)} min`],
  ["APOAPSIS", (o) => `${num(o.apoapsisAltitude / 1000, 2)} km`],
  ["PERIAPSIS", (o) => `${num(o.periapsisAltitude / 1000, 2)} km`],
  ["ECCENTRICITY", (o) => num(o.e, 5)],
  ["INCLINATION", (o) => `${num(o.i * DEG, 3)} deg`],
  ["TRUE ANOMALY", (o) => `${num(o.trueAnomaly * DEG, 3)} deg`],
  ["RADIUS", (o) => `${num(o.radius / 1000, 2)} km`],
  ["LATITUDE", (o) => `${num(o.latitude * DEG, 3)} deg`],
  ["FLIGHT PATH", (o) => `${num(o.flightPathAngle * DEG, 3)} deg`],
  ["T-PERIAPSIS", (o) => pad(hms(o.timeToPeriapsis), 9)],
  ["T-APOAPSIS", (o) => pad(hms(o.timeToApoapsis), 9)],
];

function row(label: string, value: string): string {
  return `<div class="row"><span class="k">${label}</span><span class="v">${value}</span></div>`;
}

/** Render the orbital telemetry block into `el`. The mini target summary is included
 *  only when `includeTarget` — NAV drops it if a full TARGET panel is already open. */
export function renderReadout(el: HTMLElement, state: StateResponse, includeTarget = true): void {
  const { orbit, body, ship, clock, target } = state;
  const out = [
    row("VESSEL", esc(ship.name)),
    row("BODY", esc(body.name)),
    row("SIM CLOCK", `${hms(clock.t)}  x${clock.rate}`),
    `<div class="rule"></div>`,
    ...ROWS.map(([label, fn]) => row(label, fn(orbit))),
  ];
  if (includeTarget) {
    out.push(
      `<div class="rule"></div>`,
      row("TARGET", esc(target.name)),
      row("RANGE", `${num(target.range / 1000, 2)} km`),
      row("CLOSING", `${num(target.closingSpeed, 1)} m/s`),
      row("TGT ALT", `${num(target.altitude / 1000, 2)} km`),
    );
  }
  el.innerHTML = out.join("");
}

const WARP_RATES = [0, 1, 10, 100, 1000];

export function createNavView(): ViewInstance {
  const scope = h("canvas", { class: "scope", width: 320, height: 320 }) as HTMLCanvasElement;
  const readout = h("div", { class: "readout" });
  const scroll = h("div", { class: "scrollarea" }, h("div", { class: "scope-wrap" }, scope), readout);

  const warpHeld = h("span", { class: "warp-held", hidden: true }, "⚠ HELD");
  const warpButtons = WARP_RATES.map((rate) =>
    h(
      "button",
      {
        type: "button",
        "data-rate": rate,
        class: rate === 1 ? "active" : undefined,
        onClick: () => {
          // optimistic highlight for instant feedback; the next poll confirms or corrects it
          for (const b of warpButtons) b.classList.toggle("active", b === btnByRate.get(rate));
          void post("/api/rate", { rate });
        },
      },
      `${rate}×`,
    ),
  );
  const btnByRate = new Map(WARP_RATES.map((r, i) => [r, warpButtons[i]]));
  const rateControl = h("div", { class: "rate-control" }, h("span", { class: "label" }, "WARP"), ...warpButtons, warpHeld);

  const root = h("div", { class: "view nav-view" }, scroll, rateControl);

  function render(state: StateResponse): void {
    drawScope(scope, state.orbit, state.body.radius, state.target.orbit);
    // Drop the mini target block when a full TARGET panel is already up (no duplication).
    renderReadout(readout, state, !isViewOpen("target"));
    const rate = state.clock.rate;
    for (const b of warpButtons) b.classList.toggle("active", Number(b.dataset.rate) === rate);
    warpHeld.hidden = !state.flight.warpAutoLimited;
  }

  return { root, render };
}
