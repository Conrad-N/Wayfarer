# Space Game (working title)

A hard sci-fi spaceship game played through the ship's own instrument panels. You
fly by **real orbital mechanics**. The ship carries an onboard AI — a real LLM —
that you can talk to, that reads the same telemetry you do, and that can drive the
same controls you can. Fly entirely by hand, entirely by talking to the AI, or
anywhere in between.

Later: build and refit your ship, mine asteroids, share a persistent universe with
friends, and write programs that fly your ship while you're logged off.

> **Status:** Milestone 0 **scaffolded** (web / TypeScript). The deterministic orbital
> sim, the read API, the retro nav panel + orbit scope, and the AI bridge are built;
> the sim is numerically verified (`npm run check` → 400 km circular reads 92.4 min /
> 7.67 km/s). Get oriented in [CLAUDE.md](CLAUDE.md); the contract is the
> [M0 spec](docs/07-milestone-0-spec.md).
>
> ```
> npm install
> npm run check     # prove the sim
> npm run dev       # backend :8787 + client :5173
> ```
>
> The orbit + nav panel run with no credentials; the ship-AI panel runs on a Claude
> subscription (`claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN` in `.env`, or a billed
> `ANTHROPIC_API_KEY`).

---

## The three keystones

Everything in this design falls out of three ideas. If a decision contradicts one
of these, the decision is probably wrong.

1. **One API, three clients.** The ship exposes a single control + telemetry API.
   The physical panels, the ship AI, and player-written routines are all equal
   clients of it. The game is a deterministic physics sim behind one API; the rest
   is presentation and automation.

2. **The AI is the conversation layer, never the physics layer.** A deterministic
   solver computes every trajectory. The AI translates intent into API calls,
   interprets results, and negotiates trade-offs. It never does the math itself.
   The AI's tools *are* the ship API.

3. **Routines are the time machine.** You can't unilaterally fast-forward a shared
   world, but you can write a routine and log off. The world advances; your ship
   acts; you return to consequences. The away-game is the time-skip.

---

## Documentation

Read in order:

| # | Doc | What's in it |
|---|-----|--------------|
| 01 | [Vision](docs/01-vision.md) | The fantasy, the pillars, the tone, the "why" |
| 02 | [Gameplay](docs/02-gameplay.md) | Core loop, the AI's role in play, progression, systems |
| 03 | [Architecture](docs/03-architecture.md) | The one-API model, server-authoritative sim, AI integration, routines, time, multiplayer |
| 04 | [Aesthetic](docs/04-aesthetic.md) | The retro hard-sci-fi look and sound |
| 05 | [Roadmap](docs/05-roadmap.md) | Phased plan; Milestone 0 is one ship, one planet, one AI |
| 06 | [Open Questions](docs/06-open-questions.md) | Decisions that are still open |
| 07 | [Milestone 0 Spec](docs/07-milestone-0-spec.md) | The buildable contract: orbital math, the API, the AI's tools |
| 08 | [Simulation & Time](docs/08-simulation-and-time.md) | Physics-fidelity menu + time-warp / jump-ahead design |
| 09 | [Hazards & Failure](docs/09-hazards-and-failure.md) | The "what's at stake" selection menu |

## Milestone 0 (the first buildable thing)

One ship in a stable orbit around one planet. A nav panel that presents the live
orbital state. An AI panel you can talk to — and the AI can read the live orbit and
discuss it with you. No maneuvers required yet.

The full buildable contract — orbital math, units, the API surface, the AI's tool
schema, and concrete acceptance numbers — is in
[docs/07-milestone-0-spec.md](docs/07-milestone-0-spec.md). It is stack-agnostic.
