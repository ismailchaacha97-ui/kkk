# KKK Four Fundamentals — MT4 Indicator
### "MAKE NO MISTAKE" Strategy → Complete MT4 Indicator

This indicator implements **exactly** the 4 fundamentals you described, with no interpretation drift. It enforces all filters before drawing a Buy/Sell arrow.

---

## 1️⃣ The 4 Fundamentals (as coded)

### Fundamental 1 — Trend (HTF W1 + D1)
- **Rule:** *You want at least two TF in sync to identify direction.*
- **Coded as:** 
  - `W1 Trend` + `D1 Trend` must both be bullish → **HTF BULLISH SYNC** or both bearish → **BEARISH SYNC**. No sync = no trade (unless you disable `InpRequireHTFSync`).
  - Trend detection = **EMA 50/200** + **HH/HL vs LL/LH structure**. Method selectable (`TREND_EMA_AND_STRUCTURE` is default = strongest).
  - Dashboard shows: `1.TREND HTF: W1 ▲BULL D1 ▲BULL => BULLISH SYNC`
- **Inputs:** `InpHTF1=W1 (10080)`, `InpHTF2=D1 (1440)`, `InpEMA_Fast=50`, `InpEMA_Slow=200`, `InpTrendMethod`

> The indicator works on **any chart TF** — it always checks the real W1/D1 via `iMA`/`iClose` on those timeframes, not the current chart TF.

### Fundamental 2 — AOI (Area of Interest)

- **Rule:** *Two types: HTF AOI (Weekly/Daily) and LTF AOI (4H,2H,1H). To take a trade you need to be in a HTF AOI where price reacted in the past and wait for Break & Retest on the LTF AOI.*
- **Coded as:**
  - **Fractal AOI engine:** Finds swing highs/lows (fractals with `FractalBars=2` → 5-bar fractals), clusters levels within `ZoneTolerancePips` (default 12 pips) + `ATR*` adaptive tolerance.
  - **Touch counting:** Every cluster's strength = number of fractal touches + wick rejections. `≥2 touches = valid AOI`, `≥3 touches = strong (drawn thicker)`.
  - **Two pools:** `HTF_Zones` (D1/W1, lookback 250) and `LTF_Zones` (H4 + H1 + synthetic H2, lookback 150).
  - **Drawing:** Resistance = red rectangle, Support = green rectangle, extended 15× current TF into future. Label shows `HTF RES 3x 1.08540`.
  - **Proximity filter for trade:** Price must be **inside or near HTF AOI** (≤40 pips) — otherwise HTF filter fails. Dashboard shows `2.AOI HTF: INSIDE SUP 3x 12.4p` vs `NEAR`.

- **Inputs:** `InpHTF_AOI_TF`, `InpHTF_AOI_Lookback`, `InpLTF_AOI_TF1/TF2`, `InpZoneTolerancePips`, `InpZoneATR`, `InpMinTouchesHTF/LTF`, `InpMaxZones`

### Fundamental 3 — Structure

- **Rule:** *You cannot take a trade without proper structure. Two main structures: Head & Shoulder and Break & Retest. Always enter on next LH (sell) / next HL (buy) on LTF.*
- **Coded as:**
  1. **HL/LH Swing Filter (mandatory):** `IsNextHL()` checks last two swing lows on H1/H4: `Last Low > Prev Low` → HL (for buys). `IsNextLH()` is opposite. You can disable via `InpRequireHL_LH` but default is ON — this is your “next HL/LH” rule.
  2. **Break & Retest Engine:** For every AOI zone, looks back `InpBnR_MaxBarsAfterBreak=25` bars for a close-break beyond `zone ±3 pips` then a wick-retest into the zone with reversal close. Covers bullish (resistance→support) and bearish (support→resistance).
  3. **Head & Shoulders Engine:** Classic 5-pivot detector (LS-LV1-Head-LV2-RS) with shoulder/neckline tolerances (`15%` / `12%` of head height). Detects both Bearish HS and Bullish Inverse HS on H1, H4, and synthetic H2.

