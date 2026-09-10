# 09 — Hazards & Failure Cases (selection menu)

This is the palette for **what's at stake** — every way the universe (or your own
mistake) can hurt you. Tick the ones that feel right; they are **not** all meant to
coexist. The subset you choose *is* the tone:

- mostly green ticks in **A/B/F** → a navigation & logistics puzzle (trucking sim)
- heavy **C/H/I** → a survival/horror-of-space sim
- heavy **G** → a social/economic/PvP sandbox

Items note synergies with systems in [brackets]. Difficulty/severity is yours to set.

---

## A. Orbital & navigation mechanics
- [ ] Periapsis dropped below the surface/atmosphere → impact ("lithobraking")
- [ ] Insufficient Δv to complete a planned transfer → stranded mid-transfer
- [ ] Missed/late burn (slept through the window, warp ran past the node)
- [ ] Burn executed at the wrong node or wrong orientation → worse orbit than before
- [ ] Accidental escape — went hyperbolic, flung out of the intended SOI
- [ ] Failed capture — flew past the body you meant to orbit
- [ ] Orbital decay from atmospheric drag in a low orbit [drag]
- [ ] Long-term perturbation drift (J2 precession) quietly invalidates an old plan [J2]
- [ ] Collision with another object on orbit (debris, station, ship)
- [ ] Rendezvous overshoot — closing velocity too high → collision at the dock
- [ ] Ran out of RCS/attitude propellant → can't orient to burn
- [ ] Tumbling/uncontrolled rotation → can't point the engine or antenna
- [ ] Navigation/position uncertainty grows without a fix (no GPS out here) → need to re-fix off a known body/star

## B. Propulsion, power & engineering
- [ ] Engine fails to ignite / underperforms / flames out mid-burn
- [ ] Stuck-open thruster → unwanted continuous thrust, induced tumble
- [ ] Fuel or oxidizer leak → silent Δv loss you discover too late
- [ ] Cryogenic propellant boil-off over long cruises [time]
- [ ] Reactor scram / total power loss → systems dark
- [ ] Battery depletion in eclipse/shadow → brownout of non-critical systems [eclipse]
- [ ] Solar panel damage or occlusion → power shortfall
- [ ] Overheating — no convection in vacuum; radiator failure → thermal shutdown
- [ ] Engine wear / required maintenance; catastrophic failure if over-stressed
- [ ] Aggressive burn over-stresses the structure → part damage [feel: screenshake]
- [ ] Single-point failure cascades (one bus fault browns out half the ship)

## C. Life support & the human aboard (if crewed)
- [ ] O2 depletion / CO2 scrubber failure
- [ ] Water / food / consumables run out on a long transfer [time]
- [ ] Radiation dose — solar flare/CME, trapped-belt passage, deep-space GCR [eclipse/flare]
- [ ] Cabin pressure loss / hull breach
- [ ] Thermal control failure → freeze or cook
- [ ] Crew must be *awake & rested* to hand-fly critical events (sleep schedule vs burn timing)
- [ ] Medical emergency mid-mission
- [ ] Isolation/psychological strain on very long hauls (optional, sim-heavy)

## D. Sensors, computers & information
- [ ] **Sensor failure/degradation → the AI is flying blind** (it only perceives through instruments) [human-in-the-loop, window-as-sensor]
- [ ] Onboard computer fault → lose the AI, the solver, or running routines [compute]
- [ ] Comms blackout — occluded by a body, out of range, or solar interference → no remote help [latency]
- [ ] Bug in your *own* routine drives a bad action while you're away [routines]
- [ ] AI acts confidently on stale or corrupted telemetry
- [ ] Clock drift / state desync (multiplayer) [time, determinism]
- [ ] Sensor spoofing / jamming by an adversary [multiplayer]

## E. Resources, logistics & economy
- [ ] Stranded with no fuel and no rescue in range
- [ ] Cargo lost — jettisoned, damaged, or stolen
- [ ] Debt / bankruptcy — can't afford fuel, docking fees, or repairs [trade]
- [ ] Market moved against you — hauled cargo across the system, value collapsed on arrival [trade]
- [ ] Docking fees, fines, tariffs, impound [stations]
- [ ] Perishable/time-locked cargo spoils or misses its deadline [time]
- [ ] Needed part simply isn't for sale at this station → detour [trade]
- [ ] Insurance lapse / total loss of an uninsured ship

## F. Time & planning
- [ ] The only correct maneuver is to *wait* a very long time [time-warp]
- [ ] Transfer window missed → wait a full synodic period (months) for the next [time]
- [ ] An event fires while you're away and the routine mishandles it [routines, away-game]
- [ ] You warped past the thing you needed to react to [time-warp auto-limit]

## G. Multiplayer, social & adversarial
- [ ] Piracy — interception, robbery, ransom
- [ ] Boarding / hijack of a docked or disabled ship
- [ ] Griefing collisions (deliberate ramming on shared orbits)
- [ ] Sensor spoofing / jamming / decoys [sensors]
- [ ] Contract scams & disputes
- [ ] Salvage-rights conflict over a wreck
- [ ] Territory / claim disputes; blockade of a station or route
- [ ] Market manipulation / cornering by other players [trade]

## H. Environmental hazards
- [ ] Micrometeoroid / debris impact (punctures, part loss)
- [ ] Coronal mass ejection / solar flare (radiation + sensor/electronics upset) [radiation]
- [ ] Eclipse/shadow passage (power + thermal stress) [power]
- [ ] Trapped-radiation belts around magnetized planets
- [ ] Extreme thermal environment — close to a star, or deep cold
- [ ] Charged-plasma / strong-magnetic environments degrade systems
- [ ] Dust / regolith near asteroids and during landings [landing]
- [ ] Atmospheric entry: too steep → burn up; too shallow → skip back out [atmosphere, later]
- [ ] Landing hazards: slope, boulders, low visibility, insufficient hover fuel [landing, later]

## I. Catastrophic & dramatic
- [ ] Reactor meltdown / explosion
- [ ] Structural failure — the ship breaks apart under stress
- [ ] Cascading failure (one fault triggers the next in a chain)
- [ ] Fire aboard (oxygen + ignition in a sealed volume)
- [ ] **Total loss** — death / ship destroyed. *Design hook: permadeath vs. insurance
      payout vs. respawn-at-station? This single choice colors the whole game.*

## J. Docking, stations & landing (procedure failures)
- [ ] Docking misalignment → bounce, damage, or aborted approach [rendezvous]
- [ ] Airlock / clamp / latch failure
- [ ] Hard landing → leg collapse, tip-over, damage [landing, later]
- [ ] Touched down at the wrong site → burn fuel to relocate [landing, later]

---

> **How to use this:** tick what excites you, strike what doesn't, and we'll fold the
> survivors into [02-gameplay.md](02-gameplay.md) and the milestone where each
> belongs. The biggest single design decision hiding in here is **I — total loss**:
> what *exactly* happens when you die sets the stakes for everything else.
