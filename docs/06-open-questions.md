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

### Q7. Multiplayer time model → **DECIDED: fast-forward is required in MP too**
Non-negotiable — no waiting out real months, even with friends. Baseline mechanism is a
coordinated global jump/rate (shared clock + optional in-game "jump at XX:XX → YY:YY"
notice), cheap thanks to analytic propagation resolving every ship and routine in one
shot. Per-player bubbles are an optional later refinement. Only the coordination *UX* is
left to polish (at M4); that it happens is settled. See
[08-simulation-and-time.md](08-simulation-and-time.md) Part B.

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
