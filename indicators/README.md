# WPR Swing Breakout — clean rewrite

`WPR_SwingBreakout.mq4` is a from-scratch rewrite of the decompiled
"%R / Terminal Signal / GGT" arrow indicator. **The trading idea is kept,
the implementation is not** — the original's state machine is rebuilt
deterministically and every structure bug is fixed.

## What the indicator does

1. **%R legs.** Williams %R is computed inline as
   `(HH(n) − Close) / (HH(n) − LL(n)) × −100`.
   A leg ends when %R reaches the opposite band (`−20` / `−80` by default).
   While a leg runs, its extreme high/low is tracked.
2. **Stop & reverse signal.** After an up leg ends (down leg started), a
   **BUY** fires on the first bar that breaks the high of the previous up leg —
   i.e. price takes out the level the last down-move started from.
   Symmetrically, a **SELL** fires on the first break of the previous down leg's
   low. A latch (`trend`) means one arrow per reversal, so you get clean
   stop-and-reverse flips instead of an arrow on every bar.
3. Arrow placement is cosmetic only (up arrow below the low, down arrow above
   the high, offset by 0.5 × ATR). **`BufUp[]` is not an entry price.**

## Fixes vs. the original

| # | Original bug | Fix |
|---|--------------|-----|
| 1 | `gi_108++` every tick but only reset when **more than one** bar appeared, so the scan index drifted past `Bars−1` → `array out of range` (critical error / indicator dies, or zeros corrupt the state machine) after roughly 30–60 min on an active chart | Recalculation is driven by `prev_calculated` + `time[0]`. The scan window is derived from `rates_total` on every call, so it can never go out of range |
| 2 | Whole window re-scanned every tick with **state carried over** between passes → arrows could appear on bars that had been closed for hours (repainting) | State is reset and the whole window is rebuilt oldest → newest on every recalculation. A closed bar's value is a pure function of the bars before it and never changes again |
| 3 | `if (g_time_100 == Time[0] && gi_108 == -1) return(0);` — `gi_108` is never `-1`, so the "skip same bar" guard was dead code and it recomputed on every tick | Real new-bar detection; in closed-bar mode it also returns early inside a bar (near-zero CPU) |
| 4 | `g_high_156` / `g_low_164` left at `0.0` → phantom buy arrow on the oldest scanned bar after every load / TF switch | Explicit `hasPrevHigh` / `hasPrevLow` flags; no arrow before a full swing exists |
| 5 | Alerts deduplicated by **price** (`Buf_up[1] != GlobalVariableGet(...)`) — two signals at the same price and one is silently swallowed; globals never deleted and survive restarts | Deduplicated by **bar time** in plain variables; no `GlobalVariable*` at all |
| 6 | `PlaySound` nested inside `if (Comments == TRUE)` — turning comments off also killed sound | Four independent toggles: `InpAlerts`, `InpComment`, `InpPush`, `InpSound` (+ `SendNotification` for mobile) |
| 7 | `Comment("Terminal Signal", "Time: …")` — `Comment()` concatenates arguments with no separator, rendering `Terminal SignalTime: 14:32:07` | Single formatted message; comment is cleared on `OnDeinit` |
| 8 | Used `0.0` as "no arrow" without `SetIndexEmptyValue` → arrows at price 0, broken Data Window, and `iCustom` callers had to test `!= 0` instead of `!= EMPTY_VALUE` | Buffers initialised to `EMPTY_VALUE` and `SetIndexEmptyValue()` set explicitly |
| 9 | `Periods = 3` (as noisy as %R gets), fixed `ras = 50` points offset, no filters | Configurable period/bands, ATR-scaled offset, optional EMA/SMA trend filter, wick-vs-close breakout confirmation |
| 10 | `init()` / `start()`, `extern`, `Seconds()`, `MarketInfo()`, no `#property strict`, decompiler names (`gi_108`, `gd_124`) | Modern MQL4: `OnInit` / `OnCalculate`, `input`, `#property strict`, `Digits`-aware, readable names, input validation |

