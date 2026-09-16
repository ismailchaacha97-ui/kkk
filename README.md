# NF Trades Multi-Timeframe Volume Profile MT4 Indicator

An institutional-grade, multi-timeframe MetaTrader 4 (MT4) indicator implementing the **Auction Market Theory (AMT)** and **Volume Profile (VP)** strategy taught in the NF Trades series (*"شرح استراتيجية الفوليوم بروفايل | Parts 1 & 2"*).

---

## 🎯 Strategy Overview

The strategy analyzes transacted contract volume at specific price levels rather than time-based price oscillations. It continuously evaluates the four key profiling horizons:

1. **Current Session Profile (`S-POC`, `S-VAH`, `S-VAL`)**:
   - Anchored to the CME Globex / New York session open (18:00 New York time) up to the current bar.
2. **Previous Daily Profile (`D-POC`, `D-VAH`, `D-VAL`)**:
   - Full 24-hour cycle of the prior trading day.
3. **Previous Weekly Profile (`W-POC`, `W-VAH`, `W-VAL`)**:
   - Complete prior weekly cycle.
4. **Previous Monthly Profile (`M-POC`, `M-VAH`, `M-VAL`)**:
   - Macro volume context from the prior calendar month.

---

## ⚡ Key Indicator Features

* **True Dalton / CBOT Value Area Engine:**
  - Implements the canonical 70% Value Area algorithm (Steidlmayer / Dalton method), expanding 2 bins above vs 2 bins below the Point of Control (POC).
* **Cross-Timeframe Confluence Engine:**
  - Automatically identifies when key levels from different timeframes align within a configurable pip/point threshold (e.g. `Weekly POC` aligned with `Daily VAL`).
  - Visually flags confluent levels with distinct colors, thickened lines, and specific labels.
* **On-Screen Heads-Up Display (HUD Dashboard):**
  - Displays real-time market balance state:
    - `[🟢 BULLISH IMBALANCE]` (Price > Session VAH)
    - `[🟡 BALANCED / ROTATING]` (Inside Session Value Area)
    - `[🔴 BEARISH IMBALANCE]` (Price < Session VAL)
  - Live distance to Daily, Weekly, and Monthly POCs.
  - Active confluence alerts.
* **Visual Session Volume Profile Histogram:**
  - Renders horizontal volume bars directly on the MT4 chart with distinct coloring for POC, inside Value Area (70%), and outside Value Area.
* **Multi-Timeframe Adaptive Resolution:**
  - Automatically selects optimal lower-timeframe data (M1 for Session/Daily, M5 for Weekly, M15/H1 for Monthly) to ensure high precision while preventing MT4 chart freezing.
* **Automated Trading Ready (EA Integration):**
  - Exposes 12 indicator buffers for `iCustom()` access in Expert Advisors.
* **Timezone & New York DST Handling:**
  - Automatic New York Daylight Saving Time (EDT UTC-4 vs EST UTC-5) detection and broker server time conversion.

---

## 📊 Buffer Mapping for Expert Advisors (`iCustom`)

| Buffer Index | Name | Description |
| :---: | :--- | :--- |
| `0` | `Daily POC` | Previous Day Point of Control |
| `1` | `Daily VAH` | Previous Day Value Area High |
| `2` | `Daily VAL` | Previous Day Value Area Low |
| `3` | `Weekly POC` | Previous Week Point of Control |
| `4` | `Weekly VAH` | Previous Week Value Area High |
| `5` | `Weekly VAL` | Previous Week Value Area Low |
| `6` | `Monthly POC` | Previous Month Point of Control |
| `7` | `Monthly VAH` | Previous Month Value Area High |
| `8` | `Monthly VAL` | Previous Month Value Area Low |
| `9` | `Session POC` | Current Session Point of Control |
| `10` | `Session VAH` | Current Session Value Area High |
| `11` | `Session VAL` | Current Session Value Area Low |

### MQL4 EA Example:
```c
double dailyPOC = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 0, 0);
double dailyVAH = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 1, 0);
double dailyVAL = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 2, 0);
```

---

## 🛠️ Input Parameters

### 1. Profile Calculation Settings
* `InpStepMode`: `STEP_DYNAMIC_ROWS` (Default: 200 rows) or `STEP_FIXED_POINTS`.
* `InpNumberOfRows`: Dynamic price bins (Default: `200`, matching TradingView setup in the video).
* `InpValueAreaPercent`: Value Area percentage (Default: `70.0%`).
* `InpVolumeType`: `VOL_TYPE_TICK` (Forex/CFD/Gold) or `VOL_TYPE_REAL` (Futures).

### 2. Timezone & Session Settings
* `InpSessionMode`: `SESSION_AUTO_BROKER` (Recommended for standard 5 PM NY Close brokers) or `SESSION_NY_GLOBEX_1800` (Exact 18:00 NY roll).
* `InpBrokerGMTOffset`: Broker winter GMT offset (Default: `2` for EET brokers).
* `InpAutoNY_DST`: Auto-detect US/NY Daylight Saving Time (March–November EDT -4, else EST -5).

### 3. Confluence & Alerts
* `InpEnableConfluence`: Enable cross-timeframe alignment detection (Default: `true`).
* `InpConfluenceThreshold`: Max tolerance in pips/ticks to consider two levels confluent (Default: `5.0`).
* `InpConfluenceColor`: Color for highlighting confluent levels (Default: `clrLimeGreen`).
* `InpEnableAlerts`: Popup / sound alert when price tests a confluence level.

---

## 📥 Installation

1. Open MetaTrader 4.
2. Go to **File** -> **Open Data Folder**.
3. Navigate to `MQL4` -> `Indicators`.
4. Copy `NF_VolumeProfile_MTF.mq4` into this folder.
5. In MT4, open the **Navigator** panel (`Ctrl + N`), right-click on **Indicators**, and select **Refresh** (or restart MT4).
6. Attach `NF_VolumeProfile_MTF` to your chart (e.g. `MNQ`, `NAS100`, `XAUUSD`, `EURUSD`).

---

## 🧪 Testing

The mathematical and logical engines have been validated via Python unit tests located in `tests/`:
```bash
python3 tests/run_full_tests.py
python3 tests/validate_mql4.py
```
