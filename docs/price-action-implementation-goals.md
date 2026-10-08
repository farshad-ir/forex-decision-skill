# Price Action Implementation Goals

## Purpose

This document defines the current implementation goals for the
Price Action part of the project.

The goal is to convert practical chart-reading observations into
observable and testable components that can later participate in
the market decision process.

These goals are based on current trading observations and experience.
They are not considered complete or final rules.

The list is intentionally open.

New observations may be added as the project develops.

---

## Current Implementation Goals

### 1. Price Conflict

Detect situations where buyers and sellers fight around an important
price area.

Typical observation:

* Price reaches an area after a directional move.
* Price cannot remain there.
* Opposing candle bodies appear.
* The conflict may continue for one, two, or several candles.
* Eventually one side becomes dominant.

The objective is to detect and describe the conflict before treating
its outcome as a trading signal.

---

### 2. Bottom Formation

Detect the observed behavior that may occur when a declining market
attempts to change into an upward phase.

Typical observation:

* The decline becomes reluctant.
* Price makes a final, sudden and relatively strong downward move.
* A deep low is formed.
* The market subsequently begins an upward movement.

This is an observation to be tested, not a guaranteed reversal rule.

---

### 3. Mother Candle

Detect unusually important large candles or short sequences of large
candles that create a visible price wall.

Subsequent candles may move back toward the mother candle but fail to
reach its important boundary.

The implementation should distinguish between:

* temporary penetration,
* meaningful break,
* and acceptance beyond the boundary.

---

### 4. Mother Candle Inside a Small Box

A mother candle may also define an important boundary of a Small Box.

If subsequent price action remains inside the box and cannot
meaningfully break the relevant boundary, the behavior may provide
evidence for continuation in the opposite direction.

This interaction between the mother candle and Small Box should be
studied separately.

---

### 5. Box Breakout and Rejection

A conventional box has an upper and lower boundary.

The initial expectation is:

* break of the upper boundary → upward movement
* break of the lower boundary → downward movement

However, price may break one boundary and then move in the opposite
direction.

The implementation must therefore distinguish a simple penetration
from a confirmed breakout and subsequent rejection.

---

### 6. Fractal Levels

Use historical fractals as potential price levels.

Levels should be classified according to their historical interaction
with price, including the number and nature of previous breaks or
reactions.

A level that has been interacted with only once may have little
importance.

A level with several meaningful interactions, but not excessive
repeated disturbance, may deserve greater attention.

When price approaches such a level, the important live observation is:

* does price pass through it?
* or does price reject it?

---

### 7. Return to the Moving Average

Detect the observed tendency for price that has moved far away from a
moving average to return toward it.

The return does not necessarily mean immediate absorption into the
average.

Price may:

* approach the average,
* enter it,
* leave it again,
* return again,
* and interact with it several times.

The moving average should therefore be treated as a reference area in
this observation, not simply as a line producing an immediate signal.

---

### 8. Head and Shoulders

Recognize the head-and-shoulders structure in several forms:

* regular,
* inverse,
* and sloped/irregular.

The implementation should focus on the structural behavior rather
than requiring a perfectly symmetrical geometric pattern.

---

### 9. Unusually Large Candle

Detect a candle whose size is unusually large compared with the recent
market behavior.

Such a candle is currently treated primarily as a risk condition.

The present practical behavior is:

> When an unusually large candle appears, stand aside.

This is intentionally a risk/observation state rather than a BUY or
SELL signal.

--

## 10. Path Barriers ("Castle") and Real Opposition

When price moves toward a Moving Average or an important level, it may encounter **barriers formed by price structure** along the path.

A barrier does not have to be a fractal or a clearly defined level. It may be:

* a single candle,
* two or more candles,
* a local high or low,
* or a small price structure visible in the current chart context.

The difficult part is distinguishing a **real barrier** from something that merely exists in the path.

We should not treat every candle or small structure as opposition. A small penetration, a minor reaction, or a candle that is not completely reversed is not necessarily meaningful opposition.

A structure becomes more interesting when price shows a **meaningful inability to pass through it**, or when the structure actually slows, rejects, or reverses the movement.

The implementation should therefore distinguish between:

**A structure that exists in the path**

and

**A structure that actually opposes the movement.**

This observation is strongly context-dependent and should remain flexible during the first implementation stages. It should not immediately be converted into a rigid rule.


---

## Initial Simulation Approach

Before implementing the complete Price Action system, the first step
is to **simulate the skill using a single observer**.

The observer should examine historical or live chart data and report
what it can recognize from the current Price Action observations.

The first objective is not to trade.

The first objective is to answer:

> Can a programmed observer recognize and describe the same type of
> market behavior that an experienced human can see on the chart?

The initial observer should therefore produce observations/evidence,
not trading decisions.

For example:

```text
Mother Candle: YES
Small Box: YES
Upper Boundary Tested: YES
Meaningful Break: NO
Price Rejected: YES
Unusual Candle: NO
```

Only after the behavior of the observer is understood and tested
should additional observers and decision logic be added.

---

## Open Scope

The items listed in this document are the current implementation
targets, not the complete definition of Price Action.

The project remains open to new observations.

When a new useful chart-reading observation is discovered, it may be
added to this document and evaluated independently.

The long-term objective is to build a collection of observers that
can simulate and organize practical chart-reading skills before
connecting them to the final trading decision process.
