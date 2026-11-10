# Market Structure Sync Scanner (MT4)

An MT4 indicator that scans **every pair you have** on **Weekly, Daily and H4**
and tells you which ones have **market structure in sync on all three**
timeframes:

- all three **HH + HL** → `SYNC BULLISH` (green)
- all three **LH + LL** → `SYNC BEARISH` (red)

On top of that it marks the **Area Of Interest** on **Weekly and Daily** — the
zone the current structure was built from — and draws it on the chart.

File: `mt4/MQL4/Indicators/MarketStructureSyncScanner.mq4`

---

## Install

1. In MT4 open **File → Open Data Folder**.
2. Copy `MarketStructureSyncScanner.mq4` into `MQL4/Indicators/`.
3. In MetaEditor press **F7** (Compile). It must report `0 errors`.
4. Back in MT4, refresh the Navigator (**Ctrl+N**) and drag
   **MarketStructureSyncScanner** onto any chart.
5. Allow DLLs? **No** — it needs none. Just click **OK**.

The panel appears in the top-left of that chart. It scans in the background, so
the chart stays responsive.

> Symbols that are not in Market Watch yet get added automatically
> (`AddToMarketWatch = true`). MT4 downloads their history on demand, so on the
> first run some rows will read `~load` for a few passes while the broker
> history arrives. They fill in by themselves.

---

## How structure is decided

For each symbol and each of the three timeframes:

1. **Swing points** are found as fractal pivots. A bar is a swing high when it
   is higher than `PivotLeft` bars on its newer side and `PivotRight` bars on
   its older side (lows are mirrored). `PivotRight` is what makes a swing
   *confirmed* — the scanner never repaints off an unfinished pivot. On a flat
   top the **newest** bar of the plateau is taken as the pivot.
2. The **last swing high is compared with the previous swing high**, and the
   **last swing low with the previous swing low**:

   | swing highs | swing lows | state | panel |
   |---|---|---|---|
   | higher high (HH) | higher low (HL) | bullish | `HH HL` green |
   | lower high (LH)  | lower low (LL)  | bearish | `LH LL` red |
   | HH | LL | expanding range | `HH LL` amber |
   | LH | HL | contracting range | `LH HL` amber |
   | anything else (equal pivots, mixed) | | unclear | `mixed` grey |

3. A symbol is **synced** only when all three timeframes return the *same*
   bullish or bearish state. `HH LL` on H4 never counts as a bull sync — it is
   shown, but it is not a match.

`PivotsPerSide = 2` (default) means one comparison per side: the plain
"HH and HL" you asked for. Set it to `3` to require two consecutive higher
highs *and* two consecutive higher lows — fewer, stronger signals.

---

## Reading the panel

```
MARKET STRUCTURE SYNC SCANNER
W1 + D1 + H4    pivots:2    fractal:2/2
symbols 28    ready 26    pending 2    pass 14    11:32:05
--------------------------------------------------
SYNC BULLISH (3): EURUSD  GBPJPY  XAUUSD
SYNC BEARISH (1): USDJPY
AT W1/D1 AOI (2): EURUSD(W1)  USDJPY(D1)
ENTRY LONG (1): EURUSD(W1)
ENTRY SHORT (1): USDJPY(D1)
--------------------------------------------------
SYMBOL        W1     D1     H4    SYNC     AGE        W1 AOI     D1 AOI   M15   M30   H1    ENTRY
EURUSD     HH HL HH HL HH HL    BULL     3/1/2    D 1.08432  D 1.08120 HH HL HH HL HH HL LONG 3/3
GBPJPY     HH HL HH HL HH HL    BULL     5/2/4    S 193.450t D 191.020 -     -     -     -
USDJPY     LH LL LH LL LH LL    BEAR     2/1/1    D 148.900  S 149.620>LH LL mixed LH LL SHORT 2/3
AUDUSD     HH HL LH LL HH HL    -        4/6/2    D 0.65210  -          -     -     -     -
NZDUSD     ~load ~load HH HL    -        -/-/3    -          -          -     -     -     -
```

- **AGE** = bars since the newest confirmed swing, per timeframe (`W1/D1/H4`).
  A small number means the structure just printed; a big number means it is old.
- **`~load`** history still downloading, **`nodat`** the broker has no usable
  history for that timeframe, **`~few`** history exists but not enough swings
  yet, **`mixed`** pivots do not form a clean sequence.
- **`M15 / M30 / H1`** are only graded while price is actually inside a live
  W1/D1 zone. Outside a zone they read `-`, because nobody asked the question.
