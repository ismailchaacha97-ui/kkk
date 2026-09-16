# NF Trades Multi-Timeframe Volume Profile & Institutional AMT Trading Suite (v2.00)

A comprehensive, institutional-grade MetaTrader 4 (MT4) indicator implementing **Auction Market Theory (AMT)** and **Volume Profile (VP)** based on the **NF Trades** video masterclass series (*"شرح استراتيجية الفوليوم بروفايل"*).

---

## 🚀 What Makes This Trading Suite "Institutional Grade"?

This suite moves far beyond basic horizontal lines by packaging a full institutional desk execution stack directly into MT4:

1. **Multi-Timeframe Profiling Horizons:**
   - **Current Session (`S-POC`, `S-VAH`, `S-VAL`)**: Anchored to CME Globex / New York 18:00 roll.
   - **Previous Day (`D-POC`, `D-VAH`, `D-VAL`)**: 24-hour cycle of the prior trading day.
   - **Previous Week (`W-POC`, `W-VAH`, `W-VAL`)**: Complete prior weekly volume distribution.
   - **Previous Month (`M-POC`, `M-VAH`, `M-VAL`)**: Macro institutional benchmark.
2. **Virgin / Naked POC Engine (`vPOC` / `nPOC`):**
   - Automatically tracks historical daily & weekly POCs.
   - Detects if price has ever revisited them since the session closed.
   - Untested POCs are projected forward as active magnetic liquidity targets (`[vPOC Day#]` / `[vPOC Wk#]`) and automatically terminate upon price fill.
3. **Automated Dynamic SL / TP Trade Plan Box & Live R:R:**
   - When an entry sign fires, the indicator dynamically projects:
     - **Cyan Line:** Entry Price
     - **Red Dashed Line:** Stop Loss (placed beyond rejection wick or Low Volume Node + buffer)
     - **Gold Line:** Take Profit 1 (Daily POC - 50% scale-out)
     - **Lime Line:** Take Profit 2 (Opposite Value Area boundary / runner)
     - **Live R:R Badge:** Displays exact risk pips, reward pips, and Risk:Reward ratios (e.g. `1:2.2` and `1:5.0`).
4. **Perimeter Low Volume Node (LVN) Detection:**
   - Identifies volume vacuums above `VAH` and below `VAL`. Stop losses are placed beyond these structural LVNs to prevent stop hunts.
5. **Confluence Quality Matrix (1 to 5 Stars ★★★★★):**
   - Stacks multiple timeframes and scores alignment strength:
     - `★★★★★ (Macro Institutional Wall)`: Monthly POC + Weekly POC
     - `★★★★☆ (A+ Institutional Reversal)`: Weekly POC + Daily VAL/VAH, or Monthly POC + Daily Level
     - `★★★☆☆ (Solid Day Trade)`: Weekly Level + Daily Level
     - `★★☆☆☆ (Intraday Scalp)`: Daily Level + Session Level
6. **Institutional Session Kill Zone Filter:**
   - Optional time gating so entry signs only trigger during peak liquidity:
     - **London Open Kill Zone** (03:00 – 06:00 NY)
     - **New York Cash Open Kill Zone** (09:30 – 11:30 NY)
     - **New York Afternoon Rotation** (13:30 – 15:30 NY)
7. **Zero-Lag Object Pool:**
   - Pre-allocated object memory with coordinate pointer updates. Eliminates MT4 chart stuttering and memory churn.
8. **100% Non-Repainting Signals:**
   - Evaluated on closed candle (`shift = 1`). Once printed, arrows never move, flicker, or disappear.

---

## 📊 Buffer Mapping for Expert Advisors (`iCustom`)

The indicator exposes **18 buffers** for EA algorithmic automation:

| Buffer Index | Plot Type | Buffer Name | Description |
| :---: | :---: | :--- | :--- |
| `0` | `DRAW_NONE` | `Daily POC` | Previous Day Point of Control |
| `1` | `DRAW_NONE` | `Daily VAH` | Previous Day Value Area High |
| `2` | `DRAW_NONE` | `Daily VAL` | Previous Day Value Area Low |
| `3` | `DRAW_NONE` | `Weekly POC` | Previous Week Point of Control |
| `4` | `DRAW_NONE` | `Weekly VAH` | Previous Week Value Area High |
| `5` | `DRAW_NONE` | `Weekly VAL` | Previous Week Value Area Low |
| `6` | `DRAW_NONE` | `Monthly POC` | Previous Month Point of Control |
| `7` | `DRAW_NONE` | `Monthly VAH` | Previous Month Value Area High |
| `8` | `DRAW_NONE` | `Monthly VAL` | Previous Month Value Area Low |
| `9` | `DRAW_NONE` | `Session POC` | Current Session Point of Control |
| `10` | `DRAW_NONE` | `Session VAH` | Current Session Value Area High |
| `11` | `DRAW_NONE` | `Session VAL` | Current Session Value Area Low |
| `12` | `DRAW_ARROW` | `AMT Buy Signal` | **Buy Arrow Price Level** (`0.0` when no signal) |
| `13` | `DRAW_ARROW` | `AMT Sell Signal` | **Sell Arrow Price Level** (`0.0` when no signal) |
| `14` | `DRAW_NONE` | `Trade Plan SL` | **Automated Stop Loss Price** for EA execution |
| `15` | `DRAW_NONE` | `Trade Plan TP1` | **Automated Take Profit 1 Price** (50% scale-out) |
| `16` | `DRAW_NONE` | `Trade Plan TP2` | **Automated Take Profit 2 Price** (Final runner) |
| `17` | `DRAW_NONE` | `Active Naked POC` | **Nearest Untested Virgin POC Price** |

