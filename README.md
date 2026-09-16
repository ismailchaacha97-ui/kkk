# NF Trades Multi-Timeframe Volume Profile & Entry Signals MT4 Indicator

An institutional-grade, multi-timeframe MetaTrader 4 (MT4) indicator implementing the **Auction Market Theory (AMT)** and **Volume Profile (VP)** strategy taught in the NF Trades series (*"شرح استراتيجية الفوليوم بروفايل | Parts 1 & 2"*), featuring **automated visual entry signs (arrows)**, **confluence detection**, **session profile histograms**, and an **on-screen AMT HUD dashboard**.

---

## 🎯 The 3 Core Entry Setups (Automated Signs / Arrows)

The indicator continuously analyzes market auction mechanics and prints non-repainting **Buy (🟢 Up Arrow)** and **Sell (🔴 Down Arrow)** signs directly under/above the trigger candles:

### 1. Setup 1: Value Area Extreme Rotation (Mean Reversion)
* **Bullish Sign (🟢):** Candle sweeps or tests **`D-VAL` (Daily Value Area Low)**, absorbs sellers with a lower rejection wick, and closes bullishly back above `VAL`. 
  * *Target:* **`D-POC`** (Point of Control) $\rightarrow$ **`D-VAH`**.
* **Bearish Sign (🔴):** Candle sweeps or tests **`D-VAH` (Daily Value Area High)**, absorbs buyers with an upper rejection wick, and closes bearishly back below `VAH`.
  * *Target:* **`D-POC`** $\rightarrow$ **`D-VAL`**.

### 2. Setup 2: Imbalance Retest (Breakout & Flip)
* **Bullish Sign (🟢):** Price drives into Bullish Imbalance above `D-VAH`, pulls back to test previous resistance `D-VAH` from above, and confirms `D-VAH` has flipped into support.
* **Bearish Sign (🔴):** Price drives into Bearish Imbalance below `D-VAL`, pulls back to test previous support `D-VAL` from below, and confirms `D-VAL` has flipped into resistance.

### 3. Setup 3: Multi-Timeframe Confluence Bounce (The "A+" Institutional Setup)
* **Bullish/Bearish Sign (🟢/🔴):** Triggered when price tests a higher-timeframe confluence zone (e.g. `Weekly POC + Daily VAL` or `Monthly POC + Daily VAH`) and prints a sharp rejection candle away from the cluster.

---

## ⚡ Indicator Features

* **Visual Entry Signs on Chart:** Clear Wingdings arrows (codes 233 up / 234 down) plotted with customizable size, color, and wick offset.
* **100% Non-Repainting Signals:** Evaluated on completed bars (`shift = 1`), locking the arrow in permanently once the candle closes.
* **True Dalton / CBOT Value Area Engine:** 70% Value Area algorithm using 200 price rows by default.
* **Multi-Timeframe Horizon Profiling:** Current Session (CME 18:00 NY open), Previous Day, Previous Week, and Previous Month.
* **On-Screen AMT HUD Dashboard:** Shows real-time market balance state (`Bullish Imbalance`, `Balanced / Rotating`, `Bearish Imbalance`), live distances to POCs, active confluence clusters, and latest entry sign status.
* **Visual Session Volume Profile Histogram:** Renders horizontal volume bars behind candles (`OBJPROP_BACK = true`), color-coding POC, inside Value Area, and outside Value Area.
* **Alert System:** Audio alerts, pop-up alerts, and mobile push notifications on new entry signs and confluence tests.

---

## 📊 Buffer Mapping for Expert Advisors (`iCustom`)

| Buffer Index | Plot Type | Name | Description |
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
| `12` | `DRAW_ARROW` | `AMT Buy Signal` | **Buy Arrow Price Level** (0.0 when no signal) |
| `13` | `DRAW_ARROW` | `AMT Sell Signal` | **Sell Arrow Price Level** (0.0 when no signal) |

### Expert Advisor (EA) Code Example:
```c
// Check completed bar 1 for non-repainting entry signs
double buyArrow  = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 12, 1);
double sellArrow = iCustom(Symbol(), 0, "NF_VolumeProfile_MTF", 13, 1);

if(buyArrow > 0.0 && buyArrow != EMPTY_VALUE)
{
   // Open Long Trade
   // Stop Loss: Below the rejection candle Low
   // Take Profit: Previous Day POC (Buffer 0)
}
else if(sellArrow > 0.0 && sellArrow != EMPTY_VALUE)
{
   // Open Short Trade
   // Stop Loss: Above the rejection candle High
   // Take Profit: Previous Day POC (Buffer 0)
}
```

---

## 🛠️ Input Parameters Reference

### Entry Signals Settings
* `InpShowEntrySignals`: Master toggle for Buy/Sell entry signs (Default: `true`).
* `InpSignalValVahRotate`: Enable Setup 1: Value Area Rotation (Default: `true`).
* `InpSignalImbalanceRetest`: Enable Setup 2: Imbalance Retest (Default: `true`).
* `InpSignalConfluence`: Enable Setup 3: MTF Confluence Bounce (Default: `true`).
* `InpSignalTolerancePips`: Maximum touch distance tolerance in pips/ticks (Default: `3.0`).
* `InpSignalScanBars`: Number of historical candles scanned on startup (Default: `300`).
* `InpColorBuySignal`: Buy arrow color (Default: `clrLime`).
* `InpColorSellSignal`: Sell arrow color (Default: `clrRed`).
* `InpArrowCodeBuy`: Wingdings arrow symbol (Default: `233` for Up Arrow).
* `InpArrowCodeSell`: Wingdings arrow symbol (Default: `234` for Down Arrow).
* `InpArrowOffsetPips`: Spacing between arrow and candle wick (Default: `5.0`).
* `InpSignalAlert`: Sound and pop-up alerts on new signals (Default: `true`).
* `InpSignalPushNotify`: Send push notification to MT4 mobile app (Default: `false`).

---

## 📥 Installation

1. Open MetaTrader 4.
2. Click **File** $\rightarrow$ **Open Data Folder**.
3. Open `MQL4` $\rightarrow$ `Indicators`.
4. Copy `NF_VolumeProfile_MTF.mq4` into this directory.
5. In MT4, open the **Navigator** (`Ctrl + N`), right-click **Indicators**, and click **Refresh** (or restart MT4).
6. Attach `NF_VolumeProfile_MTF` to any chart (e.g. `MNQ`, `NAS100`, `XAUUSD`, `EURUSD`).