- **ENTRY** = `LONG n/3` or `SHORT n/3`, where `n` is how many of the three
  entry timeframes agree with the zone. `wait n/3` means price is in a zone
  but not enough of them agree yet.
- Rows are sorted **confirmed entries first**, then at-AOI, then synced, then
  alphabetical.

---

## What an AOI is, and how it is graded

The **Area Of Interest** is the zone the current structure was built from — the
swing point that *defines* the trend you are reading:

| Structure on that timeframe | Zone taken | Colour |
|---|---|---|
| bullish (HH + HL) | the **last swing low** — a demand zone you want price to dip back into | green |
| bearish (LH + LL) | the **last swing high** — a supply zone you want price to rally back into | red |
| anything else | whichever of the two is **more recent** | follows the type |

The zone is the **full candle range** of that swing bar (`high`..`low`), not just
the close, because that is the area where orders were actually absorbed.

Only **W1 and D1** get an AOI. H4 is left alone on purpose: the whole point is to
line a fast timeframe up against the zones the higher timeframes drew, so grading
H4 against its own zone answers a different question.

**State suffix** on the panel price — what price has done to the zone since:

| Suffix | Meaning |
|---|---|
| *(none)* | **FRESH** — price has not come back to the zone yet |
| `t` | **TESTED** — price returned into the zone and held |
| `>` | **INSIDE** — price is in the zone right now |
| `x` | **SPENT** — price closed through the zone; it is invalidated |

A touch only counts **after price has left the zone at least once**. Without that
rule the bar immediately following the swing would always register a touch,
because the zone *is* that bar's range.

`SPENT` zones are hidden by default (`AOIShowSpent = false`) — a broken zone is
no longer a zone.

**On the chart**, the W1 and D1 zones of the chart symbol are drawn as filled
rectangles running from the swing bar out to the right (`AOIExtendBars` wide),
behind the candles. If price on the current chart enters a live zone, you get one
alert — it re-arms only after price leaves again.

---

## Entries on M15 / M30 / H1

The higher timeframes say **where** to look. They do not say **when** — a
Weekly demand zone can be valid for days. The entry timeframes answer the
*when*: an entry is a lower-timeframe structure turning the same way as the
zone price is standing in.

Two conditions, both required:

1. **Price is inside a live W1 or D1 zone.** `INSIDE` always wins over `TESTED`,
   and Weekly wins over Daily. If price is in neither, the entry timeframes are
   **not scanned at all** — an M15 signal with no zone behind it is noise, and
   grading 28 symbols × 3 extra timeframes for nothing is waste. Set
   `EntryAllowTested = true` to also accept zones price has touched and left.
2. **Enough entry timeframes agree with the zone.** A demand zone is bought, so
   it wants `HH HL` underneath it; a supply zone is sold, so it wants `LH LL`.
   `EntryMinConfirm` (1–3) sets how many of the three must agree.

| ENTRY cell | Meaning |
|---|---|
| `LONG n/3` | in a demand zone, `n` entry timeframes have turned bullish |
| `SHORT n/3` | in a supply zone, `n` entry timeframes have turned bearish |
| `wait n/3` | in a zone, but fewer than `EntryMinConfirm` agree |
| `-` | price is in no zone, so nothing was graded |

Structure that disagrees with the zone is not a near miss — it is the opposite
trade, and it never counts toward the tally.

An alert fires when a symbol **acquires** a signal and re-arms when the signal
goes away, so a signal that holds across passes shouts once rather than every
`RescanSeconds`. The first pass after attaching only records a baseline, same as
the sync alerts.

**`EntryMinConfirm` is clamped to 1–3**, so `0` cannot disable the check and
`99` cannot make it unreachable.

### Entry arrows on the chart

With `DrawEntryArrows = true`, the chart symbol gets an arrow whenever an entry
signal is live: a green **up arrow (233)** below the bar for a long, a red
**down arrow (234)** above it for a short. Hover one for a tooltip naming the
zone, its direction, and how many entry timeframes agreed.

By default an arrow is stamped only on **the bar the signal first appeared
on**, so a signal that holds for six bars leaves one marker rather than a
stripe of them. Set `EntryArrowEveryBar = true` to mark every bar the signal is
alive on instead.

`EntryArrowMax` (clamped 1–500) caps how many arrows stay on the chart; the
oldest is retired first. `EntryArrowPoints` (clamped 1–5000) is the offset from
the bar, in points.

