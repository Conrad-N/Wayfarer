import type { World } from "../sim/world";
import {
  getClock,
  getCentralBody,
  getSystem,
  getShip,
  getOrbit,
  predictOrbit,
  getTarget,
  listTargets,
  selectTarget,
  getFlight,
  planManeuver,
  planCircularize,
  planSetApsis,
  planHohmann,
  planIntercept,
  planTransferWindow,
  planMatchVelocity,
  dock,
  getCargo,
  getStation,
  transferCargo,
  executeManeuver,
  jumpToNextNode,
  jumpToNextSoi,
  setThrottle,
  setAttitudeMode,
  setExecutor,
} from "../sim/api";

// The AI layer (docs/03 Keystone 2 + docs/07 §6). The AI is the conversation
// layer, never the physics layer: it calls tools (which ARE the read API) and
// reasons from the returned numbers. It never computes orbital math itself.
//
// BACKEND: a local Ollama model served over the OpenAI-compatible API
// (http://127.0.0.1:11434/v1) — the same engine that serves the machine's
// coding agent. No cloud credentials, no per-turn billing. Any
// OpenAI-compatible server can stand in: override SHIP_AI_BASE_URL /
// SHIP_AI_MODEL / SHIP_AI_API_KEY. The tool loop below is a plain, explicit
// chat-completions loop: send system + history + the ship tools; when the
// model returns tool_calls, execute them against the live World, append the
// results as tool messages, and send again — until it returns plain text or
// MAX_TURNS is hit.
const BASE_URL = process.env.SHIP_AI_BASE_URL ?? "http://127.0.0.1:11434/v1";
const MODEL = process.env.SHIP_AI_MODEL ?? "qwen3.8:27b-iq4xs";
const API_KEY = process.env.SHIP_AI_API_KEY ?? "ollama";
// Bound the agentic tool loop so a confused turn can't spin.
const MAX_TURNS = Number(process.env.SHIP_AI_MAX_TURNS ?? 12);
// Local inference is slower than an API call; give a turn a long leash.
const REQUEST_TIMEOUT_MS = Number(process.env.SHIP_AI_TIMEOUT_MS ?? 180_000);
export { BASE_URL as AI_BASE_URL, MODEL as AI_MODEL };

// The persona system. Voice and BEHAVIOR are kept SEPARATE on purpose: the voice is
// pure flavor (how the AI talks), while BEHAVIOR is the load-bearing contract — call
// tools, never compute physics, convert SI at the edge, and NEVER fire without a
// confirmed gate (docs/03 Keystone 2 + docs/07 §6.3). Every persona gets the same
// BEHAVIOR appended, so swapping voices can never loosen the safety discipline.
interface Persona {
  id: string;
  label: string;
  voice: string;
}

const PERSONAS: Persona[] = [
  {
    id: "officer",
    label: "Flight Officer",
    voice: `You are the onboard AI of a small spacecraft, the "Wayfarer". You speak to the
operator over a text console: terse, precise, calm — a competent crewmate, not a
chatbot. Keep replies short. Plain text only — never use emojis.`,
  },
  {
    id: "bushpilot",
    label: "Old Spacer",
    voice: `You are the onboard AI of the Wayfarer, but you carry yourself like a grizzled
old deep-space bush pilot — forty years hauling ore through the black, seen every
way a ship can bite you. Warm, folksy, dryly funny. Call the operator "skipper" or
"cap". Drop the occasional spacer's saying. But underneath the drawl you are a real
crewmate: when it counts you're sharp and exact, and you NEVER clown around with the
numbers or the safety gate. Keep replies short. Plain text only — never use emojis.`,
  },
];

function personaById(id?: string): Persona {
  return PERSONAS.find((p) => p.id === id) ?? PERSONAS[0];
}

/** The roster the client renders in its persona dropdown. */
export const PERSONA_LIST = PERSONAS.map(({ id, label }) => ({ id, label }));
export const DEFAULT_PERSONA = PERSONAS[0].id;

