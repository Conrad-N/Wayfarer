# 05 — Roadmap

Phased so that each milestone is independently playable/testable, and so the
architecture (one API, server-authoritative, deterministic) is in place from the
start and never needs a rewrite.

> **Build rule:** even Milestone 0 runs the sim behind the API as an authoritative
> "server" (in-process is fine). The client only reads telemetry and sends commands.
> This is what makes multiplayer and routines later a deployment detail, not a
> rebuild. See [03-architecture.md](03-architecture.md).

---

## Status at a glance *(updated 2026-06-23)*

- **Milestone 0 — ✅ done.** Orbit, nav readout, scope, and the LLM ship-AI all ship
  and pass the numeric acceptance test (`npm run check`).
- **Milestone 1 — ✅ done**, and it went *further* than the original impulsive plan:
  the game runs the full **finite-thrust real-time flight model** from
  [10-flight-model.md](10-flight-model.md) (throttle, rigid-body attitude with
  reaction wheels, watch-and-fly burns, a functional nav ball, and a node-executor
  autopilot) — not the impulsive Δv this milestone first scoped. The negotiation loop
  exists as a *mechanism* (the AI re-calls the solvers and re-presents) but there is
  no constraint-driven objective solver yet ("minimize fuel" / "arrive by T").
- **Milestone 2 — ✅ done.** The **single-body rendezvous & docking** slice shipped
  earlier (Lambert intercept, match-velocity, guided midcourse trim, target selector,
  dock latch). The **multi-body leap is in**: a **heliocentric patched-conic sim**
  (Sol + Cradle + Vesper), **hyperbolic propagation**, and **deterministic SOI
  transitions** (escape/capture, warp auto-limit, jump-to-SOI). Interplanetary travel
  is a **two-step flow** (escape to the Sol frame, then intercept a co-frame planet),
  now served by an **auto transfer-window (porkchop) planner** that searches departure ×
  TOF. The ship is an **interplanetary-class drive** (~12 km/s budget) so the missions
  are actually flyable, and a **SYSTEM MAP** view draws the heliocentric layout +
  trajectory. Docking itself is still an MVP stub (latch only, no mechanics).
- **Milestone 3 — 🟡 early slice.** A **cargo + docked-transfer + station-inventory**
  MVP exists (two-limit mass/volume hold; inert cargo mass correctly shrinks the Δv
  budget). Ship-building/refit, mining, and the market/credits are **not started**.
- **Milestones 4–6 — ⬜ not started.**

Statuses below carry these markers: ✅ done · 🟡 partial · ⬜ not started.

---

## Milestone 0 — One ship, one planet, one AI — ✅ done

> **Full technical spec:** [07-milestone-0-spec.md](07-milestone-0-spec.md) — orbital
> math, units, the API surface, the AI's tool schema, and concrete acceptance numbers.

The smallest thing that captures the soul of the game.

- One planet with real gravitational parameters; one ship on a stable Keplerian
  orbit around it.
- Deterministic two-body propagation advancing in real time.
- A **nav readout panel** presenting live orbital state: apoapsis, periapsis, period,
  current altitude, speed, true anomaly, inclination — updating continuously.
