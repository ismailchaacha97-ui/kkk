# JobPick.mq4 — MT4 indicator (v1.10)

One overlay, three layers: **VOTES · GATES · RISK**.

```
VOTES (directional evidence, need 3/3)
  Bias .......... close vs VWAP (intraday) or EMA200 (swing)
  Trend ......... EMA fast vs EMA slow
  Momentum ...... RSI(14) or MACD histogram

GATES (hard pass/fail, all must pass)
  Regime ........ ADX >= 25 and +/-DI agrees with direction
  Participation . RVOL >= 1.20
  Extension ..... not stretched from the regime baseline
  Spread ........ spread <= 2.0 pips
  Session ....... broker-hour window      (off by default)
  HTF ........... higher-TF alignment     (off by default)
  ATR floor ..... market not dead         (off by default)
  Cooldown ...... >= 5 bars since last signal

RISK
  SL = close -/+ ATR x 1.5     TP = SL distance x 2.0
  Ratcheting chandelier trail + breakeven at 1R
```

## Why votes and gates are separate

v1.0 counted four "votes" — bias, trend, momentum, volume. That was dishonest:
bias and trend are heavily collinear, and RVOL is directionless, so the same point
landed in both the bull and the bear column. A "4/4" read like four independent
confirmations when it was really about two. Now there are **3 directional votes**
and **8 pass/fail gates** — the score means what it says.

## Install

```
<MT4 data folder>/MQL4/Indicators/JobPick.mq4
```

**File → Open Data Folder** in MT4. Compile in MetaEditor (F7) or drag onto a chart.

## The adaptive extension gate (important)

Extension = how far price has stretched. The baseline it's measured from must change
with the regime, or the gate misfires:

* **Ranging (ADX < 25)** — measured from **fair value (VWAP)**, limit 2.0 ATR.
  Far from VWAP in a range means you're buying the top of the range.
* **Trending (ADX >= 25)** — measured from the **fast EMA**, limit 2.5 ATR.
  VWAP resets every session, so in a trend price legitimately runs far from it.
  Measuring extension against VWAP during a trend blocks nearly every valid entry.

This is not cosmetic — see the numbers below.

## Backtest: v1.0 vs v1.1

Python re-implementation of the exact signal logic, 20 random seeds × 3 synthetic
regimes (trending / mean-reverting chop / pure noise), 1200 bars each. Identical
exits for both versions (SL 1.5 ATR, TP 3.0 ATR = 2R), so this isolates **entry
selection** only.

| Regime | v1.0 trades | v1.0 exp. | v1.1 trades | v1.1 exp. |
|---|---|---|---|---|
| Trend | 2211 | +0.879R | 997 | +0.965R |
| Chop | 1837 | −0.770R | 271 | −0.768R |
| Noise | 1923 | −0.017R | 557 | +0.034R |
| **All** | **5971** | **+0.083R** | **1825** | **+0.424R** |

Read it honestly:

* The trend improvement (+0.88R → +0.97R) is real: better entries, fewer of them.
* **In chop, per-trade expectancy did not improve (−0.77R either way).** v1.1 wins
  by *not trading* — 1837 trades down to 271. Same bad trade, taken 7x less often.
* Costs are excluded. Adding spread/slippage widens the gap further, since v1.0
  places 3.3x more trades.

## Caveats

* Synthetic series, one parameter set, no costs, no walk-forward. This is a
  **sanity check, not proof.** Validate on your own symbols before trusting it.
* Chop is *avoided*, not traded. A mean-reversion mode for ADX < 25 is the obvious
  next step and is not implemented.
* `MarketInfo(MODE_SPREAD)` is the **current** spread, applied to all bars. The
  spread gate is meaningful live, and inert on history.
* VWAP uses tick volume unless `InpVolumeSource = VOL_REAL` (exchange instruments
  only). No volume at all → RVOL reads 0.00 and the gate is treated as neutral.
* VWAP anchors on **broker server time**. Use `VWAP_HOURS` + `InpSessionStartHour`
  for a 17:00 NY session open.

## Suggested presets

| Style | Bias | Trend | Momentum | ADX min | Ext | ATR |
|---|---|---|---|---|---|---|
| Scalp M1–M5 | VWAP | 9 / 21 | RSI 14 | 25 | adaptive 1.5 / 2.0 | 14 × 1.0, R:R 1.5 |
| Intraday M15 | VWAP | 20 / 50 | RSI 14 | 25 | adaptive 2.0 / 2.5 | 14 × 1.5, R:R 2 |
| Swing H4–D1 | EMA200 | 20 / 50 | MACD | 20 | adaptive 2.5 / 3.0 | 14 × 2.0, R:R 3 |

