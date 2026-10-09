# Price Action Narrative Model

## Status

This document describes a conceptual model for reading price action
through the relationships between price structures, overlapping Small
Boxes, and the sequence of events over time.

The ideas are working hypotheses based on chart-reading experience.
They should be tested against additional examples before being turned
into rigid implementation rules.

## 1. Purpose

The objective is to model how an experienced trader reads price action.

It is not enough to detect isolated candle patterns, box boundaries,
penetrations, or breakouts. The model should combine evidence from
related structures and successive candles to form, revise, and explain
a broader market narrative.

Small Boxes are useful evidence and structural building blocks.
They should not be treated as the complete meaning of the chart.

Their relationships, overlap, sequence, and interaction with price can
help reveal behavior that a trader may also recognize on a chart
without boxes.

The goal is not merely to identify what happened to an individual box.
The goal is to understand what the price is doing across the larger
area and how the meaning of its behavior changes over time.

## 2. Working Example: EUR/USD H1, 28-29 August 2023

The example discussed here is the EUR/USD hourly chart on
28 and 29 August 2023.

### 2.1. 28 August: A Fight Inside an Overlapping Box Area

Approximately six Small Boxes overlapped or were located close
together in the same local price area.

Because these boxes were relatively short in height, price could move
slightly above one box or below another without genuinely escaping
the larger area represented by the cluster.

A break of one small box does not necessarily mean that price has
escaped the whole area.

The important observation is not simply that several boxes existed.
Their combined structure helps describe a fight:

- Price repeatedly moved around nearby box boundaries.
- Small penetrations did not necessarily constitute meaningful
  breakouts from the wider area.
- Downward progress appeared to be blocked or repeatedly unsuccessful.
- Upward movement eventually became possible.

This is a working interpretation of the example, not yet a universal
rule.

The model should preserve the evidence that supports or challenges
this interpretation rather than equating box count alone with
accumulation or direction.

The central question is:

**What does the combined behavior of these boxes tell us about the
struggle taking place inside the wider price area?**

The boxes help reveal the structure of the fight. Their relationship
with price helps reveal its outcome.

### 2.2. 29 August: Escape, Fluctuation, and a Meaningful Return

After the fight, price moved away from the area.

The escape was not a straight-line move. Price fluctuated and returned
toward the previous range.

Such movement is normal. After breaking away from a range, price may
move forward, pull back, approach the previous area, and then move
forward again.

A return can be interpreted as a possible attempt to gather passengers
before continuation. However, not every pullback should immediately
receive that label.

At the time of a return, the model may not know whether it is an
ordinary fluctuation, a failed breakout, or an important point in the
development of a directional move.

The interpretation must remain open until further evidence appears.

In the discussed sequence:

1. At 15:00, price closed below the lower boundary of the reference
   box.
2. At 16:00, price returned inside the box area, with a lower-boundary
   penetration.
3. At 17:00, price moved upward and broke above the upper boundary,
   beginning the upward movement described in the chart reading.

Viewed together, these events suggest that the downward break was not
accepted and that the return around 16:00 became an important point
in the upward narrative.

The later candle helps reveal the significance of the earlier return.

The return was not necessarily recognizable as the important point
while it was happening. Its significance became clearer when the
subsequent upward movement appeared.

The phrase "gathering passengers" is a trader's interpretation of
this behavior, not a directly measurable fact.

The model may report it as a possible explanation when the evidence
supports it, while keeping the underlying events explicit.

### 2.3. The Relationship Between the Two Days

The two days illustrate different but related parts of a larger
narrative.

On 28 August, the overlapping boxes help reveal a fight inside a
wider area. Downward movement appears to encounter resistance, and
upward movement eventually becomes possible.

On 29 August, price moves away from the area, fluctuates, and returns.
The subsequent rejection of the range and upward movement help explain
the significance of that return.

The combined narrative is:

**Fight inside an area -> escape from the area -> fluctuation and
return -> rejection of the return -> upward movement.**

This is a reading of the particular example, not a guaranteed trading
pattern. Other examples must be examined to determine which parts of
the sequence are repeatable and meaningful.

## 3. Repainting and the Evolution of a Narrative

The model is expected to revise its current interpretation as each
new candle becomes available.

In this sense, repainting is an intended property of the evolving
interpretation, not necessarily a defect.

The model should not be forced to reach a final conclusion too early.

For example, the model may initially report a possible downside break.
After price returns to the range, it may report that the downside
break is in doubt. When the next upward movement appears, it may
recognize that the return was important to the upward narrative.

The model should be able to say:

- What it observed.
- What it currently thinks the observation means.
- What evidence supports that interpretation.
- What evidence challenges it.
- What new event caused the interpretation to change.

Changing an interpretation does not mean that the previous event
should be erased.

The historical sequence must remain available so that the trader can
understand how the current interpretation developed.

### 3.1. Event Time and Recognition Time

Two different times must be recorded:

