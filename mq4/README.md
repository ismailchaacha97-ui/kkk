# Set & Forget — MT4 indicator (v3.00) + EA (v2.11)

Fixed builds of the Holy Grail "Set and Forget" analyst. **Neither ever trades** — they
read the market, draw the 4 Fundamentals on the chart, and alert you.

## Two builds, same analysis

| File | Kind | Where it goes |
|------|------|---------------|
| `SetAndForget_Indicator.mq4` | **Custom indicator (v3.10)** — recommended | `MQL4/Indicators/` |
| `SetAndForget_EA.mq4` | Expert Advisor (v2.20) | `MQL4/Experts/` |

Both run the identical 4-Fundamentals engine and draw the same panel, zones, structure
lines and arrows. Only the entry point differs.

### Indicator build (v3.00)

* `#property indicator_chart_window`, **no indicator buffers** — everything is drawn with
  chart objects, so it behaves like a normal overlay indicator.
* `OnCalculate()` replaces `OnTick()`; `prev_calculated == 0` (first run, history refresh,
  template reload) forces a scan, so the panel is on screen the moment you attach it.
* `OnTimer()` still refreshes the panel when **no ticks** arrive (weekend, dead symbol,
  disconnected terminal).
* Throttling now uses `GetTickCount()` instead of server time: `TimeCurrent()` can stand
  still for two days over a weekend, which used to block every rescan.
* No AutoTrading, no "Allow live trading", no trade functions at all — it is an indicator,
  it cannot place orders even by accident.
* Switching symbol or timeframe re-runs `OnInit()` → `ObjectsDeleteAll(0,"SF_")` → fresh
  redraw. Nothing stale is left on the chart.
* `InpScanAllSymbols` in indicator mode only produces alerts for the other symbols (there
  is no chart to draw on), and because indicators run on the GUI thread keep it **off**
  unless you really need it.

Install: copy to `MQL4/Indicators/`, F7 in MetaEditor, then drag it from the Navigator
onto the chart (double-click, or Insert ▸ Indicators ▸ Custom).

## "NODATA" on HTF / LTF — what it actually means

`TrendLabelEx()` returns `NODATA` in exactly three situations, and v3.10 / v2.20 print
which one on the panel (line `History`) and once in the Experts journal:

| Panel line | Meaning | Fix |
|---|---|---|
| `History  W1: EMA50 needs 50 bars, have 12` | Not enough history on that timeframe | Open the W1 (or D1) chart of the symbol once and let it download, or lower `Trend EMA slow` (e.g. 20), or use D1+H4 as the HTF pair |
| `History  W1: no price yet (0 bars)` | The timeframe has no data at all (offline chart, wrong symbol, history not downloaded) | Re-attach on a normal chart; right-click ▸ Refresh on the W1 chart |
| `History  EMA period is 0 - set Trend EMA fast/slow (e.g. 20 / 50)` | `InpHTFEMAFast` or `InpHTFEMASlow` is 0 — every timeframe reports NODATA | Set them back to 20 / 50 |

The `Prices`/`Bars` line always shows the real bar count of each timeframe, so you can tell
"no history" from "history is there but the EMA requirement is too big":

```
Bars       W1 812  D1 5210  H4 9999  H1 9999  M30 9999
```

### Why it could appear on *all five* timeframes at once

That is almost always `CopyClose()` returning `-1`, which MT4 does **while it is still
building/downloading the series of another timeframe** — typical right after attaching, on
a fresh terminal, or after a symbol/timeframe switch. Fixed in v3.10 / v2.20:

* `GetEMA()` falls back to reading closes straight from the timeseries via `iClose()` when
  `CopyClose()` comes up short, so the trend is computed from data that is already there.
* The scan re-runs after **3 seconds** (instead of a full `InpScanEverySeconds` interval)
  while any timeframe is still `NODATA`.
* Primary suspect if it persists: a zero `Trend EMA fast/slow`. `InpHTFEMATrend = 0` is the
  only period where `0` means "off" — the fast/slow periods must be >= 1.

## v2.11 — compile fix (`'zc' - parameter conversion not allowed`)

`zc` holds the AOI **touch counts**, so it must be `int[]`; `zl` holds zone **prices**, `double[]`.
v2.10 declared both as `double`, and MQL4 refuses to pass a `double[]` to the `int &zc[]`
parameter of `ClusterZones()` / `NearestZone()` (that is the 3 messages per call:
*parameter conversion not allowed*, *variable of the same type expected*,
*possible loss of data*).

If you only want to patch the copy you already have in MetaEditor, replace the line

```mq4
double zl[], zc[];
```

with

```mq4
double zl[];   // zone price
int    zc[];   // touch counts
```

and compile again. v2.11 also adds `(int)` casts on `MathMin()` so the
"possible loss of data" warnings are gone.

> The compiler output names the file `SetAndForget_HolyGrail_EA.mq4` — that is just your
> renamed copy of the same source; the fix is identical.

