# The 1%-per-day / 4%-drawdown target: arithmetic and evidence

The brief asked for a consistent **+1% per day** with a **maximum drawdown below
4%**, and for an EA with "a historical record of profitability". This document
shows why that combination cannot be delivered honestly, with the numbers this
project actually produced.

---

## 1. What +1% per day means

Compounding 1% over 258 trading days:

```
1.01^258 = 13.03  →  +1,203% per year
```

A 4% *peak-to-trough* drawdown on a +1,203% annual return implies a
return-to-drawdown ratio of **≈300**. For comparison, the best systematic
managers in the world run ratios between 0.5 and 2. Even Renaissance
Technologies' Medallion — arguably the best track record ever recorded, closed
to outside money — is reported in the 2–3 range over its best decades, with
drawdowns far above 4%.

The strategy in this repository, on its best and most favourable sample
(2013–2019), has:

```
CAGR 13.0% / max DD 1.57% = ratio 8.3
```

which is already exceptional for a bar-based retail EA, and still **40× short**
of what the target requires. On the full 2013–2026 sample the ratio is 0.46.

## 2. What a 4% drawdown actually allows

Running the same trades at different risk levels (full history, 2013–2026):

| Risk per trade | CAGR | Max drawdown | Worst single day |
|---:|---:|---:|---:|
| 0.10% | +3.2% | 7.3% | −0.47% |
| 0.20% | +6.9% | 14.9% | −1.04% |
| 0.30% | +10.8% | 21.6% | −1.55% |
| 0.50% | +18.8% | 33.7% | −2.60% |
| 1.00% | +40.9% | 56.6% | −5.22% |
| 2.00% | +75.0% | 76.4% | −10.44% |

Return and drawdown scale together — as they must, because both are just the
same edge multiplied by the risk unit. Bisecting for a 4.0% maximum drawdown:

> **Risk = 0.06% per trade → CAGR +1.8% → ≈0.006% per day.**

That is the honest, drawdown-constrained answer for this strategy on this
history: about **1.8% per year**, i.e. roughly **170× less** than the target.

At 2013–2019 conditions only (the favourable regime), a 4% drawdown budget would
allow about 0.5% risk per trade, i.e. **≈30% per year** — still 40× short of
1% per day, and that regime no longer exists.

## 3. Monte Carlo: what the single historical path hides

Bootstrap of the trade sequence (1,500 resampled paths, R-multiples drawn with
replacement, compounding):

| Risk / trade | Median max DD | 95th pct DD | P(DD > 4%) | P(DD > 10%) |
|---:|---:|---:|---:|---:|
| 0.25% | 2.65% | 4.00% | 5.1% | 0.0% |
| 0.50% | 5.24% | 7.87% | 92.9% | 0.5% |

Even at a risk so small that the *historical* drawdown was 3%, there is a 5%
chance of exceeding the 4% limit purely from trade-ordering luck. A strategy
advertised as "max 4% drawdown, 1% a day" would have to have *no* sequence risk,
which is another way of saying it would have to be riskless.

## 4. What would have to be true for the target to be real

Taking the target at face value and assuming (generously) log-normal daily
returns with 258 days a year:

| Assumed Sharpe | Required annual volatility | Required daily volatility | Implied 1-year max DD |
|---:|---:|---:|---:|
| 3 | 401% | 25.0% | 261% |
| 6 | 200% | 12.5% | 130% |
| 10 | 120% | 7.5% | 78% |

Any way you cut it, +1,203% a year forces either absurd volatility — and
therefore drawdowns tens of times the 4% budget — or a Sharpe ratio in the
double digits sustained forever, which no price-based strategy has ever
demonstrated.

For a *4%* annual drawdown the same approximation gives a maximum sustainable
annual return of roughly 4–8% for a Sharpe of 2–4. That is the real ceiling, and
it matches what the EA produced before its edge decayed.

## 5. Why "many small trades" does not escape the constraint

A common intuition is that a high-frequency edge with a high win rate can hit
1%/day without drawdowns. Two things stop it:

1. **Spread is a fixed cost per trade.** At 0.3–0.5 trades/day and ~1 spread per
   round trip, the strategy already spends ~0.04 R per trade on costs. Making the
   target per trade 170× larger does not change that; making the *number* of
   trades 170× larger multiplies the cost by 170 too.
2. **The best measured Sharpe of this system is 3.6 (in-sample).** A Sharpe-3.6
   strategy with zero costs and no fat tails would still need ~40% annualised
   volatility to make 1,200% a year, and would suffer ~30% drawdowns routinely.
   Kelly sizing at that Sharpe would be suicidal long before reaching the target.

## 6. What the "aggressive" preset does

`presets/MT4_demo_1pct_target.set` implements the risk level that would be needed
to *attempt* 1%/day with this trade distribution (3% risk per trade, 5 positions,
4%/8% daily stops). On the same trade sequence it produces:

* historical maximum drawdown of **≈76%** of the account,
* worst single day **−10.4%**,
* and still only ~75% CAGR — because returns stop compounding when the account
  is destroyed.

It is kept in the repository as a warning, not as a recommendation.

## 7. Recommendation

* If the objective is capital preservation with a hard 4% drawdown cap, this
  strategy's honest answer on 2013–2026 data is ~2% per year at 0.06% risk —
  below cash and not worth the operational risk.
* If the objective is to research a market-structure edge, the EA is a clean
  baseline: the rules are causal, the engine is tested, and the framework will
  tell you quickly whether a change helps or just overfits.
* Any offer of "1% a day with under 4% drawdown" — from an EA vendor, a signal
  group or a fund — should be treated as either a martingale/grid system that
  has not blown up yet, or a fraud. The failure mode is always the same: the
  equity curve looks smooth until the one day it is not.