## Parameters

| Input | Default | Notes |
|-------|---------|-------|
| `InpMode` | `BRK_CLOSE` | `BRK_CLOSE` = breakout must be confirmed by a close beyond the swing level (fewer wick fakeouts). `BRK_WICK` = fires intrabar, earlier but noisier |
| `InpWPRPeriod` | `14` | Original used `3`. `3`/-`30`/-`70` reproduces the old (very twitchy) feel |
| `InpLevelUp` / `InpLevelDn` | `-20` / `-80` | Classic %R bands. Original was `-30` / `-70` |
| `InpLookback` | `1000` | Bars recalculated per new bar. `0` = all history. Raise it if you want the oldest swings to be stable on very long charts |
| `InpClosedBarOnly` | `true` | **Keep this on.** With it off the forming bar (index 0) is evaluated, so arrows on bar 0 can appear and disappear before the bar closes — and alerts can fire for a signal that never confirms |
| `InpUseTrendFilter` | `false` | Optional EMA/SMA filter: buy only above the MA, sell only below |
| `InpATROffset` / `InpATRMultiplier` | `true` / `0.5` | Arrow distance from the candle. Fallback `InpOffsetPips` is in **pips** (digits-aware), not points |
| `InpAlerts` / `InpComment` / `InpPush` / `InpSound` | `true/true/false/true` | Independent channels |

## How to verify it does not repaint

1. Load it, wait for ~20 arrows, screenshot, then **change the timeframe and
   back** (forces a full recalculation from scratch). Every arrow on a closed
   bar must land on exactly the same bar and price.
2. Reload the template / restart the terminal and compare again.
3. In the strategy tester, run an `iCustom`-based EA on *Open prices only* and
   then on *Every tick based on real ticks*. The signal sequence must be
   identical (only fill prices differ).

## Reading the buffers from an EA

`iCustom` passes everything between the indicator name and the **last two**
arguments as inputs, in declaration order. The last two are always
`buffer, shift`:

```mql4
// inputs: InpMode, InpWPRPeriod, InpLevelUp, InpLevelDn, InpLookback, InpClosedBarOnly
// tail:   buffer 0 (buy) / 1 (sell), shift 1 (the bar that just closed)
double up = iCustom(_Symbol, _Period, "WPR_SwingBreakout", 1, 14, -20.0, -80.0, 1000, true, 0, 1);
double dn = iCustom(_Symbol, _Period, "WPR_SwingBreakout", 1, 14, -20.0, -80.0, 1000, true, 1, 1);

if(up != EMPTY_VALUE) { /* buy signal on the bar that just closed */ }
if(dn != EMPTY_VALUE) { /* sell signal on the bar that just closed */ }
```

Notes:

* Test against `EMPTY_VALUE`, **not** against `0`.
* `1` in the first slot is `BRK_CLOSE` — declare the enum in your EA if you
  prefer the name, and keep the input order in sync with the indicator's
  `input` block (adding a new input in the middle changes every `iCustom`
  call).
* Signals only exist for closed bars — with the default settings read shift
  `1` or higher, never `0`.

## Notes / limitations

* It is a **stop-and-reverse** marker with no stop loss, take profit,
  session filter or spread filter. Expect whipsaw in ranges; always add your
  own risk management.
* The arrow price is only a display offset. The trigger level is the swing
  high/low that was broken, which the indicator does not currently expose as a
  buffer.
* `InpLookback` defines a rolling window, so bars at the very oldest edge of
  the window drop out as new bars arrive. That only affects the oldest ~1–2
  swings in the window, never the recent bars that carry the signals.
* MQL4 / MetaTrader 4 only. I have no MetaEditor in this environment, so the
  file is **not compile-tested** — open it in MetaEditor once and let me know
  about any warnings it reports.
