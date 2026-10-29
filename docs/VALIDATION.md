# Validation report — FTMO QuantEdge

There is no MetaTrader installation or MQL4 compiler on the machine where this
EA was written, so verification was approached from two independent directions
that between them cover what a compiler would *not* catch anyway: a compiler
proves the code parses, it does not prove the formulas are right.

| Layer | Tool | What it proves |
|---|---|---|
| Static analysis | `tools/mq4_check.py` | balanced blocks, no undefined or duplicate functions, no MQL5-only calls, no unterminated statements, no MQL5 format specifiers |
| Numerical mirror | `tools/validate_math.py` | every formula in the EA re-implemented in Python and tested against synthetic series with known ground truth |
| Preset integrity | `tools/gen_presets.py` | every key in every preset exists in the EA and every preset covers all 104 inputs |

Reproduce:

```bash
python3 tools/mq4_check.py mt4/Experts/QuantEdge/FTMO_QuantEdge.mq4   # 0 errors, 0 warnings
python3 tools/validate_math.py                                       # 52/52 checks
python3 tools/gen_presets.py                                         # 6 presets
```

---

## 1. What the numerical checks cover

1. **Robust z-score** — the 1.4826·MAD consistency factor, the breakdown point
   against 20% contamination (true σ = 1.00), detection of a genuine 3σ event in
   contaminated data, and the fact that the signal bar is excluded from its own
   benchmark.
2. **Variance ratio** — VR ≈ 1 on a random walk, VR < 1 on an OU process, VR > 1
   on a persistent process, plus the classification rates that set the shipped
   threshold.
3. **OU half-life** — Kendall bias correction, Dickey–Fuller significance, false
   positive rates on random walks and trends, recovery accuracy conditional on
   passing the gate.
4. **ATR percentile** — bounded in [0,1] and actually varying.
5. **Fibonacci** — level geometry for up and down legs, maximal score on the
   level, zero off the level, insignificant swings ignored.
6. **Composite score** — boundedness under fuzzing, MR/momentum sign behaviour,
   mirror symmetry.
7. **Position sizing** — lot arithmetic, rounding direction (never overweight),
   refusal to round up to the broker minimum, FX and non-FX contracts.
8. **Governors** — halt before the hard FTMO limit, daily cap arithmetic, static
   total-loss floor, start-of-day anchoring.
9. **Execution guards** — resulting maximum trade frequency.
10. **Mechanism simulation** — bar-by-bar replay of the full decision loop on a
    mean-reverting series and on a random-walk control, with transaction costs.

---

## 2. Calibration decisions that the tests forced

The first run of the harness failed 8 of 36 checks. Four were errors in the
tests, four were real findings that changed the EA's defaults. All of them are
worth recording because they are the difference between an EA that looks
statistical and one that is.

**(a) The half-life gate needed a Dickey–Fuller critical value, not a negative
slope.** For a true random walk the regression t-statistic does not follow a
normal distribution; its 5% critical value with a constant is about −2.86. With a
naive "slope is negative" rule, 30–50% of random walks produce a believable
half-life. Measured false-positive rates by threshold:

| gate | random walk passes | persistent trend passes | fast OU (HL 5.8) passes |
|---|---|---|---|
| HL > 0 and HL ≤ 80 | ~31/40 = 78% | high | 100% |
| t ≤ −1.65 (normal 5%) | 48% | 30–36% | 100% |
| t ≤ −2.00 | 30% | 16–20% | 100% |
| **t ≤ −2.86 (DF 5%)** | **4.3%** | **4.0%** | **99.8%** |

The EA ships `InpHLTStatMin = 2.86`, applies the Kendall bias correction
`b* = b + (1+3b)/n`, and exposes the threshold as an input for users who want a
permissive (1.65) or strict (3.43) gate.

**(b) The variance-ratio window had to grow, and the VR had to be demoted from
"test" to "tilt".** Sampling noise at `w = 96` is `sd ≈ 0.18`, which makes the
band almost meaningless:

| series | w=96 mean VR (sd) | w=240 | w=400 |
|---|---|---|---|
| random walk | 0.968 (0.184) | 0.982 (0.117) | 0.991 (0.088) |
| OU θ=0.08 | 0.876 (0.174) | 0.876 (0.103) | 0.881 (0.080) |
| persistent φ=0.35 | 1.604 (0.256) | 1.638 (0.163) | 1.652 (0.125) |

Conclusion: strong persistence is detectable (100% of trend samples land above
`VR > 1.08`), mild mean reversion is not (65% at best). The EA now defaults to
`w = 240`, threshold `0.08`, and a neutral fallback of mean reversion, and the
manual states plainly that VR is a tilt rather than a hypothesis test.

**(c) The Fibonacci mirror test had its chronology inverted** in the Python
mirror (`up_leg = hi_idx < lo_idx` on a chronological array). The MQL4 code was
correct (it indexes by shift, where smaller means newer); the test was wrong and
was rebuilt with explicit price paths instead of flat arrays where every low is
tied.

**(d) The z-score mirror included the signal bar in its own window.** The EA
reads shifts 1..n and compares shift 1, so the bar being judged is never part of
its benchmark. The mirror was corrected, which raised measured detection of a
clean 3σ spike from 2.36 to 3.50.

---

## 3. Mechanism simulation

The replay uses the shipped gates (`|z| ≥ 1`, ATR percentile in [0.10, 0.95],
DF-gated half-life, `|s| ≥ 0.55`), ATR stops, the statistical target, a 48-bar
time stop, 0.5% risk sizing, a 6-entry daily cap, 10 points of round-turn cost
and the 3.5% daily governor.