`InpMomReset` (require a fresh momentum turn) is **off** — in testing it was close
to neutral: +0.521R vs +0.532R. Kept as an option for pullback-style trading.

## Notes

* MQL4 allows only **one window per indicator**, so the oscillator is reported
  numerically in the dashboard rather than as a sub-window.
* The dashboard shows each gate as `ok` / `NO`, so when no signal fires you can see
  exactly which filter blocked it.
* Not financial advice.

---

## v1.20 — mean-reversion engine (ADX < 25)

v1.10 *avoided* chop. v1.20 trades it. When the trend engine is blocked because
ADX is low, a second engine fades the stretch:

| | |
|---|---|
| Trigger | ADX < `InpMRADXMax` (25) **and** the trend votes failed |
| Setup | price ≥ `InpMRExtATR` (1.5) ATR away from the mean |
| Confirm | RSI ≤ 35 (fade long) / ≥ 65 (fade short) **and** close turns |
| Stop | `InpMRStopATR` (1.0) × ATR |
| Target | **the mean itself** — not a fixed R multiple |
| Filter | reward:risk to the mean must be ≥ `InpMRMinRR` (1.0) |

The trend and fade engines are mutually exclusive by construction: the fade can
only fire where the trend leg already produced nothing, so it never cannibalises
a trend entry. Volume, HTF and anti-chase gates are **skipped** for fades — a
volume spike in a range usually means breakout, so requiring it would fight the
fade. Spread, session, ATR-floor and cooldown still apply.

### Evidence

MR trades only, synthetic chop, realistic daily FX volatility, 1.5 pip round trip:

| | trades | win | net R |
|---|---|---|---|
| In-sample (8 seeds) | 65 | 52.3% | **+0.517R** |
| Out-of-sample (12 unseen seeds) | 76 | 60.5% | **+0.662R** |

It generalises. But be honest about where it does *not* work:

* In **strong trends** the same MR logic loses (−0.57R, n=48). Low ADX there
  means *reversal*, not consolidation — and fading a reversal is the classic
  mean-reversion blowup.
* Caveat on that caveat: the synthetic trend series flip direction every 250
  bars, so their low-ADX periods are almost all reversals. Real trends pull back
  without reversing, which is friendlier to fading. **This is the single biggest
  thing real data has to settle.**
* Two filters I tried and rejected: requiring ADX to stay low for N bars
  (never binds), and range containment ≤ N ATR (only throttles trade count;
  +0.517R at 65 trades degraded to +0.220R at 13).

If you trade strongly trending instruments, set `InpUseMR = false`.

## Validation harness — `tools/validate.py`

Everything needed to answer "edge or curve-fit":

```bash
python3 tools/validate.py                       # synthetic regimes (sanity check)
python3 tools/validate.py data/*.csv            # REAL data
python3 tools/validate.py data/*.csv --sims 5000 --cost 1.5 --folds 4
```

It computes the indicator logic in Python, then reports for every dataset:

* trade count, win rate, gross R and **net R after costs**
* **random-entry benchmark** — thousands of random entries with *identical*
  SL/TP/exit rules, giving a null distribution and a percentile
* **regime-matched random** — random entries restricted to the bars the strategy
  was eligible for. This is the hard test: if the percentile here isn't high,
  the signal adds nothing beyond simply trading in the right regime.
* walk-forward folds and chronological out-of-sample splits

### Getting real data in

MT4: **File → Open Data Folder**, or use an export script, then save CSV as
`data/SYMBOL.csv` with columns `Date,Open,High,Low,Close,Volume`. Daily or
hourly both work; ≥1000 bars recommended. Drop the files in and re-run.

### Status of validation

* ✅ Parameter choices (ADX 25, adaptive extension baseline) — tuned on
  synthetic, and the direction of the effect held across 20 seeds.
* ✅ Mean-reversion engine — in-sample + out-of-sample on unseen seeds.
* ⏳ **Not yet validated on real market data.** The sandbox this was built in
  has no direct internet egress, so bulk history couldn't be downloaded.
  The harness is ready — it needs a CSV.

Until that run exists, treat every number here as a hypothesis, not a result.
