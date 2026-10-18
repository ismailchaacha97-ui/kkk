# ExhaustionStrength — clean rewrite of the "Modified LexLampard" MQL indicator

A professional rewrite of the decompiled MQL4 indicator reviewed in this
project. Same core idea, same signal meaning — but modern
`OnInit`/`OnCalculate` code with the original's bugs fixed.

| File | Platform | Install into |
|---|---|---|
| `MQL4/Indicators/ExhaustionStrength.mq4` | MetaTrader 4 (build 600+) | `<MT4 data folder>/MQL4/Indicators/` |
| `MQL5/Indicators/ExhaustionStrength.mq5` | MetaTrader 5 | `<MT5 data folder>/MQL5/Indicators/` |

Compile with MetaEditor (F7), then attach to a chart.

---

## What it does

It is a **counter-trend exhaustion** indicator, not a trend follower.

For each signal bar it scans **backwards** (newest → oldest) over the last
`InpLength` bars, tracking record extremes and accumulating the closes at
which new records were made:

```
FallStrength = Σ closes at record highs (scanning backwards)   (old buffer "UP")
               ─────────────────────────────────────────────
               Σ closes at record lows  (scanning backwards)

RiseStrength = 1 / FallStrength                                (old buffer "DN")
```

Walking backwards after a **fall**, prices rise, so record *highs* dominate →
`FallStrength` explodes. Walking backwards after a **rise**, record *lows*
dominate → `RiseStrength` explodes. Therefore:

- **BUY arrow** — `FallStrength >= InpSignalLevel` (default 3.0, see below): the fall
  looks stretched/exhausted.
- **SELL arrow** — `RiseStrength >= InpSignalLevel`: the rise looks stretched.

Signals are generated on **closed signal bars only** by default
(`InpClosedBarOnly = true`), so arrows do not repaint. With
`InpAlternating = true` (the original's `sUp`/`sDn` behaviour, done
correctly) signals strictly alternate BUY → SELL → BUY …

> ⚠️ This flags *extended* moves. It will happily buy a falling knife.
> Use it as an exhaustion filter alongside structure / support-resistance /
> confirmation — never as a standalone entry trigger, and backtest it
> (Strategy Tester, "every tick based on real ticks" on MT5) before any
> live use. No edge is claimed or proven by the rewrite; it only makes the
> original logic correct, testable, and readable.

## Buffers (for EAs via `iCustom` / `CopyBuffer`)

| Buffer | Content |
|---|---|
| 0 | Buy arrow price (or `EMPTY_VALUE`) |
| 1 | Sell arrow price (or `EMPTY_VALUE`) |
| 2 | FallStrength (old `UP`) |
| 3 | RiseStrength (old `DN`) |

MQL5 EA example:

```mql5
int h = iCustom(_Symbol, PERIOD_CURRENT, "ExhaustionStrength",
                PERIOD_CURRENT, 15, 3.0, 500, true, true, true, 14, 0.15,
                233, 234, 2, 2, clrDodgerBlue, clrCrimson,
                false, false, "alert.wav", false, false);
double buy[], fall[];
CopyBuffer(h, 0, 1, 1, buy);   // closed bar!
CopyBuffer(h, 2, 1, 1, fall);
bool buySignal = (buy[0] != EMPTY_VALUE);
```

## Old → new input mapping

| Original | Rewrite | Notes |
|---|---|---|
| `Len` | `InpLength` | Now validated ≥ 2 |
| `TF1` + manual resampling | *(removed)* | Replaced by `CopyRates` on the signal TF |
| `TF2` | `InpSignalTimeframe` | Real `ENUM_TIMEFRAMES`; must be ≥ chart TF |
| `HistoryBars` | `InpHistoryBars` | Signal bars, no bogus rescaling |
| `UrovenSignal` | `InpSignalLevel` | Validated > 1.0; default recalibrated 6.0 → 3.0 (see below) |
| `ArrowBuyCode/SellCode/Width/Color` | `InpArrowBuyCode`, … | Same Wingdings codes 233/234 |
| `Move_Arrow * Point` | `InpArrowOffsetATR × ATR` | Scales with volatility, works on 5-digit |
| `ModeHL` | `InpUseHighLow` | `false` = body extremes (open/close) |
| `ModeOnline` | *(always on)* | `OnCalculate` + closed-bar logic replaces it |
| `sUp`/`sDn` globals | `InpAlternating` | State machine rebuilt chronologically |
| `alert`/`sound`/`email`/`GV` | `InpAlertPopup/Sound/Email/Push` | Actually fire now — see fixes below |
| `ModeinFile`, `ModeHistory` | *(dropped)* | File dump and the never-used flag removed |

Multi-timeframe: set `InpSignalTimeframe` higher than the chart (e.g. chart
M15, signal H1). The arrow is placed on the first chart bar at/after the
signal bar **closes** — the moment the signal was actually knowable — so
MTF mode does not repaint either.

## Bugs in the original that this rewrite fixes