**Event time:** When the price behavior actually occurred.

**Recognition time:** When enough subsequent evidence became
available for the model to interpret the event's significance.

For example, a return may occur at 16:00, while the model recognizes
its importance after the upward movement at 17:00.

The model may then update its interpretation of the 16:00 event.
However, it must not present the conclusion as if it had known the
future at 16:00.

This distinction is essential for honest historical replay and
evaluation.

The model should preserve both the original event and the later
interpretation of that event.

## 4. A Whole-Scene View, Not Only Isolated Detectors

A possible long-term design is a program that can inspect the broader
scene as a whole, rather than relying only on separate machines that
report individual events.

The idea is not to abandon individual observers. They may still be
useful for identifying and recording specific evidence.

However, the final interpretation may require a higher-level process
that combines the observations into a coherent narrative.

Such a program could consider:

- The cluster of overlapping Small Boxes and their shared price area.
- Price movement relative to the cluster, not just relative to one box.
- Failed or shallow penetrations versus a meaningful escape.
- The direction in which price escaped.
- The structures left behind after the escape.
- Subsequent fluctuations and returns to the reference area.
- Whether price is accepted back inside the area or rejected away
  from it.
- The sequence and timing of supporting and conflicting evidence.
- The changing significance of earlier events as new candles appear.

The program should attempt to see the same larger picture that an
experienced trader sees when looking at the chart.

The architecture should remain open. It may eventually use individual
observers, state machines, a narrative engine, or a combination of
these. Experiments should determine the most useful organization.

The possibility of one program interpreting the entire scene should
not be excluded simply because the implementation currently uses
separate observers.

## 5. Design Principles

### 5.1. Boxes Are Evidence, Not the Entire Chart

The meaning of a box depends partly on its relationship with other
boxes and on the path taken by price.

### 5.2. A Break of One Box Is Not Necessarily an Escape

When boxes overlap or lie close together, price may leave one box
while remaining inside the wider area.

The model must distinguish a local penetration from a meaningful
escape from the combined structure.

### 5.3. Separate Observation from Interpretation

For example:

- Observation: Price closed below a box boundary.
- Interpretation: The downside break may be failing.
- Later interpretation: The return may have been an important point
  before an upward movement.

These statements represent different levels of understanding and
should not be treated as interchangeable.

### 5.4. Keep Interpretations Open While Evidence Is Incomplete

Several explanations may remain possible at the same time.

The model should not force every movement into a definitive category
before sufficient evidence is available.

### 5.5. Update the Narrative as New Candles Arrive

The model should revise its current interpretation when new evidence
changes the meaning of the developing price action.

It should preserve the evidence trail instead of silently erasing
previous events or conclusions.

### 5.6. Record Event Time and Recognition Time Separately

This allows the model to explain when something happened and when
its significance became recognizable.

It also helps prevent future information from leaking into earlier
historical decisions.

### 5.7. Explain the Evidence

A useful report should explain what happened, what the model currently
thinks it means, and which evidence supports or changes that view.

The model should not produce unexplained labels alone.

### 5.8. Do Not Turn One Example into a Fixed Trading Rule

The EUR/USD example from 28-29 August 2023 is a case study for
developing and testing the model.

It is not proof that every similar-looking cluster predicts an
upward move.

The objective is to discover repeatable behavior without losing the
context that gives that behavior meaning.

## 6. Immediate Research Questions

The following questions should guide further experimentation:

1. How should neighboring or overlapping Small Boxes be grouped into
   a wider area without imposing arbitrary thresholds too early?

2. What evidence distinguishes a minor penetration of one box from
   an actual escape from the clustered area?

3. How can the model retain the reference area after escape so that
   later returns can be interpreted against the same structure?

4. What evidence supports describing a return as a possible
   "passenger-gathering" point?

5. How can the model distinguish ordinary fluctuation from a return
   that later proves important to the directional narrative?

6. How should competing narratives and confidence be represented
   without pretending that an interpretation is certain?

7. How should the model record the time of an event separately from
   the time when its significance becomes clear?

8. Can a higher-level program combine the box cluster, price path,
   and event sequence into a coherent narrative resembling what an
   experienced trader sees on the chart?

9. Which parts of this narrative can be detected mechanically, and
   which require contextual interpretation based on multiple pieces
   of evidence?

## 7. Next Step

Use the EUR/USD H1 example from 28-29 August 2023 as an initial
case study.

Examine the overlapping boxes, the fight within the wider area, the
escape, the subsequent fluctuations, and the return around 15:00,
16:00, and 17:00 on 29 August.

Preserve the event sequence and test whether the model can reconstruct
the narrative without using information from candles that had not yet
closed at the time of each historical observation.

Then examine additional chart periods to determine which behaviors
are repeatable and how the model should represent them.

The immediate goal is not to produce a trading signal.

The immediate goal is to build a model that can read, explain, and
revise a price-action narrative using explicit evidence.
