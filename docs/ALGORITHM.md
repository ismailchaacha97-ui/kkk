# VWAP Pro — the algorithm

This document is the specification the code implements and the tests verify.
Every equation below appears in `MQL4/Include/VWAPPro/` exactly once, and every
number quoted here is produced by `make test` (see `EVIDENCE.md`).

---

## 1. The estimator

For an anchor period (a trading day, a week, or a fixed clock time such as
09:30 New York) containing bars `i = 1..T`, with price observations `p_i` and
weights `w_i`:

```
                 Σ w_i · p_i
    VWAP(T)  =  ─────────────
                   Σ w_i

                 Σ w_i · (p_i − VWAP)²
    σ(T)²    =  ───────────────────────
                       Σ w_i
```

`p_i` is the bar's typical price `(H+L+C)/3`, which is the convention the
industry uses, *unless* the weighting mode carries directional information, in
which case the tick-rule price of §3 is used.

This is the definition that a trader means by "the VWAP", and it is the
definition the test suite checks against brute force: **worst relative
deviation 2.0e-16** over 3,000 random bars, **2.9e-15** over the 16,200-bar
fixture.

### Anchoring

| `InpAnchor` | key | note |
|---|---|---|
| Each chart bar | `t` | the anchor is the bar itself (a pure running VWAP) |
| Broker day | `floor(t / 86400)` | what most traders mean by "the VWAP" |
| UTC day | `floor((t − offset) / 86400)` | DST-proof; needs the broker offset |
| Fixed time | anchor instant at the last `HH:MM` | e.g. 09:30 New York, 08:00 London |
| Week | `day − ((day + 4 − weekStart) mod 7)` | note the `+4`: 1970-01-01 was a Thursday |

The `+4` is the single most common bug in hand-written "start of week" code —
it is in the test suite for that reason.

---

## 2. Numerical design (why the numbers are right)

### 2.1 Origin shifting

`Σ w p²` on EURUSD accumulates a running total around 1e9 while the quantity of
interest (`Σ w (p − VWAP)²`, order 1e-4) sits twelve digits below it. Doubles
have ~16 digits, so the naive form loses almost everything — and on a quiet
market it can produce a *negative* variance, hence `NaN` bands.

VWAP Pro accumulates deviations from a local origin (the opening price of the
anchor, re-centred every 128 bars):

```
    S1 = Σ w (p − o)      S2 = Σ w (p − o)²      S3 = Σ w (p − o)³   …
```

so every partial sum stays the size of the quantity it measures. Re-centring is
algebraically exact:

```
    S1' = S1 − δW           S2' = S2 − 2δS1 + δ²W
    S3' = S3 − 3δS2 + 3δ²S1 − δ³W      (and so on)
```

### 2.2 Compensated summation

Every accumulator is a Neumaier (Kahan–Babuška) compensated sum, so the
rounding error of a partial sum is carried rather than lost. The result is that
the dispersion is accurate *relative to itself*, at any price level:

| price level | VWAP Pro σ error | naive accumulator |
|---|---|---|
| 1.10000 (EURUSD) | 1.2e-13 | 7.6e-07 |
| 150.250 (USDJPY) | 3.6e-13 | — |
| 1.0e9 (index/CFD scale) | 4.4e-13 | **104%** |

### 2.3 Consequences the tests pin down

* **Scale invariance**: multiply every price by 1000 and the z-score,
  order-flow tilt, R² and signal are unchanged to 1e-12; σ and the bands scale
  exactly.
* **Translation invariance**: add 1,000 to every price and the z-score is
  unchanged to 1e-10.
* An independent NumPy implementation of §1 (a different language, a different
  summation strategy, computed in extended precision) agrees with the engine to
  **2.1e-16** on the VWAP and **5.8e-13** median on σ.

---

## 3. Weighting: what "volume" means on MT4

