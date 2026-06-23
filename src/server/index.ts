import "dotenv/config";
import { performance } from "node:perf_hooks";
import express from "express";
import { z } from "zod";
import { World } from "../sim/world";
import {
  getClock,
  getCentralBody,
  getSystem,
  getShip,
  getOrbit,
  getStateVector,
  predictOrbit,
  getTarget,
  listTargets,
  selectTarget,
  dock,
  undock,
  getCargo,
  getStation,
  transferCargo,
  planManeuver,
  planCircularize,
  planSetApsis,
  planHohmann,
  planIntercept,
  planTransferWindow,
  suggestIntercept,
  planMatchVelocity,
  executeManeuver,
  getPendingManeuver,
  cancelManeuver,
  jumpToNextNode,
  jumpToNextSoi,
  clearNodes,
  setThrottle,
  setAttitudeMode,
  setManualTorque,
  setExecutor,
  getFlight,
} from "../sim/api";
import type { AttitudeMode } from "../sim/flight";
import { runShipAI, aiAvailable, PERSONA_LIST, DEFAULT_PERSONA, type ChatMessage } from "./ai-bridge";

const world = new World();

// Sim tick. Propagation is analytic, so the tick cadence only affects UI
// smoothness, never accuracy. Measure real elapsed time so warp stays honest.
let last = performance.now();
let tickFailures = 0;
setInterval(() => {
  const now = performance.now();
  try {
    world.advance((now - last) / 1000);
    tickFailures = 0;
  } catch (e) {
    console.error("[sim] tick failed:", e);
    // Don't let a broken state keep getting time-warped: after a burst of
    // failures, stop advancing so we're not banking warp on a degenerate state.
    if (++tickFailures >= 5) world.rate = 0;
  } finally {
    // Always advance the clock reference so a failed (or slow) tick can't bank a
    // giant elapsed delta and inject a time jump on the next successful tick.
    last = now;
  }
}, 50);

process.on("uncaughtException", (e) => console.error("[fatal] uncaughtException:", e));
process.on("unhandledRejection", (e) => console.error("[fatal] unhandledRejection:", e));

const app = express();
app.use(express.json());

// --- THE READ API (docs/07 §5) ---------------------------------------------
app.get("/api/clock", (_req, res) => res.json(getClock(world)));
app.get("/api/central_body", (_req, res) => res.json(getCentralBody(world)));
app.get("/api/system", (_req, res) => res.json(getSystem(world)));
app.get("/api/ship", (_req, res) => res.json(getShip(world)));
app.get("/api/orbit", (_req, res) => res.json(getOrbit(world)));
app.get("/api/state_vector", (_req, res) => res.json(getStateVector(world)));
app.get("/api/predict", (req, res) => {
  // Guard the query param: Number(undefined)/Number("abc") is NaN, which would flow into
  // propagate() and return an all-NaN OrbitState with HTTP 200 (docs/FIX-SPECS H4).
  const t = Number(req.query.t);
  if (!Number.isFinite(t)) {
    return res.status(400).json({ error: "query param t (sim-seconds) must be a finite number" });
  }
  res.json(predictOrbit(world, t));
});
app.get("/api/target", (_req, res) => res.json(getTarget(world)));
app.get("/api/targets", (_req, res) => res.json(listTargets(world)));

// Select which target the telemetry, solvers and dock affordance follow.
app.post("/api/target/select", (req, res) => {
  const result = selectTarget(world, Number(req.body?.index));
  res.status(result.ok ? 200 : 400).json(result);
});

// Convenience aggregate for the client poll — a composition of the reads above.
app.get("/api/state", (_req, res) =>
  res.json({
    clock: getClock(world),
    body: getCentralBody(world),
    system: getSystem(world),
    ship: getShip(world),
    orbit: getOrbit(world),
    pendingManeuver: getPendingManeuver(world),
    flight: getFlight(world),
    target: getTarget(world),
    targets: listTargets(world),
    cargo: getCargo(world),
    station: getStation(world),
  }),
);

// Basic time-warp control (M0 convenience; full time design in docs/08).
app.post("/api/rate", (req, res) => {
  const r = Number(req.body?.rate);
  if (!Number.isFinite(r) || r < 0) {
    return res.status(400).json({ error: "rate must be a finite number ≥ 0" });
  }
  world.rate = r;
  res.json(getClock(world));
});

// --- THE WRITE API (M1, docs/07 §5) ----------------------------------------
// plan → review → execute. plan_maneuver returns a proposal (no mutation);
// execute_maneuver commits it only with { confirm: true } — the confirmation gate.
app.get("/api/maneuver/pending", (_req, res) => res.json(getPendingManeuver(world)));

app.post("/api/maneuver/plan", (req, res) => {
  const b = req.body ?? {};
  const time = Number(b.time);
  if (!Number.isFinite(time)) {
    return res.status(400).json({ error: "time (absolute sim-seconds) is required" });
  }
  // Δv components in the orbital frame [m/s]; absent axes default to zero.
  const dvLocal = {
    prograde: Number(b.prograde) || 0,
    normal: Number(b.normal) || 0,
    radial: Number(b.radial) || 0,
  };
  res.json(planManeuver(world, { time, dvLocal }));
});

