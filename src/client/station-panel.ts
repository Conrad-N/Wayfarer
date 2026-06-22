import type { CargoItemSummary, StateResponse, ViewInstance } from "./types";
import { h, post, fixed, errText } from "./dom";

// The STATION view — what you DO once docked (docs/03 §M1). Right now that's cargo
// transfer: a two-column ledger (your hold ↔ the station's hold) with LOAD/UNLOAD, and a
// live mass/Δv strip so you watch the budget move as inert mass comes aboard. It's the home
// for future docked services (refuel, repair, trade) — see the docking-system note.
//
// When adrift, the controls stay VISIBLE but disabled (the operator's house style: show the
// goal greyed out, not hidden). A target with no hold (a probe) says so.

const row = (k: string, v: string) => `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;
const t = (kg: number) => fixed(kg / 1000, 2); // tonnes

export function createStationView(): ViewInstance {
  let busy = false;
  let sig = ""; // rebuild the item rows only when the holds actually change

  const dockLine = h("div", { class: "stn-dock" });
  const meter = h("div", { class: "stn-meter" });
  const shipCol = h("div", { class: "stn-col" });
  const storeCol = h("div", { class: "stn-col" });
  const cols = h(
    "div",
    { class: "stn-cols" },
    h("div", { class: "stn-colwrap" }, h("div", { class: "stn-colhead" }, "YOUR HOLD"), shipCol),
    h("div", { class: "stn-colwrap" }, h("div", { class: "stn-colhead" }, "STATION"), storeCol),
  );
  const status = h("div", { class: "stn-status" });

  const scroll = h("div", { class: "scrollarea station" }, dockLine, meter, cols, status);
  const root = h("div", { class: "view station-view" }, scroll);

  const transfer = (direction: "load" | "unload", itemId: string) => async () => {
    if (busy) return;
    busy = true;
    status.textContent = direction === "load" ? "loading…" : "unloading…";
    try {
      const res = await post("/api/cargo/transfer", { direction, itemId, qty: 1 });
      status.textContent = res && res.ok ? "" : `[${res ? await errText(res) : "connection error"}]`;
    } catch {
      status.textContent = "[connection error]";
    } finally {
      busy = false;
      sig = ""; // reflect the move on the next render even before the poll catches up
    }
  };

  // One side's rows. `enabled(item)` decides whether its button is live; a placeholder
  // line stands in for an empty (or unavailable) hold.
  function buildCol(
    col: HTMLElement,
    items: CargoItemSummary[],
    direction: "load" | "unload",
    placeholder: string,
    enabled: (it: CargoItemSummary) => boolean,
  ): void {
    if (items.length === 0) {
      col.replaceChildren(h("div", { class: "stn-empty" }, placeholder));
      return;
    }
    col.replaceChildren(
      ...items.map((it) => {
        const btn = h(
          "button",
          { type: "button", class: "stn-btn" },
          direction === "load" ? "◂ LOAD" : "UNLOAD ▸",
        ) as HTMLButtonElement;
        btn.disabled = !enabled(it);
        btn.addEventListener("click", transfer(direction, it.id));
        return h(
          "div",
          { class: "stn-row" },
          h("span", { class: "stn-name" }, it.name),
          h("span", { class: "stn-qty" }, `${it.qty} × ${it.massKg}kg · ${it.volumeM3}m³`),
          btn,
        );
      }),
    );
  }

  function render(s: StateResponse): void {
    const { station: st, cargo, ship } = s;
    const docked = st.docked;
    const tradable = docked && st.hasHold;

    dockLine.textContent = docked
      ? st.hasHold
        ? `◉ DOCKED · ${st.name}`
        : `◉ DOCKED · ${st.name} — no cargo hold`
      : "NO DOCK — approach and dock with a target to trade";
    dockLine.classList.toggle("off", !docked);

    // Live mass/Δv strip — the whole point: watch Δv fall as you load inert mass.
    meter.innerHTML =
      row("CARGO", `${t(cargo.usedKg)} / ${t(cargo.capacityKg)} t`) +
      row("FREE MASS", `${t(cargo.freeKg)} t`) +
      row("FREE VOLUME", `${fixed(cargo.freeM3, 1)} / ${fixed(cargo.capacityM3, 1)} m³`) +
      row("SHIP MASS", `${t(ship.massKg)} t`) +
      `<div class="rule"></div>` +
      row("Δv BUDGET", `${fixed(ship.dvBudget, 0)} m/s`);

    const newSig = JSON.stringify({
      docked,
      hold: st.hasHold,
      free: cargo.freeKg,
      freeVol: cargo.freeM3,
      ship: cargo.items.map((i) => [i.id, i.qty]),
      store: st.inventory.map((i) => [i.id, i.qty]),
    });
    if (newSig !== sig) {
      sig = newSig;
      buildCol(shipCol, cargo.items, "unload", "hold empty", () => tradable);
      buildCol(
        storeCol,
        st.inventory,
        "load",
        docked ? "nothing to trade" : "—",
        // A unit must fit BOTH limits to load — mass and volume.
        (it) => tradable && cargo.freeKg >= it.massKg && cargo.freeM3 >= it.volumeM3,
      );
    }
  }

  return { root, render };
}
