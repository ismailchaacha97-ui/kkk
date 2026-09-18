# VWAP Pro — anchored VWAP for MetaTrader 4

An anchored VWAP indicator that behaves the way the textbook says a VWAP
should behave, on the data MT4 actually gives you — plus the statistics
that turn it into something you can trade: honest dispersion bands, a
regime-aware composite score, and an alerting layer.

Everything in this repository compiles twice: once inside MetaTrader 4, and
once as ordinary C++ for **1,746 automated checks** that run with nothing but
a compiler and a `make test` — and a third time as JavaScript, so the same
engine can be driven in a browser and compared against the compiled one bar by
bar.

```
$ make test
test_time    :  46 checks, 0 failures
test_math    :  65 checks, 0 failures
test_volume  :  30 checks, 0 failures
test_engine  : 1590 checks, 0 failures
test_data    :  15 checks, 0 failures

ALL SUITES PASSED

$ make check
checked 8 MQL4 source files
  OK    no portability or structural problems found
  ...  JS port vs the C++ engine: 17 of 18 series bit-identical over 16,200 bars
  ...  anchor VWAP vs independent numpy reference: max rel err 2.1e-16
  verdict: PASS - engine agrees with an independent implementation
```

**See it run:** [`web/index.html`](web/index.html) replays the shipped fixture
through the JavaScript port of the engine — live bands, regime score, and the
naive accumulator side by side. Serve the repository root
(`python3 -m http.server`) and open `/web/index.html`.

---

## Why this one is different

Most "best VWAP" indicators on the market are the same 40 lines of code:
`sum(typical_price × tick_volume) / sum(tick_volume)` plus `k × stdev`.
That formula has five failure modes, and VWAP Pro fixes each of them — with
measurements in `docs/EVIDENCE.md`, not adjectives.

| # | What goes wrong in the usual implementation | What VWAP Pro does | Measured difference |
|---|---|---|---|
| 1 | **Tick volume is treated as share volume.** On MT4 it is a quantised, autocorrelated update counter — and on many feeds it is constant, zero, or absent entirely. | Detects degenerate feeds and repairs them: real volume → clean tick volume → volatility clock, with a tick-rule split of each bar's participation. | On a feed with no volume at all the anchor still tracks the priced anchor to **0.015%** of price instead of dividing by zero. |
| 2 | **The dispersion is accumulated as `Σx² − (Σx)²/n`**, which cancels catastrophically. | Origin-shifted, Kahan-compensated accumulators (Welford/Chan form). | Naive: **7.6e-07** relative error on ordinary EURUSD data, **104%** at a 1e9 price level. VWAP Pro: **4.7e-14** and **4.4e-13**. |
| 3 | **Bands start at zero width** at the session open and are unusable for the first 30 minutes. | Shrinkage towards a Brownian-bridge prior `σ_bar·√(T/3)`. | At bar 1 of an anchor, the naive band is **exactly zero** wide; VWAP Pro's is within 2% of the ATR-implied prior. |
| 4 | **Bands assume normality.** Intraday returns are fat-tailed, so "2σ" is hit far more often than the 5% the label implies. | Optional empirical bands via a per-tail Cornish–Fisher expansion using the anchor's own skewness and excess kurtosis. | 3σ exceedance: naive **2.40%**, VWAP Pro **0.15%**, Gaussian reference 0.27%. |
| 5 | **One signal for every regime.** Fading a trend and fading noise are the same trade to them. | Composite score blends mean-reversion and trend-continuation with ADX + R² weights; the trend leg is the *t statistic* of the anchor's slope. | Synthetic trend: **+0.996**; synthetic rotation: **−0.046**. |

Three more engineering properties that no published MT4 VWAP has:

* **It never repaints.** Closed bars are committed to the engine once; the
  live bar is evaluated on a *clone* of that state, so an unfinished bar can
  never leak into a finished one. Verified against a from-scratch rerun
  (0 mismatches over 1,500 bars).
* **It never draws garbage.** 60,000 hostile bars (zero and negative prices,
  inverted ranges, NaNs, 1e300 spikes, constant and missing volume) produced
  **0** non-finite values and **0** crossed bands.
* **It is implemented three times, and the three agree.** The MQL4 headers, a
  NumPy reference in extended precision, and a JavaScript port: the anchor
  agrees to **2.1e-16** with NumPy and the JS port reproduces the compiled
  engine **bit for bit on 17 of 18 outputs** over all 16,200 fixture bars (the
  composite score differs by 4.4e-13 because `Math.exp` and `libm` disagree in
  the last ulp of `tanh`).

---

## Install

1. Copy `MQL4/Include/VWAPPro/` into your terminal's
   `MQL4/Include/VWAPPro/` folder.
2. Copy `MQL4/Indicators/VWAPPro.mq4` into `MQL4/Indicators/`.
3. Compile in MetaEditor (F7), then drag **VWAP Pro** onto a chart.

Optionally, `MQL4/Experts/VWAPProSignalEA.mq4` is a reference EA showing how to
read the buffers with `iCustom`, including position sizing from the VWAP's own
dispersion.

Want to see it before installing anything? Open the in-browser demonstration at
`web/index.html` (see above).

## What it draws

```
                                        +3σ   ─ ─ ─ ─
                                        +2σ   - - - -
  price ───────────────────╮            +1σ   .......
                           ╰────        VWAP  ─────────   ← volume weighted average price
                                        -1σ   .......
                                        -2σ   - - - -
                                        -3σ   ─ ─ ─ ─
```