// Shared behavioral contract — appended after whichever persona voice is active.
const BEHAVIOR = `You have instruments, not intuition. To answer anything about the ship's orbit,
time, or the bodies around you, CALL YOUR TOOLS and reason from the returned numbers.
Never estimate orbital quantities in your head.

Returned values are SI: meters, seconds, radians. Present them in operator-friendly
units (km, minutes, degrees) and say which. Always distinguish ALTITUDE (height
above the surface) from RADIUS (distance from the body's center). Use get_ship for
mass, propellant, and remaining Δv budget.

The sim is PATCHED CONICS: you orbit exactly ONE body at a time (its sphere of influence),
and your orbit is measured relative to THAT body. get_central_body tells you which body you're
in and its SOI radius; get_system lists every body (the star and its planets) and the next SOI
handoff ahead. Your central body CHANGES when you leave one SOI and enter another — so an
altitude only means something against the current body. To go to another PLANET, use
solve_transfer_window: from INSIDE your current body's SOI, select the destination planet (it's in
list_targets) and call it — it plans the WHOLE trip in one guided plan (a self-sized ejection burn,
midcourse trims, and an arrival match that captures you into the destination's SOI). You do NOT
escape by hand first; the planner sizes the ejection so you can't overshoot. Use jump_to_next_node
to warp to the (months-out) departure and jump_to_next_soi to skip a long coast to a boundary;
warp auto-limits near handoffs and burns.

When DOCKED you can TRADE: get_station lists the market (each good's ask = buy price and
bid = sell price, in credits Cr), get_cargo lists your hold + your wallet, transfer_cargo
trades it. Loading is a BUY (debits credits at the ask); unloading is a SELL (credits the
wallet at the bid). A station only buys goods it prices; prices differ by station, so the
play is buy cheap at one, sell dear at another (arbitrage). Cargo is also inert mass —
loading LOWERS your Δv budget, unloading RAISES it; quantify with get_ship when it matters.
The hold has two limits — mass (kg) and volume (m³) — and a buy stops at whichever binds
first: stock, mass, volume, or credits.

You can also fly the ship — burns are REAL and take time: the ship turns to its burn
vector and thrusts for tens of seconds. You change the orbit by authoring a maneuver
NODE: a time plus a Δv in three perpendicular orbital-frame axes —
  • prograde (+) / retrograde (−): along velocity — raises/lowers the OPPOSITE apsis.
  • normal (+) / antinormal (−): out of plane — changes inclination.
  • radial-out (+) / radial-in (−): toward/away from the planet — rotates the orbit.
For COMMON goals, use a SOLVER — it computes the exact burn in one call (faster and exact):
  • solve_circularize(at) — circularize at the next apoapsis/periapsis.
  • solve_set_apsis(which, altitude) — set apoapsis or periapsis to a target altitude.
  • solve_hohmann(altitude) — two-burn transfer to a circular orbit at a target altitude.
  • solve_intercept(tof?) — RENDEZVOUS with the SELECTED target (get_target). Call it with NO
    time of flight to auto-pick the cheapest; pass one only to hand-tune. Use list_targets +
    select_target to choose. NOTE: intercept needs a CO-FRAME target — get_target.sameFrame must
    be true (the target orbits the same body you do). A planet in another SOI shows sameFrame:false;
    escape your current body first, then it becomes interceptable.
  • solve_match_velocity — stop alongside the target (terminal approach). The intercept is
    closed-loop (it flies midcourse trims + a live velocity match), so ONE intercept usually
    lands inside the dock envelope; use match only to trim residual drift, then dock.
  • solve_transfer_window — plan a full INTERPLANETARY trip to the selected planet from inside
    your current SOI (sizes the ejection burn for you; the departure is usually months out).
Reach for plan_maneuver (the FORWARD CALCULATOR) only for burns no solver covers — e.g. a
plane change, or a custom mix. It does NOT find the burn for a goal: you give it a burn (time
+ prograde/normal/radial Δv), it returns the cost and resulting orbit; reason about WHICH way
to burn, preview, READ the result, and adjust until it matches. That judgment is yours.

Then plan → review → execute:
1. A solver or plan_maneuver PROPOSES a plan (does NOT fire the engine). Iterate until right.
2. Relay the proposal in plain terms and ASK the operator to confirm.
3. Only AFTER they explicitly say yes, call execute_maneuver(confirm=true). That lays
   the node and ARMS THE AUTOPILOT to fly it — orient, throttle up, cut off at the
   planned Δv. Use jump_to_next_node to warp to the burn window (or tell the operator to
   warp). Watch progress with get_flight.
You can also hand-fly: set_attitude_mode (prograde/retrograde/normal/radial/kill) and
set_throttle (0..1) — these release the autopilot. set_executor re-engages or stops it.
Never fire without explicit confirmation. If a burn won't fit the Δv budget, say so and
offer the best achievable result.

If a tool call returns an error object, report the failure plainly and never invent results
a tool did not give you. Call get_clock before predicting future positions.`;