| series | trades | win rate | mean R | final equity | worst day |
|---|---|---|---|---|---|
| OU, θ = 0.05 (matches the EA's thesis) | 48 | 65% | +0.346 | 108 574 | 1.05% |
| GBM (no edge, null control) | 9 | 44% | −0.083 | 99 613 | 0.52% |

The OU row is **circular by construction** — the data was generated to be mean
reverting, so it is evidence that the loop works, not that the strategy has an
edge. The GBM row is the useful one: on data with no exploitable structure the
same loop takes almost no trades and loses only the costs. That is the behaviour
a null control should produce, and it is why the harness includes it.

---

## 4. What is still unverified

* **Compilation.** No MetaEditor on this machine. Compile before use; the static
  checker cannot catch a type mismatch that only the real compiler sees.
* **Broker execution.** Requotes, freeze levels, stop-level changes and
  partial fills are handled defensively in code but cannot be tested here.
* **Real market edge.** Nothing in this repository demonstrates that intraday
  mean reversion on any pair pays after spreads. That requires Strategy Tester
  runs on real ticks and a forward test — see §8 of the manual.
* **FTMO rule drift.** The compliance layer implements the rules as published at
  the time of writing; FTMO changes its matrix periodically.

---

## 5. Full output

```
======================================================================
FTMO_QuantEdge - numerical validation of the mathematical core
======================================================================

1. Robust z-score  z = (C - median) / (1.4826 * MAD)
  PASS  1.4826*MAD is a consistent sigma estimator   [mean ratio 0.996 over 400 samples]
  PASS  robust sigma survives 20% contamination   [sigma 1.18 vs true 1.00]
  PASS  classic sigma is destroyed by the same contamination   [sigma 20.32 vs true 1.00]
  PASS  robust z detects the real anomaly   [z = +2.23]
  PASS  classic z misses it (the failure mode avoided)   [classic z = -0.36]
  PASS  clean 3-sigma spike registers   [z = +3.50]
  PASS  signal bar excluded from its own window   [z = 2000 for a 100 pip jump out of a flat window]

2. Variance ratio  VR(q) = Var(r_q) / (q * Var(r_1))
  PASS  random walk gives VR ~ 1   [mean VR 0.991]
  PASS  mean-reverting series gives VR < 1   [mean VR 0.884]
  PASS  trending series gives VR > 1   [mean VR 1.654]
  PASS  trending regime is detected reliably   [100% of trend samples]
  PASS  mean reversion is only a weak tilt (documented, not a test)   [66% of MR samples; random walk false-positive 21%]
  PASS  VR standard error is large, so the neutral band must exist   [sd of VR on a random walk is 0.088 at w=400]

3. Ornstein-Uhlenbeck half-life + Dickey-Fuller significance
  PASS  fast reversion theta=0.12 passes the DF gate   [100% pass (truth 5.8 bars)]
  PASS  half-life magnitude recovered for theta=0.12   [mean error 21% of 5.8 bars]
  PASS  fast reversion theta=0.05 passes the DF gate   [45% pass (truth 13.9 bars)]
  PASS  half-life magnitude recovered for theta=0.05   [mean error 42% of 13.9 bars]
  PASS  random walk is rejected by the DF gate   [4.3% false positives at the 5% critical value]
  PASS  trending series is rejected by the DF gate   [4.0% false positives]
  PASS  Kendall correction reduces the slope bias   [mean |b - b_true| 0.0294 raw -> 0.0285 corrected]
  PASS  residual bias understates the half-life (conservative for the time stop)   [estimated HL is shorter than the truth, so the 3x multiplier covers it]

4. ATR percentile rank
  PASS  percentile is inside [0,1]
  PASS  percentile actually varies (the filter is informative)   [observed range 0.00..1.00]

5. Fibonacci confluence
  PASS  price at the 50% retracement of an up leg scores positive   [score +1.00]
  PASS  price away from every level scores zero   [score +0.00]
  PASS  mirrored down leg scores negative   [score -1.00]
  PASS  0.618 level is recognised   [score +0.87 at 1.0382]
  PASS  score is maximal exactly on the level   [score +0.992 at 1.03815]
  PASS  insignificant swing is ignored   [score +0.00]

6. Composite score
  PASS  score is bounded by +/-1 for any input   [max |score| 0.999987]
  PASS  mean-reversion setup clears threshold 0.55   [score +0.717]
  PASS  inverse setup produces the mirrored score   [score -0.717]
  PASS  momentum mode follows the move   [score +0.597]

7. Position sizing
  PASS  lot size matches the risk budget   [1.66 lots]
  PASS  loss at stop <= intended risk (rounding is conservative)   [loss 498.00 of 500.00 budget]
  PASS  risk is not under-sized by more than one lot step   [shortfall 2.00]
  PASS  unaffordable trade returns 0 lots (no silent over-risk)   [0.00 lots on a 500 USD account with a 200 pip stop]
  PASS  halving the stop doubles the size   [5.00 vs 2.50]
  PASS  non-FX contract sizing uses tick value, not pip folklore   [0.05 lots for a 100 point stop]

8. FTMO governors
  PASS  governor trips before the FTMO 5% daily limit   [halted after 7 straight losses at 3.50%]
  PASS  6 trades x 0.5% risk stays under the 5% daily limit   [worst case 3.0%]
  PASS  total-loss governor stops above the 10% hard floor   [halt at 92000 vs hard floor 90000]
  PASS  daily limit anchors on start-of-day equity, not the phase balance   [5% of 103000 = 5150]

9. Execution-efficiency guards (prohibited-practice avoidance)
  PASS  daily entry cap dominates the spacing rule   [at most 6 entries/day, minimum 30s apart]
  PASS  trade frequency is far below any tick-scalping pattern   [6 entries/day = 0.50 per hour at most]
  PASS  minimum holding time prevents millisecond round-trips   [InpMinTradeDurationSec default 120s applied to every EA exit]

10. Mechanism simulation on synthetic data (control flow, not edge)
  PASS  OU (mean reverting): the loop produces trades   [48 trades]
  PASS  OU (mean reverting): daily governor never breached   [worst day 1.05% of 3.5% budget]
        OU (mean reverting): 48 trades, win rate 65%, mean R +0.346, equity 108574, governor halts 0
  PASS  GBM (no edge): the loop produces trades   [9 trades]
  PASS  GBM (no edge): daily governor never breached   [worst day 0.52% of 3.5% budget]
        GBM (no edge): 9 trades, win rate 44%, mean R -0.083, equity 99613, governor halts 0
  PASS  no edge is manufactured on the null model   [random walk mean R -0.083 (costs included)]
  PASS  the thesis model beats the null model on its own data   [+0.346 vs -0.083 R per trade]

======================================================================
All 52 checks passed.
```
