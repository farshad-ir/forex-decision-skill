# Forex Decision Skill

A rule-based framework for developing and evolving Forex trading decision skills through experimentation, testing, and iteration.

## 1. Purpose

The goal of this project is to develop a practical and testable approach to Forex trading decisions.

The project starts from simple rules and gradually improves them through observation, experimentation, testing, and iteration.

It is not intended to begin with a complex trading strategy.

---

## 2. Core Idea

A trading decision can be treated as a situation that must be recognized, evaluated, and acted upon.

The basic cycle is:

```text
Observation
    ↓
Rule
    ↓
Decision
    ↓
Result
    ↓
Analysis
    ↓
Rule Improvement
    ↓
New Test
```

A rule is not considered permanent.

If testing shows that a rule fails under a particular condition, that condition can be incorporated into a new version of the rule.

---

## 3. Rules

The `rules/` directory contains trading rules.

Rules should initially be:

* Simple
* Explicit
* Testable
* Observable
* Easy to modify

Example:

```text
Three consecutive bearish candles → SELL
```

A later observation may reveal a weakness:

```text
Three consecutive bearish candles
+
The next candle strongly recovers the previous entry area
→ Do not SELL
```

The purpose is not to make rules complicated, but to make them progressively better.

---

## 4. Scenarios

The `scenarios/` directory contains market situations in which decisions are evaluated.

A scenario may describe:

* Current market structure
* Recent price action
* Relevant observations
* Active rules
* Possible decisions
* Conditions that strengthen or weaken a decision
* Invalidation conditions

The same market situation may lead to different decisions as the rules evolve.

---

## 5. Experiments

The `experiments/` directory contains tests performed on rules and decision procedures.

An experiment should help answer questions such as:

* Does this rule work?
* Under what conditions does it fail?
* What happens when an additional condition is introduced?
* Does the new rule improve the result?
* Does the improvement remain valid on unseen data or different market conditions?

The purpose of testing is learning, not proving that a rule is permanently correct.

---

## 6. Decision Process

The project aims to develop a repeatable decision process.

A typical decision may eventually consider:

```text
Situation
    ↓
Hypothesis
    ↓
Supporting Evidence
    ↓
Contradicting Evidence
    ↓
Invalidation
    ↓
Possible Action
    ↓
Entry
    ↓
Stop
    ↓
Target
    ↓
Risk / Reward
    ↓
Decision
```

The process should also allow the correct decision to be:

```text
WAIT
```

or

```text
NO TRADE
```

A market direction alone is not sufficient reason to trade.

---

## 7. Evolution of Rules

Rules are expected to evolve.

A rule may progress from:

```text
Rule 1
Three bearish candles → SELL
```

to:

```text
Rule 2
Three bearish candles
+ no significant recovery
→ SELL
```

and later:

```text
Rule 3
Three bearish candles
+ no significant recovery
+ structural confirmation
→ SELL
```

Previous versions should remain available so that the evolution of the decision process can be studied.

---

## 8. Implementation

The `src/` directory contains the implementation of the decision framework.

The implementation is expected to support the concepts developed in the rules and experiments rather than defining the trading logic by itself.

The first implementation target is MQL5.

---

## 9. Testing

Testing may include:

* Historical market data
* Strategy Tester
* Demo trading
* Controlled experiments
* Different market conditions
* Out-of-sample testing

The project should avoid changing rules merely because of a small number of individual outcomes.

Rule changes should be based on observable patterns and repeated evidence.

---

## 10. Project Status

This project is starting from scratch.

The initial objective is not to build a complete trading system.

The initial objective is to develop a reliable process for:

```text
Observe
→ Form a Rule
→ Test
→ Find Failure Conditions
→ Improve the Rule
→ Test Again
```

The framework, rules, experiments, and implementation will evolve together as the project develops.
