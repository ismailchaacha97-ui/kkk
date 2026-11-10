# Market Structure Sync Scanner (MT4)

An MT4 indicator that scans **every pair you have** on **Weekly, Daily and H4**
and tells you which ones have **market structure in sync on all three**
timeframes:

- all three **HH + HL** → `SYNC BULLISH` (green)
- all three **LH + LL** → `SYNC BEARISH` (red)

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
--------------------------------------------------
SYMBOL        W1     D1     H4    SYNC     AGE
EURUSD     HH HL HH HL HH HL    BULL     3/1/2
GBPJPY     HH HL HH HL HH HL    BULL     5/2/4
USDJPY     LH LL LH LL LH LL    BEAR     2/1/1
AUDUSD     HH HL LH LL HH HL    -        4/6/2
NZDUSD     ~load ~load HH HL    -        -/-/3
```

- **AGE** = bars since the newest confirmed swing, per timeframe (`W1/D1/H4`).
  A small number means the structure just printed; a big number means it is old.
- **`~load`** history still downloading, **`nodat`** the broker has no usable
  history for that timeframe, **`~few`** history exists but not enough swings
  yet, **`mixed`** pivots do not form a clean sequence.
- Rows are sorted synced-first, then alphabetical.

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
`SyncOf`, `MinBarsNeeded`, `AnalyzeSeries` — is extracted **verbatim** (not
re-implemented) and compiled with `gcc -std=c99 -Wall -Wextra`, then fed
synthetic OHLC series with a known structure.

```
$ python3 tools/test_core.py
...
73 passed, 0 failed
```

Covered: clean up/down trends, expanding and contracting ranges, 2-pivot and
3-pivot modes, fractal `2/2` and `3/3`, newest-first pivot ordering and prices,
flat-top/flat-bottom plateau handling, short series, flat series, a lookback
too small to reach the pivots, the stale-structure flag, and the full sync
matrix (including the near-misses that must *not* sync).

**2. The MT4 shell is linted, not executed.**
Panel drawing, symbol iteration and history loading can only run inside MT4,
so those are checked statically:

```
$ python3 tools/lint_mq4.py
lint ok: brackets balanced, 44 external calls and 40 constants all
recognised, all 45 settings referenced
```

```
$ python3 tools/check_mql4_api.py     # ~3 min, uses the GitHub code-search API
84 ok, 0 with zero hits, 0 query failures
```

The second script cross-checks every MQL4 built-in and constant the file uses
against real `.mq4` sources, which catches misspelled or MQL5-only names.
It does **not** prove argument types — the authoritative check is still
pressing **F7** in MetaEditor, which must report `0 errors`.