- An **AI panel** you can talk to, wired to read the live orbit through the API and
  discuss it with you ("what's my apoapsis?", "is this orbit stable?", "how long
  until I'm over the north pole?").

**Done when:** you can sit and watch a correct orbit tick by on a readout, and ask
the ship AI about it and get answers grounded in the real numbers.

*Deliberately excluded:* maneuvers, graphics beyond a basic readout, multiplayer.
(A simple orbit *scope* drawing the conic is a nice stretch goal here but optional.)

---

## Milestone 1 — Maneuvers & the negotiation loop — ✅ done

The signature interaction comes online.

- ✅ The **solver**: plan a burn to achieve a target orbit. Shipped as a *library* of
  well-posed inverse solvers — circularize, set-apsis, Hohmann — plus a Lambert solver.
- ✅ The **review-before-execute** gate: plans presented as specs, committed via a
  guarded control (the AI's `execute_maneuver` and the HTTP route both require
  `confirm`).
- ✅ **Manual + AI parity** for prograde/retrograde/normal burns and full transfers —
  same API surface for both clients.
- 🟡 The **negotiation loop**: the AI can re-call the solvers and re-present under new
  framing, but there is no *constraint-driven* objective solver yet (no "minimize
  fuel" / "arrive by T"). Iterate-by-hand, not a constraint negotiator.
- ✅ Fuel and basic mass/thrust/ISP so burns actually cost something (Tsiolkovsky;
  ship mass split into dry/propellant/cargo).
- ✅ Time control — warp + **jump-to-event** for the long waits (see
  [08-simulation-and-time.md](08-simulation-and-time.md) Part B).

> **Scope change that landed here, not in M1's original plan:** the whole
> **finite-thrust real-time flight model** of [10-flight-model.md](10-flight-model.md)
> — state-vector truth with a hybrid analytic-coast / RK4-powered integrator,
> rigid-body attitude + reaction-wheel PD control, maneuver nodes, a node-executor
> autopilot, and a functional 2D nav ball — is implemented and tested. The roadmap
> originally implied impulsive burns; reality is finite burns you watch and fly.

---

## Milestone 2 — A bigger sky — ✅ done

- ✅ **Multiple bodies; patched conics; sphere-of-influence transitions.** A
  heliocentric system (Sol + Cradle + Vesper) with a body hierarchy
  ([src/sim/system.ts](../src/sim/system.ts)), analytic per-patch propagation,
  **hyperbolic** orbits ([src/sim/orbit.ts](../src/sim/orbit.ts)), and **deterministic
  SOI handoffs** in the coast path ([src/sim/world.ts](../src/sim/world.ts)) — escape to
  the parent, capture into a child, warp auto-limit at the boundary, and jump-to-SOI.
- ✅ **Transfer planning between bodies.** A **two-step flow** (escape your SOI → select
  the destination planet, now co-frame → intercept), with an **auto transfer-window
  (porkchop) planner** ([src/sim/solvers.ts](../src/sim/solvers.ts) `suggestTransferWindow`)
  that searches departure × TOF for the cheapest window. Solver tools are co-frame-gated
  with a clear "escape first" error. The default ship is an **interplanetary-class drive**
  (~12 km/s) so these trips are flyable.
- ✅ **Rendezvous & docking** — Lambert intercept, match-velocity, guided/closed-loop
  midcourse trim, a target selector, and a dock latch. *Docking is an MVP stub (latch
  only, no mechanics — see the docking TODO).*
- ✅ The orbit **scope** renders hyperbolic arcs + the **SOI ring**, the NAV readout shows
  the current body + a handoff countdown, and a new **SYSTEM MAP** view draws the
  heliocentric layout (orbit rings, SOI circles, the ship blip).

> The remaining flavour work (a fuller porkchop *plot*, richer map art) is polish, not
> milestone scope. The patched-conic backbone is in, deterministic, and flyable end-to-end.

---

## Milestone 3 — The ship as a machine — 🟡 early slice

- ⬜ Ship building / refit: parts with real mass, thrust, ISP, power, sensors, compute.
- 🟡 Resources: a **cargo** system exists (a two-limit mass+volume hold; load/unload at
  a station; inert cargo mass correctly shrinks the Δv budget). Ore, refined goods,
  credits, and consumables are not modeled yet.
- ⬜ **Mining**: asteroid rendezvous → anchor → extract → haul.
- 🟡 **Stations & docking**: a station with a transferable inventory exists and you can
  dock and move cargo. Refuel, repair, refit, and a market are **not started**.

---

## Milestone 4 — A shared universe — ⬜ not started

- Stand up the authoritative sim as a hosted server; friends connect their own ships.
- Persistence: the world and every ship survive logout.
- Global server **time rate**, coordinated socially (your stated plan).
- The economy goes **live and player-driven** — prices move; arbitrage and trade routes
  become real play.
- (Architecture already supports this from M0; this milestone is mostly networking,
  identity, and persistence — not new sim work.)

---

## Milestone 5 — Autonomy — ⬜ not started

- The **routine** layer: sandboxed scripting over the ship API, metered (tie to the
  compute resource).
- AI-assisted routine authoring and debugging.
- The **away-game**: routines execute while you're logged off; analytic propagation
  resolves what happened. This is also the individual's "time machine" (Keystone 3).

---

## Milestone 6 — Immersion & expansion (far future) — ⬜ not started

- Burn-feel FX (screenshake, engine rumble, trembling console), windows, and
  eventually a walkable 3D ship interior. See [04-aesthetic.md](04-aesthetic.md).
- Landing: airless powered descent first, then atmospheric entry & landing (needs the
  drag/atmosphere physics from [08-simulation-and-time.md](08-simulation-and-time.md)).
- Long-horizon by design; noted now so earlier art and layout choices leave room.

---

## Cross-cutting (every milestone)
- Aesthetic and sound polish accrue continuously, not as a final phase.
- Layer in failure cases from [09-hazards-and-failure.md](09-hazards-and-failure.md) as
  the relevant systems mature.
- Keep the sim deterministic and the API the single source of truth. If a feature
  needs the client to know "truth" the panels didn't read from the API, stop and
  reconsider.
