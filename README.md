# ⚡ PropFirm Institutional Edge Pro (MT4)

[![MT4 Build](https://img.shields.io/badge/MetaTrader_4-Build_1420+-00f0ff.svg)](https://www.metatrader4.com)
[![MQL4 Strict](https://img.shields.io/badge/Language-MQL4_Strict-00e676.svg)](https://docs.mql4.com)
[![Strategy Type](https://img.shields.io/badge/Strategy-Smart_Money_Concepts_%2B_Drawdown_Guard-ffb300.svg)](#)
[![Prop Firm Ready](https://img.shields.io/badge/Prop_Firms-FTMO_%7C_FundedNext_%7C_The5ers_%7C_Topstep-ff2d55.svg)](#)

> **Institutional-Grade Smart Money Orderflow & Prop Firm Challenge Protection Indicator and Trade Execution Suite for MetaTrader 4 (MT4).**  
> Engineered for hedge funds, prop firm challenge candidates, and serious quantitative discretionary traders.

---

## 🎯 Live Interactive Strategy Visualizer

Explore the interactive live terminal, simulated Smart Money orderflow, liquidity sweeps, and the real-time Prop Firm Drawdown HUD in your browser:

👉 **Live Strategy Web Visualizer:** Run or view `web_demo/index.html` (hosted live on port 8000).

---

## 📦 What's Inside the Repository

```
├── MQL4/
│   ├── Include/
│   │   └── PropFirm_Constants.mqh               # Enums, structs, color palettes & rule profiles
│   ├── Indicators/
│   │   └── PropFirm_Institutional_Edge_Pro.mq4   # Master SMC + Liquidity + Drawdown HUD Indicator
│   └── Experts/
│       └── PropFirm_Institutional_Execution_EA.mq4 # 1-Click Execution & Hard Drawdown Killswitch EA
├── web_demo/
│   └── index.html                               # Interactive HTML5/JS Strategy Simulator & Terminal
├── PROPFIRM_INSTITUTIONAL_STRATEGY_GUIDE.md     # Hedge fund trading manual & 2-stage challenge blueprint
├── validate_mql4.py                             # Automated MQL4 structural validator script
└── README.md                                    # Project documentation & installation manual
```

---

## 💎 Key Features & Institutional Capabilities

### 1. Smart Money Concepts (SMC) Market Structure Engine
- **Fractal Swings (Swing High / Swing Low):** Non-repainting high-precision fractal detection.
- **Break of Structure (BOS):** Identifies bullish and bearish trend continuations with clean labeled lines.
- **Change of Character / Market Structure Shift (CHoCH / MSS):** Instant detection of trend reversals confirmed by candle displacement.

### 2. Institutional Order Blocks & Fair Value Gaps (FVG)
- **High-Volume Order Blocks (OB):** Highlights institutional accumulation (+OB Demand) and distribution (-OB Supply) zones with volume validation.
- **Fair Value Gaps (FVG / Imbalances):** Automatic 3-bar imbalance detection with **Consequent Encroachment (50% CE Midline)**.
- **Auto-Mitigation Engine:** Mitigated zones automatically disappear or fade to keep your chart clean and noise-free.

### 3. Liquidity Sweeps & Stop Hunts (Turtle Soup)
- **Buy-Side Liquidity (BSL) Sweeps:** Detects when hedge funds wick above swing highs / equal highs to trigger retail stops, leaving rejection wicks > 35%.
- **Sell-Side Liquidity (SSL) Sweeps:** Detects when institutional buyers sweep sell-stops below swing lows.
- **Equal Highs / Lows (EQH / EQL):** Marks resting stop liquidity pools with `EQH $$$` and `EQL $$$`.

### 4. Institutional Time & Price (Killzones)
- Highlights **Asian Range** (Accumulation), **London Open Killzone** (Judas Manipulation), **New York Open Killzone** (Main Expansion), and **London Close**.
- Session status clock and optional killzone filter to ensure you only trade when institutional volume is present.

### 5. Prop Firm Capital Protection & Drawdown HUD
- **Real-Time Daily Drawdown Gauge:** Live tracking of daily loss from midnight 00:00 server equity with color-coded safety meters (Green > 3%, Orange 1-3%, Red < 1%).
- **Overall Max Drawdown Gauge:** Live tracking against the 8-10% challenge limit.
- **Dynamic Lot Sizing Calculator:** Live display of exact recommended lot sizes for **0.50% risk per trade** based on current SL pips.
- **Emergency Drawdown Warning:** Alerts the trader if daily loss reaches 70% of the maximum allowed limit.

### 6. Institutional Multi-Confluence A+ Signal Generator
Emits high-probability trading signals (with exact **Entry Price, SL, TP1, TP2, TP3, R:R Ratio, and recommended lots**) when:
1. Liquidity is swept (BSL / SSL / EQH / Asian High/Low)
2. Market structure shifts with displacement (CHoCH)
3. Price retests an unmitigated Order Block or FVG
4. Trade occurs inside London / NY Killzone
5. Momentum EMA alignment is confirmed

### 7. Companion 1-Click Execution & Killswitch EA
- **1-Click Execution Cockpit:** Buttons for `[ BUY (0.5% Risk) ]`, `[ SELL (0.5% Risk) ]`, `[ BREAK-EVEN ALL ]`, and `[ EMERGENCY CLOSE ]`.
- **Hard Daily Drawdown Killswitch:** Automatically closes all trades, deletes pending orders, and locks execution if daily drawdown hits 4.2% (preventing account breach).
- **Auto Break-Even & Partial Scale-Out:** Moves SL to Break-Even at 1.5R, closes 50% at 2.0R, and trails the remainder.

---

## 🛠️ MetaTrader 4 (MT4) Installation Guide

1. Open your **MetaTrader 4 (MT4)** desktop terminal.
2. In the top menu, click **File -> Open Data Folder**.
3. Open the `MQL4` directory:
   - Copy `PropFirm_Constants.mqh` into `MQL4/Include/`.
   - Copy `PropFirm_Institutional_Edge_Pro.mq4` into `MQL4/Indicators/`.
   - Copy `PropFirm_Institutional_Execution_EA.mq4` into `MQL4/Experts/`.
4. In MT4, open the **Navigator Window** (Ctrl + N), right-click on **Indicators**, and click **Refresh** (or restart MT4).
5. Drag `PropFirm_Institutional_Edge_Pro` onto your desired chart (e.g. **XAUUSD M15** or **EURUSD M15**).
6. Enable **Allow DLL imports** and **Allow live trading** in the Common tab.

---

## ⚙️ Indicator Parameters & Customization

| Parameter | Default | Description |
|---|---|---|
| `InpSwingLookback` | `5` | Fractal swing lookback bars for non-repainting structure |
| `InpShowStructure` | `true` | Show BOS and CHoCH structure break lines |
| `InpShowOrderBlocks` | `true` | Highlight institutional Demand (+OB) and Supply (-OB) zones |
| `InpShowFVG` | `true` | Highlight Fair Value Gaps and 50% Consequent Encroachment |
| `InpShowLiquiditySweeps` | `true` | Detect Turtle Soup / Stop Hunts on BSL & SSL |
| `InpShowKillzones` | `true` | Highlight London (07:00-10:00 GMT) & NY (12:00-15:00 GMT) |
| `InpMinConfluenceScore` | `75` | Minimum confluence score (0-100) to trigger A+ signals |
| `InpTargetRiskReward` | `3.0` | Target R:R for Take Profit projections (1:3 RRR) |
| `InpRiskPerTradePct` | `0.50` | Account risk % used for dynamic lot sizing calculations |
| `InpPropFirmProfile` | `PROPFIRM_FTMO` | Preset rules for FTMO, FundedNext, The5ers, Topstep, Custom |
| `InpMaxDailyDrawdownPct` | `5.0` | Daily Drawdown limit % (FTMO = 5.0%) |
| `InpMaxOverallDrawdownPct` | `10.0` | Max Total Drawdown limit % (FTMO = 10.0%) |
| `InpAlertPush` | `true` | Sends instant push notification to smartphone MT4 app |

---

## 📊 Indicator Buffers Reference (For EA Integration)

| Buffer Index | Name | Type | Description |
|---|---|---|---|
| `0` | `BufferBuySignal` | `DRAW_ARROW` | Institutional A+ Buy Signal (Wingding 233) |
| `1` | `BufferSellSignal` | `DRAW_ARROW` | Institutional A+ Sell Signal (Wingding 234) |
| `2` | `BufferBullSweep` | `DRAW_ARROW` | Sell-Side Liquidity (SSL) Swept (Wingding 217) |
| `3` | `BufferBearSweep` | `DRAW_ARROW` | Buy-Side Liquidity (BSL) Swept (Wingding 218) |
| `4` | `BufferCHoCHBull` | `DRAW_ARROW` | Bullish Market Structure Shift (Wingding 159) |
| `5` | `BufferCHoCHBear` | `DRAW_ARROW` | Bearish Market Structure Shift (Wingding 159) |

---

## 📱 Mobile Push Alerts Configuration

To receive institutional A+ buy/sell alerts and emergency drawdown warnings directly on your phone:
1. Download the **MetaTrader 4 App** on iOS or Android.
2. Go to **Settings -> Chat and Messages** to find your **MetaQuotes ID**.
3. In desktop MT4, go to **Tools -> Options -> Notifications**.
4. Check **Enable Push Notifications** and paste your **MetaQuotes ID**.
5. Click **Test** — you will now receive real-time sniper signals with exact Entry, SL, and TP!

---

## 🛡️ License & Disclaimer

*For educational and prop firm trading assistance. Trading forex, gold, and indices involves substantial risk of loss. Always test on demo/evaluation environments first.*
