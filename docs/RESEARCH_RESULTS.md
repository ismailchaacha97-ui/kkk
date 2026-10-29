# Research results — does FTMO_QuantEdge have an edge?

**Verdict: no.** Across two independent data sources, three timeframes and three
risk configurations, no configuration of this strategy produced a positive
expectancy that survived out-of-sample. The risk layer works and is verified;
the signal layer does not pay for its costs.

This document records the measurement, including the two occasions when a
"discovery" turned out to be my own bug. It exists so that nobody — including
future me — deploys this EA on a funded account believing something the data
does not support.

---

## 1. Data

| Source | Instrument | Period | Bars | Cost model |
|---|---|---|---|---|
| FTMO-Server4 MT5 export | EURUSD M15 / H1 / H4, XAUUSD, US500 | 2025-01-02 → 2026-05-15 | 34 079 (M15) | broker per-bar spread + 7 pt round-turn commission (raw account) |
| HistData 1-minute, resampled | EURUSD M15 / H1 / H4 | 2008, 2010, 2012, 2014, 2016, 2018 | ~25 000 (M15/yr) | 7 pt all-in spread |

Retrieval is scripted in `tools/prepare_data.py`, so the dataset is reproducible.

**Two data-preparation bugs were found and fixed before any conclusion was drawn.**
They are worth recording because each one silently inverted a result:

1. the 1-minute source is stamped in US Eastern time but was fed to the engine as
   UTC, which misaligned every session filter by 5 hours. With that bug the
   7-year pooled expectancy read **−0.083 R** (1 profitable year out of 7); with
   the clock corrected it read **+0.023 R** (5 of 7). The bug had manufactured a
   loss.
2. the H1/H4 resampler bucketed hours incorrectly, producing an H4 file with the
   same bar count as H1.

---

## 2. Method

