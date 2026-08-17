# Auto Trend Lines — Support & Resistance (Pine Script v6)

A TradingView indicator that **automatically draws trend lines for both upward and
downward trends** from support and resistance pivots, over a rolling **90-day**
lookback window — built specifically to stay light and not lag the chart.

**File:** [`AutoTrendLines.pine`](AutoTrendLines.pine)

---

## How to use it

1. Open TradingView → **Pine Editor**.
2. Paste the contents of `AutoTrendLines.pine`.
3. Click **Add to chart**. Optionally *Save* it to your account first.

---

## What it draws

| Object | Built from | Meaning |
|---|---|---|
| **Resistance line** | two swing **highs** | falling = downtrend, rising = expanding range |
| **Support line** | two swing **lows** | rising = uptrend, falling = downtrend |
| Small triangles | every confirmed pivot | shows what the lines are anchored to |
| Labels | end of each line | direction + current projected price |

Lines are colored by **slope**, so an uptrend and a downtrend are visually
distinct at a glance: teal for rising, red for falling.

## How the lines are chosen

1. **Pivot detection** — `ta.pivothigh()` / `ta.pivotlow()` with configurable
   left/right strength. A pivot is confirmed `pivotRight` bars after it prints,
   so the script stores it at its true bar index (`bar_index - pivotRight`).
2. **Windowing** — pivots older than the lookback are dropped. The window is
   measured in **calendar time** (`90 × 86,400,000 ms`), not in bars, so it means
   the same thing on a daily chart as on a 15-minute chart.
3. **Pair selection** — the newest pivot is the right anchor. The script walks
   candidates from oldest to newest and takes the **first one whose line no
   in-between pivot violates**, which yields the longest valid trend line. The
   violation test allows an ATR-based tolerance so a single noisy wick doesn't
   disqualify an otherwise good line.

## Why it doesn't lag

This is the part most auto-trendline scripts get wrong. Four design choices:

1. **Two line objects total, reused.** Drawings are *updated* with
   `line.set_xy1()` / `line.set_xy2()` instead of being re-created. A naive
   script calling `line.new()` per bar creates tens of thousands of objects.
2. **Drawing happens only inside `if barstate.islast`** — once, on the most
   recent bar, never on historical bars.
3. **Bounded pivot buffer** (default 10 per side), so the pair search is a
   tiny O(n²) with n ≤ 10.
4. **Cached results with a "dirty" flag** — the search re-runs only when the
   pivot set actually changed.

Measured by porting the algorithm to Python and instrumenting it:

| Chart history | Pair searches | Comparisons | Drawing objects created |
|---|---|---|---|
| 500 bars | 86 | 1,207 | **2** (naive: 1,000) |
| 5,000 bars | 1,075 | 27,549 | **2** (naive: 10,000) |
| 20,000 bars | 4,517 | 125,243 | **2** (naive: 40,000) |

Work grows **linearly** (~6 comparisons per bar) and the object count is
constant regardless of how much history is loaded.

## Settings

**Detection**
- `Lookback window (calendar days)` — default **90**.
- `Pivot left / right bars` — default 5/5. Higher = fewer, more significant
  pivots, confirmed later.
- `Max pivots kept per side` — default 10. The performance guardrail.
- `Break tolerance (ATR multiple)` — default 0.25. How far an in-between pivot
  may poke through a line before it's rejected; `0` is perfectly strict.
- `Only draw direction-consistent lines` — when ON, resistance must be falling
  (lower highs) and support must be rising (higher lows). When OFF (default),
  pivots are always connected and the line is colored by slope.

**Style** — colors, width, style, right-projection, labels, pivot markers, and
an optional shading of the lookback window.

**Alerts** — `Resistance trend line broken` and `Support trend line broken`
fire when a bar *closes* beyond the projected line. Add them via the alert
dialog → Condition → this indicator.

## Verification

The algorithm was ported to Python and tested before shipping:

- **Validity invariant** — across 72 synthetic datasets (up/down/flat trends),
  no in-between pivot ever violated a drawn line. ✅
- **Direction filter** — in strict mode, every drawn resistance was falling and
  every support rising (23 lines). ✅
- **Edge cases** — 8-bar series and perfectly flat data produce no line instead
  of crashing or drawing garbage. ✅
- **Buffer cap** — never exceeded over a 1,500-bar run. ✅
- Source also linted for Pine's line-continuation rule (wrapped lines must not
  be indented by a multiple of 4) and bracket balance.

## Notes and limitations

- **Pivots are confirmed, not predictive.** A pivot only becomes known
  `pivotRight` bars after it forms, so lines re-anchor as new swings confirm.
  This is inherent to pivot-based trend lines, not a bug.
- **On low intraday timeframes the pivot cap binds before the 90-day window
  does.** On a 15-min chart, 10 pivots per side typically span only a few days.
  Raise `Max pivots kept per side` if you want the full 90 days represented
  intraday — the cost is a slightly larger search.
- Only the single best support and resistance line are drawn, by design. The
  goal is a clean, readable chart rather than a thicket of lines.
