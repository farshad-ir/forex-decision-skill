# Observer Development Progress: MA Bifurcation and Parade ZigZag

## 1. Purpose

This document records the development progress of two independent algorithms in the `src` directory:

- **MA_Bifurcation** — analyzes the branching behavior of moving-average-derived price sequences to reduce the influence of small fluctuations during chart compression.
- **Parade_ZigZag** — investigates alternative methods for identifying turning points and fitting a zigzag path to historical price action.

These algorithms address different problems. They are documented together here only to report project progress; they do not depend on each other.

---

## 2. MA_Bifurcation

### 2.1. Problem

During periods of chart compression, moving averages can exhibit small fluctuations that do not necessarily represent meaningful directional movement.

Simply following every fluctuation can produce excessive noise. The objective is to identify persistent directional behavior while allowing small branches to expire when they fail to develop.

### 2.2. Branching Principle

The algorithm processes one new point at a time.

For each incoming point:

1. Existing branches are examined in their current order.
2. The point is added to the first compatible branch.
3. If no existing branch accepts the point, a new branch is created.
4. Branches retain their accumulated history while they remain active.
5. Expired branches are physically removed from the branch array.

This approach preserves competing directional developments without requiring every small fluctuation to become a permanent part of the analysis.

### 2.3. Branch Lifetime

Branch expiration is controlled by a waiting period derived from the number of active branches.

The intended rule is:

`waiting = clamp(activeBranchCount - 1, minWaitingPoints, maxWaitingPoints)`

The default limits are:

- `minWaitingPoints = 2`
- `maxWaitingPoints = 5`

The waiting period determines how long a branch can remain without sufficient development before it is removed.

### 2.4. Directional Interpretation

The algorithm evaluates the directional branches using their accumulated points.

The intended interpretation is:

- More rising branches than falling branches: **Rising**
- More falling branches than rising branches: **Falling**
- Equal counts: **Unknown**

Branches containing only one point do not contribute to the directional vote.

### 2.5. Current Progress

The branch-processing structure, branch compatibility, expiration logic, and directional interpretation have been developed.

The intended input is derived from one or more moving averages rather than directly from arbitrary price fluctuations. This allows the algorithm to investigate the branching behavior of moving-average geometry, particularly during periods of compression.

**Implementation note:** The current source still contains a placeholder assignment for the point price:

`point.price = 1;`

Consequently, connecting the point to the actual moving-average-derived value remains an implementation task. The moving-average input should not yet be considered fully connected.

### 2.6. Remaining Work

- Replace the placeholder price assignment with the actual moving-average-derived value.
- Verify that each completed H1 candle contributes exactly one new point.
- Test branch creation, compatibility, and expiration on historical data.
- Evaluate how effectively the branching mechanism filters small fluctuations during compression.
- Validate directional results against representative historical periods.

---

## 3. Parade_ZigZag

### 3.1. Problem

The objective is to identify a plausible zigzag path through historical price action by combining several methods for detecting turning points.

The analysis considers the behavior of bullish and bearish candle sequences, confirmed fractals, and alternative turning-point candidates. The resulting candidates are evaluated geometrically to identify a suitable path.

A particular application is the analysis of free candles located between the previous box and the current box, outside the box structures themselves.

### 3.2. Historical Price Interval

The current implementation analyzes a specified historical H1 interval using start and end times.

The intended application is to extract the relevant free candles between consecutive boxes and analyze their price geometry.

The automatic extraction of this interval from the arrival of a new box remains a task for the calling layer.

### 3.3. Fractal Geometry

The algorithm identifies fractal candidates using two candles on each side of the central candle.

It also supports equal neighboring values.

For a high fractal:

- The central high must be greater than or equal to all four neighboring highs.
- It must be strictly greater than at least one neighboring high.

For a low fractal:

- The central low must be less than or equal to all four neighboring lows.
- It must be strictly less than at least one neighboring low.

This permits certain equal-high and equal-low configurations to qualify as fractals without treating a completely flat set of neighboring values as a meaningful extremum.

Fractals provide candidate turning points; they do not automatically determine the final zigzag path.

### 3.4. Parade-Based Turning-Point Methods

The implementation investigates five methods for generating turning-point candidates.

