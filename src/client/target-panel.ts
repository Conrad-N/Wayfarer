import type { StateResponse, TargetState, ViewInstance } from "./types";
import { h, post, esc, fixed, errText } from "./dom";

// The TARGET view — pick a rendezvous target from the roster, read its relative state, and
// dock. The selector POSTs /api/target/select; the rest of the ship (telemetry, solvers,
// nav-ball marker) then follows that choice. DOCK is DISABLED (not hidden) until you're in
// the envelope — so the operator can always see the goal, greyed out, and watch it arm.

const row = (k: string, v: string) => `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;
const km = (m: number) => fixed(m / 1000, 2);
const min = (s: number) => fixed(s / 60, 1);

const KIND_TAG: Record<string, string> = { station: "STATION", depot: "DEPOT", probe: "PROBE" };

export function createTargetView(): ViewInstance {
  let busy = false;
  let optionCount = -1;

  const select = h("select", { class: "tgt-select" }) as HTMLSelectElement;
  const selectRow = h("div", { class: "tgt-select-row" }, h("span", { class: "label" }, "TARGET"), select);
  const readout = h("div", { class: "tgt-readout" });

  const dockBtn = h("button", { type: "button", class: "dock-btn" }, "◉ DOCK") as HTMLButtonElement;
  const undockBtn = h("button", { type: "button", class: "undock-btn", hidden: true }, "UNDOCK") as HTMLButtonElement;
  const dockState = h("span", { class: "dock-state" });
  const dockRow = h("div", { class: "tgt-dock" }, dockBtn, undockBtn, dockState);
  const status = h("div", { class: "tgt-status" });

  const scroll = h("div", { class: "scrollarea target" }, selectRow, readout, dockRow, status);
  const root = h("div", { class: "view target-view" }, scroll);

  const act = (url: string, body: unknown, pending: string, done: string) => async () => {
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
  dockBtn.addEventListener("click", act("/api/dock", {}, "docking…", "docked."));
  undockBtn.addEventListener("click", act("/api/undock", {}, "casting off…", ""));
  select.addEventListener("change", () => void act("/api/target/select", { index: Number(select.value) }, "", "")());

  function render(s: StateResponse): void {
    // (Re)build the option list only when the roster changes (it's static at runtime, so
    // this runs once). Rebuilding every tick would fight an open native dropdown.
    if (s.targets.length !== optionCount) {
      select.replaceChildren(
        ...s.targets.map((t) => h("option", { value: t.index }, `${t.name} · ${km(t.altitude)} km`)),
      );
      optionCount = s.targets.length;
    }
    if (document.activeElement !== select) select.value = String(s.target.index);

    const t: TargetState = s.target;
    const o = t.orbit;
    readout.innerHTML =
      row("DESIGNATION", esc(t.name)) +
      row("TYPE", esc(KIND_TAG[t.kind] ?? t.kind.toUpperCase())) +
      `<div class="rule"></div>` +
      row("RANGE", `${km(t.range)} km`) +
      row("CLOSING", `${fixed(t.closingSpeed, 1)} m/s`) +
      row("REL SPEED", `${fixed(t.relSpeed, 1)} m/s`) +
      `<div class="rule"></div>` +
      row("ALTITUDE", `${km(t.altitude)} km`) +
      row("APOAPSIS", `${km(o.apoapsisAltitude)} km`) +
      row("PERIAPSIS", `${km(o.periapsisAltitude)} km`) +
      row("INCLINATION", `${fixed((o.i * 180) / Math.PI, 2)}°`) +
      row("PERIOD", `${min(t.period)} min`);

    // DOCK affordance — always visible, enabled only inside the envelope.
    if (t.docked) {
      dockBtn.hidden = true;
      undockBtn.hidden = false;
      dockState.textContent = "◉ DOCKED";
    } else {
      undockBtn.hidden = true;
      dockBtn.hidden = false;
      dockBtn.disabled = !t.canDock;
      dockState.textContent = t.canDock
        ? "in docking envelope"
        : `need < 1.00 km · < 5.0 m/s (now ${km(t.range)} km · ${fixed(t.relSpeed, 1)} m/s)`;
    }
  }

  return { root, render };
}
