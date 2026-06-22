import type { FlightState, StateResponse, ViewInstance } from "./types";
import { h, post } from "./dom";
import { drawNavball } from "./navball";

// The FLIGHT view (docs/10 §10 Stage 3): nav ball + throttle + attitude-mode buttons +
// the executor toggle. A thin client of the one API — every control POSTs to /api/flight/*
// and the displayed state is read back from the poll. Grabbing the throttle or an attitude
// button releases the autopilot (the server does that); the view just reflects the state.

const ATT_MODES: Array<[string, string]> = [
  ["prograde", "PRO"],
  ["retrograde", "RET"],
  ["normal", "NML"],
  ["antinormal", "NML−"],
  ["radialOut", "R·OUT"],
  ["radialIn", "R·IN"],
  ["target", "TGT"],
  ["antiTarget", "TGT−"],
  ["node", "NODE"],
  ["kill", "KILL"],
];

const row = (k: string, v: string) => `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;
const clamp01 = (x: number) => Math.max(0, Math.min(1, x));
const mag = (v: { x: number; y: number; z: number }) => Math.hypot(v.x, v.y, v.z);

export function createFlightView(): ViewInstance {
  const navball = h("canvas", { class: "navball", width: 240, height: 240 }) as HTMLCanvasElement;
  const hud = h("div", { class: "flight-hud" });

  const fill = h("div", { class: "thr-fill" });
  const handle = h("div", { class: "thr-handle" });
  const track = h("div", { class: "thr-track" }, fill, handle);
  const valEl = h("div", { class: "thr-val" }, "0%");
  const throttle = h("div", { class: "throttle" }, h("div", { class: "thr-cap" }, "THR"), track, valEl);

  const attButtons = ATT_MODES.map(([mode, label]) =>
    h("button", { type: "button", "data-mode": mode, onClick: () => void post("/api/flight/attitude", { mode }) }, label),
  );
  const exec = h("button", { type: "button", class: "exec-toggle" }, "▶ AUTOPILOT") as HTMLButtonElement;
  const attitude = h("div", { class: "attitude" }, h("div", { class: "att-grid" }, ...attButtons), exec);
  const controls = h("div", { class: "flight-controls" }, throttle, attitude);

  const scroll = h(
    "div",
    { class: "scrollarea" },
    h("div", { class: "navball-wrap" }, navball),
    hud,
    controls,
  );
  const root = h("div", { class: "view flight-view" }, scroll);

  // --- throttle drag ---
  let dragging = false;
  let lastSent = -1;
  const throttleAt = (clientY: number): number => {
    const r = track.getBoundingClientRect();
    return clamp01((r.bottom - clientY) / r.height);
  };
  const sendThrottle = (t: number) => {
    const q = Math.round(t * 100) / 100;
    if (q === lastSent) return;
    lastSent = q;
    void post("/api/flight/throttle", { throttle: q });
  };
  const paintThrottle = (t: number) => {
    const pct = Math.round(clamp01(t) * 100);
    fill.style.height = `${pct}%`;
    handle.style.bottom = `${pct}%`;
    valEl.textContent = `${pct}%`;
  };
  track.addEventListener("pointerdown", (e) => {
    dragging = true;
    track.setPointerCapture(e.pointerId);
    const t = throttleAt(e.clientY);
    paintThrottle(t);
    sendThrottle(t);
  });
  track.addEventListener("pointermove", (e) => {
    if (!dragging) return;
    const t = throttleAt(e.clientY);
    paintThrottle(t);
    sendThrottle(t);
  });
  const endDrag = (e: PointerEvent) => {
    if (!dragging) return;
    dragging = false;
    try {
      track.releasePointerCapture(e.pointerId);
    } catch {
      /* already released */
    }
  };
  track.addEventListener("pointerup", endDrag);
  track.addEventListener("pointercancel", endDrag);

  // executor toggle — flips against the last-rendered state
  let executorOn = false;
  exec.addEventListener("click", () => void post("/api/flight/executor", { on: !executorOn }));

  function render(state: StateResponse): void {
    const f: FlightState = state.flight;
    drawNavball(navball, f, state.target);
    executorOn = f.executorOn;

    // While dragging, the operator's hand owns the slider; otherwise follow the server.
    if (!dragging) {
      lastSent = -1;
      paintThrottle(f.throttle);
    }

    const aligned = f.pointingErrorDeg < 1.5;
    const omegaDeg = mag(f.angularVel) * (180 / Math.PI);
    hud.innerHTML =
      row("POINTING", aligned ? "ALIGNED" : `${f.pointingErrorDeg.toFixed(1)}° off`) +
      row("RATE", `${omegaDeg.toFixed(1)}°/s`) +
      row("THROTTLE", `${Math.round(f.throttle * 100)}%${f.warpAutoLimited ? " · WARP HELD" : ""}`);

    for (const btn of attButtons) {
      btn.classList.toggle("active", !f.executorOn && btn.dataset.mode === f.attitudeMode);
    }
    exec.classList.toggle("active", f.executorOn);
    exec.textContent = f.executorOn ? "■ AUTOPILOT ON" : "▶ AUTOPILOT";
  }

  return { root, render };
}