// Inverse solvers (deterministic instruments). Each parks a plan that flows through the
// same review → execute gate; the operator picks which solver + target.
const apsisOf = (v: unknown): "apoapsis" | "periapsis" => (v === "periapsis" ? "periapsis" : "apoapsis");

app.post("/api/maneuver/circularize", (req, res) => {
  res.json(planCircularize(world, apsisOf(req.body?.at)));
});

app.post("/api/maneuver/set_apsis", (req, res) => {
  const targetAltitude = Number(req.body?.targetAltitude);
  if (!Number.isFinite(targetAltitude) || targetAltitude <= 0) {
    return res.status(400).json({ error: "targetAltitude (meters) is required" });
  }
  res.json(planSetApsis(world, apsisOf(req.body?.which), targetAltitude));
});

app.post("/api/maneuver/hohmann", (req, res) => {
  const targetAltitude = Number(req.body?.targetAltitude);
  if (!Number.isFinite(targetAltitude) || targetAltitude <= 0) {
    return res.status(400).json({ error: "targetAltitude (meters) is required" });
  }
  res.json(planHohmann(world, targetAltitude));
});

// Clamp a requested max-revolutions count to a sane range; undefined ⇒ solver default.
const revsOf = (v: unknown): number | undefined => {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? Math.min(20, Math.round(n)) : undefined;
};

// A clear reason when a Lambert tool is unavailable because the target is in another SOI.
const crossFrameError = () => {
  const t = getTarget(world);
  return `${t.name} is in another body's sphere of influence — escape your current SOI first, then intercept it`;
};

app.post("/api/maneuver/intercept", (req, res) => {
  if (!getTarget(world).sameFrame) return res.status(409).json({ error: crossFrameError() });
  const raw = Number(req.body?.tof);
  const tof = Number.isFinite(raw) && raw > 0 ? raw : undefined; // omitted ⇒ auto-pick the cheapest TOF
  const plan = planIntercept(world, tof, revsOf(req.body?.revs));
  if (!plan) return res.status(422).json({ error: "no transfer solution — try a different time of flight or target" });
  res.json(plan);
});

// The cheapest intercept TOF for the selected target (the panel seeds its TOF field with this).
app.get("/api/maneuver/intercept/suggest", (req, res) => {
  if (!getTarget(world).sameFrame) return res.status(409).json({ error: crossFrameError() });
  const s = suggestIntercept(world, revsOf(req.query?.revs));
  if (!s) return res.status(422).json({ error: "no intercept solution for the current target" });
  res.json(s);
});

app.post("/api/maneuver/match", (_req, res) => {
  if (!getTarget(world).sameFrame) return res.status(409).json({ error: crossFrameError() });
  const plan = planMatchVelocity(world);
  if (!plan) return res.status(422).json({ error: "no velocity-match solution for the current target" });
  res.json(plan);
});

// Auto transfer-window (porkchop) — the interplanetary path: search departure × TOF.
app.post("/api/maneuver/transfer_window", (_req, res) => {
  if (!getTarget(world).sameFrame) return res.status(409).json({ error: crossFrameError() });
  const plan = planTransferWindow(world);
  if (!plan) return res.status(422).json({ error: "no transfer window found within the search horizon" });
  res.json(plan);
});

// Docking (MVP stub) — allowed only inside the envelope; no mechanics yet.
app.post("/api/dock", (_req, res) => {
  const result = dock(world);
  res.status(result.ok ? 200 : 409).json(result);
});
app.post("/api/undock", (_req, res) => res.json(undock(world)));

// Cargo: read the hold / the docked station, and transfer across the dock. Loading inert
// mass shrinks the Δv budget; unloading grows it (getShip folds cargo into burnout mass).
app.get("/api/cargo", (_req, res) => res.json(getCargo(world)));
app.get("/api/station", (_req, res) => res.json(getStation(world)));
app.post("/api/cargo/transfer", (req, res) => {
  const direction = req.body?.direction === "unload" ? "unload" : "load";
  const itemId = String(req.body?.itemId ?? "");
  const qty = req.body?.qty === undefined ? 1 : Number(req.body.qty);
  if (!itemId) return res.status(400).json({ error: "itemId is required" });
  if (!Number.isFinite(qty) || qty <= 0) return res.status(400).json({ error: "qty must be a positive number" });
  const result = transferCargo(world, direction, itemId, qty);
  res.status(result.ok ? 200 : 409).json(result);
});

app.post("/api/maneuver/execute", (req, res) => {
  const result = executeManeuver(world, req.body?.confirm === true);
  res.status(result.ok ? 200 : 409).json(result);
});

