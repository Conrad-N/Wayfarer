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

### Multiplayer (M4): the shared event-clock

**The governing law** (it overrides everything else in this section): *never gate a
player's in-game intent on real-world time.* A time-skip is something a player **pulls**
("I'm leaving anyway" / "I don't want to sit through this wait"), never something the game
**pushes** ("to do X you must now wait real hours"). Occasional short real waits (≲ an hour)
are tolerable but to be minimized. This is pillar 4 of [01-vision.md](01-vision.md).

For a small, trusted, **cooperative** group — target ~4 friends, with no direct
player-vs-player antagonism ([06](06-open-questions.md) Q4) — one model honors that law
*without anyone coordinating out-of-band*:

> **One shared, consistent timeline, advanced by a discrete-event scheduler.**

Everyone is always at the same sim-time. That keeps the world both **mutable** (players
affect the same persistent things) and **paradox-free** (there is no "my past" for someone
else to rewrite — the asteroid is mined at the one shared instant it's mined). This is the
reason a single clock is the backbone and **per-player time bubbles are explicitly *not* the
model**: let two players roam the same world at different "nows" and you get the unmineable
asteroid (A mines it at day 1000; B, earlier in real time but at day 500, mines the same
full rock in A's past — no consistent history exists). A shared clock dissolves that.

The clock does **not** run at a fixed rate. It **sleeps until the next moment some
participant actually has business, then jumps there.**

**Every agent declares a time-state** — players *and* their ship AIs, since the AI is
real-time too:

- **LIVE-hold** — "I'm acting now." Pins the clock to the present. Only grantable by
  *actually doing a time-sensitive thing* (a burn, docking, a manual maneuver, later
  combat); **idling does not hold** — after a few seconds of no time-critical action you
  decay to don't-care, so an AFK player can never freeze the world.
- **Wake-at-T** — "skip me to sim-time T (or until a condition — see ambush alarms below),
  then wake me." An alarm.
- **Don't-care** — no constraint; **forced for offline players.** Means "don't wake me for
  *others'* stops — only for my own ship's events and my own target," so a long-hauler
  isn't dragged awake at every short-cadence player's alarm.

**The clock advances** to the soonest of {any agent's wake-time, any agent's own scheduled
events} — **but only when no agent holds LIVE.** A jump is interruptible: any agent can
raise a LIVE-hold to halt it, landing exactly at the current sim-time (trivial, because
coasting is analytic).

**Two kinds of event — and only one stops the clock:**

- **Compute-events** (SOI handoffs, patched-conic frame switches, a routine's deterministic
  next step, a market tick) need the *server to recalculate*, not a human to decide. The
  scheduler **emulates straight through them** at CPU speed; no player ever sees a stop.
  Because propagation is analytic (Part A), their cost scales with the *number of events*,
  not the *duration* — coasting 200 days through three handoffs is three closed-form
  evaluations, effectively instant. Only **burns** (numerical) and dense routine
  micro-stepping cost real compute, and both are short by nature.
- **Decision-events** (a player wants to hand-fly; a routine hits a condition it isn't
  authorized to handle; a conditional/ambush trigger fires; someone's explicit wake-at-T)
  need an agent *in the loop*. **These are the only real stops.**

So **how often a skip stops is a knob you control via how much standing authority you give
your routine** — more authority → fewer interruptions → smoother skip (ties to the
review-before-execute gate, [03](03-architecture.md) Keystone 2).

**Two gears, both consensual:** discrete **jump-to-next-event** (skip the dead time) and
**continuous group warp** (e.g. 10×, to *watch* a maneuver together). Both advance only
when no one holds LIVE.

**Why it works — and where it wouldn't.** Every meeting two cooperative players actually
*want* is one they each set an alarm for, so the clock delivers it frictionlessly; the only
thing lost is the *unplanned* encounter — which only matters when players can be threats to
each other, and (for now) they can't. At ~4 trusted friends this model is complete. At MMO
scale it collapses: someone is always LIVE, the clock can never jump, and you're back to a
real-time-locked EVE — which the governing law forbids. **The small player count is
load-bearing.**

**Paying compute, not real time, is principle-safe.** A skip that costs the server some
crunch is a *loading bar* ("the computer is thinking"), not a *gate* ("wait for the
universe"). Keep it bounded — analytic coasting does this for free; only a pathological
routine (say a 600-day continuous burn) would warrant a soft cap.

### Co-presence is intentional — and that is the design
With no antagonism, players rarely share live-time *by accident*, and that's fine: every
*wanted* meeting is a scheduled convergence the clock makes cheap ("Vesper, day 900" → both
arrive at that instant). Where serendipity *is* wanted, it's engineered with **attractors**
("truck-stops": a depot whose market ticks at set times, a salvage event with a closing
window, a convoy worth escorting) that make independent alarms naturally pool — players meet
*at the truck-stop, on purpose*, with no coordinating. If direct antagonism is ever added it
arrives as **conditional / "ambush" alarms** ("wake me when another ship enters this SOI")
plus *targeted* no-skip pressure near a credible threat — a surgical exception, never a
global real-time lock. (Out of scope now; [06](06-open-questions.md) Q4.)

### The away-game — the offline / "I don't want to play through this" case
The away-game is **not** the time machine; the shared clock above is. It is the narrower,
pull-direction tool for two situations: you log off, or you simply don't want to sit through
a wait. In both you delegate to a **routine** and the world advances without you; on return,
analytic propagation + routine resolution computes what happened in one shot
([05-roadmap.md](05-roadmap.md) M5). Three consequences make routines **load-bearing, not a
late bonus:**

- **A skip is only meaningful if you've delegated what your ship does meanwhile.** "Wake me
  at day 700" with no plan is just pointless coasting. Setting an alarm and setting a routine
  are two halves of one act — which is why the routine layer is entangled with the time
  model, not separable from it ([03](03-architecture.md) Keystone 3).
- **A routine that resolves during a skip must be deterministic** — rule-based standing
  orders ("circularize at apoapsis", "abort if fuel < X"), *not* live LLM reasoning — or the
  skip wouldn't replay identically across machines (Part A determinism). The ship AI may
  *author* a routine, but the routine runs with no further LLM calls. This is Keystone 2: the
  LLM is quarantined to conversation; the deterministic layer owns anything that touches the
  sim.
- **Offline ships must be safe by construction.** Since offline forces don't-care, the world
  can skip past a logged-off player; for that to be humane, their ship defaults to a stable
  safe-hold (no risky maneuvers) unless a routine explicitly owns the risk. The time model
  depends on this invariant.

### The AI across a skip *(least-designed corner — flagged, not settled)*
Because the ship AI is real-time too, it needs two modes: **live-conversational** (you're
present — it can hold LIVE while it acts and converse at 1×) and **headless standing-orders**
(during a skip — it resolves at event boundaries via a deterministic routine and does *not*
try to converse across compressed time). How it hands off between them, and how much
unsupervised authority it carries, is the next thing to pin down.
