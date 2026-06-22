# 07 — Milestone 0 Technical Spec

**Goal of M0:** one ship on a stable Keplerian orbit around one planet; a nav panel
that presents the live orbital state; an AI panel that can read that same state
through the API and discuss it. No maneuvers. Stack-agnostic — this spec is the
contract; the engine choice ([06-open-questions.md](06-open-questions.md), Q1) does
not affect any of it.

This document is deliberately precise. Hard sci-fi means the numbers must be right,
so the numbers are written down.

---

## 1. Conventions

| Quantity | Internal unit | Notes |
|----------|--------------|-------|
| Length / distance | **meters (m)** | display may show km |
| Time | **seconds (s)** | sim-time, not wall-clock |
| Angle | **radians** internally | display in degrees |
| Mass | **kilograms (kg)** | ship mass static in M0 |
| Velocity | **m/s** | |

- **The simulation and the API speak SI.** Unit-friendliness (km, minutes, degrees)
  is a *presentation* concern, done in the panel and by the AI, never in the sim.
- **Reference frame:** planet-centered inertial (**PCI**), right-handed. **+Z** is
  the planet's north spin axis; **+X** is a fixed reference direction in the
  equatorial plane; **+Y** completes the triad. In M0 the planet does not rotate, so
  this frame is simply fixed in space.
- **Angles measured** counter-clockwise looking down from +Z.

---

## 2. The central body

One body, defined by a small parameter set. M0 default is **Earth-like** so every
number is checkable against reality:

```
name                "Cradle"  (placeholder)
mu  (μ = G·M)       3.986004418e14   m^3 / s^2
radius (R)          6.371e6          m
rotation_period     null             (non-rotating in M0)
```

`μ` (the standard gravitational parameter) is the only constant the orbit math needs.
`R` is needed to convert orbital **radius** (distance from center) into **altitude**
(height above surface) — keep those two distinct everywhere; conflating them is the
classic bug.

---

## 3. Ship orbital state & propagation

### 3.1 Stored state (the source of truth)

A ship's orbit is stored as **classical orbital elements at an epoch** — compact,
exact, and analytically propagatable:

```
a       semi-major axis            m
e       eccentricity               (0 ≤ e < 1 for M0; closed orbits only)
i       inclination                rad
Omega   RAAN (Ω, longitude of asc. node)   rad
omega   argument of periapsis (ω)  rad
M0      mean anomaly at epoch       rad
t0      epoch (sim-time)            s
```

Everything else is **derived** by propagating to the current sim-time `t`. We never
store position/velocity as truth — they're computed on demand. This is what makes
fast-forward free later (Keystone 3): state at any `t`, past or future, is one closed
-form evaluation, no stepping.

### 3.2 Propagation pipeline (elements + t → everything)

```
1. Mean motion:        n = sqrt(μ / a^3)                         [rad/s]
2. Mean anomaly now:   M = M0 + n·(t − t0)        (wrap to [0, 2π))
3. Solve Kepler:       M = E − e·sin(E)   for eccentric anomaly E
                       Newton: E ← E − (E − e·sinE − M)/(1 − e·cosE)
                       seed E = M; iterate to |ΔE| < 1e-10 (≈4 iters at e<0.1)
4. True anomaly:       ν = 2·atan2( √(1+e)·sin(E/2),  √(1−e)·cos(E/2) )
5. Radius:             r = a·(1 − e·cos E)            [m]
6. Speed (vis-viva):   v = sqrt( μ·(2/r − 1/a) )      [m/s]
```

For the full Cartesian state vector (needed by `get_state_vector` and for latitude):

```
7. Perifocal position: r_pf = r·[cos ν, sin ν, 0]
   Perifocal velocity:  v_pf = (μ/h)·[−sin ν, e + cos ν, 0],  h = sqrt(μ·a·(1−e²))
8. Rotate perifocal → PCI by the 3-1-3 sequence (Ω, i, ω):
   Q = Rz(Ω)·Rx(i)·Rz(ω)        r = Q·r_pf      v = Q·v_pf
```

