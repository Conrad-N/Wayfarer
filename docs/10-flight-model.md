# 10 — Flight Model (real-time, finite-thrust flight)

M0/M1 flew by **impulsive Δv**: the ship *was* its orbit, and a burn rewrote the
elements instantly. This document brings **finite-thrust, attitude-aware, real-time
flight** forward — KSP-style: a throttle, burns that take time, and a ship that
turns to its burn and flies it while you watch.

This **revises [08-simulation-and-time.md](08-simulation-and-time.md) D3** ("impulsive
first; finite burns when low-thrust engines arrive"). Not for accuracy — chemical
burns are short enough that impulsive is honest — but because *flying the ship is the
core loop we want*. The analytic backbone is untouched: you still **coast on rails**
(Kepler now, patched conics at M2); only **powered flight** integrates.

---

## 1. The source of truth becomes the state vector

The ship's truth becomes its **Cartesian state + rigid-body attitude**:

```
translational   r  position       [m, PCI]
                v  velocity       [m/s, PCI]
                m  mass           [kg]   (= dry + propellant)
rotational      q  orientation    (quaternion, body → PCI)
                w  angular vel.    [rad/s]
```

While coasting, `r,v` are equivalently the orbital elements — we convert both ways
with the functions M1 already ships and tests: `propagate` (elements → state) and
`stateToElements` (state → elements, RV2COE). That round-trip is what makes the
hybrid below seamless.

## 2. Two propagation modes (hybrid)

- **On-rails — coasting (throttle = 0):** analytic Kepler / patched-conic propagation,
  exactly as M0/M1. Warp free, skips cheap, determinism trivial.
- **Powered — thrust on (throttle > 0):** **numerical integration at a fixed timestep**
  (RK4) of `r, v, m` under gravity + thrust along the ship's facing. The conic morphs
  continuously; elements are derived from `(r,v)` each step for the readout.
- **Transition** is seamless: elements→`(r,v)` when the engine lights, `(r,v)`→elements
  when it cuts.

## 3. Determinism & time-warp

- Integration is **fixed-substep** (`dt_phys`, e.g. 1/64 s), never wall-clock —
  identical inputs give identical trajectories, so multiplayer and skip-resolution hold
  ([08](08-simulation-and-time.md)). `src/sim` stays pure: `dt` is passed in, no `Date.now()`.
- **Warp during a burn is allowed — it just isn't free.** Coasting warps arbitrarily
  (analytic, O(1)). Under thrust the integrator does a **lazy catch-up**: it grinds
  `dt_phys` substeps to cover the warped interval, carrying any overflow to later ticks
  so per-frame cost stays bounded. So you *can* speed through a burn — wall-clock
  compresses and the trajectory stays correct and deterministic — you just pay CPU ∝ warp,
  and at extreme rates it auto-limits (catches up over several ticks) rather than melting.
  Substep size never grows with warp, so accuracy doesn't degrade.
- The away-game resolves coasts analytically and grinds the short burn segments — still cheap.

## 4. Attitude — rigid-body dynamics

The ship rotates like a real body, not a cursor:

- **State:** orientation `q`, angular velocity `w`, body inertia tensor `I` (diagonal,
  principal axes).
- **Dynamics (fixed-step):** Euler's equation `I·ẇ = τ − w × (I·w)`; quaternion
  kinematics `q̇ = ½ q ⊗ w`.
- **Control authority:** **reaction wheels** — one max control torque `τ_max` per axis,
  no propellant cost. (RCS thrusters and wheel saturation/desaturation are a later refinement.)
- **Attitude controller (the autopilot's inner loop):** a quaternion **PD law** →
  torque, clamped to `τ_max`, tuned near-critically-damped so it slews to and holds a
  heading without wild overshoot. This is what you watch flip around.
- **Hold modes (commanded heading):** prograde, retrograde, normal, anti-normal,
  radial-in, radial-out, **point-at-node**, **kill-rotation** (null `w`), and **manual**.
  Hold modes constrain the thrust axis; roll is tracked but free (cosmetic for a single
  engine).
- **Manual:** direct pitch / yaw / roll torque inputs.

## 5. Throttle & engine

- **Throttle** `t ∈ [0,1]` — a commanded value, set by the panel slider, the AI, and
  (later) routines, all through the API.
- **Engine:** thrust `F` (N), `Isp` (s). Thrust accel = `F·t/m` along +facing; mass
  flow `ṁ = F·t/(Isp·g0)`. Burns last tens of seconds — that is the point.

## 6. Maneuver nodes & execution (replaces the instant burn)

- The **solver is unchanged** — `planRaiseApoapsis` / `planTransferToCircular` still
  compute Δv. *Execute* now drops a **maneuver node**: a Δv vector (prograde / normal /
  radial components) at a sim-time, instead of teleporting the orbit.
- **Node executor (autopilot):** point at the node's burn vector → at `T − ½·burnDur`
  throttle up → integrate until delivered Δv meets the node → throttle 0. The classic
  flip-and-burn, flown for you while you watch — or fly it by hand (manual throttle +
  attitude).
- Finite burns won't hit the target perfectly (cosine + gravity losses) — that's real,
  and why you have a nav ball and a throttle. For now burns fly **open-loop** and may
  miss slightly; you trim by hand.
- **Later (noted):** a **closing-the-loop burn autopilot** — trims/re-solves the node
  against the live orbit so finite-burn error is nulled automatically (e.g. re-deriving a
  transfer's circularization node at apoapsis). Deferred for now.

## 7. Nav ball (functional 2D)

A circle in the orbital frame carrying the markers — prograde/retrograde,
normal/anti-normal, radial-in/out, the active **node** — and the ship's **pointing
reticle**, which slews across it in real time as the ship turns, plus a turn-rate
(`w`) indication. CRT-styled to sit beside the existing panels; a full 3-D sphere is a
later upgrade.

## 8. API additions (reads unchanged; the write surface grows)

- `set_throttle(0..1)`, `set_attitude_mode(mode)`, `set_manual_torque(pitch,yaw,roll)`.
- nodes: `create_node`, `list_nodes`, `delete_node`, `execute_node` (executor on/off).
- telemetry adds: attitude `q`, `w`, throttle, current thrust, the frame markers
  (prograde dir, node dir, …), Δv remaining on the active node, and the warp-clamp state.
- AI tools mirror these — the AI flies by **commanding**, never by computing physics
  (Keystone 2).

## 9. Keystones — all intact

- **1 — one API, three clients:** same surface, more commands. Panel, AI, routines stay equal.
- **2 — AI is conversation, never physics:** the AI sets throttle / attitude / nodes; math stays in the solver + integrator.
- **3 — server-authoritative + deterministic:** held by fixed-step integration. The only
  change is warp clamps during thrust — physical, not a regression.

## 10. Build stages

1. **Physics core (headless, tested):** state vector + hybrid coast/powered propagation +
   rigid-body attitude + PD controller + fixed-step loop. `check-sim` asserts: a finite
   burn delivers `Δv = Isp·g0·ln(m0/m1)`; a 180° slew settles in ~`T`; a coast still
   matches the analytic orbit; results are identical across timestep sizes.
2. **Flight API + nodes + executor:** throttle / attitude / manual commands, node CRUD,
   the node-executor autopilot, the warp clamp; HTTP routes + AI tools + persona.
3. **UI:** nav ball, throttle slider, attitude-mode buttons, node display + executor
   controls. The orbit scope morphs live during burns (falls out for free).

## 11. Default numbers (tunable, set in Stage 1)

Tuned generously — a near-future tech level — for fun, while staying legitimately
feasible (same spirit we'll apply to fuel efficiency etc.). Turning and burning are
~40% quicker than a literal present-day reading.

| Quantity | Default | Gives |
|----------|---------|-------|
| Thrust `F` | 50 kN | accel ≈ 4.2 m/s² at 12 t; a 109 m/s burn ≈ 26 s |
| `Isp` | 320 s | `ṁ` ≈ 16 kg/s at full throttle |
| Inertia (≈10 m × 3 m, 12 t) | `I_roll ≈ 1.4e4`, `I_pitch=I_yaw ≈ 1.1e5` kg·m² | — |
| Reaction-wheel torque `τ_max` | ≈ 5.5 kN·m/axis | ~16 s for a 180° flip |
| Angular-rate cap | ~20°/s | keeps slews readable |
| Warp under thrust | lazy catch-up (auto-limits) | speed through burns at CPU cost, still deterministic |
