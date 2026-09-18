# VWAP Pro — user guide

## Install

1. **Files.** Copy the folder `MQL4/Include/VWAPPro/` into your terminal's data
   folder, so you end up with `MQL4/Include/VWAPPro/VpEngine.mqh` and friends
   (in MetaTrader: *File → Open Data Folder*, then `MQL4/Include/`).
2. **Compile.** Copy `MQL4/Indicators/VWAPPro.mq4` into `MQL4/Indicators/`, open
   it in MetaEditor, press **F7**. You should get *0 errors, 0 warnings*.
3. **Attach.** Drag **VWAP Pro** from the Navigator onto a chart. It appears in
   a sub-window by default; if you prefer it over price, drag it onto the price
   window instead (MT4 will merge the scales — this is MT4's behaviour, not the
   indicator's).

Nothing else is required. The indicator has no external dependencies, makes no
network calls, writes no files, and never places an order.

## Reading the chart

| Element | Meaning |
|---|---|
| Solid line | Anchored VWAP. The reference price for the current anchor. |
| Dotted / dashed / long-dash lines | ±1σ / ±2σ / ±3σ (or the 80 / 95 / 99% bands in `confidence` mode). |
| Buffer 7 (hidden) | Composite score, −1…+1. Read it with `iCustom(..., 7, shift)`. |

The panel (top-left by default) shows:

```
anchor   2026-09-18 00:00        the current anchor period
bars     412                     bars in the anchor
vwap     1.10432                 the anchor
sigma    18.4 pts (0.017%)       dispersion
z        -1.42                   (close - vwap) / sigma
slope    -0.031 %/bar            drift, % of price per bar
t        2.31                    t statistic of that slope
flow     -0.22                   aggressive sell - buy tilt
r2       0.61                    regression fit of the anchor
sk/kur   0.14 / 4.82             skewness / excess kurtosis
score    -0.58                   composite, and the reason below
weight   tick x split price      which volume source was trusted
```

The last line matters. If the panel says **range**, your feed has no usable
volume and the indicator is running on its documented volatility-clock
fallback. Check `InpVerbose = true` in the Experts tab for the details.

## Configuration

### Choosing an anchor

| Setting | Use it for |
|---|---|
| `InpAnchor = Broker day` (default) | "The" daily VWAP; resets at your broker's midnight. |
| `InpAnchor = UTC day` + `InpTZOffsetHours` | Daily VWAP that does not shift when your broker's DST changes. Set the offset to the broker's GMT offset (e.g. `2` for GMT+2 in summer). |
| `InpAnchor = Fixed` + `InpAnchorTime` | Session-anchored VWAP: `09:30` New York, `08:00` London, `00:00` Tokyo. The time is server time; the anchor takes the *last* occurrence of that clock time. |
| `InpAnchor = Week` + `InpWeekStart` | Weekly VWAP. `1` = Monday. |
| `InpAnchor = Each chart bar` | A pure running VWAP (no reset) — useful for seeing the estimator without anchors. |

The panel always prints the anchor's start time, so you never have to guess
which session you are looking at.

### Choosing the volume source

`InpVolumeMode = Auto` is right almost always: it uses real volume when the
feed has it, tick volume when the tick column varies, and the volatility clock
otherwise. Overrides exist for specific jobs:

| Mode | When |
|---|---|
| `Tick volume` | You want the classic MT4 behaviour. |
| `Real volume` | Futures/CFDs where the volume column is contract size. |
| `Tick rule + split price` | FX, where you want the anchor and the flow tilt to carry the aggressive side of the bar. This is the mode used by the flow term of the score when Auto detects a clean feed. |
| `Range` / `Body` / `Uniform` | Degenerate feeds, or academic comparison of weighting schemes. |
| `Precision (inverse variance)` | You believe a bar's noise scales with its range; then `w = v·(scale/range)²` is the minimum-variance weighting. |

### Choosing the bands

* `sd` (default): `InpBand1..3` are multiples of σ. Familiar, and what other
  indicators look like.
* `confidence`: `InpBand1..3` become probabilities (0.80 / 0.95 / 0.99 by
  default) and the bands are corrected for the anchor's own skewness and
  kurtosis. On a fat-tailed intraday series this puts the 3rd band where the
  exceedances actually are (0.15% measured here, versus 2.40% for Gaussian
  bands on the same data).

### Alerts

`InpAlerts` fires a once-per-bar alert when `|z|` first exceeds `InpAlertZ`
(and, if you want it in the score too, when the score flips sign past ±0.3).
`InpPushNotify` mirrors them to your phone. Alerts are edge-triggered and
rate-limited per anchor, so a fast market cannot flood the log.

See `../docs/TESTING.md` for the verification suite.

## Using it from an EA

```mql4
double score = iCustom(Symbol(), Period(), "VWAPPro",
                       /* inputs, in order */ ...,
                       7,   // buffer 7 = composite score
                       1);  // shift 1 = last CLOSED bar
```

Rules of thumb:

1. **Always read shift ≥ 1** for decisions. Shift 0 is the live bar and is
   recomputed on every tick *by design* — it is an estimate, not a value.
2. Read the band buffers (1–6) to size stops: a stop at ±2σ is one that is
   scaled to the current session rather than to a fixed number of pips.
3. Read `InpMinBars`-limited score 0 as "no opinion", not as a flat market.

`MQL4/Experts/VWAPProSignalEA.mq4` is a complete, small example: it waits for
closed bars, enters on a threshold crossing, exits at zero, places its stop on
the 2σ band and sizes the position so that the stop risks a fixed fraction of
equity.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Panel shows `weight range` | The feed has no varying volume (common on some FX brokers and on "chart only" symbols). The indicator is working correctly; the anchor is a volatility-clock VWAP. |
| Nothing is drawn, panel says `waiting` | Fewer bars than `InpMinBars` are available on the symbol/timeframe (e.g. a newly added symbol). |
| Bands are absent for the first bars of a session | By design: until the prior has data the band width is the ATR-implied prior — it is drawn, but it is narrow. |
| Values differ from another VWAP indicator | Expected. Different volume source (that one uses raw tick volume), and different σ (that one has no prior and no compensation). Compare the *anchor line* before the bands: if the anchor differs on a day-anchored broker's chart, check both are anchored to the same day boundary. |
| Chart is slow on 20 years of M1 | Set `InpSigmaMode = session` and `InpZWindow = 0` (both are the defaults). Window σ is the only O(window) path. |
