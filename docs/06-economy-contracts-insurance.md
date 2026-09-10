# 06 — Economy, contracts, insurance, rescue

## Money and debt

Credits (cr). The player starts with a ship, a loan, and a little cash. Debt accrues
interest per sim day. Debt is the pressure that makes bad contracts tempting.

## Stations

Start with three, in different orbits so travel between them is a real choice:

| station | orbit | buys well | sells cheap | notes |
|---|---|---|---|---|
| Lowline Yard | low orbit | hull material, plating | propellant | the starter station; busy, cheap, low-value work |
| Meridian Depot | high circular | engines, reactors, sensors | spares | pays for intact high-value parts |
| Farside Relay | lunar orbit | anything (scarcity) | nothing | far, expensive to reach, best prices |

Each station has: a market (buy and sell prices per material and part kind, drifting
slowly with stock), a contract board, a repair dock, and reputation with the player.

## Contracts

Generated on the board from templates:

- **Strip:** bring back N tonnes of material or specific part kinds from derelict X.
- **Recover:** bring back one specific intact part (a reactor, a sensor package).
- **Clear:** reduce derelict X below a mass threshold (get it out of a lane).
- **Deliver:** carry goods from this station to another.
- **Tow (later):** bring a whole wreck to a station.
- **Rescue (later):** go get someone stranded.

A contract has: target, pay, bonus conditions (time, condition of parts), penalty for
failure, expected return time (used by insurance overdue checks), and a risk note
that hints at hazards. Reputation gates the better ones.

## Insurance

Bought at a station before departure:

- **Hull:** if the ship is lost, the insurer provides a replacement of similar class
  at the station (worse condition, no upgrades). Premium scales with ship value.
- **Rescue:** the insurer sends a tug when you call, or when you are overdue by a set
  period. Premium scales with destination distance and delta-v. Deductible applies.
- **Cargo:** declared cargo value is covered if the ship is lost. Premium scales with
  declared value.

Insurance is optional and costs real money each trip. The temptation to skip it is
the point.

## Rescue

A rescue call (from a terminal or the tablet, needs working comms or an insurer's
overdue check) dispatches a tug from the nearest station. Arrival time depends on
the transfer. Cost, if not insured, is a base fee plus a charge per unit of delta-v
the tug needs. The tug tows the ship back to that station. The bill is added to debt
if unpaid. Oxygen is the constraint while you wait.

## Prices and drift

Every material and part kind has a base price. Station stock rises when players sell
and falls when they buy; prices move against stock slowly per sim day. This gives a
reason to sell engines at the depot and hull at the yard, and keeps the loop from
having one right answer.
