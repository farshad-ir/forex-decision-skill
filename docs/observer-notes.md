# Observer Notes

## Structure

Purpose:

Extract a clean structural path from raw fractals.

Pipeline:

Fractal
→ Local High / Local Low
→ Pure Pivot
→ Swing Path
→ Inside / Breakout

Notes:

* Raw fractals are filtered.
* Consecutive highs or lows are merged into stronger extrema.
* Small swings are removed by swing filtering.
* The resulting path alternates between highs and lows.
* Each structural point can be classified as:

  * Inside
  * Breakout

Practical Meaning:

Structure provides a compressed narrative of market movement.

---

## Fractal Geometry

Purpose:

Detect clusters of nearby fractals.

### Small Box

Definition:

4 fractals within a maximum price distance of 0.0030.

Observed Usage:

* Often appears during pauses or pullbacks inside a move.
* May precede continuation.
* May precede reversal.
* Requires additional price-action analysis.

### Large Box

Definition:

6 fractals within a maximum price distance of 0.0080.

Observed Usage:

* Can visually suppress market noise.
* Multiple overlapping large boxes may highlight broader market regions.
* Current interpretation remains a hypothesis and requires further study.

Notes:

* Overlap is part of the algorithm.
* Overlapping boxes are not removed.

---

## Research Direction

Main objective:

Use market observers as sources of evidence.

Decision making should be based on:

Observer Signals
→ Market Context
→ Price Action
→ Trading Decision

The project goal is not to create more indicators.

The goal is to develop robust trading decision skills.
