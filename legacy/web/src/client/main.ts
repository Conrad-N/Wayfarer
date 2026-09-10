import "./style.css";
import { VIEWS } from "./registry";
import { createSlot } from "./slot";
import type { StateResponse } from "./types";

// Four fixed slots; each can show ANY view via its switcher (the "any display in any
// panel" system). The default layout keeps the four you fly with up — NAV / FLIGHT /
// MANEUVER / TARGET — with CARGO and the AI console one switch away. Duplicates are fine.
const DEFAULT_LAYOUT = ["nav", "flight", "maneuver", "target"];

const console_ = document.getElementById("console")!;
const slots = DEFAULT_LAYOUT.map((id) => createSlot(VIEWS, id));
for (const s of slots) console_.append(s.element);

// The client never computes truth — it polls the read API and hands the state to every
// mounted view (docs/03).
async function poll(): Promise<void> {
  try {
    const res = await fetch("/api/state");
    if (!res.ok) return;
    const state = (await res.json()) as StateResponse;
    for (const s of slots) s.render(state);
  } catch {
    /* transient — try again next tick */
  }
}
setInterval(poll, 100);
void poll();