#### Method 1: Three Opposing Candles

A sequence of three candles opposing the current parade can indicate a possible reversal.

#### Method 2: Opposing Wick Crosses Anchor Open

An opposing candle's wick crossing the parade anchor's opening price can provide evidence that the existing parade has been challenged.

#### Method 3: Trailing Anchor

The anchor can advance as the parade develops, allowing the method to follow the evolving structure rather than relying exclusively on its original starting point.

#### Method 4: Close Beyond Anchor

A candle closing beyond the anchor provides another possible condition for identifying a change in the parade.

#### Method 5: Cumulative Favourable Candles and Anchor Advancement

The method considers favourable candle development and changes to the anchor as the parade progresses.

These methods provide alternative ways of generating candidates. Their results can be compared rather than assuming that one rule must explain every market configuration.

### 3.5. Candidate Consolidation

Different methods can identify the same candle and the same type of extremum.

The implementation merges candidates that refer to the same candle and extremum type while retaining information about their originating methods.

This preserves the provenance of each candidate and avoids unnecessarily duplicating identical turning-point locations.

The algorithm also applies limits to the number of candidate points and intermediate zigzag vertices.

### 3.6. Geometric Zigzag Fitting

After generating turning-point candidates, the algorithm evaluates combinations to select a zigzag path.

The path has fixed beginning and ending points, while its intermediate vertices are selected from the candidate set. The intermediate vertices must alternate between highs and lows.

The primary fitting criterion is the sum of squared errors between actual candle closing prices and the piecewise-linear path:

`SSE = sum((close - fittedPrice)^2)`

An interior-amplitude imbalance measure is used as a secondary criterion.

The algorithm retains the best path and, when available, an alternative path.

This allows the analysis to compare plausible geometric interpretations rather than treating every detected fractal or parade reversal as a mandatory zigzag vertex.

### 3.7. Current Progress

The current implementation includes:

- Historical H1 interval analysis.
- Fractal detection with support for equal neighboring highs and lows.
- Five parade-based candidate-generation methods.
- Consolidation of candidates identified by multiple methods.
- Candidate-source tracking.
- Limits on candidate and zigzag sizes.
- Geometric evaluation of alternative zigzag paths.
- Retention of the best path and an alternative when available.

Together, these components establish a framework for comparing different interpretations of historical price geometry.

### 3.8. Remaining Work

- Connect the analysis to the arrival of a new box.
- Extract the free candles between the previous box and the current box.
- Ensure that the interval boundaries follow the project's box-indexing and time conventions.
- Compare the results of the five parade methods on representative historical intervals.
- Examine how fractal candidates and parade candidates contribute to the selected paths.
- Validate the selected zigzags against known historical configurations.

---

## 4. Development Status

| Aspect | MA_Bifurcation | Parade_ZigZag |
|---|---|---|
| Primary objective | Analyze branching behavior in moving-average-derived sequences | Identify and fit plausible zigzag paths |
| Main input | Sequential points intended to come from moving averages | Historical H1 candle data |
| Core mechanism | Compatible branches with controlled expiration | Fractal and parade-based turning-point candidates |
| Noise handling | Remove branches that fail to develop | Consolidate candidates and evaluate alternative paths |
| Directional or geometric result | Rising, Falling, or Unknown | Best-fitting zigzag and, when available, an alternative |
| Current limitation | Actual moving-average-derived price assignment remains to be connected | Automatic extraction of free candles between consecutive boxes remains to be connected |

---

## 5. Summary

Two independent areas of observer development have progressed.

**MA_Bifurcation** introduces a persistent branching mechanism for studying moving-average-derived sequences. Its purpose is to distinguish developing directional structures from small fluctuations, particularly during chart compression. The actual moving-average input connection remains unfinished.

**Parade_ZigZag** combines several parade-based reversal methods, fractal detection that accommodates equal neighboring values, candidate consolidation, and geometric fitting. It provides a framework for comparing alternative zigzag interpretations of historical price action. Its connection to automatic extraction of free candles between consecutive boxes remains unfinished.

Both algorithms have moved beyond a purely conceptual stage into implementation. Their next steps are to complete their respective input connections and evaluate their behavior on selected historical H1 intervals.