// The ship's tools — one per API function (Keystone 1: the AI's tools ARE the ship
// API). A plain name/description/schema/run tuple so the loop below can execute
// them directly against the live World (the sim advances between requests).
interface ShipTool {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
  run: (args: Record<string, unknown>) => unknown;
}

const obj = (
  properties: Record<string, unknown>,
  required: string[] = [],
): Record<string, unknown> => ({
  type: "object",
  properties,
  ...(required.length ? { required } : {}),
});

function shipTools(world: World): ShipTool[] {
  return [
    {
      name: "get_clock",
      description: "Current simulation time (seconds) and the time-warp rate.",
      parameters: obj({}),
      run: () => getClock(world),
    },
    {
      name: "get_central_body",
      description:
        "Physical parameters of the body you are CURRENTLY orbiting (id, name, mu, radius), its " +
        "parent body, and its sphere-of-influence radius (null for the star). Which body this " +
        "is changes as you cross SOI boundaries — always check it before reasoning about altitude.",
      parameters: obj({}),
      run: () => getCentralBody(world),
    },
    {
      name: "get_system",
      description:
        "The whole solar system (patched conics): every body — the star and its planets — with " +
        "mu, radius, sphere-of-influence radius, parent, and current heliocentric position; " +
        "plus which body you currently orbit and the next SOI handoff ahead (escape or capture) " +
        "with its time. Use to plan interplanetary travel and answer 'what bodies are out there'.",
      parameters: obj({}),
      run: () => getSystem(world),
    },
    {
      name: "get_ship",
      description:
        "The ship's identity and propulsion state: total/dry mass (kg), propellant " +
        "remaining (kg), specific impulse (s), and the remaining Δv budget (m/s).",
      parameters: obj({}),
      run: () => getShip(world),
    },
    {
      name: "get_flight",
      description:
        "Flight state: attitude/pointing, throttle, the autopilot (executor) status, the " +
        "orbital-frame markers, and the maneuver-node queue with Δv remaining.",
      parameters: obj({}),
      run: () => getFlight(world),
    },
    {
      name: "get_orbit",
      description:
        "The ship's complete current orbital state (SI): elements, anomalies, " +
        "apoapsis/periapsis radius and altitude, current radius/altitude/speed, " +
        "period, latitude, times to periapsis/apoapsis, and the PCI state vector.",
      parameters: obj({}),
      run: () => getOrbit(world),
    },
    {
      name: "get_target",
      description:
        "The SELECTED rendezvous target and the relative state: name, range (m), closing " +
        "speed (m/s, positive = approaching), and its current orbit. The solvers " +
        "(intercept / match-velocity) and the dock all act on this target. Use this to " +
        "answer 'how far is the target' and to plan a rendezvous.",
      parameters: obj({}),
      run: () => getTarget(world),
    },
    {
      name: "list_targets",
      description:
        "Every available rendezvous target with its altitude, period, and current range " +
        "from the ship, and which one is selected. Use to answer 'what can I dock with' " +
        "and to pick a target before solving a rendezvous.",
      parameters: obj({}),
      run: () => listTargets(world),
    },
    {
      name: "select_target",
      description:
        "Choose which target the telemetry, the rendezvous solvers, and the dock follow. " +
        "Call before solve_intercept / solve_match_velocity / dock if the operator names a " +
        "different target. Pass its index from list_targets.",
      parameters: obj(
        { index: { type: "number", description: "Target index from list_targets (0-based)." } },
        ["index"],
      ),
      run: (a) => selectTarget(world, Number(a.index)),
    },
    {
      name: "predict_orbit",
      description:
        "The ship's orbital state at a future or past simulation time. Use this to " +
        "answer questions like 'where will I be in 40 minutes' or 'when am I next " +
        "over the pole'. Call get_clock first to learn the current time.",
      parameters: obj(
        { t: { type: "number", description: "Absolute simulation time in seconds." } },
        ["t"],
      ),
      run: (a) => predictOrbit(world, Number(a.t)),
    },
    {
      name: "plan_maneuver",
      description:
        "Preview a single maneuver NODE — a burn at a chosen time with a Δv split across " +
        "the three orbital-frame axes. This is a FORWARD CALCULATOR, not a goal-seeking " +
        "solver: you supply the burn, it returns the Δv magnitude, propellant cost, " +
        "remaining Δv budget, and the resulting orbit (apo/peri/inclination). It does NOT " +
        "fire the engine. To reach a target orbit, iterate: preview, read the result, " +
        "adjust the numbers, preview again — then present it and wait for explicit " +
        "operator confirmation before execute_maneuver.",
      parameters: obj(
        {
          time_s: {
            type: "number",
            description:
              "Absolute simulation time the burn fires, in SECONDS. Call get_clock for 'now'; add seconds to burn later.",
          },
          prograde_ms: {
            type: "number",
            description: "Δv along velocity, m/s. + = prograde (raises the opposite apsis), − = retrograde.",
          },
          normal_ms: {
            type: "number",
            description: "Δv along the orbit normal, m/s. Changes inclination / plane. + = normal, − = antinormal.",
          },
          radial_ms: {
            type: "number",
            description: "Δv along radial-out, m/s. + = away from the planet, − = toward it.",
          },
        },
        ["time_s"],
      ),
      run: (a) =>
        planManeuver(world, {
          time: Number(a.time_s),
          dvLocal: {
            prograde: Number(a.prograde_ms) || 0,
            normal: Number(a.normal_ms) || 0,
            radial: Number(a.radial_ms) || 0,
          },
        }),
    },
    {
      name: "solve_circularize",
      description:
        "Plan the burn that CIRCULARIZES the orbit at the next apoapsis or periapsis (one " +
        "tangential burn). Proposes only; does NOT fire. Present and wait for confirmation.",
      parameters: obj(
        { at: { enum: ["apoapsis", "periapsis"], description: "Which apsis to circularize at." } },
        ["at"],
      ),
      run: (a) => planCircularize(world, a.at === "periapsis" ? "periapsis" : "apoapsis"),
    },
    {
      name: "solve_set_apsis",
      description:
        "Plan the burn that sets the APOAPSIS or PERIAPSIS to a target altitude (burns at the " +
        "opposite apsis, leaving it fixed). Proposes only; does NOT fire.",
      parameters: obj(
        {
          which: { enum: ["apoapsis", "periapsis"], description: "Which apsis to move." },
          target_altitude_m: {
            type: "number",
            description: "Target altitude above the surface, in METERS. e.g. 800 km = 800000.",
          },
        },
        ["which", "target_altitude_m"],
      ),
      run: (a) => planSetApsis(world, a.which === "periapsis" ? "periapsis" : "apoapsis", Number(a.target_altitude_m)),
    },
    {
      name: "solve_hohmann",
      description:
        "Plan a two-burn HOHMANN transfer to a CIRCULAR orbit at a target altitude (depart " +
        "now, circularize at the far side ~half an orbit later). Assumes a near-circular " +
        "start. Proposes only (both burns, total Δv/fuel); does NOT fire.",
      parameters: obj(
        {
          target_altitude_m: {
            type: "number",
            description: "Target circular altitude above the surface, in METERS. e.g. 800 km = 800000.",
          },
        },
        ["target_altitude_m"],
      ),
      run: (a) => planHohmann(world, Number(a.target_altitude_m)),
    },
    {
      name: "solve_intercept",
      description:
        "Plan a RENDEZVOUS with the target (get_target) using a Lambert intercept: an " +
        "intercept burn that arrives at the target's future position after `tof` seconds, " +
        "then a match-velocity burn. Two burns; handles phasing automatically. OMIT tof_s to " +
        "let the solver auto-pick the cheapest time of flight for this target — the easiest " +
        "first call. Δv depends strongly on the TOF, so to hand-tune, pass one and sweep a " +
        "few. Proposes only; does NOT fire. Returns an error if no solution.",
      parameters: obj({
        tof_s: {
          type: "number",
          description:
            "Time of flight to the rendezvous, in SECONDS (e.g. 70 min = 4200). Omit to auto-pick the cheapest.",
        },
        max_revs: {
          type: "number",
          description:
            "Max full revolutions the transfer may make (default 4). 0 forces a direct arc; more loops can find a cheaper transfer for a poorly-phased target.",
        },
      }),
      run: (a) =>
        planIntercept(world, a.tof_s === undefined ? undefined : Number(a.tof_s), a.max_revs === undefined ? undefined : Number(a.max_revs)) ??
        (getTarget(world).sameFrame
          ? { error: "no transfer solution — try a different time of flight" }
          : { error: "target is in another body's sphere of influence — escape your current SOI first, then intercept" }),
    },
    {
      name: "solve_transfer_window",
      description:
        "Plan a FULL INTERPLANETARY transfer to the SELECTED planet — call this from INSIDE your " +
        "current body's SOI (no need to escape first). A heliocentric porkchop picks the soonest " +
        "cheap departure window and the planner SIZES THE EJECTION BURN ITSELF, so you can't " +
        "overshoot. Returns one guided plan: an ejection burn, then a heliocentric injection + " +
        "midcourse trims (resolved live in the star's frame). It flies you into the destination " +
        "planet's SOI on a close approach; once captured, circularize manually (solve_circularize). " +
        "Proposes only; does NOT fire. The departure is typically months out — relay it and use " +
        "jump_to_next_node to warp there after the operator confirms.",
      parameters: obj({}),
      run: () => {
        const r = planTransferWindow(world);
        return r.ok ? r.plan : { error: r.error };
      },
    },
    {
      name: "solve_match_velocity",
      description:
        "Plan a single burn that KILLS the relative velocity to the target (stop alongside it). " +
        "Exact, computed live. Use on terminal approach after an intercept gets you close. " +
        "Proposes only; does NOT fire. Unavailable for a target in another body's SOI.",
      parameters: obj({}),
      run: () =>
        planMatchVelocity(world) ?? { error: "target is in another body's sphere of influence — escape your current SOI first" },
    },
    {
      name: "dock",
      description:
        "Dock with the station — allowed only inside the docking envelope (within ~1 km and " +
        "~5 m/s of it; check get_target.canDock). MVP stub: it just latches on. Returns an " +
        "error if not in the envelope.",
      parameters: obj({}),
      run: () => dock(world),
    },
    {
      name: "get_cargo",
      description:
        "The ship's cargo hold + the wallet: each stack (name, per-unit mass + volume, quantity), " +
        "the two limits it fills against — mass (kg) and volume (m³), each with used/capacity/free — " +
        "and creditsCr (your money). Cargo is inert mass — it counts toward the burnout mass, so " +
        "loading it lowers the Δv budget (see get_ship). A load stops at whichever limit fills first.",
      parameters: obj({}),
      run: () => getCargo(world),
    },
    {
      name: "get_station",
      description:
        "The MARKET of the target you're DOCKED to: each good with askCr (price to BUY one) and " +
        "bidCr (credits you GET selling one), plus qty in stock to buy. Also your creditsCr. " +
        "A good listed at qty 0 is one the station BUYS but doesn't sell. Reports docked:false " +
        "when adrift, or hasHold:false for a target with no market (e.g. a probe). Dock first " +
        "(get_target.canDock) to trade. Prices differ by station — that's where arbitrage lives.",
      parameters: obj({}),
      run: () => getStation(world),
    },
    {
      name: "transfer_cargo",
      description:
        "Trade across the dock (must be docked). direction 'load' = BUY (station→ship, pays askCr); " +
        "'unload' = SELL (ship→station, earns bidCr). Buying adds inert mass and CUTS the Δv budget; " +
        "selling frees it and pays you. A buy is bounded by stock, the hold's free mass AND volume, " +
        "and your credits; a sell needs the station to price that good. Returns moved, unitPriceCr, " +
        "totalCr, and your new creditsCr.",
      parameters: obj(
        {
          direction: { enum: ["load", "unload"], description: "load = BUY (station→ship), unload = SELL (ship→station)." },
          item_id: { type: "string", description: "The stack id from get_cargo / get_station (e.g. 'ore')." },
          qty: { type: "number", description: "Units to trade (clamped to stock/capacity/credits). Default 1." },
        },
        ["direction", "item_id"],
      ),
      run: (a) => transferCargo(world, a.direction === "unload" ? "unload" : "load", String(a.item_id), a.qty === undefined ? 1 : Number(a.qty)),
    },
    {
      name: "execute_maneuver",
      description:
        "Commit the planned maneuver: lay the burn(s) as nodes and arm the autopilot to " +
        "fly them with finite thrust (orient → throttle → cut off at the planned Δv). " +
        "ONLY after the operator explicitly confirms. Requires confirm=true.",
      parameters: obj(
        { confirm: { type: "boolean", description: "Must be true, and only after explicit operator confirmation." } },
        ["confirm"],
      ),
      run: (a) => executeManeuver(world, a.confirm === true),
    },
    {
      name: "jump_to_next_node",
      description:
        "Warp to the next maneuver node's burn window so the autopilot flies it. Use " +
        "after executing a transfer to reach the circularization burn, or tell the " +
        "operator to warp there instead.",
      parameters: obj({}),
      run: () => jumpToNextNode(world),
    },
    {
      name: "jump_to_next_soi",
      description:
        "Warp to just before the next sphere-of-influence handoff (escaping the current body, or " +
        "being captured by another) so it's crossed at 1×. Use after an escape/transfer burn to " +
        "skip the long coast to the boundary. Returns an error if no handoff is ahead.",
      parameters: obj({}),
      run: () => jumpToNextSoi(world),
    },
    {
      name: "set_throttle",
      description:
        "Set engine throttle 0..1 (hand-flying; releases the autopilot). Combine with " +
        "set_attitude_mode to burn in a chosen direction.",
      parameters: obj(
        { throttle: { type: "number", description: "0 = off, 1 = full." } },
        ["throttle"],
      ),
      run: (a) => setThrottle(world, Number(a.throttle)),
    },
    {
      name: "set_attitude_mode",
      description:
        "Point the ship: prograde, retrograde, normal, antinormal, radialIn, radialOut, " +
        "or kill (stop rotation). Hand-flying — releases the autopilot. The ship turns " +
        "at a finite rate; check get_flight for pointing error.",
      parameters: obj(
        { mode: { enum: ["prograde", "retrograde", "normal", "antinormal", "radialIn", "radialOut", "kill"], description: "Attitude hold mode." } },
        ["mode"],
      ),
      run: (a) => setAttitudeMode(world, String(a.mode) as Parameters<typeof setAttitudeMode>[1]),
    },
    {
      name: "set_executor",
      description: "Engage (true) or stop (false) the maneuver-node autopilot.",
      parameters: obj(
        { on: { type: "boolean", description: "true = fly the queued nodes; false = stop and hold." } },
        ["on"],
      ),
      run: (a) => setExecutor(world, a.on === true),
    },
  ];
}

