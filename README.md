# VWAP + Volume Profile — MetaTrader 4 indicator

One self-contained MQL4 file that puts an **anchored VWAP with standard-deviation
bands** and a per-session **Volume Profile with POC / VAH / VAL** on the same chart.

```
MQL4/Indicators/VWAP_VolumeProfile.mq4
```

No DLLs, no external data files, no include files — drop it in, compile, drag it on a chart.

---

## Install

1. In MT4: **File → Open Data Folder** → `MQL4/Indicators/` (create the folder if it is missing).
2. Copy `MQL4/Indicators/VWAP_VolumeProfile.mq4` there.
3. Open the file in MetaEditor (**F4**), press **F7** (Compile). It must end with `0 errors, 0 warnings`.
4. Back in MT4: refresh the Navigator (right-click → Refresh), drag **VWAP_VolumeProfile** onto a
   chart, main window.

Works on any symbol and timeframe. `D1`/`W1` charts need the *Monthly* or *Fixed* anchor
(the indicator tells you in the data window if you picked an anchor that is shorter than one bar).

---

## What it draws

| Element | Meaning |
|---|---|
| **VWAP** (solid) | `Σ(v·p) / Σ(v)` inside the current anchor period; resets at every session boundary |
| **±1 SD / ±2 SD** (dotted) | `VWAP ± K·σ`, where `σ² = Σ(v·p²)/Σ(v) − VWAP²` — volume-weighted deviation, not a rolling-STD of closes |
| **Histogram rows** | volume traded at each price of the session, drawn sideways, scaled to the heaviest row |
| **POC** (red) | the row with the most volume — Point Of Control |
| **VAH / VAL** (orange, dotted) | edges of the **Value Area**: rows grown out of the POC, always taking the heavier neighbour, until `InpValueAreaPct` of the session volume is inside |
| **Box** | outline of the value-area price range for the session |
| **Labels** | `POC / VAH / VAL` prices and session volume, in a column right of the profile |
| **Data window** | VWAP, both bands, POC/VAH/VAL, session volume, distance from VWAP in points, previous session's POC shift |

### The MT4 volume caveat (read this once)

MT4 does **not** publish volume per price level — only per bar (tick volume for FX). So a bar's
volume has to be *assigned* to the price rows that bar traded in. Two models are available
(`InpVolModel`):

* **Uniform** — the bar's volume is split over its touched rows proportionally to the price
  overlap. Neutral, mass-preserving, the usual choice.
* **OHLC-weighted** — 25 % Close, 10 % Open, 7.5 % High, 7.5 % Low, 50 % uniform. Trades cluster
  near the close of a bar, so this usually puts the POC closer to reality on range days.

Both models conserve total volume: `Σ(rows) = Σ(bar volume)` for the session. The profile shape is
an **estimate** — it is not exchange floor data. Use it for structure (where acceptance is), not
for exact numbers. On stocks/crypto indices where the broker supplies real volume, set
`InpVolSource = iVolume()` and the weights become actual lots.

---

## Inputs

**VWAP**

| Input | Default | Notes |
|---|---|---|
| `InpAnchor` | Daily | `Daily`, `Weekly`, `Monthly`, `Fixed anchor date` |
| `InpOffsetHour` / `InpOffsetMin` | 0 / 0 | session boundary **in chart/server time** (the axis). Use `22` for a broker that closes at 22:00 server time (5 pm NY in summer) |
| `InpWeekdayStart` | 1 | for the Weekly anchor: 1 = Monday … 7 = Sunday |
| `InpAnchorDate` | `""` | for `Fixed`: e.g. `2026.01.02 00:00`. Empty = start from the oldest bar in range |
| `InpPriceType` | (H+L+C)/3 | also `(H+L+2C)/4`, `(H+L)/2`, Close |
| `InpVolSource` | Tick volume | `iVolume()` for real lots, `Time-based` to weight every bar equally (turns VWAP into an average price) |
| `InpMaxBars` | 3000 | calculation/display depth. `0` = whole history (slow on M1) |
| `InpDrawBands`, `InpSD1`, `InpSD2` | on, 1.0, 2.0 | band multipliers |

**Volume profile**