## Why the chart was empty

| # | Bug in v2.00 | What it did |
|---|--------------|-------------|
| 1 | `input group "..."` used for the input sections | `group` is **MQL5-only** syntax. MT4 reports `'group' - syntax error` and nothing compiles, so the chart keeps whatever old EX4 was attached (or nothing). All headers are now plain `input string` separators, which work on every MT4 build. |
| 2 | `DetectEngulfing()` copied `look+1` bars but read index `look+1` | **Array out of range on the very first scan** (look=3 → reads index 4 of a 4-element array). MT4 kills an EA on that error, so the chart went blank a few seconds after attaching. Fixed with `Hist()` + `cur=k`, `prv=k+1`, `k <= n-2`, and it now only looks at *closed* bars. |
| 3 | Every history loop used the *requested* bar count (`InpAOILookback = 500`), not the count actually returned by `CopyHigh/…` | With short W1/D1 history (a few hundred weekly bars, or a symbol you just added) the loops walked past the end of the array → another runtime stop. All loops are now bounded by the real copied count. |
| 4 | Drawing only happened inside `OnTick()` | On a closed market, on a symbol with no ticks, or right after attaching, nothing was ever drawn. Now the chart is drawn in `OnInit()` and refreshed by `OnTimer()`, so it works with zero ticks. |
| 5 | All feedback was `Print()` + objects you couldn't verify | There is now a status panel (and an optional `Comment()` line) that always shows something: price, HTF trend, LTF sync, AOI, structure, entry, and the exact WAIT reason. |

Also fixed: duplicate loop-variable declarations (MQL4 strict), signal arrows now pruned
(no more endless object list), zones get visible borders, and every object is guarded
against zero time/price.

## Install

1. MetaEditor → **File ▸ Open Data Folder** → `MQL4/Experts/` → copy `SetAndForget_EA.mq4` there.
2. Open it in MetaEditor and press **F7** (Compile). It must say **0 errors**.
3. Refresh the Navigator in MT4, drag the EA on a chart, and tick **Allow live trading**
   is *not* needed (there is no `OrderSend`), but keep **Allow DLL imports** off.
4. The EA does not open trades, so it also runs on a demo chart with AutoTrading off.

## What you should see immediately after attaching

Top-left dark panel with these lines (example):

```
SET & FORGET v2.10   EURUSD  H1
Price      1.08421
Trend      W1:UP  D1:UP  ->  HTF UP
LTF        H4:UP  H1:UP  M30:RANGE  ->  sync 2/3
AOI        price not at an LTF zone
Structure  none
Entry      no engulfing on H1/H4
WAIT - price not at an LTF AOI (UP trend)
Bars       W1:812  D1:5210  H1:9999   (scan 14:32)
```

On the chart itself: shaded LTF supply/demand zones with dotted borders, dashed HTF
levels, gold structure lines (break & retest level / H&S neckline), and BUY/SELL arrows
with a `... setup` label whenever a valid setup fires.

The last `Bars` line is the quickest health check: if `W1:0` or `D1:0`, the terminal has
not downloaded that history yet — open the W1 and D1 charts of the symbol once and wait
for the download, then re-attach the EA.

## If it is still blank

1. **Experts tab of the Terminal window** — read the last lines. You want
   `=== Set and Forget EA v2.10 ... ===` followed by the `HTF: ...` line.
   * `array out of range` → you are still running the old EX4; recompile, then remove/re-attach.
   * `'group' - syntax error` → compiling an old copy from another folder.
2. **Objects list (Ctrl+B)** — filter `SF_`. You should see `SF_PNL_BG` and `SF_PNL_0…`.
   If the list is empty, the EA is not running at all (smiley face in the top-right corner
   must be a *smiling* face, not sad).
3. Turn on `InpCommentFallback` (default on) — the text appears in the top-left corner even
   if every graphical object failed.
4. Set `InpDebugLog = true` and look at the Experts tab after one scan.
5. `InpScanAllSymbols` off (default) analyses the chart symbol only. Turn it on only after
   the single-symbol mode works — it downloads W1/D1/AOI history for every Market Watch
   symbol and is slow on a fresh terminal.

## Notes on settings

* Entry timeframes: MT4 has no H2/H3 data. Use **H1/H4** (defaults). `PERIOD_H2` compiles
  but returns no bars, and the panel would then show `NODATA`.
* `InpAOITolPoints = 0` and `InpStructTolPoints = 0` mean "auto" (ATR(14) H1 × 0.5) — good
  for FX majors on 5-digit brokers. Set an explicit value (e.g. `200`) if your broker's
  `Point` is unusual (indices, crypto, 3-digit gold).
* The strategy is strict by design: HTF sync + LTF 2/3 + price at an AOI + matching
  structure + engulfing. Long stretches of `WAIT` are normal and now explain themselves.
* Alerts repeat at most once per `InpAlertCooldownMin` per symbol+direction.