function toOpenAiTools(tools: ShipTool[]) {
  return tools.map(({ name, description, parameters }) => ({
    type: "function",
    function: { name, description, parameters },
  }));
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

// Wire shape for the OpenAI-compatible chat completions API.
interface LlmMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
  tool_calls?: Array<{ id: string; function: { name: string; arguments: string } }>;
  tool_call_id?: string;
}

interface ChatCompletionResponse {
  choices?: Array<{
    message?: {
      role?: string;
      content: string | null;
      tool_calls?: Array<{ id?: string; function?: { name?: string; arguments?: string } }>;
    };
  }>;
}

/** True if the model server answers. Cached for 30 s so the status endpoint stays cheap. */
const health = { checkedAt: 0, ok: false };
export async function aiAvailable(): Promise<boolean> {
  const now = Date.now();
  if (now - health.checkedAt < 30_000) return health.ok;
  try {
    const res = await fetch(`${BASE_URL}/models`, {
      headers: { authorization: `Bearer ${API_KEY}` },
      signal: AbortSignal.timeout(3000),
    });
    health.ok = res.ok;
  } catch {
    health.ok = false;
  }
  health.checkedAt = now;
  return health.ok;
}

// The client's rolling history becomes the prompt context directly (roles already
// match chat-completions). A short window is plenty: orbital numbers are re-read
// via tools every turn, so stale context is less a problem here than with cloud
// models — but the window still bounds prompt size on the (slower) local model.
const MAX_CONTEXT_TURNS = 12;

