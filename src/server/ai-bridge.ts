import { query, tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
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
// AUTH (open question Q2): this runs on the host's Claude subscription, not a
// per-token API key. `claude setup-token` mints a CLAUDE_CODE_OAUTH_TOKEN that
// the Agent SDK's bundled runtime uses to talk to the subscription. Friends'
// chats are routed through the host's plan for the prototype. Drop in an
// ANTHROPIC_API_KEY instead and it falls back to billed-API auth.

const MODEL = process.env.SHIP_AI_MODEL ?? "claude-sonnet-4-6";

// Snappiness knobs. The ship-AI answers quick operator questions and drives the planner;
// it doesn't need deep deliberation, and the inverse solver tools mean it rarely has to
// iterate. Cap the reasoning effort LOW (fastest responses) and bound the agentic tool
// loop so a confused turn can't spin. Both override-able from .env.
type Effort = "low" | "medium" | "high" | "xhigh" | "max";
const EFFORT = (process.env.SHIP_AI_EFFORT as Effort) ?? "low";
const MAX_TURNS = Number(process.env.SHIP_AI_MAX_TURNS ?? 12);

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

When DOCKED you can trade cargo: get_station lists the dock's hold, get_cargo lists
yours, transfer_cargo moves it. Cargo is inert mass — loading it LOWERS your Δv budget,
unloading RAISES it; quantify the change with get_ship before and after when it matters.
The hold has two limits — mass (kg) and volume (m³) — and a load stops at whichever fills
first, so a bulky load can run out of room with mass to spare (and vice versa).

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
offer the best achievable result.`;

// In-process MCP tools, one per read-API call. Built fresh per request so they
// close over the live World (the sim advances between requests). readOnlyHint
// lets the model batch them. The tools ARE the ship API — Keystone 2.
function shipTools(world: World) {
  const reply = (data: unknown) =>
    ({ content: [{ type: "text" as const, text: JSON.stringify(data) }] });
  const readonly = { annotations: { readOnlyHint: true } };

  return createSdkMcpServer({
    name: "ship",
    version: "1.0.0",
    tools: [
      tool(
        "get_clock",
        "Current simulation time (seconds) and the time-warp rate.",
        {},
        async () => reply(getClock(world)),
        readonly,
      ),
      tool(
        "get_central_body",
        "Physical parameters of the body you are CURRENTLY orbiting (id, name, mu, radius), its " +
          "parent body, and its sphere-of-influence radius (null for the star). Which body this " +
          "is changes as you cross SOI boundaries — always check it before reasoning about altitude.",
        {},
        async () => reply(getCentralBody(world)),
        readonly,
      ),
      tool(
        "get_system",
        "The whole solar system (patched conics): every body — the star and its planets — with " +
          "mu, radius, sphere-of-influence radius, parent, and current heliocentric position; " +
          "plus which body you currently orbit and the next SOI handoff ahead (escape or capture) " +
          "with its time. Use to plan interplanetary travel and answer 'what bodies are out there'.",
        {},
        async () => reply(getSystem(world)),
        readonly,
      ),
      tool(
        "get_ship",
        "The ship's identity and propulsion state: total/dry mass (kg), propellant " +
          "remaining (kg), specific impulse (s), and the remaining Δv budget (m/s).",
        {},
        async () => reply(getShip(world)),
        readonly,
      ),
      tool(
        "get_flight",
        "Flight state: attitude/pointing, throttle, the autopilot (executor) status, the " +
          "orbital-frame markers, and the maneuver-node queue with Δv remaining.",
        {},
        async () => reply(getFlight(world)),
        readonly,
      ),
      tool(
        "get_orbit",
        "The ship's complete current orbital state (SI): elements, anomalies, " +
          "apoapsis/periapsis radius and altitude, current radius/altitude/speed, " +
          "period, latitude, times to periapsis/apoapsis, and the PCI state vector.",
        {},
        async () => reply(getOrbit(world)),
        readonly,
      ),
      tool(
        "get_target",
        "The SELECTED rendezvous target and the relative state: name, range (m), closing " +
          "speed (m/s, positive = approaching), and its current orbit. The solvers " +
          "(intercept / match-velocity) and the dock all act on this target. Use this to " +
          "answer 'how far is the target' and to plan a rendezvous.",
        {},
        async () => reply(getTarget(world)),
        readonly,
      ),
      tool(
        "list_targets",
        "Every available rendezvous target with its altitude, period, and current range " +
          "from the ship, and which one is selected. Use to answer 'what can I dock with' " +
          "and to pick a target before solving a rendezvous.",
        {},
        async () => reply(listTargets(world)),
        readonly,
      ),
      tool(
        "select_target",
        "Choose which target the telemetry, the rendezvous solvers, and the dock follow. " +
          "Call before solve_intercept / solve_match_velocity / dock if the operator names a " +
          "different target. Pass its index from list_targets.",
        { index: z.number().int().describe("Target index from list_targets (0-based).") },
        async (args) => reply(selectTarget(world, args.index)),
      ),
      tool(
        "predict_orbit",
        "The ship's orbital state at a future or past simulation time. Use this to " +
          "answer questions like 'where will I be in 40 minutes' or 'when am I next " +
          "over the pole'. Call get_clock first to learn the current time.",
        { t: z.number().describe("Absolute simulation time in seconds.") },
        async (args) => reply(predictOrbit(world, args.t)),
        readonly,
      ),
      // Write actions (NOT read-only). plan_maneuver only proposes; execute_maneuver
      // commits, and the persona is instructed to call it solely after the operator
      // confirms — the confirmation gate (docs/07 §6.3).
      tool(
        "plan_maneuver",
        "Preview a single maneuver NODE — a burn at a chosen time with a Δv split across " +
          "the three orbital-frame axes. This is a FORWARD CALCULATOR, not a goal-seeking " +
          "solver: you supply the burn, it returns the Δv magnitude, propellant cost, " +
          "remaining Δv budget, and the resulting orbit (apo/peri/inclination). It does NOT " +
          "fire the engine. To reach a target orbit, iterate: preview, read the result, " +
          "adjust the numbers, preview again — then present it and wait for explicit " +
          "operator confirmation before execute_maneuver.",
        {
          time_s: z
            .number()
            .describe("Absolute simulation time the burn fires, in SECONDS. Call get_clock for 'now'; add seconds to burn later."),
          prograde_ms: z
            .number()
            .describe("Δv along velocity, m/s. + = prograde (raises the opposite apsis), − = retrograde."),
          normal_ms: z
            .number()
            .describe("Δv along the orbit normal, m/s. Changes inclination / plane. + = normal, − = antinormal."),
          radial_ms: z
            .number()
            .describe("Δv along radial-out, m/s. + = away from the planet, − = toward it."),
        },
        async (args) =>
          reply(
            planManeuver(world, {
              time: args.time_s,
              dvLocal: { prograde: args.prograde_ms ?? 0, normal: args.normal_ms ?? 0, radial: args.radial_ms ?? 0 },
            }),
          ),
      ),
      // Inverse SOLVERS — deterministic instruments that compute the exact node(s) for a
      // common goal in ONE call. PREFER these over iterating plan_maneuver when the goal
      // fits (faster + exact). Each only PROPOSES a plan; execute_maneuver still commits.
      tool(
        "solve_circularize",
        "Plan the burn that CIRCULARIZES the orbit at the next apoapsis or periapsis (one " +
          "tangential burn). Proposes only; does NOT fire. Present and wait for confirmation.",
        { at: z.enum(["apoapsis", "periapsis"]).describe("Which apsis to circularize at.") },
        async (args) => reply(planCircularize(world, args.at)),
      ),
      tool(
        "solve_set_apsis",
        "Plan the burn that sets the APOAPSIS or PERIAPSIS to a target altitude (burns at the " +
          "opposite apsis, leaving it fixed). Proposes only; does NOT fire.",
        {
          which: z.enum(["apoapsis", "periapsis"]).describe("Which apsis to move."),
          target_altitude_m: z.number().describe("Target altitude above the surface, in METERS. e.g. 800 km = 800000."),
        },
        async (args) => reply(planSetApsis(world, args.which, args.target_altitude_m)),
      ),
      tool(
        "solve_hohmann",
        "Plan a two-burn HOHMANN transfer to a CIRCULAR orbit at a target altitude (depart " +
          "now, circularize at the far side ~half an orbit later). Assumes a near-circular " +
          "start. Proposes only (both burns, total Δv/fuel); does NOT fire.",
        { target_altitude_m: z.number().describe("Target circular altitude above the surface, in METERS. e.g. 800 km = 800000.") },
        async (args) => reply(planHohmann(world, args.target_altitude_m)),
      ),
      tool(
        "solve_intercept",
        "Plan a RENDEZVOUS with the target (get_target) using a Lambert intercept: an " +
          "intercept burn that arrives at the target's future position after `tof` seconds, " +
          "then a match-velocity burn. Two burns; handles phasing automatically. OMIT tof_s to " +
          "let the solver auto-pick the cheapest time of flight for this target — the easiest " +
          "first call. Δv depends strongly on the TOF, so to hand-tune, pass one and sweep a " +
          "few. Proposes only; does NOT fire. Returns an error if no solution.",
        {
          tof_s: z
            .number()
            .optional()
            .describe("Time of flight to the rendezvous, in SECONDS (e.g. 70 min = 4200). Omit to auto-pick the cheapest."),
          max_revs: z
            .number()
            .int()
            .min(0)
            .optional()
            .describe("Max full revolutions the transfer may make (default 4). 0 forces a direct arc; more loops can find a cheaper transfer for a poorly-phased target."),
        },
        async (args) =>
          reply(
            planIntercept(world, args.tof_s, args.max_revs) ??
              (getTarget(world).sameFrame
                ? { error: "no transfer solution — try a different time of flight" }
                : { error: "target is in another body's sphere of influence — escape your current SOI first, then intercept" }),
          ),
      ),
      tool(
        "solve_transfer_window",
        "Plan a FULL INTERPLANETARY transfer to the SELECTED planet — call this from INSIDE your " +
          "current body's SOI (no need to escape first). A heliocentric porkchop picks the soonest " +
          "cheap departure window and the planner SIZES THE EJECTION BURN ITSELF, so you can't " +
          "overshoot. Returns one guided plan: an ejection burn, then a heliocentric injection + " +
          "midcourse trims (resolved live in the star's frame). It flies you into the destination " +
          "planet's SOI on a close approach; once captured, circularize manually (solve_circularize). " +
          "Proposes only; does NOT fire. The departure is typically months out — relay it and use " +
          "jump_to_next_node to warp there after the operator confirms.",
        {},
        async () => {
          const r = planTransferWindow(world);
          return reply(r.ok ? r.plan : { error: r.error });
        },
      ),
      tool(
        "solve_match_velocity",
        "Plan a single burn that KILLS the relative velocity to the target (stop alongside it). " +
          "Exact, computed live. Use on terminal approach after an intercept gets you close. " +
          "Proposes only; does NOT fire. Unavailable for a target in another body's SOI.",
        {},
        async () =>
          reply(planMatchVelocity(world) ?? { error: "target is in another body's sphere of influence — escape your current SOI first" }),
      ),
      tool(
        "dock",
        "Dock with the station — allowed only inside the docking envelope (within ~1 km and " +
          "~5 m/s of it; check get_target.canDock). MVP stub: it just latches on. Returns an " +
          "error if not in the envelope.",
        {},
        async () => reply(dock(world)),
      ),
      tool(
        "get_cargo",
        "The ship's cargo hold: each stack (name, per-unit mass + volume, quantity), and the " +
          "two limits it fills against — mass (kg) and volume (m³), each with used/capacity/free. " +
          "Cargo is inert mass — it counts toward the burnout mass, so loading it lowers the Δv " +
          "budget (see get_ship). A load stops at whichever limit fills first.",
        {},
        async () => reply(getCargo(world)),
        readonly,
      ),
      tool(
        "get_station",
        "The cargo hold of the target you're DOCKED to (its inventory you can load from). " +
          "Reports docked:false when adrift, or hasHold:false for a target with no hold " +
          "(e.g. a probe). Dock first (get_target.canDock) to trade.",
        {},
        async () => reply(getStation(world)),
        readonly,
      ),
      tool(
        "transfer_cargo",
        "Move cargo across the dock (must be docked). direction 'load' = station→ship, " +
          "'unload' = ship→station. Loading adds inert mass and CUTS the Δv budget; " +
          "unloading frees it. Bounded by what's in stock and the hold's free mass AND volume " +
          "(a dense item runs out of kg, a bulky one runs out of m³).",
        {
          direction: z.enum(["load", "unload"]).describe("load = station→ship, unload = ship→station."),
          item_id: z.string().describe("The stack id from get_cargo / get_station (e.g. 'ore')."),
          qty: z.number().int().min(1).default(1).describe("Units to move (clamped to availability/capacity)."),
        },
        async (args) => reply(transferCargo(world, args.direction, args.item_id, args.qty ?? 1)),
      ),
      tool(
        "execute_maneuver",
        "Commit the planned maneuver: lay the burn(s) as nodes and arm the autopilot to " +
          "fly them with finite thrust (orient → throttle → cut off at the planned Δv). " +
          "ONLY after the operator explicitly confirms. Requires confirm=true.",
        { confirm: z.boolean().describe("Must be true, and only after explicit operator confirmation.") },
        async (args) => reply(executeManeuver(world, args.confirm === true)),
      ),
      tool(
        "jump_to_next_node",
        "Warp to the next maneuver node's burn window so the autopilot flies it. Use " +
          "after executing a transfer to reach the circularization burn, or tell the " +
          "operator to warp there instead.",
        {},
        async () => reply(jumpToNextNode(world)),
      ),
      tool(
        "jump_to_next_soi",
        "Warp to just before the next sphere-of-influence handoff (escaping the current body, or " +
          "being captured by another) so it's crossed at 1×. Use after an escape/transfer burn to " +
          "skip the long coast to the boundary. Returns an error if no handoff is ahead.",
        {},
        async () => reply(jumpToNextSoi(world)),
      ),
      tool(
        "set_throttle",
        "Set engine throttle 0..1 (hand-flying; releases the autopilot). Combine with " +
          "set_attitude_mode to burn in a chosen direction.",
        { throttle: z.number().min(0).max(1).describe("0 = off, 1 = full.") },
        async (args) => reply(setThrottle(world, args.throttle)),
      ),
      tool(
        "set_attitude_mode",
        "Point the ship: prograde, retrograde, normal, antinormal, radialIn, radialOut, " +
          "or kill (stop rotation). Hand-flying — releases the autopilot. The ship turns " +
          "at a finite rate; check get_flight for pointing error.",
        {
          mode: z
            .enum(["prograde", "retrograde", "normal", "antinormal", "radialIn", "radialOut", "kill"])
            .describe("Attitude hold mode."),
        },
        async (args) => reply(setAttitudeMode(world, args.mode)),
      ),
      tool(
        "set_executor",
        "Engage (true) or stop (false) the maneuver-node autopilot.",
        { on: z.boolean().describe("true = fly the queued nodes; false = stop and hold.") },
        async (args) => reply(setExecutor(world, args.on === true)),
      ),
    ],
  });
}

// Fully-qualified names (mcp__<server>__<tool>) the model is pre-approved to call.
const ALLOWED_TOOLS = [
  "mcp__ship__get_clock",
  "mcp__ship__get_central_body",
  "mcp__ship__get_system",
  "mcp__ship__get_ship",
  "mcp__ship__get_flight",
  "mcp__ship__get_orbit",
  "mcp__ship__get_target",
  "mcp__ship__list_targets",
  "mcp__ship__select_target",
  "mcp__ship__predict_orbit",
  "mcp__ship__plan_maneuver",
  "mcp__ship__solve_circularize",
  "mcp__ship__solve_set_apsis",
  "mcp__ship__solve_hohmann",
  "mcp__ship__solve_intercept",
  "mcp__ship__solve_transfer_window",
  "mcp__ship__solve_match_velocity",
  "mcp__ship__dock",
  "mcp__ship__get_cargo",
  "mcp__ship__get_station",
  "mcp__ship__transfer_cargo",
  "mcp__ship__execute_maneuver",
  "mcp__ship__jump_to_next_node",
  "mcp__ship__jump_to_next_soi",
  "mcp__ship__set_throttle",
  "mcp__ship__set_attitude_mode",
  "mcp__ship__set_executor",
];

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

/** True if the server has credentials to run the ship AI. */
export function aiAvailable(): boolean {
  return Boolean(
    process.env.CLAUDE_CODE_OAUTH_TOKEN || process.env.ANTHROPIC_API_KEY,
  );
}

// The HTTP layer is stateless and re-sends the whole conversation each turn.
// The Agent SDK takes a single prompt, so render the history into one: a lone
// user turn passes through verbatim; a longer exchange becomes a labelled
// transcript so the model knows which operator line it's answering.
function composePrompt(history: ChatMessage[]): string {
  const turns = history.filter((m) => m.content.trim().length > 0);
  if (turns.length <= 1) return turns[0]?.content ?? "";
  const transcript = turns
    .map((m) => `${m.role === "user" ? "OPERATOR" : "SHIP-AI"}: ${m.content}`)
    .join("\n");
  return `${transcript}\n\n(Respond as SHIP-AI to the latest OPERATOR message.)`;
}

/** Run the ship AI over the conversation and return its reply text. The persona only
 *  changes the voice; the BEHAVIOR contract appended to it is identical for every one. */
export async function runShipAI(
  world: World,
  history: ChatMessage[],
  persona?: string,
): Promise<string> {
  const systemPrompt = `${personaById(persona).voice}\n\n${BEHAVIOR}`;
  // When a subscription token is present, blank ANTHROPIC_API_KEY for the
  // runtime so billing can't silently fall through to the per-token API.
  const env = process.env.CLAUDE_CODE_OAUTH_TOKEN
    ? { ...process.env, ANTHROPIC_API_KEY: undefined }
    : undefined;

  let assistantError: string | undefined;

  for await (const message of query({
    prompt: composePrompt(history),
    options: {
      model: MODEL,
      effort: EFFORT, // low = minimal thinking, fastest replies (Sonnet 4.6 supports effort)
      maxTurns: MAX_TURNS, // bound the tool loop so a confused turn can't spin
      systemPrompt, // full replacement — pure ship persona, no Claude Code preset
      mcpServers: { ship: shipTools(world) },
      allowedTools: ALLOWED_TOOLS,
      tools: [], // strip every built-in tool: the AI gets the ship API and nothing else
      settingSources: [], // hermetic — ignore any ambient ~/.claude or project settings
      permissionMode: "dontAsk", // never block on a prompt; deny anything not pre-approved
      env,
    },
  })) {
    if (message.type === "assistant" && message.error) {
      assistantError = String(message.error);
    }
    if (message.type === "result") {
      if (message.subtype === "success") {
        return message.result.trim() || "[ship AI returned no text]";
      }
      const detail = message.errors?.join("; ") || assistantError || message.subtype;
      throw new Error(`ship AI did not complete: ${detail}`);
    }
  }

  throw new Error("ship AI produced no result");
}