1. `Li_36` was used outside the `for` loop that declared it, and arrows
   were written at a signal-TF index into chart-indexed buffers — wrong
   bars or no compile on modern builds. → Explicit signal→chart mapping
   (`ChartIndexForSignal`).
2. Timeframe handling treated a timeframe's minute value (60, 240, 1440…)
   as a bar count and overflowed a fixed `ArrayClose[][240]` above H4;
   with default inputs it re-read the same bar repeatedly. → `CopyRates`
   on the real signal timeframe; any TF works.
3. The alert block re-checked `sUp`/`sDn` *after* the arrow block had
   already toggled them off — alerts could never fire. → Alert once per
   signal bar, primed on attach so historical signals stay silent.
4. Buffers were never cleared, so stale arrows survived recalculation. →
   All buffers are reset to `EMPTY_VALUE` every calculation.
5. `Lowest = 1,000,000` sentinel and stale `Clos/Hig/Loww` globals broke
   high-priced symbols and missing data. → `DBL_MAX` extremes, per-bar
   locals, `close <= 0` data is skipped.
6. Dead `#property indicator_level1/2` in a chart-window indicator,
   unused `SignUp`/`SignDn`/`ModeHistory`, and a meaningless
   `HistoryBars / (TF2 / Period())` rescale. → Removed.
7. `init()`/`start()` + `extern` → `#property strict`, `OnInit`/
   `OnCalculate`, `input`, validated parameters (`INIT_PARAMETERS_INCORRECT`).

One deliberate change of detail: the original sampled every M1 sub-bar
inside each signal bar (that was the point of `TF1`); the rewrite evaluates
one sample per signal bar (its open/high/low/close). The signal *meaning*
is unchanged, but with the per-bar sampling the ratio's scale is cleaner
and the level may want re-tuning per symbol/timeframe — treat
`InpSignalLevel`: the original 6.0 was reached easily only because it accumulated up to
`Len × TF-minutes` M1 samples per bar. With one sample per signal bar, 6.0 is crossed on
roughly 1% of bars — most charts show **no arrows at all**. The rewrite therefore defaults
to **3.0**; set it back to 6.0 for the original strictness, or lower it (2.0–2.5) on quiet
symbols/timeframes. The on-chart diagnostics (below) show the strongest ratio in your
window so you can calibrate it to your symbol instead of guessing.

## Troubleshooting: "I don't see any arrows"

The indicator now tells you why. Attach it and read the comment in the
top-left corner of the chart (set `InpShowDiagnostics = false` once happy):

```
ExhaustionStrength v2.01
Signal TF: PERIOD_H1 | Bars evaluated: 500
Last closed: Fall=1.84 Rise=0.54 (level 3.00)
Arrows drawn: 0 BUY / 0 SELL
>> No bar crossed the level. Strongest seen: Fall 2.31 / Rise 1.95.
>> Lower InpSignalLevel (try 2.5) or increase InpHistoryBars...
```

Checklist, in order:

1. **Did it compile?** MetaEditor → Compile must show `0 errors`. An
   uncompiled `.mq4/.mq5` shows nothing at all. Also use the right file:
   `.mq4` for MT4, `.mq5` for MT5.
2. **Is it actually running?** Its name appears top-right of the chart,
   the diagnostics comment appears top-left, and the Experts/Journal log
   prints `ExhaustionStrength: evaluated N bars, drew X BUY / Y SELL...`
3. **Zero arrows drawn?** Then no bar crossed `InpSignalLevel` in the
   evaluated window — the diagnostics print the strongest ratio seen.
   Lower `InpSignalLevel` (2.5, then 2.0) and/or raise `InpHistoryBars`.
   Remember signals must also *alternate* (BUY, SELL, BUY…), which thins
   them further in a one-way market.
4. **Arrows drawn but not on screen?** They're in the last
   `InpHistoryBars` signal bars — scroll back, or check with
   Ctrl+B (Object List is empty; use the Data Window, Ctrl+D, and hover:
   buffers 0/1 show prices where arrows exist).
5. **Wrong timeframe combo?** `InpSignalTimeframe` must be >= the chart
   timeframe, otherwise init fails and the log says so.

## Verification

No MetaEditor exists in the development sandbox, so the files could not be
compiled here. They were statically audited (balanced syntax, no legacy
`init/start/extern`, no leftover decompiled globals) and the core
algorithm was replicated in Python and tested on synthetic series:

- steady fall → `FallStrength ≈ 16` → BUY (alternating, once);
- steady rise → `RiseStrength ≈ 15` → SELL;
- range-bound chop → ratio ≈ 2 → no signal;
- V-shaped reversal → signals strictly alternate;
- forming bar never signals in closed-bar-only mode.

Please compile in MetaEditor on your machine; if your build reports
anything, paste the errors back and they'll be fixed.

## License / credit

Original concept: "LexLampard 2016" as circulated in decompiled form.
This rewrite is provided for educational purposes; validate before trading.
