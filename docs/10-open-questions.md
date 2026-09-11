# 10 — Open questions

Undecided things. When one is decided, move the answer to `DECISIONS.md` and delete
it here.

- **Q1 Combat.** Leaning no. Hazards and physics are the enemy. Pirates or hostile
  salvagers would change the whole tone. Decide before M6.
- **Q2 Scope of the system.** Start with one planet and its moon. Add more planets
  only if transfers between them are fun rather than long.
- **Q3 Death.** Uninsured and stranded with no oxygen: permadeath (new career), or a
  costly bailout that adds crushing debt? Could be a difficulty option. Decide in M5.
- **Q4 Warp in the local scene.** Capped at 1x now. Could allow low warp when
  nothing is moving. Decide after M4 by feel.
- **Q5 Free cutting.** Cutting plating anywhere (not just at cut points) is a big
  feature. Shipbreaker has it. Park until M6 and see if cut points alone carry the
  game.
- **Q6 Name.** Wayfarer is a working title.
- **Q7 Player ship building.** Should the player be able to refit their own ship from
  salvaged parts using the same graph? Probably yes, later. Not before M6.
- **Q8 resolved (2026-09-10).** Conrad approved magnetic boots, physical grips,
  a restrained pilot seat, and bounded suit reaction wheels before M5. See DECISIONS.
- **Q9 Unstrapped warp (asked 2026-09-10, unanswered).** Conrad asked whether the
  player may be left unstrapped during warp. Today `orbital_flight.gd` refuses warp
  above 1x unless the player is seated, because under warp the interior is carried
  by the orbital layer and a free-floating body would not be simulated honestly.
  Options: (a) keep the rule; (b) also allow warp when the boots are latched, since
  a latched player is rigid with the ship; (c) allow free-floating warp and freeze
  the player relative to the ship, accepting the fudge. Leaning (b). Conrad decides.
