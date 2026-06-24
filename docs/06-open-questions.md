# 06 — Open Questions

Decisions that are genuinely open. Roughly ordered by how much they shape everything
downstream. None of these block writing more design; the top few do shape Milestone
0's stack.

## Top of the list (shapes Milestone 0)

### Q1. Engine / stack → **DECIDED: web / TypeScript**
An authoritative **Node/TypeScript backend** (deterministic sim + Claude bridge + later
persistence/multiplayer) plus a **browser client** (Canvas/WebGL for the panels and the
orbit scope). Chosen for fastest iteration on a terminal-heavy UI, zero-install
multiplayer (friends open a URL), one language end-to-end, and easy Claude calls. (The
Godot tooling in this environment belongs to an unrelated project.) Reversible if ever
needed: every client is just a client of the one API, so a native client could be added
later without touching the sim, economy, or AI.

### Q2. AI access model — shared key vs bring-your-own?
Does the server hold one Claude credential for everyone, or does each player bring
their own (their AI runs on their account / Max subscription / rate limits / bill)?
Bring-your-own scales socially and is thematically nice (*your* ship, *your* mind),
but is more plumbing.

**Resolved (prototype auth):** the ship AI runs on a Claude **subscription**, not a
billed API key. The bridge uses the Claude Agent SDK
([07](07-milestone-0-spec.md) §6 / [src/server/ai-bridge.ts](../src/server/ai-bridge.ts));
its runtime authenticates with a `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`.
For now this is **shared** — friends' chats route through the host's subscription, so
the host eats the usage and the plan's rate/usage limits are the practical ceiling.
That's fine for a private playtest but isn't a scaling or commercial answer (a personal
plan is for the individual subscriber). **Still open:** the durable model — most likely
**bring-your-own** (each player supplies their own token/key) once there's more than a
handful of players, with a billed API key as the alternative for a host-funded server.

### Q3. Physics model → **DECIDED: patched conics + secular perturbations**
Analytic propagation; impulsive burns first, finite burns later. Full rationale and the
per-perturbation plan are in [08-simulation-and-time.md](08-simulation-and-time.md)
Part A.

## Gameplay-shaping

### Q4. Is there threat / failure / combat?
What can go wrong? Running out of fuel and stranding? Life-support consumables and a
clock? Hostile actors? Pure-logistics survival vs. PvE/PvP changes the emotional
core. Current lean from [01-vision.md](01-vision.md): danger is the environment and
your own mistakes, not enemies — but undecided.

→ **Selection menu now exists** — pick from [09-hazards-and-failure.md](09-hazards-and-failure.md)
to settle this. The standout sub-decision is **total loss**: permadeath vs. insurance
payout vs. respawn-at-station colors the entire game.

→ **Updated 2026-06-23 — leaning firmly to no *direct* player-vs-player antagonism for
now**, and the multiplayer time model ([08](08-simulation-and-time.md) Part B, Q7) assumes
it: with no threat, every wanted meeting is a scheduled convergence and the shared
event-clock can skip freely. If antagonism is ever added it comes as opt-in **"ambush"
triggers** (conditional alarms — "wake me when a ship enters this SOI") plus *targeted*
no-skip pressure near a credible threat, not free-for-all PvP. Danger today is the
environment and your own mistakes.

### Q5. What is a "career"? What's the long arc?
Sandbox with emergent goals (à la space-trucker sims), or authored objectives/
missions, or a tech/territory progression? What are you *for* once you can fly?

### Q6. The economy.
What's scarce, what's traded, where do credits come from and go? Mining implies a
sink for ore — who buys it, and why? Only matters from M3 but worth seeding early.

→ **Direction set:** a live, player-driven market (EVE / Ostranauts-style) via stations
& trade — see [02-gameplay.md](02-gameplay.md). Specifics (currency sinks/sources, what's
scarce, how prices move) remain open.

## Time & multiplayer

### Q7. Multiplayer time model → **DECIDED: the shared event-clock**
Governing law: never gate a player's in-game intent on real-world time (skip is a *pull*,
never a *push*). Mechanism for the small cooperative group (~4 friends): **one shared,
consistent timeline advanced by a discrete-event scheduler** — the world sleeps to the
next moment any agent (player or AI) needs, jumps there whenever no one is mid-action, and
emulates silently through pure-compute events. No out-of-band coordination; one shared
clock keeps the world mutable *and* paradox-free (per-player bubbles are explicitly out —
they break causality). Cheap thanks to analytic propagation (cost ∝ events, not duration).
Full design in [08-simulation-and-time.md](08-simulation-and-time.md) Part B.

**Still open (sub-questions, not the model):** (a) **how the ship AI behaves across a
skip** — live-conversational vs. headless deterministic standing-orders, and the handoff
between them (the least-designed corner); (b) the exact rules for what earns a LIVE-hold;
(c) alarm *priority* (soonest-wins vs. "don't stop me for minor events"). Start
soonest-wins.

## AI character

### Q8. Customizable AI persona? → **DECIDED: yes**
**Decided (player request):** each player customizes their own ship AI — name,
personality, verbosity, and default autonomy. Mechanically it's the persona section of
the system prompt ([07](07-milestone-0-spec.md) §6.2) plus a little save data; the
safety rails and tool access underneath stay fixed regardless of persona.

### Q9. How much should the AI volunteer vs. wait to be asked?
A silent tool that answers when addressed, or a crewmate that pipes up ("heads up,
periapsis is decaying")? The latter is more alive but needs careful event triggers so
it isn't noise.

## Routines (later, but seed now)

### Q10. Sandbox technology.
Constrained scripting/DSL to start vs. WASM for real "arbitrary code." What language
do players actually write? How is it metered against the compute resource?

---

> Add to this list freely. An answered question should move into the relevant doc as
> a decision, with a one-line note here pointing to it.
