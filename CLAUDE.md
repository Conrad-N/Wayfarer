# CLAUDE.md — Wayfarer (Space Game)

Hard sci-fi spaceship game. This repo is at **Milestone 0**: one ship on a stable
orbit around one planet, a retro nav panel, and a real LLM ship-AI that reads the
live orbit through the same API the panel uses.

**Read the design first.** [docs/](docs/) is the source of truth — start at
[docs/README is the repo README]; the load-bearing docs are
[docs/03-architecture.md](docs/03-architecture.md) (the three keystones) and
[docs/07-milestone-0-spec.md](docs/07-milestone-0-spec.md) (this milestone's contract).

## The three keystones (don't violate these)

1. **One API, three clients.** Panels, AI, and (later) routines are equal clients of
   one ship API behind the authoritative sim. The API lives in
   [src/sim/api.ts](src/sim/api.ts); HTTP routes and the AI's tools both call it.
2. **The AI is conversation, never physics.** The deterministic solver owns all math
   ([src/sim/orbit.ts](src/sim/orbit.ts)); the AI calls tools and narrates. Never
   ask the LLM to compute orbital quantities.
3. **Server-authoritative + deterministic.** The client never computes truth — it
   reads telemetry and renders. SI units internally; convert only at the UI edge.

## Layout

```
src/sim/      pure, deterministic, dependency-free orbital sim (runs in Node)
  types.ts      shared types (OrbitalElements, OrbitState, CentralBody)
  constants.ts  Earth-like default body + helpers
  orbit.ts      Kepler propagation (elements + t -> full state)
  world.ts      the authoritative World (body + ship + sim-time + warp rate)
  api.ts        THE read API — the single contract
src/server/   Node + Express backend
  index.ts      sim tick, API routes, AI chat endpoint
  ai-bridge.ts  Anthropic tool-use loop; the AI's tools wrap the read API
src/client/   browser (Vite, vanilla TS): nav readout, orbit scope, AI console
scripts/      check-sim.ts — numeric acceptance test (docs/07 §8)
```

## Run

```
npm install
npm run check       # prove the sim: 400 km circular -> ~92.4 min, ~7.67 km/s
npm run typecheck
npm run dev         # backend (:8787) + Vite client (:5173, proxies /api)
```

The orbit + nav panel work with no credentials. The ship-AI panel runs on a Claude
**subscription** (no per-token API key): the bridge uses the Claude Agent SDK
(`@anthropic-ai/claude-agent-sdk`), whose in-process MCP tools ARE the read API.
Mint a token once with `claude setup-token`, copy `.env.example` → `.env`, and set
`CLAUDE_CODE_OAUTH_TOKEN`. A billed `ANTHROPIC_API_KEY` is the alternative. Model
defaults to `claude-sonnet-4-6` (override with `SHIP_AI_MODEL`). The shared-vs-
bring-your-own access model is still open question Q2.

## Conventions

- SI everywhere in `src/sim` and the API; friendly units only in `src/client`.
- Keep `src/sim` pure and deterministic — no `Date.now()`/`Math.random()` in it, no
  Node or DOM deps. It must give identical output for identical inputs (multiplayer
  and the away-game depend on this).
- If a feature needs the client to know something the panels didn't read from the
  API, stop — that breaks Keystone 1.