function contextMessages(history: ChatMessage[]): LlmMessage[] {
  const turns = history.filter((m) => m.content.trim().length > 0).slice(-MAX_CONTEXT_TURNS);
  const messages = turns.map((m) => ({ role: m.role, content: m.content }));
  if (messages[messages.length - 1]?.role !== "user") {
    messages.push({ role: "user", content: "(continue)" });
  }
  return messages;
}

function chatCompletion(messages: LlmMessage[], tools: ShipTool[]): Promise<ChatCompletionResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  return (async () => {
    try {
      const res = await fetch(`${BASE_URL}/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${API_KEY}` },
        body: JSON.stringify({ model: MODEL, messages, tools: toOpenAiTools(tools), temperature: 0.2 }),
        signal: controller.signal,
      });
      const data: unknown = await res.json().catch(() => null);
      if (!res.ok) {
        const detail = data ? JSON.stringify(data).slice(0, 300) : String(data);
        throw new Error(`model server HTTP ${res.status}: ${detail}`);
      }
      return data as ChatCompletionResponse;
    } catch (e) {
      if (e instanceof Error && e.name === "AbortError") {
        throw new Error(`model server request timed out after ${REQUEST_TIMEOUT_MS / 1000} s`);
      }
      if (e instanceof Error && (e.name === "TypeError" || e.name === "ConnectError")) {
        throw new Error(`model server unreachable at ${BASE_URL} — is it running?`);
      }
      throw e;
    }
  })().finally(() => clearTimeout(timer));
}