**These arrows are not a backtest.** The scanner keeps no history of what the
entry timeframes looked like on past bars, so it cannot claim a signal existed
back there. An arrow means "an entry was valid here, detected on this bar" —
not "this is where you should have entered". Arrows only ever appear at the
right-hand edge and accumulate forward from the moment you attach the
indicator.

---

## The settings that matter most

| Input | Default | What it does |
|---|---|---|
| `ScanScope` | `0` | `0` = Market Watch (your pairs), `1` = every symbol in the terminal, `2` = the `CustomSymbols` list |
| `IncludeFilter` / `ExcludeFilter` | `""` | Comma lists of substrings. e.g. `ExcludeFilter = ".m,#,cash"` drops micro/index feeds; `IncludeFilter = "EUR,GBP,XAU"` narrows the scan |
| `PivotLeft` / `PivotRight` | `2 / 2` | Fractal strength. Raise to `3/3` for major swings only, drop to `1/1` for fast, noisy ones |
| `PivotsPerSide` | `2` | `2` = HH/HL, `3` = HH+HH/HL+HL (stricter) |
| `TF_High` / `TF_Mid` / `TF_Fast` | `W1 / D1 / H4` | Dropdowns — any three timeframes work, e.g. `D1/H1/M15` |
| `MaxSwingAgeBars` | `0` | `0` = off. Otherwise a structure whose newest swing is older than this is treated as stale and cannot sync |
| `RescanSeconds` / `SymbolsPerPass` | `30 / 8` | Scan cadence. Raise `SymbolsPerPass` to finish a pass faster, lower it if the chart feels heavy |
| `ShowOnlySynced` | `false` | Hide everything that is not synced |
| `PanelCorner` | `0` | `0` top-left, `1` top-right, `2` bottom-left, `3` bottom-right |
| `AlertPopup` / `AlertPush` / `AlertEmail` / `AlertSound` | on/off/off/on | Fired the moment a symbol *becomes* synced |
| `AlertCooldownMin` | `120` | Suppresses repeat alerts for the same symbol + direction |
| `ShowPivotsOnChart` | `true` | Draws the swing points it actually used on the current chart, so you can eyeball the calls |
| `ScanAOI` | `true` | Master switch for the Weekly/Daily Area Of Interest columns |
| `DrawAOIOnChart` | `true` | Draws the chart symbol's W1/D1 zones as rectangles |
| `AOIExtendBars` | `40` | How far right each drawn zone extends, in current-chart bars (clamped 5–500) |
| `AOIShowSpent` | `false` | Also draw/report zones price has already closed through |
| `AOIAlertOnTouch` | `true` | One alert when the chart symbol's price enters a live zone |
| `ColorDemand` / `ColorSupply` / `ColorAOISpent` | green / red / grey | Zone colours |
| `ScanEntries` | `true` | Master switch for the M15/M30/H1 entry columns |
| `TF_Entry1` / `TF_Entry2` / `TF_Entry3` | `M15 / M30 / H1` | The entry timeframes — any three work |
| `EntryMinConfirm` | `1` | How many entry timeframes must agree with the zone (clamped 1–3) |
| `EntryAllowTested` | `false` | Also signal on zones price has touched and left, not only ones it is inside |
| `EntryAlert` | `true` | Alert when a symbol acquires an entry signal |
| `ColorEntryLong` / `ColorEntryShort` | green / red | Entry verdict colours |
| `DrawEntryArrows` | `true` | Stamp an arrow on this chart for each entry signal |
| `EntryArrowEveryBar` | `false` | `false` = only the bar the signal appeared on; `true` = every bar it is alive on |
| `EntryArrowPoints` | `100` | Arrow offset from the bar, in points (clamped 1–5000) |
| `EntryArrowMax` | `50` | How many arrows to keep on the chart before retiring the oldest (clamped 1–500) |

**Note on broker suffixes.** If your broker uses `EURUSD.m` / `EURUSDm`,
`IncludeFilter` matching is a plain substring test, so `EUR` still matches.

**Note on alerts at startup.** The first completed pass only records a
baseline; it does not shout about syncs that were already there. Set
`AlertOnStartup = true` if you want those too.

---

## Tests

There is no MetaEditor in CI, so the verification is split in two.

