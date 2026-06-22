# 02 — Gameplay

## The core loop (active play)

1. **Observe** — read the ship's state off the instruments (orbit, fuel, systems).
2. **Intend** — decide on a goal ("I want to be in a 500 km circular orbit", "go to
   that asteroid", "get home before I run out of consumables").
3. **Plan** — either plan the maneuver by hand, or ask the AI to. The solver
   produces a concrete maneuver plan with hard numbers.
4. **Review** — the plan is presented as specs: delta-v, burn duration, fuel burned,
   resulting orbit, arrival time, etc.
5. **Negotiate (optional)** — "too much fuel, take longer", "more aggressive, I'm in
   a hurry", "can we aerobrake instead?" You (or the AI) try the burn a different way
   and re-present. This back-and-forth is a **rich interaction we want to grow into —
   depth to add once the basics are solid, not a foundational pillar or an MVP
   requirement.** The judgment lives in the operator (you or the AI); the planner is
   just the forward calculator both of you check options against.
6. **Execute** — commit the burn. Dangerous/irreversible actions are gated (a
   guarded switch, a confirmation) whether triggered by you, the AI, or a routine.
7. **Monitor** — watch it play out in real time (or under time control).
8. **Arrive** — and start the loop again.

The fun is in steps 3–5: turning a vague human intention into a rigorous, executable
plan, and haggling with physics over the trade-offs.

## The AI's role in play

The AI is a **peer operator**. Anything you can do, it can do; anything it can do,
you can do. It exists on a spectrum of delegation:

- **Tutor** — you drive, it explains. "Why is my periapsis dropping?"
- **Advisor** — you ask, it proposes, you decide. "Plan me a transfer to the
  station." It comes back with options and trade-offs.
- **Operator** — you authorize, it flies. "Get us into a parking orbit and hold."
- **Autopilot** — pre-authorized standing orders during a session.

The skill arc of a player is: lean on the AI → understand what it's doing → start
doing it by hand → eventually **write routines** so your own automation does it
without you. The AI is training wheels you never have to take off, but might want to.

### What the AI literally does under the hood

The AI is given the live ship state and the ship API as tools. When you talk to it,
it calls read-tools to inspect state and the solver to plan, then either reports
back or proposes a write-action that you confirm. It does **not** compute physics in
its head — see [03-architecture.md](03-architecture.md), Keystone 2.

### The human-in-the-loop question

Are there genuinely hard sci-fi situations where a *human* is the right controller —
not the AI, not a pre-written algorithm? Yes. The defensible ones cluster around four
ideas, and the strongest tie directly into other systems:

- **Degraded sensing — the window as a sensor of last resort.** The AI perceives the
  universe *only through instruments* (Keystone 2). When sensors are damaged, jammed,
  flare-blinded, or spoofed, the AI goes effectively blind — but a human looking out a
  **window** ([04-aesthetic.md](04-aesthetic.md)) has an independent channel the AI
  can't touch, and is the only agent who can act on it. This makes the window
  *mechanically meaningful*, not just decoration.
- **Latency — when the smart compute is far away.** If the best solver/AI runs on a
  distant station (you rent heavy compute), light-speed delay and comms blackouts mean
  it can't close a fast control loop. Onboard you have only a limited computer
  [compute] and yourself. Occluded or far out, the human + a dumb local autopilot are
  *all there is*.
- **The seconds-scale novelty regime.** A deterministic controller (PID/guidance) is
  fast but can't judge; an LLM can judge but deliberates in seconds and can be wrong
  under true novelty. The human is the only agent that is *fast enough AND capable of
  contextual judgment AND accountable* — uniquely suited to events too quick for AI
  deliberation but too novel for a fixed script.
- **Authority & accountability.** Some irreversible calls (abandon ship, ram, sacrifice
  cargo, who to rescue) can be *reserved* for the human by design — command authority,
  not raw capability. Dovetails with the review-before-execute gate.

> Not all four need to exist. **Degraded-sensing + the window** is the standout: fully
> hard sci-fi, it makes failure case D ("AI flying blind",
> [09](09-hazards-and-failure.md)) dramatic, and it gives Idea 1's windows a real job.
> **Endorsed direction**, to be deepened later — captured now so it isn't lost.

## Progression vectors

Progress is measured along several independent axes, not a single XP bar:

- **Ship capability** — better engines (more thrust / higher ISP), bigger tanks,
  better sensors, mining gear, habitation, and **compute**.
- **Resources** — propellant, ore, refined materials, money/credits, consumables.
- **Knowledge (the player's own)** — the real progression. You actually get better
  at orbital mechanics. A veteran needs the AI less and the routines more.

### "Compute" as a resource (strong idea, optional)

The ship's onboard computer is a finite resource. Better computers could gate:

- how long / how capable a **routine** can be,
- how much **AI** context or how many tokens you get per session,
- how fast the **solver** runs, or how far ahead it can plan.

This diegetically ties the AI and the automation systems into the upgrade economy:
your intelligence and your autonomy are things you literally install and power.

## Systems (in rough order of introduction)

### Navigation (Milestone 0–2)
The spine of the game. Orbital state readout, maneuver planning, the review/negotiate
loop, burns. Grows from single-burn changes → full transfers → multi-body
patched-conic routing → rendezvous.

### Rendezvous & docking (Milestone 2)
Matching position *and* velocity with another object is the hardest core orbital
problem and the gateway to mining, stations, and multiplayer interaction.

### Ship building & refit (Milestone 3)
Add/remove/upgrade parts. Every part changes the physics: mass, thrust, ISP,
sensor range, power draw, compute. The ship is a spreadsheet you fly.

### Mining (Milestone 3)
Rendezvous with an asteroid, match velocity, anchor, extract ore, haul it back to
something that wants it. The gameplay is the *rendezvous and the logistics*, not the
drilling animation.

### Stations, docking & trade (Milestone 3–4)
Dock with orbital stations to refuel, repair, refit, and **buy/sell into a living
economy** — prices move with supply and demand, so arbitrage and trade routes become
real play (touchstones: EVE Online, Ostranauts). Starts simple and single-player;
becomes shared and player-driven in multiplayer. Natural home for the economic failure
cases in [09](09-hazards-and-failure.md) §E.

### Landing (later)
Touch down on celestial bodies — **airless first** (pure powered descent: suicide-burn
timing, hover fuel, slope and site selection), **atmospheric later** (entry corridor —
too steep burns up, too shallow skips back out; then descent and touchdown). Requires
the drag/atmosphere physics in [08-simulation-and-time.md](08-simulation-and-time.md).

### Routines & the away-game (Milestone 5)
Write code against the ship API to run while you're logged off. The AI helps you
author and debug it. This is also how time effectively fast-forwards in a shared
world. See [03-architecture.md](03-architecture.md).

## Open gameplay questions
See [06-open-questions.md](06-open-questions.md) — especially the economy, whether
there's combat/threat, and what the actual long-term goal of a "career" is.
