# The Price Chessboard: Connecting the Observer and the Trader

## 1. The Core Idea

We want to build a **chessboard of price and time** that keeps the Observer and the Trader separate while enabling effective communication between them.

The board has two axes:

- **Horizontal axis:** Time and the sequence of market candles.
- **Vertical axis:** Price, divided into bands separated by 15 pips.

A vertical line divides the board into two distinct areas:

- **Left side of the line — The Observer's domain:** Historical candles and the structures formed by actual market movements.
- **Right side of the line — The Trader's domain:** The Trader examines how price has behaved within different price bands and uses that evidence to make decisions about future market movements.

This board is not merely a visual chart. It is a model for organizing market information and transforming historical price behavior into evidence that can support decision-making.

## 2. The Geometry of the Board

Suppose we are working with EURUSD. Price bands are constructed at intervals of 15 pips.

Assuming that one pip in EURUSD equals `0.0001`, several consecutive bands might look like this:

| Band | Lower Price | Upper Price |
|---|---:|---:|
| 1 | 1.0800 | 1.0815 |
| 2 | 1.0815 | 1.0830 |
| 3 | 1.0830 | 1.0845 |
| 4 | 1.0845 | 1.0860 |
| 5 | 1.0860 | 1.0875 |

Each band represents a specific interval in price space.

As time advances, successive candles interact with these bands. Price may pass through a band, remain inside it, return to it, or move away from it.

Consequently, each cell of the board represents a combination of a time interval and a price interval.

The central vertical line separates the **observed historical region** from the **decision-making region**. It does not necessarily mark the end of access to historical data. Rather, it establishes a conceptual boundary between two different responsibilities.

## 3. The Observer's Side: What Has Happened?

The Observer is responsible for identifying and interpreting market structure.

In our project, RedCarpet and its existing components examine candles, boxes, zigzag points, moving-average directions, and significant events.

The Observer should be able to determine:

- Which candles entered or passed through each price band?
- From which side did price enter the band?
- How deeply did price penetrate the band?
- Did the penetration occur through the candle body or only through its wick?
- Through which side did price leave the band?
- Did price return to the band after leaving it?
- Were any significant structural levels or turning points located within the band?

The Observer does not reduce history to a collection of numbers. Instead, it preserves the **sequence of price events so that the market's behavior can be reconstructed**.

For example, price might have visited the same band three times. During the first visit, it passed through quickly. During the second, it remained inside the band for several candles. During the third, it penetrated the band only with a wick.

Simply counting three visits would fail to capture these differences.

## 4. The Trader's Side: What Happened Within Each Band?

The Trader asks questions of the Observer but does not necessarily seek a ready-made trading signal.

For example:

> How has price behaved within the 1.0845–1.0860 band during the last 30 candles?

The answer should reconstruct the history of price visits to that band.

For each visit, the Trader should be able to examine:

1. Did price enter from above or below?
2. Did the entry occur through the candle body or the wick?
3. How far did price penetrate into the band?
4. How many candles did price spend inside it?
5. Did price exit through the opposite side, or return through the same side?
6. Did price revisit the band after leaving it?
7. How did the most recent visit differ from previous visits?
8. Which significant price levels or structural points were located within the band?

The Trader can make the same request for any other price band.

Instead of knowing only the market's general direction, the Trader can investigate the actual history of price behavior within a precisely defined price interval.

## 5. Using the Board to Determine Trading Levels

The objective is not to label every band as support or resistance in advance.

**The meaning of a price band should be derived from the actual behavior of price within it.**

The Trader can use this information to investigate three types of trading levels.

### Entry Point

Suppose the Trader expects price either to pass through a particular band or to return after entering it.

The Trader can examine the band's history, including candle bodies, wicks, penetration depth, and exit paths. These observations provide evidence for evaluating possible market scenarios.

### Stop Loss

The Trader can investigate which price boundary or structural point would invalidate the hypothesis behind a proposed entry.

The distance between the entry price and the stop-loss level can then be calculated.

In this framework, the stop loss should not simply be an arbitrary number or a fixed distance. It can be based on the observed market structure and the amount of risk the Trader is willing to accept.

### Take Profit

The Trader can examine the bands ahead of the current price and investigate how price has historically approached, crossed, or reversed within them.

This information can help evaluate potential price targets and the relationship between potential profit and potential loss.

However, historical behavior does not guarantee that price will follow the same path in the future.

## 6. Defined Risk and Future Predictions

Ultimately, the Trader must make decisions about the future, even though future price movements are unknown.

Using the history of price bands, observed market structure, and evidence supplied by the Observer, the Trader develops a hypothesis about future candles.

The Trader can then determine:

- Under what conditions an entry should be considered.
- How much capital should be exposed to risk.
- At what point the original hypothesis should be considered invalid.
- Within which price range a potential profit-taking level should be considered.

From this perspective, the Trader is making a **risk-defined wager on future market behavior, supported by evidence**.

The prediction may be correct or incorrect. The purpose of the system is not to eliminate uncertainty, but to provide enough information to make disciplined decisions under uncertainty.

## 7. Software Architecture: Connecting the Two Sides

This architecture requires two complementary communication paths.

### Path One: New Events

When the Observer detects an event, such as a significant-level touch, a directional change, or a contradiction between two independent theories, it reports that event to its consumer.

The Trader can receive the event and, when necessary, investigate the relevant historical price behavior.

### Path Two: Historical Queries

At any moment, the Trader can ask a question about a specific price band over a specified historical period.

For example:

> Examine the 1.0845–1.0860 price band over the last 30 candles.

The answer is reconstructed from the existing candle and box arrays and, when useful, the available zigzag geometry.

At this stage, we do not need to build a separate database containing every historical event. The primary information already exists in market history and the structures produced by the Observer.

When a query is made, the Trader retrieves and organizes the relevant information.

This keeps the architecture simple and avoids maintaining unnecessary duplicate data.

## 8. The Fundamental Design Principle

The fundamental principle of this project is:

**The Observer reports what has happened. The Trader asks what those events mean within a particular price region and uses the available evidence to make risk-defined decisions about the future.**

The Price Chessboard connects these two responsibilities within a shared conceptual space.

- The 15-pip bands define the price regions that can be investigated.
- The time axis preserves the chronological order of events.
- The vertical dividing line distinguishes historical observation from future-oriented decision-making.
- The Observer identifies and describes market behavior.
- The Trader investigates that behavior in the context of a specific question and uses the resulting evidence to formulate a trading hypothesis.

The board therefore provides a common framework in which the Observer's structural knowledge becomes accessible to the Trader without merging their responsibilities.

## 9. The First Implementation Step

The first implementation should be a simple, testable historical query:

**Reconstruct price behavior within one specified price band over the last 30 candles and inspect the result in the log.**

The initial test should establish whether the reconstruction accurately represents actual market behavior.

For each visit to the selected band, the output should identify:

- The time of entry and exit.
- The direction of entry and exit.
- The maximum and minimum penetration.
- Whether the relevant price levels were reached by candle bodies or only by wicks.
- The duration of the visit.
- Any relevant box boundaries or zigzag points.
- The relationship between the current visit and previous visits.

Once the accuracy of this reconstruction has been verified, the same capability can be extended to other price bands and made available for different types of Trader queries.

The result will be the first working connection between the Observer and the Trader: not a predefined trading signal, but a mechanism through which the Trader can ask precise questions about historical price behavior and receive structured, verifiable evidence in return.