- **Strict vs Relaxed:** 
  - `InpStrictStructure=false` (default): HL/LH alone is enough (BnR/HS are bonuses, shown in dashboard).
  - `InpStrictStructure=true`: Requires HL/LH **AND** (BnR **OR** HS) — this is your “ideal entry will be having HS or BnR on LTF AOI”.

- **Inputs:** `InpDetectHS`, `InpDetectBnR`, `InpHS_Lookback`, `InpBnR_MaxBarsAfterBreak`, `InpRequireHL_LH`, `InpStrictStructure`

### Fundamental 4 — Entry Signal

- **Rule:** 
  - `1. Trend — minimum two LTF (2H,1H,30M) to be in sync.`
  - `2. AOI — must identify AOI where price reacted most in LTF. DO NOT WANT to Enter if we are above this LTF AOI.`
  - `3. Structure — enter on next LH (sell) / next HL (buy). Ideal is HS or BnR on LTF AOI.`
  - `4. ENTRY — only one valid entry is Engulfing on 1H,2H,4H.`

- **Coded as:**
  - **LTF Trend Sync:** Scans `M30, H1, H2(synthetic), H4` with same EMA+Structure engine. Counts `bullCount`/`bearCount`. Requires `≥2 in sync` with HTF bias (`InpRequireTwoLTFTrendSync=true`). Dashboard: `LTF SYNC: M30 ▲ H1 ▲ H2 — H4 ▲ => 3BULL SYNC OK`.
  - **“Do Not Enter Above LTF AOI”:** If `InpDoNotEnterAboveAOI=true`, blocks trade when price is `> zone.high + InpMaxDistanceAbovePips (20p)` away — prevents chasing. Also for sells, blocks if price is still above resistance without touching.
  - **Engulfing Detector:** Scans your selected entry TFs: `H4`, `H2 (synthetic)`, `H1`. Two modes: `ENGULF_BODY_ONLY` (default, body engulfs prior body) and `ENGULF_FULL_CANDLE`. Filters: `MinBodyRatio` (current body ≥1.0× prior), `MinBodyATR`, `WickFilter`, `Doji rejection`. Checks on **closed bar shift=1** (`InpEntryOnClosedBar`) to avoid repaint; optionally also on forming bar 0.
  - **Final Signal:** `BUY = HTF Bull Sync + LTF Bull Sync + HTF AOI proximity + LTF AOI touch + HL true + (BnR/HS if strict) + Bullish Engulfing`. `SELL` is mirror. All 4 fundamentals must be true — “MAKE NO MISTAKE”.

- **Inputs:** `InpUseEntryTF_H4/H2/H1/M30`, `InpEngulfMode`, `InpRequireTwoLTFTrendSync`, `InpDoNotEnterAboveAOI`, `InpEntryOnClosedBar`

---

## 📊 What You See on Chart

1. **HTF zones** (darker red/green) and **LTF zones** (brighter) as filled rectangles with touch-count labels.
2. **Buy/Sell arrows** (Wingdings 233/234) at `Low-ATR*0.6` / `High+ATR*0.6` on the **closed signal bar**.
3. **Dashboard** (top-left, dark panel) showing all 4 fundamentals live:
   ```
   KKK 4 FUNDAMENTALS — MAKE NO MISTAKE
   1.TREND HTF: W1 ▲BULL D1 ▲BULL => BULLISH SYNC
   LTF SYNC: M30 ▲ H1 ▲ H2 ▲ H4 ▲ => 4BULL SYNC OK
   2.AOI  HTF: INSIDE SUP 3x 12.4p
        LTF: TOUCH SUP 2x 4.1p
   3.STRUCT: HL:YES LH:NO BnR B:Y S:N HS B:N S:N => OK
   4.ENTRY Engulf: BULL YES H1 | BEAR NO
   SIGNAL: BUY | Last: BUY 14:30
   HTF 6 zones | LTF 8 zones | H2 842 bars
   ```
   Colors: Lime = OK, Yellow = wait, Red = fail.

4. **Alerts** (popup/push/email/sound) with full context: `KKK 4F BUY EURUSD M15 HTF:BULLISH SYNC LTF:3BULL ...`