| Input | Default | Notes |
|---|---|---|
| `InpShowProfile` | true | master switch for the histogram |
| `InpProfMode` | Volume | `Volume`, `TPO` (time at price, one count per row per bar), `Volume+TPO` blend |
| `InpVolModel` | Uniform | see the caveat above |
| `InpBins` | 40 | price rows per session, 3–400 |
| `InpValueAreaPct` | 70 | value-area volume share |
| `InpProfWidth` | 24 | maximum row length, in bars |
| `InpProfSessions` | 2 | how many sessions get a profile. `0` = every session in range (object-budget capped) |
| `InpClipSession` | false | never let a row extend past the end of its session |
| `InpHideCurrent` | false | skip drawing the forming session (numbers still shown) |
| `InpShowLookback` | false | one combined profile for the whole calculated range |
| `InpRowHeightPct` | 80 | row thickness as a share of the bin (gap between rows) |
| `InpSkipEmpty` | true | do not draw rows with zero volume |
| `InpDrawVA`, `InpDrawPOCLine`, `InpDrawLabels` | true | individual layers |

**Look & feel** — colours, `InpLiveTick` + `InpRedrawMs` (throttle, default 500 ms),
`InpShowStats`, `InpFontSize`, `InpAlertVWAP` + `InpSound`, `InpTag`.

`InpTag` matters if you put the indicator on the **same chart twice**: give the copies
`1` and `2`, otherwise they fight over the same object names.

---

## Recipes

* **Intraday, 5m chart** — defaults. Daily anchor, `InpOffsetHour` set to your broker's rollover
  hour, 40 rows, 2 sessions.
* **Cleaner bands for scalping** — `InpSD1 = 1`, `InpSD2 = 2.5`, `InpBins = 30`, `InpProfSessions = 1`.
* **Anchored VWAP from an event** — `InpAnchor = Fixed`, `InpAnchorDate = 2026.08.12 00:00`
  (NFP / CPI / earnings / swing low). No reset, one rolling reference price.
* **Auction-market look (TPO)** — `InpProfMode = TPO`, `InpBins = 48`, `InpShowLookback = true`.
* **Slow machine / big history** — `InpBins = 24`, `InpProfSessions = 1`, `InpLiveTick = false`,
  `InpMaxBars = 1000`.

---

## Behaviour notes

* **The profile scrolls with the chart.** Rows are anchored to the *session*, not to the screen,
  so the picture stays attached to the bars it was built from — which is what you want when you
  scroll back to check a level.
* **Nothing repaints that shouldn't.** The VWAP for a bar is final once the session's later bars
  are unknown; the live session's VWAP and profile obviously move until the session closes.
  The current session's profile is a *forming* profile — labelled `LIVE POC ... forming`.
* **The alert fires once per bar** on the close crossing VWAP, evaluated on the forming bar, so a
  cross can appear and disappear within a bar. Use `InpLiveTick = false` if you want bar-close only.
* **Objects are reused, not recreated**, so there is no flicker on tick updates, and an object
  budget (`VVP_OBJ_BUDGET`) keeps a runaway setting (e.g. `InpBins = 400` × 400 sessions) from
  freezing the terminal — the data window reports `! object budget reached`.
* Removing the indicator, or changing any input, deletes exactly the objects it created
  (name-prefixed `VVP<tag>_`), including leftovers from a crashed previous run.

---

## MQL4 vs MQL5 API traps this file avoids

These are the calls that break an MT4 build when code is copied or auto-converted
from MQL5, and they are pinned by the checker:

| MQL4 (correct here) | MQL5 / wrong-for-MT4 |
|---|---|
| `SetIndexEmptyValue(i, EMPTY_VALUE)` | `SetIndexEmpty()` — **does not exist in MQL4** |
| `ObjectCreate(name, type, sub_window, t1, p1, t2, p2)` | `ObjectCreate(chart_id, name, ...)` and the pre-600 form with an extra `number` argument |
| `ObjectMove(name, point, time, price)` — **one** anchor point per call | `ObjectMove(name, 0, t1, p1, t2, p2)` |
| `ObjectSet(name, OBJPROP_COLOR/STYLE/WIDTH/BACK/RAY, value)` (legacy index space) | `ObjectSet(name, OBJPROP_HIDDEN, …)` — those IDs belong to the other property enum |
| `ObjectSetInteger(chart_id, name, prop, value)` for `FILL/SELECTABLE/SELECTED/HIDDEN` | 3-arg `ObjectSetInteger(name, prop, value)` |
| `ObjectsDeleteAll(0, prefix)` | walking the chart with `ObjectsTotal()/ObjectName()` |