Latitude of the sub-ship point (enough for "when am I over the pole?", no Cartesian
needed): with argument of latitude `u = ω + ν`,  `sin(lat) = sin(i)·sin(u)`. Maximum
latitude equals the inclination `i`, reached at `u = 90°` and `u = 270°`.

---

## 4. Derived telemetry catalog

Everything the nav panel and the AI can read. All from the elements + μ + R + t.

| Field | Symbol | Formula | Unit |
|-------|--------|---------|------|
| Semi-major axis | a | (stored) | m |
| Eccentricity | e | (stored) | — |
| Inclination | i | (stored) | rad |
| RAAN | Ω | (stored) | rad |
| Arg. of periapsis | ω | (stored) | rad |
| Period | T | 2π·√(a³/μ) | s |
| Mean motion | n | √(μ/a³) | rad/s |
| Periapsis radius | r_p | a·(1−e) | m |
| Apoapsis radius | r_a | a·(1+e) | m |
| Periapsis altitude | — | r_p − R | m |
| Apoapsis altitude | — | r_a − R | m |
| True anomaly | ν | §3.2 | rad |
| Eccentric anomaly | E | §3.2 | rad |
| Mean anomaly | M | §3.2 | rad |
| Current radius | r | a·(1−e·cosE) | m |
| Current altitude | h | r − R | m |
| Speed | v | √(μ·(2/r−1/a)) | m/s |
| Specific energy | ε | −μ/(2a) | J/kg |
| Spec. ang. momentum | h⃗ | √(μ·a·(1−e²)) | m²/s |
| Flight-path angle | γ | atan2(e·sinν, 1+e·cosν) | rad |
| Time since periapsis | — | M/n | s |
| Time to periapsis | — | (2π−M)/n | s |
| Time to apoapsis | — | ((π−M) mod 2π)/n | s |
| Sub-ship latitude | — | asin(sin i·sin(ω+ν)) | rad |

---

## 5. The API contract (reads)

M0 is read-only — no maneuvers — but the API is shaped **write-ready** so M1's
commands slot in without reshaping. In M0 these are plain in-process function calls;
the signatures are defined as a contract so they can become RPC at M4 unchanged.

```
get_clock()            → { t: seconds, rate: number }          // sim-time + time multiplier
get_central_body()     → { name, mu, radius, rotation_period|null }
get_ship()             → { id, name, mass_kg }                  // mass static in M0
get_orbit()            → OrbitState                             // the §4 catalog, SI
get_state_vector()     → { r:[x,y,z], v:[vx,vy,vz] }            // PCI, m & m/s
predict_orbit(t)       → OrbitState                             // §4 catalog at sim-time t
```

`OrbitState` is the full §4 field set as a flat object in SI units. `predict_orbit`
is the same evaluation as `get_orbit` at an arbitrary `t` — it exists now because it's
nearly free (closed-form) and it powers questions like "where will I be in 40
minutes?" and "when am I next over the pole?".

**Write-ready note:** M1 adds `plan_maneuver(constraints) → ManeuverPlan` and
`execute_maneuver(plan, confirm) → result`, plus the confirmation gate. The read
surface above does not change.

---

## 6. The AI layer

The AI panel is a thin bridge: player message + ship-state snapshot → Claude (with
the API as tools) → narration back. Keystones 1 & 2 made concrete.

### 6.1 Tool schema given to Claude

In M0 the AI's tools *are* the read API. Each is a Claude tool definition; returns are
the SI shapes from §5. The AI converts units and explains; it never recomputes physics.

```
get_clock          — "Current simulation time (s) and time rate."          (no params)
get_central_body   — "Physical parameters of the planet being orbited."    (no params)
get_orbit          — "The ship's complete current orbital state (SI)."     (no params)
predict_orbit      — "The ship's orbital state at a future/past sim-time."  { t: seconds }
```

