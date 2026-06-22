import type { StateResponse, ViewInstance } from "./types";
import { h, esc, fixed } from "./dom";

// The CARGO HOLD view — your hold as live instrumentation: the manifest, a capacity bar,
// and the mass breakdown that drives Δv. Read-only; transfers happen at the STATION panel
// (keep one open beside this to watch the budget move as you load). Pairs with docs/03 §M1.

const row = (k: string, v: string) => `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;
const t = (kg: number) => fixed(kg / 1000, 2); // tonnes
const m3 = (v: number) => fixed(v, 1); // cubic metres

export function createCargoView(): ViewInstance {
  const manifest = h("div", { class: "cargo-manifest" });
  const massBar = h("div", { class: "cargo-bar" }, h("div", { class: "cargo-bar-fill" }));
  const massFill = massBar.querySelector(".cargo-bar-fill") as HTMLElement;
  const volBar = h("div", { class: "cargo-bar" }, h("div", { class: "cargo-bar-fill" }));
  const volFill = volBar.querySelector(".cargo-bar-fill") as HTMLElement;
  const summary = h("div", { class: "cargo-summary" });

  const scroll = h(
    "div",
    { class: "scrollarea cargo" },
    h("div", { class: "cargo-head" }, "CARGO MANIFEST"),
    manifest,
    h("div", { class: "cargo-barlabel" }, "MASS"),
    massBar,
    h("div", { class: "cargo-barlabel" }, "VOLUME"),
    volBar,
    summary,
  );
  const root = h("div", { class: "view cargo-view" }, scroll);

  function render(s: StateResponse): void {
    const { cargo, ship } = s;

    manifest.innerHTML = cargo.items.length
      ? cargo.items.map((it) => row(`${esc(it.name)} ×${it.qty}`, `${t(it.totalKg)} t · ${m3(it.totalM3)} m³`)).join("")
      : `<div class="cargo-empty">hold empty</div>`;

    const massPct = cargo.capacityKg > 0 ? Math.min(100, (cargo.usedKg / cargo.capacityKg) * 100) : 0;
    massFill.style.width = `${massPct}%`;
    massFill.classList.toggle("full", massPct > 99.5);

    const volPct = cargo.capacityM3 > 0 ? Math.min(100, (cargo.usedM3 / cargo.capacityM3) * 100) : 0;
    volFill.style.width = `${volPct}%`;
    volFill.classList.toggle("full", volPct > 99.5);

    summary.innerHTML =
      row("MASS", `${t(cargo.usedKg)} / ${t(cargo.capacityKg)} t`) +
      row("VOLUME", `${m3(cargo.usedM3)} / ${m3(cargo.capacityM3)} m³`) +
      `<div class="rule"></div>` +
      row("DRY MASS", `${t(ship.dryMassKg)} t`) +
      row("CARGO MASS", `${t(ship.cargoKg)} t`) +
      row("PROPELLANT", `${t(ship.propellantKg)} t`) +
      row("TOTAL MASS", `${t(ship.massKg)} t`) +
      `<div class="rule"></div>` +
      row("Δv BUDGET", `${ship.dvBudget.toFixed(0)} m/s`);
  }

  return { root, render };
}
