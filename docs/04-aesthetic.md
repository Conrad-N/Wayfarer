# 04 — Aesthetic

## The one-line brief

> Hardware that looks like it was built by an aerospace contractor who assumed the
> void would try to kill it. Monochrome, low-res, robust, every pixel wired like its
> life depends on it — because it does.

## The governing fiction

The displays are built for a place with no repair shop. The design lore, in your own
words: *"this screen has every pixel wired separately because an issue with
backlighting taking the whole thing out at once in the void of space is not ideal."*

That fiction is a real art-direction constraint, and a useful one:

- **Discrete emitters, not a backlit panel.** Each pixel is its own light source.
  Visually this reads as an **LED/EL matrix** look — slight per-pixel variance, tiny
  dark gaps between pixels, individual cells that can fail in isolation (a dead pixel
  is lore, not a bug). This is subtly *different* from a smooth CRT glow.
- **Graceful degradation.** Things fail partially, never all-at-once. A panel with
  three dead segments still flies the ship. This can become real feedback: damage
  shows up as failing instruments.

## Two display species (a useful distinction)

The fiction supports two looks; using both, for different jobs, is characterful:

1. **Digital matrix panels** — alphanumerics, gauges, annunciators, system status.
   Chunky monochrome dot-matrix / segment displays. Crisp, blocky, high-contrast.
2. **Analog vector scope** — the orbit display. A glowing oscilloscope/radar tube
   drawing conic sections as vector lines, with phosphor persistence and bloom. The
   orbit is *drawn*, not rasterized. (Bonus: vector conics are easy and cheap to
   render, and historically accurate — early space hardware used exactly this.)

The split — digital matrices for numbers, an analog scope for the trajectory — gives
you visual variety while staying period-honest.

## Palette

- Monochrome per panel. Classic phosphor/LED choices: **amber (P3)** and
  **green (P1)**. A common scheme: amber for navigation, green for systems, red
  reserved strictly for caution/warning. Keep red rare so it *means* something.
- High contrast, near-black backgrounds. Light = information; darkness = absence of
  information.

## Typography

- Fixed-width bitmap font, limited glyph set, the kind that looks burned in.
- Numeric readouts: leading zeros, fixed decimal places, explicit units, monospaced
  columns that don't reflow as values change. **Stable layout is a feature** — a
  number that jitters its position is unreadable in a vibrating ship.
- Reserve **7-/14-segment** style for the most critical single numbers (altitude,
  delta-v remaining, time-to-node).

## Physical interface

- Bezels, screws, etched labels, toggle switches, rotary selectors.
- **Guarded controls for dangerous actions** — flip up the cover, then press, to
  commit a burn or jettison. The friction is intentional and diegetic; it *is* the
  review-before-execute gate (see [03-architecture.md](03-architecture.md)) made
  physical.
- Tactile feedback: things click, latch, and seat.

## Sound

Diegetic and mechanical. Relay clacks, key travel and bottoming-out, the thunk of a
contactor, cooling-fan hum, the soft tick of telemetry updating, an alarm klaxon that
you will learn to dread. Silence and hum are the baseline; sound is information.

## Post-processing

Tasteful, not a nausea simulator. Subtle per-pixel grid/gaps for the matrix panels;
persistence + bloom for the scope. Note that the "every pixel wired separately"
fiction argues **against** a uniform rolling-scanline CRT look and **toward** a
discrete-pixel matrix look for the digital panels — keep the heavy CRT treatment for
the analog scope where it belongs.

## Immersion & physicality

The panels are the interface, but you should still *feel* the ship around you.

- **Burn feedback.** During a maneuver: screen-shake, a deep engine rumble, the console
  trembling, gauges quivering, the hum building and cutting at engine shutdown. A burn
  should feel like a physical event, not a number changing — and that *sells the cost*
  of an aggressive burn (see structural-stress failure in
  [09](09-hazards-and-failure.md)).
- **Windows.** A real viewport is atmosphere — and, per the human-in-the-loop idea in
  [02-gameplay.md](02-gameplay.md), potentially a **sensor of last resort**: when the
  instruments are blinded, the eyeball through the glass is the only nav source the AI
  can't use but you can.
- **A walkable interior (later).** A small 3D ship interior you move through —
  engineering, cockpit, airlock — turning "operating panels" into "inhabiting a ship".
  Far-future; noted so earlier layout choices leave room for it.

> Tension to respect: heavy immersion FX belong to the *ship* (shake, rumble, the view
> out the window), **not** to the *displays*, which stay stoic, discrete, and robust per
> the rule above.

## North-star references
Apollo DSKY. Submarine sonar and fire-control panels. Cold-War mission control.
Oscilloscope and vector-display arcade hardware. The instrument-only tension of
*Das Boot*. The cold competence of *2001* and *The Expanse*.