A mismatched argument count is reported by MetaEditor as
`')' - open parenthesis expected`, which is why the checker verifies the arity of
every one of these calls.

### Traps a real MetaEditor build actually reported

| MetaEditor said | on this line | fix used here |
|---|---|---|
| `'SetIndexEmpty' - function not defined` | `SetIndexEmpty(i, EMPTY_VALUE)` | `SetIndexEmptyValue(i, EMPTY_VALUE)` — the MQL4 name |
| `')' - open parenthesis expected` | `switch(Period)` (and `case PERIOD_*:`) | the predefined `Period` int is never read; `VVPPeriodSeconds()` measures the smallest positive `Time[]` gap instead and returns a `long` |
| `possible loss of data due to type conversion` | `int d = (int)MathFloor(...)`, `int rows = (int)MathRound(...)` | no `MathFloor`/`MathRound` left in the file: session keys are pure integer arithmetic (`VVPFloorDiv`), and the only double→int conversions sit in `VVPFloorToInt` / `VPVRoundToInt` |

Two rules that fall out of this, both enforced by `tools/mql4_lint.py`:

* **time maths stays in integers.** Day and week numbers come from
  `VVPFloorDiv(Time[i] - offset, 86400)`, so the session key is `long` end to end and
  no `double` ever appears near it. Bar length is *measured*, not looked up in a
  `PERIOD_*` switch — which also makes `W1`/`MN1` correct instead of assuming
  604800/2419200 seconds.
* **narrowing lives in one place.** `VVPIntString()` covers `long`→text (some MT4
  builds declare `IntegerToString()` with an `int` argument), and `(datetime)` is
  written out at every `Time[]` offset instead of relying on an implicit widening.

## Verification in this repo

There is no MetaEditor in this environment, so the code is checked two other ways — both run
offline and are part of the repo:

```bash
python3 tools/mql4_lint.py      MQL4/Indicators/VWAP_VolumeProfile.mq4
python3 tools/reference_check.py
```

* `tools/mql4_lint.py` — static pass for the things that break an MT4 build: unbalanced blocks,
  calls to undefined helpers, MQL5-only API in an MQL4 file (e.g. `OnCalculate`, `CopyRates`),
  MQL5-style `ObjectCreate(chart_id, ...)` misuse, **calls that are not in the MQL4 reference**
  (`SetIndexEmpty` is caught here), the documented argument count of every chart-object call,
  globals used before declaration, loop counters
  written outside their `for()` scope, buffer count vs `IndicatorBuffers(n)`, unused inputs.
* `tools/reference_check.py` — a line-by-line **Python port of the indicator's maths** with unit
  tests, plus assertions against the `.mq4` text (formula and API-usage invariants). It pins:
  session-key bucketing (daily/weekly/monthly + the time offset), the cumulative VWAP and the
  volume-weighted σ, **session reset with no leak from the previous session**, band symmetry,
  volume conservation of both intra-bar models, exact POC selection, the greedy value-area walk
  on a hand-computed histogram `[5,10,30,25,10]` (rows 2–4, 81.25 %), `100 %`/`0 %` value-area
  extremes, doji/zero-volume/no-data safety, and the render geometry + object-budget arithmetic.

Current state: `OK: no static errors found` and `ALL CHECKS PASSED`.

Compile-time truth still belongs to MetaEditor: these tools prove the API usage and the
maths, not the last byte of parser behaviour. If F7 reports anything, paste the exact
line it points at — the allowlist/arity rules above usually name the cause immediately.

## Porting to MT5

The object calls already follow the MQL5-compatible pattern; to port, replace `init/start/deinit`
with `OnInit/OnDeinit/OnCalculate`, swap the predefined arrays for `CopyRate/Open/...` (or the
`time[]/open[]/high[]/low[]/close[]/tick_volume[]` inputs of `OnCalculate`), use
`PLOT_DRAW_TYPE` properties instead of `SetIndexStyle`, and use `iVolume(_Symbol, PERIOD_CURRENT, i)`
plus `real_volume` for genuine volume per bar.
