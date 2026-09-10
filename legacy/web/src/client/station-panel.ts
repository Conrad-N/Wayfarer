import type { MarketItemSummary, StateResponse, ViewInstance } from "./types";
import { h, post, fixed, errText } from "./dom";

// The STATION view — what you DO once docked (docs/03 §M1, docs/02 §Stations). It's now a
// MARKET: a price sheet of the station's goods, each with a BUY (load, pays the ask) and a
// SELL (unload, earns the bid). Trading moves inert mass too, so a live mass/Δv strip plus
// the wallet sit on top — you watch credits and Δv move with every trade. Prices differ by
// station (static), so the play is buy cheap here, sell dear there (arbitrage).
//
// When adrift, the controls stay VISIBLE but disabled (the operator's house style: show the
// goal greyed out, not hidden). A target with no market (a probe) says so.

const row = (k: string, v: string) => `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`;
const t = (kg: number) => fixed(kg / 1000, 2); // tonnes

export function createStationView(): ViewInstance {
  let busy = false;
  let sig = ""; // rebuild the market rows only when the holds/wallet actually change

  const dockLine = h("div", { class: "stn-dock" });
  const meter = h("div", { class: "stn-meter" });
  const marketHead = h("div", { class: "stn-colhead" }, "MARKET — BUY ◂ ask · SELL ▸ bid");
  const market = h("div", { class: "stn-col" });
  const status = h("div", { class: "stn-status" });

  const scroll = h("div", { class: "scrollarea station" }, dockLine, meter, marketHead, market, status);
  const root = h("div", { class: "view station-view" }, scroll);

  const trade = (direction: "load" | "unload", itemId: string) => async () => {
    if (busy) return;
    busy = true;
    status.textContent = direction === "load" ? "buying…" : "selling…";
    try {
      const res = await post("/api/cargo/transfer", { direction, itemId, qty: 1 });
      if (res && res.ok) {
        const data = await res.json().catch(() => null);
        status.textContent =
          data && typeof data.totalCr === "number"
            ? `${direction === "load" ? "bought" : "sold"} ${data.moved} ${itemId} · ${direction === "load" ? "−" : "+"}${data.totalCr} Cr`
            : "";
      } else {
        status.textContent = `[${res ? await errText(res) : "connection error"}]`;
      }
    } catch {
      status.textContent = "[connection error]";
    } finally {
      busy = false;
      sig = ""; // reflect the move on the next render even before the poll catches up
    }
  };

  // One market row: name, a stock/held detail line, and BUY/SELL buttons priced inline.
  // `held` is how many of this good the ship carries (for the SELL gate + the detail line).
  function marketRow(it: MarketItemSummary, held: number, canBuy: boolean, canSell: boolean): HTMLElement {
    const buy = h("button", { type: "button", class: "stn-btn buy" }, `BUY ◂ ${it.askCr}`) as HTMLButtonElement;
    buy.disabled = !canBuy;
    buy.addEventListener("click", trade("load", it.id));
    const sell = h("button", { type: "button", class: "stn-btn sell" }, `SELL ▸ ${it.bidCr}`) as HTMLButtonElement;
    sell.disabled = !canSell;
    sell.addEventListener("click", trade("unload", it.id));
    return h(
      "div",
      { class: "stn-mrow" },
      h("span", { class: "stn-name" }, it.name),
      h("span", { class: "stn-qty" }, `stock ${it.qty} · hold ${held} · ${it.massKg}kg ${it.volumeM3}m³`),
      buy,
      sell,
    );
  }

  function render(s: StateResponse): void {
    const { station: st, cargo, ship } = s;
    const docked = st.docked;
    const tradable = docked && st.hasHold;

    dockLine.textContent = docked
      ? st.hasHold
        ? `◉ DOCKED · ${st.name}`
        : `◉ DOCKED · ${st.name} — no market`
      : "NO DOCK — approach and dock with a target to trade";
    dockLine.classList.toggle("off", !docked);

    // The wallet + the mass/Δv strip — watch credits and the budget move as you trade.
    meter.innerHTML =
      row("CREDITS", `${Math.floor(cargo.creditsCr)} Cr`) +
      `<div class="rule"></div>` +
      row("CARGO", `${t(cargo.usedKg)} / ${t(cargo.capacityKg)} t`) +
      row("FREE MASS", `${t(cargo.freeKg)} t`) +
      row("FREE VOLUME", `${fixed(cargo.freeM3, 1)} / ${fixed(cargo.capacityM3, 1)} m³`) +
      `<div class="rule"></div>` +
      row("Δv BUDGET", `${fixed(ship.dvBudget, 0)} m/s`);

    const heldOf = (id: string) => cargo.items.find((i) => i.id === id)?.qty ?? 0;

    const newSig = JSON.stringify({
      docked,
      hold: st.hasHold,
      credits: Math.floor(cargo.creditsCr),
      free: cargo.freeKg,
      freeVol: cargo.freeM3,
      ship: cargo.items.map((i) => [i.id, i.qty]),
      store: st.inventory.map((i) => [i.id, i.qty, i.askCr, i.bidCr]),
    });
    if (newSig !== sig) {
      sig = newSig;
      if (!tradable || st.inventory.length === 0) {
        market.replaceChildren(
          h("div", { class: "stn-empty" }, docked ? "no goods traded here" : "—"),
        );
      } else {
        market.replaceChildren(
          ...st.inventory.map((it) => {
            const held = heldOf(it.id);
            // BUY needs stock, money, and room for one unit (both limits). SELL needs you to
            // carry the good and the station to price it (every listed good is priced).
            const canBuy =
              it.qty > 0 && cargo.creditsCr >= it.askCr && cargo.freeKg >= it.massKg && cargo.freeM3 >= it.volumeM3;
            const canSell = held > 0 && it.bidCr > 0;
            return marketRow(it, held, canBuy, canSell);
          }),
        );
      }
    } else {
      // The signature is unchanged, but the per-good prices in the labels never change, so the
      // only live thing is button enablement — refresh it cheaply without rebuilding the DOM.
      const rows = market.querySelectorAll<HTMLElement>(".stn-mrow");
      st.inventory.forEach((it, idx) => {
        const r = rows[idx];
        if (!r) return;
        const held = heldOf(it.id);
        const buyBtn = r.querySelector<HTMLButtonElement>(".stn-btn.buy");
        const sellBtn = r.querySelector<HTMLButtonElement>(".stn-btn.sell");
        if (buyBtn)
          buyBtn.disabled = !(
            tradable && it.qty > 0 && cargo.creditsCr >= it.askCr && cargo.freeKg >= it.massKg && cargo.freeM3 >= it.volumeM3
          );
        if (sellBtn) sellBtn.disabled = !(tradable && held > 0 && it.bidCr > 0);
      });
    }
  }

  return { root, render };
}
