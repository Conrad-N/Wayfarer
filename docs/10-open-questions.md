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
- **Q9 resolved (2026-09-12).** Conrad chose a fourth option: the player may move
  freely inside the ship during warp, and may not leave it. The ship never applies
  thrust above 1x (warp is auto-capped to 10x while rotating or burning and forced
  to 1x near objects), so the frozen hull is a still room and Jolt can simulate a
  walking or floating player against it without any fudge. Required pieces:
  (1) stop the seat/boots/wheel gating in `set_warp` and the per-tick limit at
  `orbital_flight.gd:199`; keep the 1x-near-objects rule and the 10x auto-cap;
  (2) during warp, keep simulating the player in Jolt against the frozen hull
  instead of copying the player transform from the orbital state each tick;
  (3) refuse airlock door moves while warp is above 1x, with a HUD message such as
  "DROP TO 1X BEFORE OPENING THE AIRLOCK", in `_can_move_door`;
  (4) on the drop back to local mode, give an unseated player the same velocity
  offset the seated pilot already receives so nobody hits a wall;
  (5) unstrapping mid-warp no longer ends warp. GPT task, first thing in M5.
  See DECISIONS.