---

## ⚙️ Installation

1. Copy `KKK_FourFundamentals.mq4` to `MT4 → File → Open Data Folder → MQL4/Indicators/`
2. Open **MetaEditor** (F4), compile (F7) — should show `0 errors`.
3. Restart MT4 or Refresh Navigator.
4. Drag onto any chart (e.g., EURUSD M15 or H1). 
5. In `Inputs` tab, leave defaults for first test, then tune per symbol:
   - For **XAUUSD**: increase `InpZoneTolerancePips` to 20-30 (gold is wider).
   - For **5-digit brokers**: pips are auto-detected (`GetPipValue()` handles `Point*10`).
6. Check `Allow DLL imports` OFF (not needed).
7. Click OK — dashboard appears top-left.

> **H2 timeframe:** MT4 has no native H2. The indicator **synthesizes H2** by merging H1 bars into even-hour 2H blocks (00-02,02-04...). You get real H2 OHLC, ATR, EMA, swings, AOI, and engulfing without offline charts. Look at dashboard footer: `H2 842 bars` confirms synthesis.

---

## 🎛️ Inputs Quick Reference

| Group | Input | Default | Purpose |
|-------|-------|---------|---------|
| **TREND** | `InpTrendMethod` | EMA+Structure | Most reliable |
| | `InpEMA_Fast/Slow` | 50/200 | Classic HTF filter |
| | `InpRequireHTFSync` | true | W1+D1 must agree |
| **AOI** | `InpZoneTolerancePips` | 12 | Cluster radius |
| | `InpMinTouchesHTF/LTF` | 2 | Strength threshold |
| | `InpMaxZones` | 6 | Keep chart clean |
| **STRUCTURE** | `InpStrictStructure` | false | false=HL/LH only, true=require HS/BnR |
| | `InpDetectHS/BnR` | true/true | Visual + filter |
| | `InpBnR_MaxBarsAfterBreak` | 25 | Retest window |
| **ENTRY** | `InpUseEntryTF_H4/H2/H1` | true | Where engulfing scanned |
| | `InpEngulfMode` | BODY_ONLY | Strict body engulf |
| | `InpRequireTwoLTFTrendSync` | true | 2 LTF must agree |
| | `InpDoNotEnterAboveAOI` | true | Enforces “not above AOI” |
| **DISPLAY** | `InpShowDashboard` | true | Panel |
| | `InpAlertPopup` | true | Alert |

See code header for full list — every rule has an input to toggle/relax.

---

## 🧪 How to Test

1. **Historical:** Attach to H1, press `F12` to bar-by-bar, watch arrows only print when all 4 fundamentals align. Hover dashboard to understand why a signal was blocked.
2. **Strategy Tester:** Set indicator on chart, use `Visual Mode`, check that H2 synthetic builds (footer count >0) and zones draw on D1 levels.
3. **Tune:** If too few signals → lower `InpMinTouches` to 2, set `InpStrictStructure=false`, widen `InpZoneTolerancePips`. If too many → raise touches to 3, enable strict, require `H2` sync.

---

## ⚠️ Notes & Limitations

- **Non-repaint:** HTF/LTF zones can shift slightly as new fractals form (normal for AOI), but **Buy/Sell arrows are placed on closed bar 1** and never repaint forward (they stay at `Time[1]`).
- **No DLL, no external dependency.** Works offline.
- **MT4 only.** For MT5, logic can be ported (replace `iMA` signatures, `SYMBOL_` constants).
- **Philosophy preserved:** The indicator does not invent signals — it **blocks** them unless Trend+AOI+Structure+Engulfing all agree.

---

## 📁 Files

- `KKK_FourFundamentals.mq4` — main indicator (compile in MetaEditor)
- `KKK_FourFundamentals.set` — preset with defaults for Forex majors
- `XAU_Gold.set` — preset with wider tolerance for Gold
- `INSTALL.txt` — 1-page quick install

---

**Made for KKK — 4 Fundamentals, Make No Mistake. Trade with the trend, at the AOI, with structure, on engulfing.**
