import type { StateResponse, ViewInstance } from "./types";
import { h, post, get, esc, fixed, errText } from "./dom";

// The MANEUVER view — a thin client of the API. Two ways to author a plan, both flowing
// through the same review → EXECUTE gate:
//   • MANUAL: one node — a burn time + Δv in the three orbital-frame axes (the forward
//     calculator; you iterate the numbers).
//   • SOLVERS: deterministic instruments that compute the exact node(s) for a common goal
//     in one click (circularize, set apo/peri, Hohmann, intercept, match-velocity).
// Whatever the SERVER holds pending is what's shown — so a plan the ship-AI proposed appears
// here too (Keystone 1). EXECUTE commits behind a confirm; JUMP TO BURN skips the coast.
// (Docking lives in the TARGET view now.)

const km = (m: number) => fixed(m / 1000, 0);
const min = (s: number) => fixed(s / 60, 1);
const sign = (v: number) => (Number.isFinite(v) ? `${v >= 0 ? "+" : ""}${v.toFixed(0)}` : "—");
const comps = (d: { prograde: number; normal: number; radial: number }) =>
  `${sign(d.prograde)}/${sign(d.normal)}/${sign(d.radial)}`;
const mmss = (s: number) => {
  if (!Number.isFinite(s)) return "--:--";
  const t = Math.max(0, Math.round(s));
  return `${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`;
};
const row = (k: string, v: string) => `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;

const dvInput = (label: string, value: number, step: number) => {
  const input = h("input", { type: "number", step, value }) as HTMLInputElement;
  return { wrap: h("label", { class: "dv-in" }, h("span", {}, label), input), input };
};

export function createManeuverView(): ViewInstance {
  let busy = false;
  let nowT = 0;
  let lastTarget = -1; // seed the TOF field with a sane default whenever the target changes
  let seeding = false;

  const fuel = h("div", { class: "mnv-fuel" });
  const readout = h("div", { class: "mnv-readout" });
  const status = h("div", { class: "mnv-status" });

  // --- manual burn form ---
  const pro = dvInput("PRO", 0, 1);
  const nrm = dvInput("NRM", 0, 1);
  const rad = dvInput("RAD", 0, 1);
  const tIn = dvInput("T+ s", 0, 10);
  const planBtn = h("button", { type: "submit", class: "mnv-plan-btn" }, "PLAN");
  const form = h("form", { autocomplete: "off" }, pro.wrap, nrm.wrap, rad.wrap, tIn.wrap, planBtn);

  // --- solvers ---
  const alt = dvInput("ALT km", 800, 10);
  const tof = dvInput("TOF min", 80, 5);
  const revs = dvInput("REVS", 4, 1); // max full revolutions the intercept transfer may make (default matches the solver)

  // --- actions ---
  const execute = h("button", { type: "button", class: "mnv-execute" }, "EXECUTE BURN") as HTMLButtonElement;
  const jump = h("button", { type: "button", class: "mnv-jump", hidden: true }, "JUMP TO BURN") as HTMLButtonElement;
  const cancel = h("button", { type: "button" }, "CANCEL") as HTMLButtonElement;
  const actions = h("div", { class: "mnv-actions", hidden: true }, execute, jump, cancel);

  const plan = async (url: string, body: unknown) => {
    if (busy) return;
    busy = true;
    status.textContent = "computing…";
    try {
      const res = await post(url, body);
      status.textContent = res && res.ok ? "" : `[${res ? await errText(res) : "connection error"}]`;
    } catch {
      status.textContent = "[connection error]";
    } finally {
      busy = false;
    }
  };

  const solverBtn = (label: string, run: () => void) => h("button", { type: "button", onClick: run }, label);
  const altM = () => (Number(alt.input.value) || 0) * 1000;
  const tofS = () => (Number(tof.input.value) || 0) * 60;
  const revsN = () => Math.max(0, Math.round(Number(revs.input.value) || 0));

  // Seed the TOF field with the cheapest time of flight for the now-selected target. Each
  // target's phasing is different, so one fixed TOF can't serve them all — a stale value lands
  // in the pathological band where Lambert demands an absurd burn. Solved at the current REVS
  // cap so the seed reflects the same setting the INTERCEPT button will use.
  const seedTof = async () => {
    if (seeding) return;
    seeding = true;
    try {
      const res = await get(`/api/maneuver/intercept/suggest?revs=${revsN()}`);
      if (res && res.ok) {
        const s = await res.json();
        if (typeof s.tofSeconds === "number") tof.input.value = String(Math.round(s.tofSeconds / 60));
      }
    } catch {
      /* keep whatever's in the field; the operator can still type one */
    } finally {
      seeding = false;
    }
  };

  const solvers = h(
    "div",
    { class: "mnv-solvers" },
    h("div", { class: "mnv-sub" }, "SOLVERS"),
    h(
      "div",
      { class: "solver-row" },
      solverBtn("CIRC@APO", () => void plan("/api/maneuver/circularize", { at: "apoapsis" })),
      solverBtn("CIRC@PERI", () => void plan("/api/maneuver/circularize", { at: "periapsis" })),
    ),
    h(
      "div",
      { class: "solver-row" },
      alt.wrap,
      solverBtn("HOHMANN→", () => void plan("/api/maneuver/hohmann", { targetAltitude: altM() })),
      solverBtn("SET APO", () => void plan("/api/maneuver/set_apsis", { which: "apoapsis", targetAltitude: altM() })),
      solverBtn("SET PERI", () => void plan("/api/maneuver/set_apsis", { which: "periapsis", targetAltitude: altM() })),
    ),
    h(
      "div",
      { class: "solver-row" },
      tof.wrap,
      revs.wrap,
      solverBtn("INTERCEPT TGT", () => void plan("/api/maneuver/intercept", { tof: tofS(), revs: revsN() })),
      solverBtn("MATCH VEL", () => void plan("/api/maneuver/match", {})),
    ),
  );

  const scroll = h(
    "div",
    { class: "scrollarea maneuver" },
    fuel,
    h("div", { class: "mnv-head" }, "MANUAL BURN · ΔV m/s"),
    form,
    solvers,
    readout,
    actions,
    status,
  );
  const root = h("div", { class: "view maneuver-view" }, scroll);

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    void plan("/api/maneuver/plan", {
      time: nowT + (Number(tIn.input.value) || 0),
      prograde: Number(pro.input.value) || 0,
      normal: Number(nrm.input.value) || 0,
      radial: Number(rad.input.value) || 0,
    });
  });

  const action = (url: string, body: unknown, pending: string, done: string) => async () => {
    if (busy) return;
    busy = true;
    status.textContent = pending;
    try {
      const res = await post(url, body);
      status.textContent = res && res.ok ? done : `[${res ? await errText(res) : "connection error"}]`;
    } catch {
      status.textContent = "[connection error]";
    } finally {
      busy = false;
    }
  };
  // Changing the rev cap changes the cheapest TOF — re-seed the field so it stays in sync.
  revs.input.addEventListener("change", () => void seedTof());
  execute.addEventListener("click", action("/api/maneuver/execute", { confirm: true }, "firing…", "burn away."));
  jump.addEventListener("click", action("/api/maneuver/jump", {}, "warping to burn…", "burn complete."));
  cancel.addEventListener("click", action("/api/maneuver/cancel", {}, "aborting…", ""));

  function render(s: StateResponse): void {
    nowT = s.clock.t;
    if (s.target && s.target.index !== lastTarget) {
      lastTarget = s.target.index;
      void seedTof();
    }
    fuel.innerHTML =
      row("PROPELLANT", `${fixed(s.ship.propellantKg, 0)} kg`) + row("ΔV BUDGET", `${fixed(s.ship.dvBudget, 0)} m/s`);

    // 1) A maneuver is armed / flying — show the autopilot + JUMP TO BURN.
    const f = s.flight;
    if (f.executorOn || f.nodes.length > 0) {
      const n = f.nextNode;
      const aligned = f.pointingErrorDeg < 2;
      readout.innerHTML =
        `<div class="mnv-head2">AUTOPILOT${f.warpAutoLimited ? " · WARP HELD" : ""}</div>` +
        (n ? row("NEXT BURN", `${fixed(n.dvMag, 0)} m/s${f.nodes.length > 1 ? ` (+${f.nodes.length - 1})` : ""}`) : "") +
        (n ? row("Δv LEFT", `${fixed(n.dvRemaining, 1)} m/s`) : "") +
        (n ? row("T-MINUS", mmss(n.time - s.clock.t)) : "") +
        row("THROTTLE", `${Math.round(f.throttle * 100)}%`) +
        row("POINTING", aligned ? "ALIGNED" : `${fixed(f.pointingErrorDeg, 0)}° off`);
      actions.hidden = false;
      execute.hidden = true;
      jump.hidden = false;
      return;
    }

    // 2) A planned maneuver awaiting confirmation — show the burns + result + EXECUTE.
    const p = s.pendingManeuver;
    if (p) {
      const multi = p.burns.length > 1;
      const lines = [`<div class="mnv-head2">${esc(p.label.toUpperCase())}</div>`];
      p.burns.forEach((b, i) => {
        const tag = multi ? `BURN ${i + 1} · T+${mmss(b.time - s.clock.t)}` : `T+ ${mmss(b.time - s.clock.t)}`;
        // Retarget nodes (midcourse trims / live velocity match) are computed in flight from the
        // actual state — show that rather than the nominal (often zero) precomputed Δv.
        const val = b.live
          ? b.dvMag < 1
            ? "midcourse trim · in flight"
            : `${comps(b.dvLocal)} · ${fixed(b.dvMag, 0)} m/s · live`
          : `${comps(b.dvLocal)} · ${fixed(b.dvMag, 0)} m/s`;
        lines.push(row(tag, val));
      });
      lines.push(row("TOTAL Δv", `${fixed(p.dvMag, 1)} m/s · ${fixed(p.propellantKg, 0)} kg`));
      if (p.feasible) {
        lines.push(
          row("ΔV AFTER", `${fixed(p.dvBudgetAfter, 0)} m/s`),
          row("RESULT", `apo ${km(p.after.apoapsisAltitude)} · peri ${km(p.after.periapsisAltitude)} km`),
          row("INCLIN.", `${fixed((p.after.i * 180) / Math.PI, 2)}°`),
          row("PERIOD", `${min(p.after.period)} min`),
        );
      } else {
        lines.push(`<div class="mnv-warn">⚠ ${esc(p.note ?? "not feasible")}</div>`);
      }
      readout.innerHTML = lines.join("");
      actions.hidden = false;
      execute.hidden = false;
      execute.disabled = !p.feasible;
      jump.hidden = true;
      return;
    }

    // 3) Idle.
    readout.innerHTML = "";
    actions.hidden = true;
  }

  return { root, render };
}