### 6.2 Persona system-prompt sketch

> You are the onboard AI of a small spacecraft. You speak to the operator over a text
> console: terse, precise, calm, a competent crewmate — not a chatbot. You have
> instruments, not intuition: to answer anything about the ship's orbit, **call your
> tools** and reason from the returned numbers. Never estimate orbital quantities in
> your head. Returned values are SI (meters, seconds, radians); present them in
> operator-friendly units (km, minutes, degrees) and say which. If a value is
> ambiguous, distinguish **altitude** (above surface) from **radius** (from center).

### 6.3 Confirmation gate
Trivial in M0 (no write-actions exist). The gate is specified now so it's not
bolted on later: any future tool that changes the world returns a *proposal* and
requires explicit operator confirmation before a second call commits it. See
[03-architecture.md](03-architecture.md).

---

## 7. M0 runtime architecture

```
   ┌────────────────────────────┐
   │  Authoritative sim (server) │   one body + one ship (elements, epoch)
   │  advances sim-time by rate  │   answers reads by propagating to "now"
   └───────────────┬────────────┘
                   │  THE API (§5)  — in-process for M0
        ┌──────────┴───────────┐
        │                      │
  ┌─────┴──────┐        ┌──────┴───────┐
  │ Nav panel  │        │  AI bridge   │
  │ polls reads│        │ chat→Claude  │
  │ renders §4 │        │ (tools=§6.1) │
  └────────────┘        └──────────────┘
```

- **Sim loop:** advance `t += dt · rate` on a fixed cadence (e.g. 10–30 Hz is plenty;
  the orbit is analytic so cadence only affects UI smoothness, not accuracy).
- **Nav panel:** polls `get_orbit()` each frame, renders the §4 readout. (A vector
  *scope* drawing the conic is an optional stretch — see [04-aesthetic.md](04-aesthetic.md).)
- **AI bridge:** on each player message, snapshot state, run the Claude tool-use loop,
  stream narration to the console.
- **Determinism:** pure analytic Kepler propagation ⇒ identical output for identical
  `(elements, epoch, μ, t)` on any machine. No integrator, no drift.

---

## 8. Acceptance criteria

M0 is done when all of the following hold for the **canonical test orbit** — a
circular 400 km orbit around the Earth-like default (a = R + 400 km = 6.771e6 m,
e = 0):

- [ ] Nav panel shows period **≈ 92.4 min** (5544 s) and speed **≈ 7.67 km/s**
      (7672 m/s), apoapsis altitude = periapsis altitude = **400 km**, and these stay
      stable as sim-time advances (it's circular — they shouldn't drift).
- [ ] True anomaly / position advances smoothly and wraps cleanly at one full period.
- [ ] A second **elliptical** test (e.g. 400 km × 800 km altitude) shows speed rising
      toward periapsis and falling toward apoapsis per vis-viva, period ≈ 96.5 min.
- [ ] The AI, asked "what's my orbit?", calls `get_orbit`, and reports the numbers
      correctly in friendly units — distinguishing altitude from radius.
- [ ] The AI, asked "when am I next over the north pole?" on an inclined orbit, uses
      `predict_orbit` / the anomaly and gives an answer consistent with the panel.
- [ ] Same inputs reproduce the same state across restarts (determinism).

> Quick sanity math for reviewers: v_circular = √(μ/r) = √(3.986e14 / 6.771e6) =
> 7672 m/s. T = 2π·√(r³/μ) = 5544 s = 92.4 min. ✓

---

## 9. Explicitly out of scope for M0

Maneuvers and the solver (M1) · fuel/mass changes (M1) · multiple bodies / patched
conics / SOI (M2) · planet rotation, longitude, ground tracks · orbital perturbations
(J2, drag, third-body) · networking/persistence (M4) · routines (M5) · any graphics
beyond the readout (the scope is optional).

When M0 works, the spine of the game exists: a correct universe, a window into it,
and a mind aboard that can read it with you.
