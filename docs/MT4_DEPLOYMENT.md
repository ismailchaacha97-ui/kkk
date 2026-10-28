# Deploying the EA in MetaTrader 4

## 1. Install

1. In MT4: `File → Open Data Folder → MQL4 → Experts`, copy
   `EA/LiquiditySweep_Portfolio.mq4` there.
2. Open it in MetaEditor and press **F7** to compile. Expect 0 errors;
   the EA uses no external libraries or includes.
3. Refresh the Navigator in MT4 (right-click → Refresh).

## 2. Configure

* Attach the EA to **one** H1 chart. The chart symbol is only used as the clock;
  the traded symbols come from `InpSymbols`.
* Load a preset: in the EA properties dialog, **Load** →
  `presets/MT4_standard.set` (or `MT4_conservative.set`).
* Set `InpGMTOffsetHours` to the broker's server offset from UTC
  (`2` for most GMT+2/GMT+3 ECN brokers in winter, `3` in summer — MT4 does not
  apply DST automatically, so if your broker shifts, either adjust this twice a
  year or accept a one-hour session shift).
* Make sure every symbol in `InpSymbols` exists at your broker with the **exact**
  name (suffixes such as `EURUSD.pro` or `EURUSDm` must be used as they appear in
  Market Watch). The EA calls `SymbolSelect()` and logs a warning for any symbol
  it cannot resolve.
* Open each symbol's H1 chart once (or use the History Center) so that H1 data
  is downloaded. The EA needs at least ~400 H1 bars per symbol.

## 3. Presets

| Preset | Symbols | Risk / trade | Max positions | Use |
|---|---|---:|---:|---|
| `MT4_standard.set` | 5 | 0.25% | 3 | validated configuration |
| `MT4_conservative.set` | 2 | 0.15% | 2 | small accounts, first live months |
| `MT4_demo_1pct_target.set` | 5 | 3.00% | 5 | **demo only**, see `RISK_AND_TARGET.md` |

Account size: with 0.25% risk and the minimum lot of 0.01, a stop of ~12 pips on
EURUSD risks ~$1.20, which is 0.25% of $480. Below roughly $500 of equity the
minimum lot size starts overriding the risk model and the EA will skip trades
(it refuses to round risk *up*). Use a cent account, or the conservative preset,
or a larger balance.

## 4. Before going live

* Run the MT4 **strategy tester** on H1 with "Every tick" for at least
  2015–2025 on the standard preset, and compare the shape of the equity curve
  with `reports/figures/equity_full_2013_2026.png`. They will not be identical
  (different broker data, different spread model, tester intrabar assumptions),
  but the sign of the result in each period should match: positive 2015–2021,
  flat-to-negative 2022+.
* If your tester shows large profits after 2022, suspect the data or the spread
  settings before celebrating — see the bug note in `VALIDATION.md`.
* Enable **Allow live trading**, and check the Experts log for the
  "initialised" line and for stale-symbol warnings.
* Watch the first two weeks on a demo account at the same broker and timezone.

## 5. What the EA writes

* A dashboard comment on the chart: equity, day/week P&L, positions, session
  state, halt flags.
* Journal entries when a daily/weekly stop triggers, when an order is retried,
  and (with `InpVerboseLog=true`) for every signal, fill and stop modification.
* Magic number `InpMagicNumber` isolates all orders; the EA only ever manages
  positions carrying that magic. It will not touch manual trades.

## 6. Safety behaviour

| Situation | Behaviour |
|---|---|
| Daily loss beyond `InpDailyStopPct` | no new trades until the next server day |
| Daily loss beyond `InpDailyHardStopPct` | close all EA positions, halt for the day |
| Weekly loss beyond `InpWeeklyStopPct` | no new trades until next week |
| Spread above limit | symbol skipped for that bar |
| Stale/missing H1 bar on a symbol | symbol skipped for that bar (avoids trading on a frozen quote) |
| Broker rejects the stop (error 130) | order re-sent without a stop, then modified |
| Not enough margin / min lot above risk | trade skipped, logged |
| Friday after `InpFridayCloseHourUTC` | EA positions closed |

## 7. Limitations of the MT4 build

* Logic is evaluated once per finished H1 bar; intrabar the EA only reacts to
  broker-side stop/target orders. This matches the reference engine, but it means
  the EA cannot beat the broker to a stop.
* No built-in news filter. The daily guards limit the damage, but the EA will
  hold a position through an NFP or FOMC release if it was opened earlier.
* Single magic number: do not run two instances with different symbols but the
  same magic on the same account.
* `InpPivotLookback = 400` means the pivot scan is bounded; if you raise
  `InpPivotK`, raise the lookback too.