// Be lenient with tool arguments: local models can emit slightly malformed JSON.
// Salvage the first {...} span, then give up with {} (the tool's own error will
// tell the model what was missing).
function parseToolArgs(raw: string | undefined): Record<string, unknown> {
  if (raw == null) return {};
  try {
    return JSON.parse(raw) ?? {};
  } catch {
    const match = raw.match(/\{[\s\S]*\}/);
    if (match) {
      try {
        return JSON.parse(match[0]) ?? {};
      } catch {
        /* fall through */
      }
    }
    return {};
  }
}

// Tool results are JSON; truncate pathological ones (big lists) so a single tool
// call can't blow the context window.
function toolOutput(value: unknown): string {
  const text = JSON.stringify(value ?? { error: "no result" });
  return text.length > 8000 ? text.slice(0, 8000) + '…" (truncated)' : text;
}

/** Run the ship AI over the conversation and return its reply text. The persona only
 *  changes the voice; the BEHAVIOR contract appended to it is identical for every one. */
export async function runShipAI(
  world: World,
  history: ChatMessage[],
  persona?: string,
): Promise<string> {
  const systemPrompt = `${personaById(persona).voice}\n\n${BEHAVIOR}`;
  const tools = shipTools(world);
  const messages: LlmMessage[] = [
    { role: "system", content: systemPrompt },
    ...contextMessages(history),
  ];

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const response = await chatCompletion(messages, tools);
    const message = response.choices?.[0]?.message;
    if (!message) throw new Error("model server returned no message");

    if (message.tool_calls && message.tool_calls.length > 0) {
      // Record the assistant's tool-call turn, execute each call against the
      // live World, and feed the results back as tool messages.
      messages.push({
        role: "assistant",
        content: message.content ?? "",
        tool_calls: message.tool_calls.map((c) => ({
          id: c.id ?? "",
          function: { name: c.function?.name ?? "", arguments: c.function?.arguments ?? "{}" },
        })),
      });
      for (const call of message.tool_calls) {
        const name = call.function?.name ?? "";
        const tool = tools.find((t) => t.name === name);
        let output: string;
        if (!tool) {
          output = JSON.stringify({ error: `unknown tool '${name}' — check the tool list` });
        } else {
          try {
            output = toolOutput(await tool.run(parseToolArgs(call.function?.arguments)));
          } catch (e) {
            output = JSON.stringify({ error: `tool failed: ${e instanceof Error ? e.message : String(e)}` });
          }
        }
        messages.push({ role: "tool", tool_call_id: call.id ?? "", content: output });
      }
      continue;
    }

    return (message.content ?? "").trim() || "[ship AI returned no text]";
  }

  throw new Error(`ship AI hit the ${MAX_TURNS}-turn tool-loop limit without answering`);
}
