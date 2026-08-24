# Second Entry Price Action MT4 Indicator (21 EMA + Naked S/R)

An institutional-grade **MetaTrader 4 (MT4) Custom Indicator** implementing the **Second Entry Price Action Strategy** (PATs / Al Brooks / Mack methodology), combining **21 Exponential Moving Average (Dynamic Support & Resistance)**, **Naked Horizontal Support & Resistance Levels**, and **Rejection Candle (Pin Bar / Hammer) Confirmation**.

---

## 📊 Strategy Overview & Market Mechanics

The **Second Entry** strategy is based on a foundational market microstructure principle:  
*In a trending market, counter-trend traders almost always attempt twice to reverse the trend. When the second attempt fails at a key inflection level (such as the 21 EMA or Horizontal S/R), trapped traders are forced to cover, creating a high-probability continuation surge in the dominant trend direction.*

```
                 BULLISH SECOND ENTRY LONG (2EL)
                 
     [New Swing High]
           /\
          /  \ (Leg 1 Down)
         /    \
        /      \   [1st Entry Long (1EL) - Failed attempt to resume]
       /        \  /\
      /          \/  \ (Leg 2 Down - Trapping Bears)
     /                \
    /                  \  <--- [Rejection Pin Bar / Hammer off 21 EMA]
  ------------------------------------------------------------- 21 EMA (Dynamic Support)
                        \   ▲ [2EL BUY SIGNAL ARROW]
                         \ /  SL placed 2 pips below signal low
                          ▼   TP projected at 1:1.5 to 1:2 R:R
```

```
                 BEARISH SECOND ENTRY SHORT (2ES)
                 
                          ▲   TP projected at 1:1.5 to 1:2 R:R
                         / \  SL placed 2 pips above signal high
  ----------------------/---\---------------------------------- 21 EMA (Dynamic Resistance)
                       /     \  <--- [Rejection Pin Bar / Shooting Star off 21 EMA]
                      /       ▼ [2ES SELL SIGNAL ARROW]
                     /  /\
                    /  /  \ (Leg 2 Up - Trapping Bulls)
                   /  /    \
                  /  /      \ [1st Entry Short (1ES) - Failed attempt to resume]
                 /  /
                /  / (Leg 1 Up)
               \/
        [New Swing Low]
```

---

## 🎯 Core Entry Rules

### 1. Bullish Setup (Second Entry Long - 2EL)
1. **Trend Identification**: Market is in an established uptrend above the 21 EMA (EMA sloping upward).
2. **Pullback (Leg 1 Down)**: Price pulls back from a local swing high towards the EMA.
3. **First Entry Long (1EL)**: Price ticks above the prior candle's high. This first attempt fails to make a new high.
4. **Second Push (Leg 2 Down)**: Sellers push price down a second time into the **21 EMA** or a **Key Support Level**.
5. **Signal Candle Confirmation**:
   - The signal candle produces a strong **lower rejection wick** (&ge; 35% of total bar range).
   - Candle closes in the upper half of its range (bullish hammer / rejection).
   - Low of candle touches or is within proximity of the 21 EMA or Key Support line.
6. **Trigger**: 2EL Buy signal arrow fires, target projected at 1:2.0 Risk:Reward.

---

### 2. Bearish Setup (Second Entry Short - 2ES)
1. **Trend Identification**: Market is in an established downtrend below the 21 EMA (EMA sloping downward).
2. **Pullback (Leg 1 Up)**: Price pulls back up from a local swing low towards the EMA.
3. **First Entry Short (1ES)**: Price ticks below the prior candle's low. This first attempt fails to make a new low.
4. **Second Push (Leg 2 Up)**: Buyers push price up a second time into the **21 EMA** or a **Key Resistance Level**.
5. **Signal Candle Confirmation**:
   - The signal candle produces a strong **upper rejection wick** (&ge; 35% of total bar range).
   - Candle closes in the lower half of its range (bearish pin bar / shooting star).
   - High of candle touches or is within proximity of the 21 EMA or Key Resistance line.
6. **Trigger**: 2ES Sell signal arrow fires, target projected at 1:2.0 Risk:Reward.

---

## ⚡ Indicator Features

| Feature | Description |
| :--- | :--- |
| **Dynamic 21 EMA** | Multi-color EMA line (Green in uptrends, Red in downtrends, Blue/Gray in flat ranges). |
| **Naked S/R Levels** | Automatic calculation of multi-touch horizontal support & resistance levels using fractal swings. |
| **2EL & 2ES Signal Arrows** | Clear, non-repainting Buy (Lime) and Sell (Red) arrows on confirmed bar close. |
| **On-Chart HUD Panel** | Glassmorphism dashboard displaying Trend Direction, EMA Value, Slope in pips, S/R count, and live setup state. |
| **SL / TP Projections** | Automatic on-chart Stop Loss (with buffer) and Take Profit target lines (customizable R:R ratio). |
| **Multi-Alert Engine** | MT4 Pop-up Alerts, Sound notifications, Mobile Push Notifications (`SendNotification`), and Email alerts (`SendMail`). |
| **Non-Repainting Execution** | Signals calculate on closed bars with de-duplication locks to prevent multiple alerts per candle. |

---

## ⚙️ Input Parameters

