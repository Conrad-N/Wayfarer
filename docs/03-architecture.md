# 03 — Architecture

This is the most important document. The aesthetic and the feature list can change;
this is the load-bearing structure.

## Keystone 1 — One API, three clients

```
                    ┌─────────────────────────────┐
                    │   Authoritative simulation   │
                    │   (deterministic physics)    │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │        THE SHIP API          │   ← the single contract
                    │  reads (telemetry) +         │
                    │  commands (control)          │
                    └───┬───────────┬───────────┬──┘
                        │           │           │
              ┌─────────┴──┐  ┌─────┴─────┐  ┌──┴─────────┐
              │  Panels    │  │  Ship AI  │  │  Routines  │
              │ (buttons,  │  │ (LLM, NL  │  │ (player    │
              │  switches, │  │  ↔ API)   │  │  code)     │
              │  readouts) │  │           │  │            │
              └────────────┘  └───────────┘  └────────────┘
                  human          natural         automated
                  hands          language        scripts
```

The three clients are **peers**. None has private access to the simulation. The
button that fires a thruster, the AI deciding to fire a thruster, and a routine
firing a thruster all go through the same API call. Build that API once, well, and
the entire rest of the game is clients of it.

**Practical consequence:** the API is the central design artifact. Define it as a
set of typed commands and telemetry reads — e.g. `get_orbital_state()`,
`plan_maneuver(constraints)`, `execute_maneuver(plan, confirm)`, `scan()`,
`set_throttle()`, `dock()`, `mine()`. That one definition drives the UI bindings,
the AI's tool schema, and the routine standard library simultaneously.

## Keystone 2 — The AI is conversation, never physics

Hard sci-fi requires correct numbers. LLMs are unreliable at arithmetic. Therefore:

- **The deterministic solver owns all physics.** Orbits, transfers, burn results —
  all computed by real code.
- **The AI owns intent and language.** It maps "more aggressive burn" to a solver
  call with a tighter time constraint, reads the result, and explains it.

The AI runs a standard tool-use loop: it's given the live ship state plus the ship
API as its tool schema (Keystone 1), it calls read-tools and the solver, and it
either reports back or proposes a write-action for you to confirm. Anthropic's
tool-use does exactly this shape already, so the AI layer is mostly: a persona
system prompt + the API exposed as tools + a confirmation gate on writes.

### The review-before-execute gate
Write-actions (anything that changes the world irreversibly or burns resources)
return a **proposed plan** by default rather than executing. The human confirms.
This is the same gate whether the action originated from a panel, the AI, or a
routine — it lives in the API, not in any one client. Standing authorizations
("you may make minor corrections without asking") relax it during a session.

## Keystone 3 — Routines are the time machine

In a shared persistent world you can't unilaterally warp time. But you can write a
routine and log off. The world keeps advancing; your routine operates your ship; you
come back to the results. **The away-game is how an individual effectively
fast-forwards.**

This is why routines belong in the architecture from the start even though they ship
last: they're not a bonus feature, they're the resolution to the time-vs-multiplayer
tension (see *Time*, below).

## The simulation

### Server-authoritative from day one — even in single-player
The simulation is the authority. In single-player it runs in-process (a "server" on
localhost); in multiplayer it runs on your hosted server. **Same code, same API.**
Building it this way from Milestone 0 means multiplayer is a deployment change, not a
rewrite. The client never computes truth; it reads telemetry and sends commands.

### Physics model — patched conics + secular perturbations *(decided)*

> **Authoritative detail** (the full fidelity menu, the analytic-vs-numerical
> trade-off, perturbations, and burns) is in
> [08-simulation-and-time.md](08-simulation-and-time.md) Part A. Summary below.

Two realistic options:

- **Patched conics (recommended).** Each ship is under the influence of exactly one
  body at a time, on a clean Keplerian orbit, switching at sphere-of-influence
  boundaries. This is what KSP does. It is "real enough" for hard sci-fi and has a
  killer property below.
- **Full n-body.** Truer, but no closed-form orbits, harder to plan, harder to keep
  deterministic across machines, and far more expensive to fast-forward.

**Why patched conics is more than a shortcut:** a Keplerian orbit can be *propagated
analytically*. You can compute "where is this ship at time T" in closed form without
simulating every intermediate tick. That makes time-warp and the away-game cheap:
the server can compute the state hours into the future instantly, and can resolve
"what did your routine do over 6 hours" without grinding every frame. This single
property is worth a lot — see *Time*.

### Determinism
The sim must be deterministic: same inputs → same outputs, on every machine. Required
for multiplayer consistency and for replaying/resolving routines headlessly.

## Time

> **Authoritative detail** — active warp, jump-to-event, the three multiplayer time
> models, and the away-game — is in [08-simulation-and-time.md](08-simulation-and-time.md)
> Part B. Active warp + jump-ahead is a confirmed core feature, not just the away-game.
> Summary below.

- The world has its own **sim-time**, decoupled from wall-clock by a **time rate**.
- **Analytic propagation** (from patched conics) lets the server jump sim-time
  forward cheaply, including resolving any routines that ran during the jump.
- **Single-player:** time control is trivial — set the rate, or skip to the next
  event (next burn node, next SOI change, arrival).
- **Multiplayer (friends server):** start with a **global server time rate**,
  coordinated socially ("we're running 60× tonight", "jump to Tuesday 0800"). This is
  your stated plan and it's fine for a small group.
- **Confirmed required, not a back-pocket idea:** fast-forward must work in multiplayer
  (see [08-simulation-and-time.md](08-simulation-and-time.md) Part B). The global jump is
  cheap because analytic propagation resolves every ship and routine to the target time
  in one shot. Per-player time bubbles (à la EVE/Elite) remain an optional later
  refinement, never required for a small trusted group.

## The AI integration layer

A service sitting between the player's chat panel and the API:

1. Receives player message + a snapshot of relevant ship state.
2. Calls the LLM with: the ship-AI **persona** system prompt + the ship **API as
   tools**.
3. Runs the tool-use loop (reads, solver calls), gating write-actions behind
   confirmation.
4. Returns narration to the chat panel and any proposed action to the review UI.

**Provider:** the prototype tied into a Claude Max subscription. For a friends
server the open question is whether the server holds one shared key, or each player
**brings their own Claude credentials** (your AI = your account, your rate limits,
your bill). The latter is elegant and scales socially. See
[06-open-questions.md](06-open-questions.md).

## The routine / automation layer

Routines are player code that calls the same API. Because they run unattended and
(in multiplayer) on shared infrastructure, **arbitrary host code is not acceptable**.
Options, roughly in order of effort:

- **Constrained scripting (start here).** A sandboxed scripting language (e.g. Lua
  in a locked-down sandbox) or a small purpose-built DSL whose only capabilities are
  API calls. Easy to meter and reason about.
- **WASM (robust long-term).** Compile-to-WASM lets players write "arbitrary code"
  in real languages while staying sandboxed, deterministic, and resource-limited.
  This is the principled answer to "arbitrary code that's still safe."

Either way the routine is **metered** — CPU/steps, API-call rate, wall-time — and the
budget can be tied to the ship's **compute** resource (see
[02-gameplay.md](02-gameplay.md)). A routine can never exceed its own ship's
authority; it's just a third client of the API, with a leash.

The AI helps author and debug routines — naturally, because the AI already knows the
API (it's the AI's own toolset) and can read the routine's behavior through the same
telemetry.

## What to nail down first
The **API surface** for Milestone 0 (orbital telemetry reads + the AI's tool schema
for reading it). Everything else clips onto that. See
[05-roadmap.md](05-roadmap.md).
