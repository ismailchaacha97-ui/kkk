# Hidden Institutional Entry — Pure Price Action MT4 Indicator

**Professional Edition v2.0** — Lag-free, no-repaint, pure price action indicator for MetaTrader 4 that identifies hidden institutional entry points.

Built by a professional trader & MQL4 developer. No lagging oscillators (RSI/MACD/MA). Only candlestick behavior, market structure, and institutional footprint.

---

## 🎯 What It Detects

Large institutions don't chase price — they:

1. **Engineer liquidity** (sweep stops above/below swing highs/lows)
2. **Create displacement** (impulse candle that breaks structure — BOS/CHoCH)
3. **Leave footprint** (Order Block = last opposite candle before impulse, or Fair Value Gap / Imbalance)
4. **Re-enter on mitigation** (price returns to OB/FVG with stealth trigger)

This indicator reconstructs that sequence and fires a **high-probability entry** only when price mitigates back into an unmitigated zone with a clean candlestick confirmation.

### Core Pillars

| Pillar | Logic (closed bar only) | Why it matters |
|---|---|---|
| **Market Structure** | Fractal swings (5-bar), HH/HL vs LH/LL, BOS & CHoCH | Defines trend and where institutions must break structure |
| **Liquidity Sweep** | Wick beyond recent swing + aggressive rejection (wick/range ≥ 40%) + close back inside | Stop hunt = institutions collecting orders |
| **Institutional Impulse** | Range ≥ 1.35× ATR(14) AND body/range ≥ 55% AND close breaks swing | Real displacement, not retail noise |
| **Institutional Zone** | Bullish OB = last bearish candle before bullish BOS; Bearish OB = opposite. FVG = 3-bar imbalance gap | Where unfilled orders rest |
| **Entry Trigger** | Mitigation touch + **Bullish/Bearish Engulfing** or **Pin Bar** (long wick) or Inside-Bar break + tick-volume spike | Confirms institutions defending the zone |

**Result:** Green up-arrow = hidden institutional buy, Red down-arrow = sell. No repaint — signals only on **closed bar (index 1)**.

---

## ⚡ Performance — Zero Lag Design

- **No repaint:** Never evaluates forming bar `0`, only closed bars.
- **No lagging indicators:** Pure `Open/High/Low/Close/Volume` — no RSI, MACD, MA, Stochastic.
- **Optimized `OnCalculate`:** Uses `prev_calculated` + `lastBarTime` to compute only on new bars; full scan capped by `InpMaxBarsCalc` (800). Fractal check is O(n), zone arrays limited to 12-64.
- **Error-proof:** Strict mode, `EMPTY_VALUE` handling, `Bars < 100` guard, `Point`/`Digits` aware, spread-aware FVG filter, and `IsTesting()` guard for alerts.

Compiles clean on **MT4 Build 1380+** with `#property strict`.

---

## 📦 Installation

1. Copy `HiddenInstitutionalEntry.mq4` to:
   ```
   MT4 → File → Open Data Folder → MQL4 → Indicators → HiddenInstitutionalEntry.mq4
   ```
2. In MT4 Navigator → Refresh → drag onto chart.
3. Compile in MetaEditor (F7) — should show **0 errors, 0 warnings** (strict).
4. Recommended timeframes: **M15, H1, H4** on **FX majors, Gold, Indices**.

### Inputs Overview

**Market Structure:**
- `InpSwingPeriod=5` — classic Bill Williams fractal (2–10).
- `InpBOSConfirmBars=10` — how quickly BOS must follow sweep.
- `InpUseCHoCH` — detect trend reversals.

**Institutional Impulse:**
- `InpImpulseATRFact=1.35` — impulse range vs ATR.
- `InpImpulseBodyFact=0.55` — strong body = commitment.
- `InpRequireBOSImpulse=true` — impulse must break structure.

**Zones (OB/FVG):**
- `InpUseOrderBlock / InpUseFVG` — enable/disable.
- `InpMinFVGPoints` — filter noise.
- `InpMaxZones=12`, `InpZoneExpiryBars=120` — performance + relevance.
- `InpShowZones=true` — draws rectangles (dark green/red for OB, separate for FVG).

**Liquidity Sweep:**
- `InpUseSweep` — filter zones to only those after a sweep.
- `InpRejectionFactor=0.40` — wick/range for rejection.
- `InpSweepLookback=15` bars.

**Entry Trigger:**
- `InpUseEngulfing=true` — requires body engulf (>1.05× prior).
- `InpUsePinBar=true` — hammer/shooting star (wick ≥60% range).
- `InpUseInsideBreak` — optional, more signals.
- `InpVolumeConfirm=true` — tick volume > 1.25× MA(20).

**Display:**
- `InpArrowOffsetATR=25` — arrow distance.
- `InpAlerts=true` — popup + push + email.
- `InpShowDashboard=true` — bias panel.

---

## 🔧 How to Trade It (Professional Workflow)

1. Wait for **arrow** inside a drawn OB/FVG rectangle.
2. Confirm **structure bias** (dashboard shows BULLISH/BEARISH/NEUTRAL).
3. Entry at close of signal candle, stop beyond zone edge (± zone height or swing).
4. Target: next opposing structure / 1.5–2.5× zone height / recent liquidity high/low.
5. Filter: Avoid signals against strong higher-timeframe structure; higher confluence when sweep + BOS + OB/FVG align (all required by default).

> **Pure price action mantra:** No indicator predicts — this one *reveals where institutions are forced to reveal themselves*. Use it as entry timing, not a holy grail.

---

## 📊 Visuals

- **Green arrow below bar** = Institutional Buy (demand OB/FVG mitigation + bullish engulfing/pin).
- **Red arrow above bar** = Institutional Sell.
- **Dark green rectangle** = Bullish OB (demand).
- **Dark red rectangle** = Bearish OB (supply).
- **Blue/Orange rectangles** = FVG imbalances.
- Dotted mid-line = 50% fair value.

All zones expire after 120 bars if not mitigated.

---

## 🧠 Algorithm Highlights (MQL4)

- `IsSwingHigh/Low()` — fractal detection with `InpSwingPeriod/2` half-window.
- `IsBOSBullish/Bearish()` — close breaks last swing.
- `IsInstitutionalImpulse()` — range/ATR + body ratio + BOS.
- `FindBullish/BearishOrderBlockForImpulse()` — last opposite candle pre-impulse (High-Low zone).
- `IsBullish/BearishFVG()` — 3-bar gap logic, ATR & spread filtered.
- `IsLiquiditySweepHigh/Low()` — wick beyond swing + rejection + close-back-inside.
- `IsBullish/BearishEntryTrigger()` — engulfing (body engulfs), pinbar (wick/range), volume spike.
- `OnCalculate()` — incremental, strict closed-bar evaluation, zone lifecycle management.

See code comments for trader-grade explanations.

---

## ✅ Verification

- Compiled with `#property strict` — no errors.
- Tested logic against classic ICT/SMC cases: EURUSD H1 sweep + BOS + OB retest, XAUUSD M15 FVG mitigation.
- No repaint verified: buffers written only at `idx=1` (closed), never `idx=0`.

---

## 📄 License

MIT — free to use, modify, and share. Attribution appreciated.

---

*Professional trader tip: Pair this indicator with higher-timeframe structure (H4/D1) manually. Institutions operate multi-timeframe — this indicator times the lower-timeframe entry inside the higher-timeframe narrative.*

