# WPR Swing Breakout — signals, filters, and honest measurement

Two files:

| File | Goes in | Purpose |
|------|---------|---------|
| `indicators/WPR_SwingBreakout.mq4` | `MQL4/Indicators/` | Draws the arrows, applies the confluence filters |
| `experts/WPR_SwingBreakout_EA.mq4` | `MQL4/Experts/` | Trades the arrows, and **measures** them (incl. a random-entry control group) |

Read [The 80% question](#the-80-question) before you touch a parameter. It is the
most important section in this file.

---

## The 80% question

You asked for 80%+ win rate. I can't promise that, and neither can anyone else
who is being honest. Here is why, with the actual arithmetic.

**Win rate is a property of your exit, not of your entry.** The same signal,
with the same accuracy, produces completely different win rates depending on
where you put the target and the stop:

| TP : SL (R multiple) | Break-even win rate (before costs) |
|---|---|
| 0.3 : 1 | 76.9 % |
| 0.5 : 1 | 66.7 % |
| 1 : 1 | 50.0 % |
| 1.5 : 1 | 40.0 % |
| 2 : 1 | 33.3 % |
| 3 : 1 | 25.0 % |

*(break-even = 1 / (1 + R))*

So "80% win rate" is reachable — just set TP = 0.25 × SL. But then every loser
eats four winners, your average R is ~0, and one abnormal move or one gap wipes
out months of small gains. That is the shape of every "90% win rate" bot you
have ever seen marketed: tiny targets, no stop (or a huge one), martingale or
averaging underneath. The win rate is real. The account still dies.

The three ways vendors fake an 80% backtest:

1. **No stop loss / averaging.** Losses are simply not realised, so they never
   count as losses. Add a stop and the win rate collapses.
2. **Repainting signals.** The arrow appears on a bar that already closed, so
   the "signal" is drawn with hindsight. It looks perfect in history and is
   untradeable in real time. (This repo's indicator is explicitly built to not
   do that — see [Non-repainting](#non-repainting-verification).)
3. **Curve fitting.** Optimise 6 parameters on one symbol, one period, one
   2-year window, and you can always produce a beautiful equity curve. It
   disintegrates the moment you move the dates or the pair.

**What to optimise instead:** expectancy per trade in R (`average R > 0`),
profit factor (`> 1.2` after costs), drawdown you can actually tolerate, and
stability across symbols, periods and out-of-sample windows. If the system
makes 0.25R per trade at 45% win rate with a 10% drawdown, it is a better
system than one making 0.02R at 80% with a 60% drawdown — and it will still be
there in two years.

The EA in this repo prints all of those numbers for you, including the
break-even win rate for your current TP:SL, so you can see immediately whether
your win rate is actually good or just expensive.

---

## What the indicator does

1. **%R legs.** Williams %R is computed inline:
   `(HH(n) − Close) / (HH(n) − LL(n)) × −100`.
   A leg ends when %R reaches the opposite band (`−20` / `−80` by default).
   While a leg runs, its extreme high/low is tracked.
2. **Stop & reverse signal.** After a down leg has begun (i.e. the previous up
   leg is finished), a **BUY** fires on the first bar that breaks the high of
   that previous up leg — price takes out the level the last down-move started
   from. Symmetrically for sells. A latch means one arrow per reversal instead
   of an arrow on every bar.
3. **Confluence filters.** A raw breakout is only plotted if the enabled
   filters agree (see below). Rejected signals do **not** flip the latch, so a
   signal that was rejected (bad spread, dead volatility, wrong session) can
   still fire on a later bar while the breakout condition holds.
4. Arrow placement is cosmetic (up arrow below the low, down arrow above the
   high, offset 0.5 × ATR). **`BufUp[]` is not an entry price.**

## The filter stack

Each enabled filter contributes 1 point. `InpMinScore = 0` (default) means
*all enabled filters must pass*; set it to `N` to require only N of them.

| Filter | What it removes |
|---|---|
| `InpUseHTFFilter` | Counter-trend breakouts. Reads the last **closed** higher-timeframe bar, so it is deterministic |
| `InpUseADXFilter` | Range whipsaws — breakouts need an ADX above `InpADXMin` |
| `InpUseVolFilter` | Dead markets and news spikes: ATR must be inside `[Min, Max]` × its own recent average |
| `InpUseSpreadFilter` | Signals that only "work" because the spread was wide (uses the terminal's historical spread) |
| `InpUseSessionFilter` | Illiquid hours (server time; handles wrap-around, e.g. 22 → 4) |
| `InpUseImpulseFilter` | Weak doji breakouts — the signal candle needs a real body in the signal direction |
| `InpUseNoChase` | Late entries more than `InpMaxChaseATR` × ATR away from the broken level |
| `InpMinBarsBetween` | Clusters of signals on the same move (cooldown in bars) |

Turning filters on raises *precision* and lowers *frequency*. That is the only
honest trade available. You cannot add filters and keep the same number of
trades.

## Non-repainting verification

1. Load it, wait for ~20 arrows, screenshot, then **change timeframe and back**
   (forces a full recalculation). Every arrow on a closed bar must land on
   exactly the same bar and price.
2. Restart the terminal and compare again.
3. Run the EA on *Open prices only* and then on *Every tick based on real
   ticks*. The trade sequence must be identical (only fills differ).

Why it holds: on every recalculation the buffers are wiped and the swing state
is rebuilt oldest → newest from a reset state, so a closed bar's value is a
pure function of the bars before it. Higher-timeframe data is always read from
the last **closed** HTF bar, never the forming one.

---

## How to measure it properly (do this before trusting any number)

### 1. Run the signal, then run the control group

Same symbol, same dates, same exits, same lot size:

| Run | `InpRandomBaseline` |
|---|---|
| A — signal | `false` |
| B — control | `true` (random entries, `InpRandEveryNBars = 20`, seed 42) |

If run A's profit factor and average R are not clearly better than run B's, the
entry logic is not adding anything and every good-looking win rate is just the
exit rule plus a trending sample. This is the single most useful test in this
repo, and almost nobody runs it.

Use **Every tick based on real ticks** in the strategy tester. "Open prices
only" hides spread and intrabar stop-outs and will flatter any system.

### 2. Walk forward

Split your history, e.g.:

| Window | Use |
|---|---|
| 2018–2021 | observe / form a hypothesis |
| 2022 | optimise parameters here only |
| 2023–2024 | out-of-sample — **never touch parameters again** |
| 2025–now | second out-of-sample, different market regime |

A result that holds on 2023–2024 with parameters fitted on 2022 means something.
A result that only exists on the window you optimised means nothing.

### 3. Robustness, not maxima

When you optimise, take the **middle of a plateau**, not the peak. If
`InpADXMin = 20` gives 1.4 PF but 18 gives 0.9 and 22 gives 1.0, that peak is
noise. If 18/20/22 all give ~1.3, the parameter is robust.

### 4. Sample size

Below ~100 trades the win rate has a confidence interval of roughly ±10
percentage points. A "70% win rate" from 30 trades is a coin flip with a lucky
streak. The EA prints the trade count first for exactly this reason.

### 5. Cross-check

Run the same parameters on 3–5 uncorrelated symbols. An edge that only exists
on EURUSD M15 is a fit. An edge that shows up on EURUSD, XAUUSD and USDJPY is
probably real.

---

## Parameters

### Indicator (signal + filters)

| Input | Default | Notes |
|---|---|---|
| `InpMode` | `BRK_CLOSE` | `BRK_CLOSE` = close must break the swing level (fewer wick fakeouts). `BRK_WICK` = fires intrabar, earlier, noisier |
| `InpWPRPeriod` | `14` | Original used `3`. `3` / `−30` / `−70` reproduces the old twitchy feel |
| `InpLevelUp` / `InpLevelDn` | `-20` / `-80` | Classic %R bands |
| `InpLookback` | `1000` | Bars recalculated per new bar (`0` = all) |
| `InpClosedBarOnly` | `true` | **Keep on.** Off = bar 0 is evaluated and arrows can appear/disappear before the close |
| `InpUseHTFFilter` … `InpMinScore` | see table above | The filter stack |
| `InpMinScore` | `0` | `0` = all enabled filters must pass; `N` = at least N of them |
| Display / alerts | — | Arrow offset, alert, comment, push, sound |

### EA (exits + risk + reporting)

| Input | Default | Notes |
|---|---|---|
| `InpStopLossATR` / `InpTakeProfitATR` | `1.5` / `3.0` | 1:2. Break-even win rate ≈ 33 % |
| `InpUseBreakeven` / `InpBEStartATR` / `InpBELockPips` | on / `1.0` / `1.0` | Locks a pip once the trade is 1 ATR in profit (lowers win rate, raises expectancy) |
| `InpUseTrailing` / `InpTrailStartATR` / `InpTrailATR` | on / `1.5` / `1.5` | Same trade-off |
| `InpMaxBarsInTrade` | `0` | Time exit in bars, `0` = off |
| `InpReverseOnSignal` | `true` | Close and reverse on an opposite arrow; `false` = let SL/TP decide |
| `InpLots` / `InpUseRiskPercent` / `InpRiskPercent` | `0.10` / off / `1.0` | Fixed size or % risk per trade |
| `InpMaxEntrySpreadPips` | `3.0` | Live guard, skipped if spread is wider |
| `InpRandomBaseline` / `InpRandSeed` / `InpRandEveryNBars` | off / 42 / 20 | Control group |

**If you want a higher win rate, do it consciously:** lower
`InpTakeProfitATR` (e.g. `1.0` with SL `1.5` → break-even 60%) and watch
whether *profit factor* and *average R* survive. If net profit falls while the
win rate rises, you bought a number and sold your expectancy.

---

## Reading the buffers from an EA

`iCustom` passes everything between the indicator name and the **last two**
arguments as inputs, in declaration order; the last two are `buffer, shift`.
Signal inputs are declared before cosmetic ones on purpose, so you stop before
the display block:

```mql4
// inputs: InpMode, InpWPRPeriod, InpLevelUp, InpLevelDn, InpLookback, InpClosedBarOnly,
//         ...all filter inputs..., InpMinBarsBetween, InpATRPeriod, InpMinScore
// tail:   buffer 0 = buy, 1 = sell, 2 = confluence score; shift 1 = last closed bar
double up    = iCustom(_Symbol,_Period,"WPR_SwingBreakout", 1,14,-20.0,-80.0,1000,true,
                       true,PERIOD_H1,50,MODE_EMA, true,14,20.0, true,50,0.7,2.5,
                       true,2.0, false,8,18, true,0.35, true,1.0, 3,14,0,  0,1);
double score = iCustom(_Symbol,_Period,"WPR_SwingBreakout", 1,14,-20.0,-80.0,1000,true,
                       true,PERIOD_H1,50,MODE_EMA, true,14,20.0, true,50,0.7,2.5,
                       true,2.0, false,8,18, true,0.35, true,1.0, 3,14,0,  2,1);

if(up != EMPTY_VALUE) { /* filtered buy on the bar that just closed */ }
```

* Test against `EMPTY_VALUE`, **not** against `0`.
* `1` in the first slot is `BRK_CLOSE` — declare the enum in your EA if you
  want the name.
* Keep the input order in sync: adding an input in the middle silently shifts
  every `iCustom` call.

---

## Fixes vs. the original decompiled indicator

| Original bug | Fix |
|---|---|
| `gi_108++` every tick but reset only when **more than one** bar appeared, so the scan index drifted past `Bars−1` → `array out of range` (critical error, indicator dies) after ~30–60 min on an active chart | Recalculation driven by `prev_calculated` + `time[0]`; window derived from `rates_total`, can never go out of range |
| Whole window rescanned every tick with state carried over → arrows appeared on bars closed hours ago (repainting) | Buffers wiped and state rebuilt oldest → newest on every recalculation |
| `if (… && gi_108 == -1) return(0);` — `gi_108` is never `-1`, so the guard was dead code | Real new-bar detection; early return inside a bar in closed-bar mode |
| `g_high_156` / `g_low_164` left at `0.0` → phantom arrow on load | `hasPrevHigh` / `hasPrevLow` flags |
| Alerts deduplicated by **price** via global variables that were never deleted | Deduplicated by **bar time**; no `GlobalVariable*` at all |
| `PlaySound` nested inside `if (Comments)` | Independent alert / comment / push / sound channels |
| `Comment("Terminal Signal", "Time: …")` → renders `Terminal SignalTime: …` | Single formatted message, cleared on `OnDeinit` |
| `0.0` used as "no arrow" without `SetIndexEmptyValue` | `EMPTY_VALUE` + `SetIndexEmptyValue()` |
| `Periods = 3`, fixed 50-point offset, no filters | Configurable period/bands, ATR-scaled offset, 7 confluence filters, score threshold |
| `init()` / `start()`, `extern`, `Seconds()`, no `strict`, names like `gi_108` | `OnInit` / `OnCalculate`, `input`, `#property strict`, input validation, readable names |

## Limitations

* No MetaEditor in this environment: **neither file is compile-tested.** Open
  them once and send me any warnings.
* Stop-and-reverse with filters can skip a reversal, so a position can be held
  through an adverse move. Always keep a stop loss (`InpStopLossATR`).
* The trigger level (the swing high/low that was broken) is not exposed as a
  buffer — only the arrow price is, and that is a display offset.
* `InpLookback` is a rolling window: the oldest ~1–2 swings in it drop out as
  new bars arrive. Recent bars (the ones carrying signals) are unaffected.
* MQL4 / MetaTrader 4 only.