**1. The structure engine is compiled and run for real.**
Everything between the `//=== CORE-BEGIN` and `//=== CORE-END` markers in the
`.mq4` — `IsPivotHigh`, `IsPivotLow`, `CollectPivots`, `ClassifyStructure`,
`SyncOf`, `MinBarsNeeded`, `AnalyzeSeries`, `FindAOI`, `EntrySignal` — is
extracted **verbatim** (not re-implemented) and compiled with
`gcc -std=c99 -Wall -Wextra`, then fed synthetic OHLC series with a known
structure.

The one edit made on the way in is stripping `&` from array parameter
declarations, because MQL4 requires `double &high[]` and C has no such syntax.
The harness proves that is the *only* change: an independent
whitespace-insensitive pattern must reproduce the compiled source exactly, and
no logical `&&` may be altered. If anyone edits the core in a way that breaks
that equivalence, the test refuses to run rather than quietly testing a
different program.

```
$ python3 tools/test_core.py
extracted CORE verbatim (13914 chars); stripped '&' from 26 array parameter
declarations for C, nothing else changed
...
287 passed, 0 failed
```

Covered: clean up/down trends, expanding and contracting ranges, 2-pivot and
3-pivot modes, fractal `2/2` and `3/3`, newest-first pivot ordering and prices,
flat-top/flat-bottom plateau handling, short series, flat series, a lookback
too small to reach the pivots, the stale-structure flag, the full sync
matrix (including the near-misses that must *not* sync), the AOI engine —
demand/supply selection, all four zone states, the adjacent-overlap case that
must *not* count as a touch, `AOI_ANY` recency in both directions, the
lookback clamp, zone levels and pivot time, and the guards — and
`EntrySignal`: both zone polarities, every confirm threshold and the ones just
either side of it, sideways structure never confirming, an undirected zone
never producing a signal in *either* polarity, and the `minConfirm` clamps.

**1b. Those tests are checked against deliberately broken code.** A green suite
only means something if it goes red when the code is wrong, so
`tools/mutate_check.py` applies 17 small defects to `FindAOI` and
`EntrySignal`, re-runs the suite after each one, requires every one to be
caught *by a failing assertion* (a compile error does not count as a catch),
and restores the file afterwards.

```
$ python3 tools/mutate_check.py
baseline (unmutated)     : 287 passed, 0 failed  [pass]
  INSIDE ignores the zone ceiling                      CAUGHT  [257 passed, 6 failed]
  ...
ok: all 17 mutations were caught by the core fixtures
```

This is not decoration, and it has caught real gaps twice. The first draft of
the AOI fixtures passed cleanly while two of nine mutations went undetected,
which is why the adjacent-overlap and `AOI_ANY`-recency cases exist. Then the
first draft of the entry fixtures let *"undirected zone still produces a
signal"* through: both of my undirected-zone cases used all-bullish structure,
and the mutated code defaults to wanting bearish, so it confirmed nothing
either way and the test could not tell the difference. Both polarities are now
covered.

**2. The MT4 shell is linted, not executed.**
Panel drawing, symbol iteration and history loading can only run inside MT4,
so those are checked statically:

```
$ python3 tools/lint_mq4.py
lint ok: brackets balanced, 47 external calls and 49 constants all
recognised, all 66 settings referenced
```

```
$ python3 tools/check_mql4_api.py     # ~10 min, uses the GitHub code-search API
97 ok, 0 with zero hits, 0 query failures
```

The second script cross-checks every MQL4 built-in and constant the file uses
against real `.mq4` sources, which catches misspelled or MQL5-only names.

**What these offline checks are worth — measured, not assumed.** The first
version of this indicator passed both of them cleanly and MetaEditor still
reported **22 errors and 4 warnings**. All of them were things a name check
cannot see:

- 18× *"arrays are passed by reference only"* — MQL4 requires `&` on every
  array parameter. Nothing was misspelled, so the lint was satisfied.
- 4× *"cannot convert enum"* — `ANCHOR_TOP` / `ANCHOR_BOTTOM` belong to
  `ENUM_ARROW_ANCHOR` (for `OBJ_ARROW`), not the `ENUM_ANCHOR_POINT` used by
  `OBJ_LABEL`. Both names exist in the MQL4 corpus, so the API check passed
  them. `ANCHOR_BOTTOM` was silently resolving to `ANCHOR_LEFT`.
- `Period()` returns `int` in MQL4, so assigning it to `ENUM_TIMEFRAMES` needs
  a cast; and `stLocal` needed initialising at its declaration.

All are fixed. The lesson is written into the tooling: **the authoritative
check is pressing F7 in MetaEditor**, which must report `0 errors`. Treat the
scripts as a fast pre-filter for typos, not as a compiler.
