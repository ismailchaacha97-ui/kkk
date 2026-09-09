# MT4 / MetaTrader 4 port

Two MQL4 files implementing the study's rule, plus the notes you need for the numbers to mean
what they mean:

| file | what it is |
|---|---|
| `EMAStudy_Signals.mq4` | indicator: the two EMAs, the flip arrows, flat-spell shading, alerts, and an **on-chart replay of the study's own accounting** for this symbol/timeframe |
| `EMAStudy_AutoTrade.mq4` | Expert Advisor with the identical rule, for the Strategy Tester (indicators cannot be backtested there) |

```
1. MetaEditor: File > Open Folder, or copy both files to
   <MT4 data folder>/MQL4/Indicators/EMAStudy_Signals.mq4
   <MT4 data folder>/MQL4/Experts/EMAStudy_AutoTrade.mq4
   (terminal: File > Open Data Folder)
2. MetaEditor: press F7 on each file. Both should compile with 0 errors.
3. Terminal: Content Navigator > Indicators > EMAStudy_Signals > drag onto a D1 chart.
   History: View > Data Rooms > Symbols > double-click a few years to download, or the
   indicator will tell you it does not have enough bars.
```

Written blind — there is no MetaEditor in the environment that produced these files, so **"compiles"
is not a claim I can make**. `python3 scripts/check_mql4.py` from the repo root runs the mechanical
checks that catch the mistakes people actually make writing MQL4 offline (delimiter balance, missing
semicolons, calls outside the vetted builtin list, `indicator_buffers` vs `SetIndexBuffer` vs plot
properties, non-ASCII bytes). It passes on both files. If MetaEditor disagrees, the compile message
will point at a line; the fixes are usually one of the things in "gotchas" below.

## What the indicator shows

Example of the layout (illustrative values, not a result):

```
EMAStudy_Signals  60/132  EMA  D1  ->  LONG  (this state: 41 bars)
studied on 82 markets, D1: median Sharpe 0.43, positive in 94% of markets, ~1.5 flips/yr,
diversified book at 10% vol: maxDD -21% vs -63% for buy & hold at matched risk
REPLAY  EMA 60/132  EURUSD D1  |  21.4 yr, 5380 bars, 251 bars/yr
changes 2.78/yr   round trips 1.39/yr   in-position 64%   trades 29   win 62%   avg +1.83%   best +28.4%   worst -6.1%
strategy   CAGR +6.42%   Sharpe 0.51   maxDD -24.8%
buy & hold CAGR +4.10%   Sharpe 0.29   maxDD -51.2%   (costs 6.0 bps on 40 changes)
```

`round trips/yr` is the figure comparable with the report (1.46 for 60/132 across the 82 markets);
`changes/yr` counts both sides of each of those round trips, so it is roughly twice as large. Do not
compare one with the other and conclude the platform is trading 2x more than the study.

The `REPLAY` block is the point of the exercise: it re-runs the study's methodology on **your** chart —
same one-bar lag, close-to-close returns, cost per position change, warm-up bars dropped, annualisation
measured from the data — the `bars/yr` figure is printed, so you can see what the feed actually has
(≈252 US equities, ≈260 five-day FX, 365 for 24/7 crypto) rather than what a template assumes — and it
sits next to buy & hold on the identical window. If the numbers you see there look nothing like
the report's, the data is telling you something and I would believe the data.

Inputs worth knowing:

| input | default | why it exists |
|---|---|---|
| `TradingMode` | `EMA_LONG_FLAT` | the study's long/short variant is worse on Sharpe and only useful as a hedge; the panel reports which you are seeing |
| `SignalTimeframe` | `PERIOD_CURRENT` | set it to `PERIOD_D1` and the strategy is a daily system regardless of the chart you are staring at (this is the *only* configuration the study measured) |
| `MAMethod` | `MODE_EMA` | set `MODE_SMA` to run the study's control, which tied with the EMA |
| `CostBps` | `6.0` | per position change; the study used 10 for stocks, 6 for index/ETF, 3–4 for futures, 20 for crypto |
| `StatsYears` | `0` (all) | limit the replay window |
| `ShadeFlatSpells` | `true` | the light wash is the part of the market the system declines to hold |

## Semantics, so the two systems are the same system

* **The signal is the previous closed bar.** Position for bar *t* is decided by
  `EMA_fast(t-1) > EMA_slow(t-1)`. On the chart that means the arrow prints on the bar whose *open* you
  could have acted on, and it does not move afterwards. No repaint, because the current bar's close is
  never used for anything.
* **The drawn lines are live** on the signal's own timeframe (the forming bar's EMA updates intrabar),
  which is what you expect from a moving average overlay, and which is *not* what the signal uses.
  On a chart faster than `SignalTimeframe` the lines are a staircase of closed signal bars.
* **Warm-up.** The study drops the first `slow` bars of each series and requires 250 more after that.
  The indicator refuses to draw arrows before `slow + 2` closed signal bars, and the replay reports how
  many bars it actually used. On a chart faster than `SignalTimeframe` the replay's warm-up is measured
  in chart bars, so it drops fewer *signal* bars than the study would; the state itself is still exact.
* **Arrows flip only at entries/exits.** In long/flat mode the red arrow means "go flat", not "short";
  in long/short mode it means "go short". The panel says which mode is on.

## Does MT4's EMA agree with the one in the backtest? Measured.