* signals from closed bars only, filled at the **next bar's open**;
* entry pays half the spread plus commission plus slippage, exit pays the other half;
* when a bar's range covers both stop and target, the **stop** is assumed hit first;
* EA-initiated exits fill at the bar close;
* the daily-loss anchor rolls at the same server time as the EA (CET midnight =
  01:00 on FTMO's GMT+2/+3 servers);
* tuning, where any happened, used 2008/2010/2012; 2014/2016/2018 and the
  FTMO 2025-26 export were never used to choose a parameter.

### The harness is validated

A negative result is only meaningful if the engine can detect a positive one. The
same code, the same costs (zero), three synthetic series:

| Series | Trades | Expectancy | Profit factor |
|---|---|---|---|
| OU, θ = 0.10 — strong provable reversion | 67 | **+0.295 R** | **2.30** |
| OU, θ = 0.02 — weak reversion | 178 | −0.120 R | 0.74 |
| Random walk — no edge by construction | 183 | −0.117 R | 0.76 |

The engine finds an edge when one exists and loses on a random walk, so the
results below are a property of the market, not of the code.

---

## 3. Cost is the first obstacle

Median all-in round-trip cost as a fraction of ATR:

| Timeframe | FTMO 2025-26 | HistData 2008 | 2014 | 2018 |
|---|---|---|---|---|
| M15 | **14 %** (2 pt spread + 7 pt commission vs 6.4 pip ATR) | 4.9 % | 12.9 % | 9.6 % |
| H1 | 3–6 % | 2.4 % | 5.8 % | — |

On M15 the round trip costs a seventh of the average bar range before the
strategy has done anything. Any intraday edge must therefore be large; that is a
structural constraint, not a matter of parameter choice. This measurement is the
reason the EA now carries a cost gate (`InpMaxCostAtr`): it refuses bars where
cost/ATR is extreme, which is the only defensible response when the edge is
unknown.

---

## 4. Is there raw structure to harvest?

**Return autocorrelation, EURUSD, pooled over all sources**

| Horizon | M15 | H1 |
|---|---|---|
| 1 bar | −0.053 (t −24.7) | −0.041 (t −7.0) |
| 4 bars | −0.021 (t −9.8) | −0.028 (t −5.1) |
| 8 bars | −0.009 (t −4.4) | — |
| 16 bars | −0.015 (t −6.9) | −0.050 (t −9.6) |
| 32 bars | +0.004 (t +2.0) | −0.037 (t −7.2) |

Mean reversion is real and statistically strong, but concentrated at horizons
(1–2 bars on M15) where the spread is a large fraction of the move, and at
16–32 bars on H1 where it is at least measurable. This is the honest basis for a
mean-reversion thesis — and the reason the thesis still fails is the next section.

**Conditional drift, and the control that kills it.** After a 12-bar (12 h) move
on H1 of more than 2 ATR, the forward 24-bar return, compared with the
unconditional baseline of the same year:

| Year | Baseline | After down > 2 ATR | Excess | After up > 2 ATR | Excess |
|---|---|---|---|---|---|
| 2008 | −0.044 | −0.173 | **−0.129** | −0.173 | **−0.129** |
| 2010 | −0.129 | −0.504 | **−0.375** | −0.151 | −0.022 |
| 2012 | +0.023 | +0.100 | +0.077 | +0.041 | +0.018 |
| 2014 | −0.537 | −0.282 | +0.254 | −0.682 | −0.145 |
| 2016 | +0.018 | +0.280 | +0.262 | −0.354 | **−0.373** |
| 2018 | −0.233 | −0.209 | +0.024 | −0.234 | −0.001 |

Pooled, "fade a big down move" looks like a +0.10 to +0.20 ATR edge with t ≈ 3.
Against the unconditional baseline it is not: the excess flips sign year to year.
**What looked like a conditional edge was the sample's drift.** This is the single
most important table in this document — it is what separates a real study from a
curve-fit.

---

## 5. The strategy, measured out of sample

Expectancy in R per trade with correct costs per dataset. `hist train` =
2008/2010/2012, `hist test` = 2014/2016/2018, `FTMO` = 2025-01 → 2026-05. A real
edge would be positive in **all three**.

| TF | Preset | n train | exp train | n test | exp test | n FTMO | exp FTMO | PF FTMO |
|---|---|---|---|---|---|---|---|---|
| M15 | conservative | 195 | +0.029 | 204 | −0.107 | 73 | +0.015 | 1.04 |
| M15 | balanced | 596 | −0.016 | 461 | −0.112 | 160 | −0.132 | 0.74 |
| M15 | active | 441 | −0.016 | 170 | −0.250 | 42 | −0.355 | 0.46 |
| H1 | conservative | 75 | −0.065 | 98 | −0.136 | 19 | −0.244 | 0.50 |
| H1 | balanced | 148 | −0.071 | 180 | −0.128 | 43 | +0.006 | 1.01 |
| H1 | active | 161 | −0.070 | 175 | −0.177 | 46 | +0.040 | 1.10 |
| H4 | conservative | 16 | +0.288 | 12 | −0.039 | 7 | −0.372 | 0.36 |
| H4 | balanced | 37 | +0.083 | 29 | +0.072 | 14 | −0.266 | 0.55 |
| H4 | active | 42 | +0.088 | 37 | −0.046 | 15 | −0.195 | 0.65 |

Every row has at least one negative fold. The best-looking row (H4 balanced,
positive on both historical folds) collapses on the independent FTMO export at
−0.266 R. With 14–37 trades per fold, none of these numbers is statistically
distinguishable from zero anyway: at a per-trade standard deviation of ~0.9 R,
37 trades give a standard error of 0.15 R.

**Nothing here is deployable.** The M15 "conservative +0.029 / FTMO +0.015" pair
is not an edge; it is zero within noise, on 195 and 73 trades.

---

## 6. What was tried and rejected

| Attempt | Outcome |
|---|---|
| Fade overextended moves (the core thesis) | loses after cost; the apparent edge was baseline drift |
| Momentum / trend-following mode on H1 and H4 | ≈ 0 in-sample, decays out-of-sample (H4: +0.203 → +0.020) |
| Variance-ratio regime switch | a tilt, not a test (see `docs/VALIDATION.md`); does not create edge |
| Dickey–Fuller gate on the OU half-life | correctly rejects noise (4 % false positives) — necessary, but not sufficient |
| Session filtering | London/NY beats Asia consistently, but no session makes the strategy positive everywhere |
| Exit restructuring (statistical mean vs fixed R, z-exit on/off, trailing, time stops) | shifts the win-rate/R-mix, does not move expectancy beyond zero |
| Cost gate `InpMaxCostAtr` | removes the worst bars; keeps the sign, does not create edge |
| Parameter sweeps (threshold, z, half-life, ATR band, weights, lookbacks) | no region survives on all three datasets |

---

## 7. What this means for the EA

1. **Do not run it on a paid FTMO evaluation expecting profit.** On the evidence
   it is a coin flip that pays the spread.
2. **The risk layer is real and verified.** In every run above the worst daily
   loss stayed under 1.7 %, against the 3.5 % governor and 5 % FTMO limit, and no
   circuit breaker was ever needed. That protection is worth having, and it is
   independent of whether the signal makes money.
3. **The changes kept from this research** are the ones justified by measurement
   rather than by fit: `InpCommissionPoints` (cost realism), `InpMaxCostAtr`
   (refuse structurally unpayable trades), and the honest documentation.
4. **No preset was changed to the H4 configuration**, even though it looked best
   on historical data, because it failed on the independent FTMO export.

## 8. What a real edge would require

The framework is sound; the ingredient it lacks is information. Concretely, in
the order I would try them:

* **tick data and a fill model.** M15 OHLC cannot resolve stop/target ordering or
  spread dynamics; a tick backtest is the only way to test anything that depends
  on intrabar path.
* **a pre-registered hypothesis** with an economic reason, tested once. Everything
  in §6 was exploratory, and exploratory work at this sample size cannot
  distinguish edge from luck.
* **cross-sectional information** — relative strength across a basket of majors,
  carry, or a positioning/flow series — rather than a single instrument's own
  price history, which is where the published FX anomalies actually live.
* **more instruments.** A single pair over 6 years yields a few hundred trades;
  pooling 8–10 instruments per year is what makes a 0.05 R edge detectable.

Until one of those produces a positive result on data that was not used to
design it, the correct output of this repository is the risk framework plus the
negative result.