```c
// === 1. EMA (DYNAMIC S/R) SETTINGS ===
InpEMAPeriod            = 21;             // EMA Period (Standard: 21)
InpEMAMethod            = MODE_EMA;       // Moving Average Method
InpEMAAppliedPrice      = PRICE_CLOSE;    // Applied Price
InpEnableEMATrendColor  = true;           // Color EMA by Trend Direction (Green/Red)
InpEMASlopeThresholdPts = 1.5;            // Slope Threshold in Pips

// === 2. HORIZONTAL S/R SETTINGS ===
InpEnableSR             = true;           // Enable Naked S/R Detection
InpSRBarsBack           = 300;            // Historical Bars to Scan
InpSRSwingStrength      = 5;              // Swing Fractal Strength (Left/Right bars)
InpSRMinTouches         = 2;              // Min Touches to confirm Key Level
InpSRZoneTolerancePips  = 6.0;            // S/R Level Zone Tolerance (Pips)
InpSRMaxLines           = 6;              // Max S/R Lines on Chart

// === 3. SECOND ENTRY STRATEGY RULES ===
InpEnable2EL            = true;           // Enable Second Entry Long (2EL)
InpEnable2ES            = true;           // Enable Second Entry Short (2ES)
InpMaxPullbackBars      = 25;             // Max Pullback Duration (Bars)
InpMinPullbackBars      = 2;              // Min Pullback Duration (Bars)
InpStrictTrendFilter    = true;           // Strict Trend Filter (Price on correct side of EMA)
InpAllowSRBounces       = true;           // Allow Bounces off Key S/R if near EMA
InpMaxLevelDistPips     = 10.0;           // Max Distance from EMA/SR Level (Pips)

// === 4. CANDLE REJECTION FILTERS ===
InpRequireRejection     = true;           // Require Sharp Rejection / Pinbar
InpMinWickPercent       = 35.0;           // Min Rejection Wick % of Total Candle
InpMaxOppositeWickPct   = 35.0;           // Max Opposing Wick %
InpRequireCloseInTrend  = true;           // Require Bullish Close for 2EL / Bearish for 2ES
InpMustTouchLevel       = true;           // Candle Wick MUST Touch EMA or S/R

// === 5. RISK MANAGEMENT & TARGETS ===
InpShowSLTP             = true;           // Draw SL & TP Target Lines on Chart
InpRiskRewardRatio      = 2.0;            // Take Profit Risk:Reward Ratio (1:2.0)
InpSLBufferPips         = 2.0;            // Stop Loss Buffer (Pips)
InpATRPeriod            = 14;             // ATR Period for Dynamic Volatility Buffer

// === 6. VISUALS & HUD DASHBOARD ===
InpBuyArrowCode         = 233;            // Wingdings Code for Buy (233 = Arrow Up)
InpSellArrowCode        = 234;            // Wingdings Code for Sell (234 = Arrow Down)
InpArrowSize            = 2;              // Signal Arrow Size
InpShowPatternLabels    = true;           // Show "2EL" / "2ES" Text Labels
InpShowDashboard        = true;           // Show On-Chart HUD Dashboard

// === 7. ALERTS & NOTIFICATIONS ===
InpAlertOnBarClose      = true;           // Alert Only on Bar Close (No Repaint)
InpPopupAlert           = true;           // Enable MT4 Pop-up Alert
InpSoundAlert           = true;           // Enable Sound Alert
InpPushNotification    = false;          // Enable Mobile Push Notification
InpEmailAlert           = false;          // Enable Email Notification
```

---

## 🚀 Installation Guide for MetaTrader 4

1. Download the indicator source file: [`SecondEntry_PriceAction_EMA.mq4`](./SecondEntry_PriceAction_EMA.mq4).
2. Open MetaTrader 4 and click **File &rarr; Open Data Folder**.
3. Open the **MQL4 &rarr; Indicators** directory.
4. Paste `SecondEntry_PriceAction_EMA.mq4` into this folder.
5. In MT4, go to the **Navigator window (Ctrl+N)**, right-click on **Indicators** and click **Refresh** (or restart MT4).
6. Drag **SecondEntry_PriceAction_EMA** onto any chart (Recommended: EURUSD, GBPUSD, XAUUSD, US30 on **M1, M5, or M15**).
7. Under the **Common** tab, ensure **"Allow DLL imports"** (if needed) is checked and press **OK**.

---

## 📈 Best Practices & Pro Trading Rules

1. **Trade in Strong Sessions**: Best results occur during high-volume sessions (London & New York sessions, especially 08:00–12:00 GMT and 13:30–17:00 GMT).
2. **Avoid Range-Bound Chop**: If the 21 EMA is flat and price oscillates repeatedly through it without direction, stay on the sidelines until a directional breakout occurs.
3. **Confluence is King**: The highest win rate setups occur when the 2-legged pullback tests the **21 EMA and a Naked Horizontal S/R level at the exact same price zone**.
4. **Strict Risk Management**: Risk no more than 1%–2% of account equity per trade. Always place your Stop Loss beyond the rejection wick.

---

## 🌐 Interactive Web Visualizer & Backtest Simulator

An interactive web simulator is included in this repository. You can launch it locally:

```bash
node web/server.js
```

Then open `http://localhost:3000` in your browser to:
- Inspect interactive candlestick charts with real-time EMA and S/R calculations.
- Test step-by-step 2EL and 2ES pullback detection.
- Simulate trades with customizable Risk:Reward ratios.
- Review win rate, profit factor, and trade log statistics.
- Download the `.mq4` indicator file directly.
