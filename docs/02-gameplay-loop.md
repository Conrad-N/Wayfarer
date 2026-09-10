# 02 — Gameplay loop

## The loop

```
STATION                PLAN                 FLY                 SALVAGE              RETURN
take contract    ->   plan transfer   ->   burn, coast,   ->   EVA, scan, cut,  ->  pack, plan,
buy fuel, spares,     check dv/O2/time     warp, arrive,       haul, manage         burn home,
insurance, repair,    budget               match velocity      hazards and          dock, sell,
sell salvage                                                    your own ship        pay debt
```

A single trip should take 20 to 90 minutes of real time. Time warp makes coasts short.

## Station

Docked at a station you use its terminals, or your own ship's, to:
- read the contract board and accept work,
- buy propellant, oxygen, spare parts, tools, and insurance,
- sell salvaged parts and raw material at that station's prices,
- repair ship systems that need a dock,
- pay down debt.

Stations differ: a low-orbit yard buys hull material cheap and sells fuel dear; a
high-orbit depot pays well for intact engines and reactors. Prices are the reason
to fly further.

## Plan

At a terminal you open the planner: pick a target, get a transfer, read the
delta-v, propellant, time, and oxygen it needs against what you have. The
calculators are in-game and complete. The optional ship AI can talk you through
them but does nothing the calculators cannot.

## Fly

Real orbital mechanics. You set up a maneuver, point the ship, burn, then coast
under warp. Arriving means matching velocity with the wreck. As you close in, the
local scene loads silently and the wreck becomes a physical thing.

## Salvage

You leave through the airlock with a suit, a cutter, a grapple, hand grips, magnetic boots, and
a scanner. The suit has oxygen, propellant, and battery. The wreck is an unknown
shape made of known parts. You:
- scan to learn part values, masses, and where hazards are,
- decide an order: what to cut first so the rest becomes reachable,
- cut at cut points; the wreck splits into free-floating bodies, momentum conserved,
- carry parts with a physical grip and suit thrust, or haul them with the grapple.
  Added mass slows your acceleration and makes turning harder,
- fit parts through your cargo door, or cut them smaller and lose value, or tow
  them outside and accept a heavier, slower ship,
- watch your own ship: a loose tank drifting into it is your problem.

Hazards are physical. Fuel vents and pushes. Coolant sprays and shoves. Pressurised
compartments pop. Live power arcs. They move things, including you and your ship.

## Return

Pack, check the mass budget, plan the burn home. A heavier ship needs more
propellant than it did on the way out. That was in the budget, or it wasn't.

## Failure and recovery

Things that go wrong, and the in-world answers:

| Trouble | In-world answers |
|---|---|
| Out of propellant | Insurance rescue. Paid rescue tug (cost scales with distance and delta-v). Salvage propellant from the wreck. |
| Ship disabled (power, engine, comms) | Repair with spares. Salvage the part from the wreck. Call rescue if comms work. |
| Suit oxygen low on EVA | Get back to the ship. If the ship is gone, the insurer's overdue check finds you, eventually. |
| Debt | Interest accrues per day of sim time. Contracts get more desperate. |

There is no free respawn. Uninsured and stranded is a lost ship. Whether that is
permadeath or a costly bailout is open question Q3.

## Progression without stats

- **Tools:** stronger cutters, longer grapples, better scanners.
- **Ship:** bigger cargo door, more propellant, more power, more spares, a tow rig.
- **Knowledge:** you learn ship classes, where their reactors sit, what leaks.
- **Reputation:** stations open better contracts to people who deliver.
- **Money:** less debt means you can turn down bad jobs.