Eight buffers:

| Buffer | Content |
|---|---|
| 0 | Anchored VWAP |
| 1–2 | ±1σ (or 80% confidence) |
| 3–4 | ±2σ (or 95%) |
| 5–6 | ±3σ (or 99%) |
| 7 | **Composite score, −1…+1** (hidden; this is what an EA should read) |

The on-chart panel reports the anchor's start time, σ in points, the current
z-score, the slope, the order-flow tilt, R², skew/kurtosis, the score, and —
importantly — *which volume source the engine decided to trust*.

## Inputs (the ones that matter)

| Input | Default | Why you would change it |
|---|---|---|
| `InpAnchor` | Broker day | `Fixed` + `InpAnchorTime` for a London or NY-open anchored VWAP; `UTC day` to be DST-proof. |
| `InpVolumeMode` | Auto | Force `Tick rule + split price` on FX where you want the order-flow tilt to mean something; `Real volume` on futures/CFDs that have it. |
| `InpBandMode` | sd | Switch to `confidence` and enter 0.80 / 0.95 / 0.99 to get *empirical* bands that respect fat tails. |
| `InpAdaptSigma` | true | Turn off only to reproduce the textbook behaviour exactly (see `docs/EVIDENCE.md` for the cost). |
| `InpTZOffsetHours` | 0 | Set to your broker's GMT offset if you use the UTC-anchored mode. MT4 does not expose the server offset reliably, so it is explicit rather than guessed. |

Full reference: `docs/USER_GUIDE.md`. The mathematics: `docs/ALGORITHM.md`.

---

## Repository layout

```
MQL4/Include/VWAPPro/     the engine - shared, byte for byte, with the tests
  VpCompat.mqh            portability layer (MQL4 <-> C++)
  VpTime.mqh              proleptic Gregorian calendar, anchor arithmetic
  VpMath.mqh              Welford/Chan statistics, OLS, ATR, ADX, Hurst
  VpVolume.mqh            feed probing, tick-rule splits, weighting modes
  VpEngine.mqh            the anchored VWAP engine, bands, signals
  VpAnchor.mqh            anchor calendar (session/day/UTC/fixed/week)
MQL4/Indicators/VWAPPro.mq4      the indicator (plotting, panel, alerts)
MQL4/Experts/VWAPProSignalEA.mq4 reference consumer
tests/                   1,746 assertions that run without MetaTrader
tools/                   fixture generator, real-data fetcher, broker export
                         converter, numpy cross-check, JS cross-check, MQL4
                         static checker, benchmark
docs/                    algorithm, user guide, testing, evidence
web/index.html           in-browser demonstration (drives web/vwap.js)
```

## Test it yourself

```bash
make test                       # all five suites (needs only g++)
make check                      # MQL4 static rules + independent numpy check
python3 tools/crosscheck.py tests/fixtures/synth_m1_eurusd.csv
```

The data fixture that ships here is **synthetic and labelled as such**: a
deterministic generator models the things a VWAP must survive (intraday
volatility seasonality, gaps, fat tails, integer autocorrelated tick counts,
hidden order flow). To run the identical battery on *real* data:

```bash
python3 tools/fetch_data.py binance --symbol BTCUSDT --days 20 --out tests/fixtures/btc.csv
make test
```

`test_data.cpp` picks up every `.csv` in `tests/fixtures/`, so exporting your
own broker's history through the same checks is one command:

```bash
python3 tools/mt4_export_to_fixture.py ~/EURUSD_M1.csv \
        --out tests/fixtures/eurusd_m1_real.csv --symbol EURUSD --reverse
make test        # the numbers printed are now *your* feed's numbers
```

The converter reports what it found — constant tick volume, missing real
volume, gaps, out-of-order bars — because those are exactly the properties that
decide whether a VWAP can be computed on a feed at all.

Performance (the engine is O(1) per bar; the only exception is the optional
rolling window, which is O(window) *by definition*):

```
$ make bench
  bars        wall (s)    ns/bar   bars/s     (engine only)
      10,000      0.070      6843   146145
     100,000      0.676      6747   148223
   1,000,000      6.706      6704   149165

  Flat ns/bar across a 100x size range == O(1) per bar (the design goal).
  For scale, 1,000,000 bars with a 512-bar window: 7774 ns/bar.
```

6.7 microseconds per bar is one tick's worth of work — and that figure includes
the ATR, ADX, regression and all four weighted moments, i.e. everything the
chart needs, computed on every bar.

## Scope and honest limits

* **MQL4 / MetaTrader 4 only.** The engine is written in the intersection of
  MQL4 and C++; porting it to MQL5 is mostly a mechanical change of the input
  and buffer plumbing, not of the maths.
* The dispersion is the volume-weighted standard deviation of price *about the
  anchor* — the definition that has existed since VWAP was first used for
  execution benchmarking — not an implied-volatility model.
* The composite score is a *decision aid*: it converts several statistics into
  one bounded number so that a rule or an EA can be written against it. It is
  not a promise of profit, and nothing here is financial advice.
* The bands are only as good as the volume column. On a feed with no volume at
  all the engine says so, on the panel and in the journal, and falls back to a
  volatility clock — a documented degradation, not silence.

## Licence

MIT — see `LICENSE`.
