# 08 — Simulation Fidelity & Time

Two questions that are really one question. *How real is the physics?* and *how do
we move through time?* are linked, because *the cheaper your propagation, the freer
your time control* — analytic orbits are exactly what let you skip a month in a
single frame without lying about where everything ended up.

---

## Part A — Physics fidelity: the menu

"Hard sci-fi" does **not** mean simulate every atom. It means *don't lie, and make
the trade-offs real*. Everything below is an approximation — the only question is
**which** approximations, and what each one costs you.

| Model | What it captures | Propagation | What you give up |
|-------|------------------|-------------|------------------|
| **Two-body Kepler** (M0) | One body's gravity, exact closed orbit | **Analytic** — state at any time in closed form | Everything beyond a single gravity source |
| **Patched conics** (recommended backbone) | A whole solar system: ship is bound to one dominant body at a time, switching at sphere-of-influence (SOI) edges. *KSP's model.* | **Analytic** within each patch | True multi-body effects: no Lagrange points, no halo orbits, no n-body capture; tiny discontinuities at SOI handoffs |
| **Perturbed conics** (recommended additions) | Conic + small forces: **J2** oblateness (orbital precession — real, and the basis of sun-synchronous orbits), **atmospheric drag** (low orbits decay → enables reentry), solar radiation pressure, third-body tugs | **Semi-analytic**: evolve elements by closed-form *secular rates* (cheap) — or numerically integrate the small forces (accurate, pricier) | Exactness; some perturbations only modeled on average |
| **Full N-body** | Every body pulls on everything; exotic orbits emerge naturally. *The Principia mod.* | **Numerical only** — integrate every step (RK4 / adaptive / symplectic) | Cheap time-warp, easy determinism, plannable targets, performance at scale |
| **CR3BP** (optional pocket) | Circular restricted 3-body — Lagrange points & station-keeping, as special content | Mixed | A general solution; it's a special case |

### The hinge: analytic vs numerical propagation

This is the single most consequential physics decision, and it's not really about
realism — it's about everything *downstream* of the physics:

- **Analytic** (Kepler / patched / secular perturbations) → state at any time `T` is a
  closed-form evaluation. This gives you, almost for free: **time-warp without
  accuracy loss** (you evaluate at the exact target time — no step error
  accumulates), **jump-to-event**, **away-game resolution**, **cross-machine
  determinism**, and **plannable targets** (stable conics you can aim at).
- **Numerical** (n-body / special perturbations) → you must integrate every step.
  Warp costs CPU or accuracy, determinism gets fragile across machines, planning is
  hard (no stable targets; trajectories drift chaotically), and cost scales with
  ships × bodies.

Full n-body buys a realism most players cannot perceive moment-to-moment, and pays
for it by sacrificing time-warp, determinism, networkability, and planning. For this
game that's a bad trade.

### Burns: impulsive vs finite
- **Impulsive** (instantaneous Δv) — valid for chemical / short burns; you stay on
  conics. **Started here** (M0/M1).
- **Finite / continuous** — thrust acts over time; during the burn you're not on a
  single conic and must integrate.

> **Update — finite burns brought forward.** Real-time finite-thrust flight (throttle,
> attitude, watch-and-fly burns) is now the baseline, not a low-thrust-only feature.
> Only *powered* flight integrates; coasting stays analytic. Full spec:
> [10-flight-model.md](10-flight-model.md).

### Decision — settled
**Patched conics + secular perturbations, propagated analytically.** J2 fairly early
(it changes planning); atmospheric drag when atmosphere/reentry arrives; SRP and
third-body only where a scenario needs them. **Impulsive burns first**, finite
(low-thrust) burns when ion drives appear. Optional CR3BP pockets for Lagrange-point
content. The *"real enough to be honest, cheap enough to warp and network"* sweet spot
— KSP-stock with selective extra rigor.

> **Not locked in even so.** The propagator sits *behind the API* and is deterministic,
> so it's swappable without touching a client: start with two-body Kepler (M0), add SOI
> patching (M2), layer perturbations in later — all pure internal upgrades.

### Decisions (settled)
- **D1 — backbone:** patched conics, not full n-body. ✓
- **D2 — perturbations:** secular J2 early; atmospheric drag with reentry/atmosphere;
  SRP / third-body only where a scenario calls for it. ✓
- **D3 — burns:** ~~impulsive first; finite when low-thrust engines arrive~~ →
  **revised: real-time finite-thrust flight brought forward now** (throttle, rigid-body
  attitude, watch-and-fly burns). Coasting stays analytic; only powered flight
  integrates. See [10-flight-model.md](10-flight-model.md). ✓

---

## Part B — Time control

With real orbital mechanics you will *routinely* face waits of hours to months
(transfer windows, long ellipses, interplanetary cruises). **Time control is a core
feature, not a convenience.** Part A is what makes it cheap and honest.

### Single-player (from M1): implement freely
- **Time rate / warp** — 1× … 10,000×+. Because orbits are analytic, **high warp does
  not degrade accuracy**: the sim evaluates state at the exact target time rather than
  taking giant error-prone steps. (This is the thing physics-by-integration games
  can't do cleanly.)
- **Jump-to-event ("warp to…")** — skip directly to the next meaningful instant: next
  maneuver node, SOI change, periapsis/apoapsis, arrival, comms window. Closed-form
  state means this is *instant*, even across months. **This is the headline feature
  for "things take forever."**
- **Auto-limits** — warp drops automatically near events, on proximity to another
  object, during a finite burn, or on an alarm. You can't blindly warp through
  something that needs your hands. (Standard KSP-style behavior.)

### Multiplayer (M4): a confirmed requirement, not an option
**Decided:** fast-forward must work in multiplayer too — waiting out real months is a
non-starter even among friends. The player count is small and trusted, so the mechanism
can stay simple:

- **Baseline — coordinated global jump / rate.** One shared clock. An authorized jump
  advances the *entire world* to a target time; an optional in-game notice covers async
  coordination ("at 20:00 the world jumps to day 14, 08:00"). Everyone always shares the
  same time. Dead simple, and exactly right for a handful of trusted players.
- **Why it's cheap:** analytic propagation (Part A) resolves *every ship and every
  routine* to the target time in closed form, in one shot — no grinding the sim through
  the skipped interval. A global jump is essentially free on the server.
- **Optional later refinement — per-player bubbles:** let an *isolated* player warp
  solo, snapping to the common rate near others. More agency, more edge cases; a
  nice-to-have on top of the baseline, never required.

Solo warp + jump-to-event stay freely available in single-player and whenever a player
is isolated. The only thing left for M4 is *polish* of the coordination UX — that it
happens is settled.

### The away-game (the always-available skip)
Routines run while you're logged off; on return, analytic propagation + routine
resolution computes what happened in one shot (see [03-architecture.md](03-architecture.md),
[05-roadmap.md](05-roadmap.md) M5). It needs no coordination because *you're* gone —
it's the multiplayer-safe time machine, and another reason the sim must stay cheap to
propagate.