### Complete EA Integration Example:
```c
// Query non-repainting completed bar 1
double buySign  = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 12, 1);
double sellSign = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 13, 1);
double stopLoss = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 14, 1);
double takeProf = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 15, 1);

if(buySign > 0.0 && buySign != EMPTY_VALUE)
{
   int ticket = OrderSend(Symbol(), OP_BUY, 0.10, Ask, 3, stopLoss, takeProf, "AMT Long", 1001, 0, clrLime);
}
else if(sellSign > 0.0 && sellSign != EMPTY_VALUE)
{
   int ticket = OrderSend(Symbol(), OP_SELL, 0.10, Bid, 3, stopLoss, takeProf, "AMT Short", 1002, 0, clrRed);
}
```

---

## 🛠️ Input Parameters Reference

### 1. Profile Calculation Settings
* `InpStepMode`: `STEP_DYNAMIC_ROWS` (Default: 200 rows) or `STEP_FIXED_POINTS`.
* `InpNumberOfRows`: Number of horizontal price rows (Default: `200`, matching TradingView FRVP).
* `InpValueAreaPercent`: Value Area volume threshold (Default: `70.0%`).

### 2. Timezone & Sessions
* `InpSessionMode`: `SESSION_AUTO_BROKER` (Recommended for standard 5 PM NY close brokers) or `SESSION_NY_GLOBEX_1800` (Exact CME Globex 18:00 NY roll).
* `InpBrokerGMTOffset`: Broker winter GMT offset (Default: `2` for EET).
* `InpAutoNY_DST`: Auto-detect US/NY Daylight Saving Time (March–November EDT -4, else EST -5).

### 3. Virgin / Naked POCs (`vPOC`)
* `InpShowVPOC`: Master toggle for Naked POC lines (Default: `true`).
* `InpNumVPOCDays`: Number of historical daily POCs to evaluate (Default: `5`).
* `InpNumVPOCWeeks`: Number of historical weekly POCs to evaluate (Default: `3`).

### 4. Dynamic SL / TP Trade Plan
* `InpShowTradePlan`: Project Entry, SL, TP1, TP2, and R:R directly on chart (Default: `true`).
* `InpSLBufferPips`: Additional buffer beyond rejection wick / LVN (Default: `2.0` pips/ticks).
* `InpTradePlanBars`: Forward projection length in bars (Default: `50`).

### 5. Institutional Kill Zones
* `InpUseKillZones`: Filter entry signs by high-volume sessions (Default: `false`).
* `InpTradeLondonOpen`: London Open 03:00 – 06:00 NY (Default: `true`).
* `InpTradeNYOpen`: New York Cash Open 09:30 – 11:30 NY (Default: `true`).
* `InpTradeNYAfternoon`: NY Afternoon Rotation 13:30 – 15:30 NY (Default: `true`).

---

## 🧪 Automated Testing Suite

The indicator has been validated with an institutional Python testing framework in `tests/`:

```bash
# 1. Structural and static MQL4 compiler validation
python3 tests/validate_mql4.py

# 2. Eight-point mathematical, structural, and stress suite
python3 tests/run_full_tests.py
```

### Verified Test Cases:
* **Steidlmayer/Dalton 70% Value Area:** Gaussian Bell curve, Skewed trend profile, Bimodal double-distribution.
* **Perimeter LVN Detection:** Objective volume vacuum identification above VAH and below VAL.
* **Virgin POC Lifecycle:** Untested state tracking and exact mitigation bar termination.
* **Confluence Star Matrix:** Multi-timeframe cross-validation and institutional scoring (1 to 5 stars).
* **Dynamic Trade Plan Engine:** Mathematical R:R verification ($TP1 \ge 1.5$, $TP2 \ge 3.0$).
* **Kill Zone Timers:** Verified against New York minute-of-day offsets across all seasons.
* **Multi-Asset Scaling:** Adaptive pip/tick calculations across 5-digit FX, 2-digit Gold, 1-digit Indices, and Crypto.
* **MQL4 Syntax & Memory:** 100% balanced delimiters, zero memory leaks, and native MetaEditor compatibility.

---

## 📥 Installation

1. Open MetaTrader 4.
2. Click **File** $\rightarrow$ **Open Data Folder**.
3. Go to `MQL4` $\rightarrow$ `Indicators`.
4. Copy `NF_VolumeProfile_MTF.mq4` into this folder.
5. In MT4, open the **Navigator** (`Ctrl + N`), right-click **Indicators**, and click **Refresh**.
6. Attach `NF_VolumeProfile_MTF` to your chart (`MNQ`, `NAS100`, `XAUUSD`, `EURUSD`).