MetaTrader seeds its EMA with a simple average of the first `Period` values and recurses from there;
this study (like pandas `ewm(adjust=False)` and TradingView's `ta.ema`) seeds with the first
observation. The difference decays at `(1 - 2/(N+1))` per bar, but a crossover system is a *sign*
function, so the only question that matters is whether it flips a trade. `scripts/check_mt4_parity.py`
answers that on the study's own universe for the 60/132 pair:

| history behind the scored region | markets with identical signals | median disagreement | worst | median Sharpe gap | worst Sharpe gap |
|---|---|---|---|---|---|
| full history (median 2,553 bars) | 48 / 83 byte-identical | 0.000% of bars | 0.26% of bars | **0.0000** | ±0.030 |
| 4× slow = 528 bars | 52 / 83 | 0.000% | 10.6% | 0.0000 | large |
| 3× slow = 396 bars | 38 / 83 | 0.758% of bars | 9.1% | 0.0000 | ±1.2 |

And in the full-history case **77 of 83 markets end up with exactly the same number of flips**, with a
median EMA divergence of 3 bp of price (max 30 bp). So: with enough history loaded, MT4's EMA *is* this
system; the odd one-out market differs by a pair of trades either side of a bar that sat on the line.

With only 3–4× the slow period loaded, the medians look fine but individual markets diverge hard — that
is not a bug in either implementation, it is a 132-bar average that has not finished warming up. The
practical rule: **load at least 10× `SlowPeriod` bars** (1,320 daily bars ≈ 5 years) before believing
anything you see, on either platform. Table:
`results/tables/mt4_ema_parity.{csv,md}`.

## Backtesting it in the Strategy Tester

1. `EMAStudy_AutoTrade.mq4`, any symbol, **D1**, model **"Open prices only"** — this rule only ever acts
   at a bar open, so that model reproduces its fills exactly and runs fast.
2. Set `FixedLots` (or `AutoLot` + `RiskPercent`, which needs `StopAtrMult > 0` to size against a stop).
3. Report tab > "Errors" — a real `OrderSend` rejection prints the error code; the tester with
   `MaxSpreadPoints = 0` will happily fill in spreads your broker would not.
4. **Do not add `StopAtrMult` and then compare to the report.** A protective stop is not part of the
   strategy that was measured; the EA prints that warning on init for exactly this reason.

What the study says to expect, so you can tell a bad broker feed from a bad decade: per-market median
Sharpe ≈ 0.43 with ~1.5 flips/yr, roughly 66% of bars long, drawdowns around a third, and *not* a
reliable win over holding on return in US equities. If your test shows Sharpe 1.8 on a 400-bar sample or
a fast pair doing better than a slow one, you have found data, not alpha.

## MT5 / MT4 differences that will bite you

The files are MQL4. To move them to MQL5, in this order: `iMA` returns a *handle* (create it in `OnInit`,
then `CopyBuffer` into an array; there is no per-bar `iMA(symbol, tf, p, 0, MODE_EMA, price, shift)`),
`iBarShift`/`iTime`/`iClose` need the same treatment or `CopyRates`, `IndicatorCounted` is replaced by
`prev_calculated` (already used here), `SetIndexBuffer` becomes `PlotIndexSetInteger`/`SetIndexBuffer` with
`PLOT_DRAW_BEGIN`, order management becomes the `CTrade` class (`#include <Trade\Trade.mqh>`), and
`OrderClose`/`OrdersTotal` loops over `PositionsTotal()`/`OrderInfo` do not exist. `PRICE_CLOSE` on MT5
crypto/FX symbols is fine; `MODE_EMA` seeding is the same SMA-seeded convention, so the parity table above
applies to MT5 too.

## Gotchas the structure check cannot see

* **The replay is only directly comparable to the report when `SignalTimeframe` equals the chart's
  timeframe.** Otherwise the position is held across several chart bars per signal bar, so returns are
  compounded at a finer resolution: same trades, more observations, and a Sharpe computed over those.
  Put it on a D1 chart to reproduce the study; use a faster chart with `SignalTimeframe = PERIOD_D1`
  only to see the same signals arrive earlier in the day.
* `#property strict` must stay on: without it the MT4 compiler uses the old (pre-600) semantics and the
  `input enum` types, `OnCalculate` and `ObjectSetInteger` calls in these files stop behaving as written.
* `ObjectsDeleteAll(0, "EMAS_F")` deletes by prefix — if you rename the prefix, rename both call sites,
  or the chart accumulates rectangles forever.
* `SendNotification` does nothing until a MetaQuotes ID is set in Tools > Options > Notifications, so
  `PushNotify` is off by default.
* On symbols where the broker's D1 bar is not a trading day (some crypto feeds run 24/7 and roll the day
  at 00:00 UTC), the daily close you see is not the one the study used. This changes results more than
  any implementation detail in this folder.
* The EA decides once per bar and takes the current regime immediately, so **attaching it mid-bar can
  open a position mid-bar**. That is deliberate (it is holding the regime either way) but it is not a
  bar-open fill, so a live journal's first entry will not match the tester's. With `MaxSpreadPoints > 0`
  a bar whose spread is too wide is skipped entirely and not retried until the next bar.
* `Alert()` fires once per bar because it is gated on `Time[0]`; do not "fix" that by moving it out of the
  new-bar block, or it will fire on every tick.