// Jump-to-event: warp to the next node's burn window; the executor then flies it.
app.post("/api/maneuver/jump", (_req, res) => {
  const result = jumpToNextNode(world);
  res.status(result.ok ? 200 : 409).json(result);
});

// Jump-to-event: warp to just before the next SOI handoff (escape/capture), crossed at 1×.
app.post("/api/jump_soi", (_req, res) => {
  const result = jumpToNextSoi(world);
  res.status(result.ok ? 200 : 409).json(result);
});

app.post("/api/maneuver/cancel", (_req, res) => res.json(cancelManeuver(world)));
app.post("/api/maneuver/clear", (_req, res) => res.json(clearNodes(world)));

// --- FLIGHT CONTROL (docs/10) ----------------------------------------------
// Throttle, attitude, and the executor — all equal clients of the one API.
app.get("/api/flight", (_req, res) => res.json(getFlight(world)));

app.post("/api/flight/throttle", (req, res) => {
  const t = Number(req.body?.throttle);
  if (!Number.isFinite(t)) return res.status(400).json({ error: "throttle (0..1) required" });
  res.json(setThrottle(world, t));
});

const MODES: AttitudeMode[] = [
  "prograde", "retrograde", "normal", "antinormal", "radialIn", "radialOut",
  "target", "antiTarget", "node", "kill", "manual",
];
app.post("/api/flight/attitude", (req, res) => {
  const mode = req.body?.mode as AttitudeMode;
  if (!MODES.includes(mode)) return res.status(400).json({ error: `mode must be one of ${MODES.join(", ")}` });
  res.json(setAttitudeMode(world, mode));
});

app.post("/api/flight/manual", (req, res) => {
  const tau = world.ship.maxTorqueNm;
  const n = (x: unknown) => Math.max(-1, Math.min(1, Number(x) || 0)) * tau;
  // body axes: x = roll (thrust axis), y = pitch, z = yaw
  res.json(setManualTorque(world, { x: n(req.body?.roll), y: n(req.body?.pitch), z: n(req.body?.yaw) }));
});

app.post("/api/flight/executor", (req, res) => res.json(setExecutor(world, req.body?.on === true)));

// --- AI BRIDGE (docs/07 §6) ------------------------------------------------
app.get("/api/ai/status", (_req, res) =>
  res.json({ available: aiAvailable(), personas: PERSONA_LIST, defaultPersona: DEFAULT_PERSONA }),
);
// Serialize chat turns over the shared `world` (docs/FIX-SPECS H3). One ship,
// one operator-at-a-time: each turn's plan→execute tool sequence runs to
// completion before the next turn touches `world`, so session B can't commit
// session A's reviewed-but-unconfirmed pending burn (Keystone 2's gate).
let chatChain: Promise<unknown> = Promise.resolve();

// Validate + bound the chat body (docs/FIX-SPECS M-chatvalidate). A blind cast lets a
// malformed `messages` throw inside composePrompt (→ 500), and an unbounded array becomes a
// large prompt billed to the host's subscription (the Q2 cost concern). zod is already a dep.
const ChatBody = z.object({
  messages: z
    .array(z.object({ role: z.enum(["user", "assistant"]), content: z.string().max(8000) }))
    .max(50),
  persona: z.string().optional(),
});

app.post("/api/ai/chat", async (req, res) => {
  if (!aiAvailable()) {
    return res.status(503).json({
      error:
        "AI offline: set CLAUDE_CODE_OAUTH_TOKEN (subscription) or ANTHROPIC_API_KEY " +
        "in the server environment.",
    });
  }
  const parsed = ChatBody.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "invalid chat payload" });
  const history = parsed.data.messages as ChatMessage[];
  const persona = parsed.data.persona;
  const run = chatChain.then(() => runShipAI(world, history, persona));
  chatChain = run.catch(() => {}); // keep the chain alive even if this turn throws
  try {
    const reply = await run;
    res.json({ reply });
  } catch (err) {
    // Log full detail server-side; return a generic message. The raw SDK error can carry
    // auth-failure detail, paths, or token strings to the browser (docs/FIX-SPECS M-aileak).
    console.error("[ai] ", err);
    res.status(500).json({ error: "ship AI error — see server logs" });
  }
});

// Terminal error handler (docs/FIX-SPECS H5). Express 5 forwards both synchronous throws and
// rejected promises from every route here, so a sim/solver edge case yields a JSON 500 — not
// Express's default HTML stack-trace page leaked to the client. Must be registered last.
app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error("[http] route error:", err);
  if (res.headersSent) return;
  res.status(500).json({ error: "internal error" });
});

const PORT = Number(process.env.PORT ?? 8787);
app.listen(PORT, () => {
  console.log(`[server] ship sim + API on http://localhost:${PORT}`);
  const auth = process.env.CLAUDE_CODE_OAUTH_TOKEN
    ? "online (Claude subscription)"
    : process.env.ANTHROPIC_API_KEY
      ? "online (API key)"
      : "offline (no subscription token or API key)";
  console.log(`[server] ship AI: ${auth}`);
});