MT4's `tick_volume` is the number of price updates in a bar. It is not traded
size, it is integer, it is broker-specific, and it is sometimes constant or
absent. VWAP Pro therefore probes the feed and picks a weighting family:

```
1. real volume          if any bar carries a positive real volume
2. tick volume          if it varies (a constant column carries no information)
3. volatility clock     |H−L| — scale free, always available
```

`InpVolumeMode` lets you force any of: `tick`, `real`, `tick-rule + split
price`, `range`, `body`, `uniform`, or precision weighting
`w = v / (range/rangeScale)²` (inverse-variance, i.e. Gauss–Markov optimal when
the bar's observation noise scales with its range).

### Tick rule (BVC)

Each bar's participation is split by where it closed inside its own range:

```
    pos    = (C − L) / (H − L)              ∈ [0, 1]
    f_buy  = (1 + k (2·pos − 1)) / 2        clamped to [0.02, 0.98]
```

`k = 1` is the classic bulk-volume classification rule. The price observation
for the bar is then the buy/sell weighted blend of the levels each side
actually traded at, not the typical price alone:

```
    p_eff = 0.6 · [ f_buy·(H+C)/2 + (1−f_buy)·(L+C)/2 ] + 0.4 · (H+L+C)/3
```

**Deliberately absent**: any damping that reduces conviction for small-bodied
bars. A long-legged bar closing exactly on its low is one of the strongest
selling signatures on a chart; penalising it costs exactly the bars where the
tick rule has the most information. `test_volume.cpp` pins the monotonicity of
`f_buy` in `pos` so this cannot regress.

Measured effect on a stream of bars that close on their highs versus their
lows, versus the same stream weighted the textbook way:

```
typical price anchor 1.103167   |   tick-rule (buying) 1.103186
                                |   tick-rule (selling) 1.103114
```

---

## 4. Dispersion: the shrinkage prior

Early in an anchor there is not enough data for σ to mean anything — the
textbook running σ is exactly **zero on the first bar**, so every z-score is
`±∞` and the bands have zero width. VWAP Pro shrinks the observed variance
towards a Brownian-bridge prior:

```
    σ_prior(T)² = (ATR/2)² · T/3                T = bars in the anchor

    σ_used²     = (1 − λ)·σ_obs² + λ·σ_prior²   λ = n_prior / (T + n_prior)
```

`σ_bar·√(T/3)` is the standard deviation of a driftless path's deviation from
its own running average (the Brownian bridge), and `ATR/2` is a robust
range-based estimate of the per-bar σ. `n_prior` (input `InpAdaptPriorBars`,
default 40) controls how quickly the prior is forgotten: at T = 40 the prior
still carries half the weight, at T = 400 a tenth.

Effect, measured on the fixture:

| | first bar of an anchor |
|---|---|
| textbook running σ | 0 (band width 0) |
| VWAP Pro | 5.26e-05, against an ATR-implied prior of 5.33e-05 |

The prior is a *statistical* statement, not a cosmetic one: without it the
first 30 minutes of every session contribute `|z| > 3` readings (and therefore
false signals) at 16× the correct rate. With it:

```
P(|z| > 3)   VWAP Pro 0.15%    naive running σ 2.40%    Gaussian 0.27%
```

---

## 5. Bands

Two modes.

**`sd`** (default, familiar): `VWAP ± k·σ` with `k` from the inputs.

**`confidence`**: inputs are probabilities (0.80 / 0.95 / 0.99 by default),
converted to normal quantiles and then corrected for the anchor's *own*
skewness `g1` and excess kurtosis `g2` with a Cornish–Fisher expansion:

```
    x_q ≈ z + (z²−1)·g1/6 + (z³−3z)·g2/24 − (2z³−5z)·g1²/36
```

Each tail is evaluated separately, so a right-skewed anchor really does get a
wider upper band than lower band (there is a test for that), and the correction
is clamped to `[0.5z, 2z]` so a fat-tail reading can never collapse or explode
a band. Skewness and kurtosis are accumulated as weighted third and fourth
central moments about the same shifted origin.

This matters because intraday VWAP deviations are strongly leptokurtic. The
fixture measures, for the same data, a 3σ exceedance rate of 2.40% for Gaussian
bands versus 0.15% for the corrected ones — the difference between a "1 in 40
bars" event and "1 in 700 bars".

---

## 6. The composite score

Two hypotheses about a deviation from the anchor are both true, in different
regimes:

* **mean reversion** — `fade = −tanh(z / 1.6)`: price stretched away from the
  anchor tends to come back;
* **trend continuation** — `trend = tanh(t / 6)`, where `t` is the
  **t statistic of the anchor's own regression slope**. Using the t statistic
  rather than the slope's size is what makes the score dimensionless: on a
  quiet anchor a small drift can be highly significant, on a wild one a big
  drift can still be indistinguishable from a random walk.

Regime weights come from ADX and R²:

```
    trendness = clamp(0.6·clamp((ADX−15)/25,0,1) + 0.4·clamp(3R²,0,1), 0, 1)
    flow      = tanh(2.5 · (buyVol − sellVol)/(buyVol + sellVol))

    score     = 0.85·[(1−trendness)·fade + trendness·trend]  +  0.15·flow
```

clamped to `[−1, +1]`, and forced to exactly `0` until `InpMinBars` bars have
accumulated in the anchor.

Measured behaviour on constructed regimes: a persistent trend scores
**+0.996**; an oscillation around a flat anchor scores **−0.046** (the sign is
the prediction — fade the extension).

On the chart, buffer 7 carries the score and the panel prints its components,
so nothing about the score is a black box.

---

## 7. Robustness rules

These are not defensive decoration; every one of them is a behaviour that was
observed in a failing test first.

1. **A bar must be believable.** All four prices finite and positive,
   `H ≥ L`, and `H − L ≤ C`. Real feeds push zero/negative prices after a
   reconnect and inverted ranges after a bad tick. A rejected bar moves
   *nothing*: not the anchor, not the ATR, not the prior.
2. **Moments cannot overflow.** Bars whose distance from the anchor exceeds
   1e150 are skipped rather than allowed to square into `inf`.
3. **Outputs are sanitised** before they reach a buffer: every value finite,
   `0 ≤ σ ≤ VWAP`, and the bands forced into `dn3 ≤ dn2 ≤ dn1 ≤ VWAP ≤ up1 ≤
   up2 ≤ up3`. The fuzz suite (60,000 hostile bars) asserts these branches are
   never *needed*; they exist so that a corrupted accumulator cannot draw a
   crossed band on a live account.
4. **The live bar is evaluated on a clone** of the committed engine, so closed
   bars cannot repaint and an unfinished bar cannot contaminate state. The
   clone is unit-tested, including its ring buffer, against a from-scratch run.

---

## 8. Complexity

`O(1)` per bar for the anchor, moments, regression and ATR/ADX, plus `O(w)` per
bar only if you ask for a rolling-window σ (`InpSigmaMode = window`, window ≤
4096). A 20-year M1 history loads in one linear pass; the window pass is
skipped entirely in the default mode.

## References

The estimator and the band correction are standard statistics; the interest here
is in applying them correctly to a platform that gives you the wrong volume:

* Berkowitz, Logue & Noser (1988) — *The total cost of transactions on the NYSE*
  (VWAP as an execution benchmark).
* Easley, López de Prado & O'Hara — tick-rule / VPIN volume classification.
* Chan, Golub & LeVeque (1983) — *Updating formulae and a pairwise algorithm
  for computing sample variances* (the numerically stable merge).
* Hinnant, H. — *chrono-compatible low-level date algorithms* (the calendar).
* Cornish & Fisher (1938) — expansions of a distribution's quantiles in
  cumulants.
* Welford (1962) — *Note on a method for calculating corrected sums of squares*.
