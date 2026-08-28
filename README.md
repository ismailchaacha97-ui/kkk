# BuyLowSellHigh — MT4 "Buy Low / Sell High" Toolkit

A mean-reversion toolkit for MetaTrader 4 that signals (and optionally auto-trades)
**buys at oversold extremes** and **sells at overbought extremes**.

| File | What it is |
|---|---|
| `MQL4/Indicators/BuyLowSellHigh.mq4` | Chart indicator: BUY/SELL arrows + alerts (main deliverable) |
| `MQL4/Experts/BuyLowSellHigh_EA.mq4` | Optional EA that auto-trades the indicator's signals |

> ⚠️ **Educational code, not financial advice.** Mean reversion loses money in strong
> trends if misconfigured. Always backtest in the Strategy Tester and run on a demo
> account before risking real money.

---

## 1. Installation

1. In MT4: **File → Open Data Folder** → open `MQL4/`.
2. Copy `BuyLowSellHigh.mq4` into `MQL4/Indicators/` and
   `BuyLowSellHigh_EA.mq4` into `MQL4/Experts/`.
3. Open MetaEditor (F4), select each file and press **Compile** (F7) — both should
   compile with `0 errors, 0 warnings`.
4. Back in MT4, refresh the Navigator (right-click → Refresh).
5. Drag **BuyLowSellHigh** onto a chart to see signals, or attach
   **BuyLowSellHigh_EA** to a chart with **AutoTrading enabled** to trade them.

## 2. How the signal logic works

The indicator marks a BUY arrow (below the candle) the first time price enters an
extreme oversold state, and a SELL arrow (above the candle) the first time it enters
an extreme overbought state. Three engines are built in (`InpMode`):

### Mode 1 — `RSI + Bollinger` (default)
* **BUY:** RSI < oversold level (30) **and** close pierces the **lower Bollinger Band**.
* **SELL:** RSI > overbought level (70) **and** close pierces the **upper Bollinger Band**.
* One arrow per "dip/spike episode" (the first bar the condition is true).

### Mode 2 — `Stochastic`
* **BUY:** %K crosses **above** %D while %K was below the oversold level (20) — buys
  the low *after* upward confirmation.
* **SELL:** %K crosses **below** %D while %K was above the overbought level (80).
* Uses the Low/High price field (`STO_LOWHIGH`), i.e. the same values as MT4's
  standard Stochastic oscillator with default settings.

### Mode 3 — `Z-Score`
* Z = (close − rolling mean) / rolling std-dev over `InpZWindow` bars.
* **BUY:** Z crosses below −2 (price statistically "too cheap").
* **SELL:** Z crosses above +2 (price statistically "too expensive").

### Trend filter (all modes, on by default)
An optional 200-period SMA keeps you "buying low" only **above** the long average
(dips in uptrends) and "selling high" only **below** it (rallies in downtrends).
Set `InpUseTrendFilter = false` to fade every extreme in pure range-trade style.

### No repainting
With `InpSignalOnClose = true` (default) a signal is only evaluated on **closed**
bars, so arrows never appear/disappear afterwards. Alerts fire once, when the bar closes.

## 3. Indicator inputs

**Signal engine** (these 17 are forwarded by the EA via `iCustom`, keep in sync):

| Input | Default | Meaning |
|---|---|---|
| `InpMode` | RSI+BB | Signal engine (0=RSI+BB, 1=Stoch, 2=Z-Score) |
| `InpRsiPeriod` | 14 | RSI period |
| `InpRsiBuyLevel` / `InpRsiSellLevel` | 30 / 70 | RSI oversold / overbought levels |
| `InpBBPeriod` / `InpBBDeviation` | 20 / 2.0 | Bollinger period / deviations |
| `InpStochK` / `InpStochD` / `InpStochSlowing` | 14 / 3 / 3 | Stochastic settings |
| `InpStochBuyLevel` / `InpStochSellLevel` | 20 / 80 | Stochastic extreme levels |
| `InpZWindow` / `InpZLevel` | 100 / 2.0 | Z-Score window / entry level |
| `InpUseTrendFilter` / `InpTrendPeriod` | true / 200 | Long-SMA trend filter |
| `InpSignalOnClose` | true | Closed-bar signals (keep true for the EA) |
| `InpMaxBars` | 2000 | History bars scanned (0 = all) |

**Visuals & alerts:**

| Input | Default | Meaning |
|---|---|---|
| `InpArrowGapATR` | 0.35 | Arrow offset from the candle (× ATR14) |
| `InpArrowWidth` | 2 | Arrow size |
| `InpAlertPopup` / `InpAlertSound` / `InpAlertPush` / `InpAlertEmail` | popup only | Alert channels |
| `InpSoundFile` | alert.wav | WAV in the terminal `Sounds/` folder |
| `InpShowInfo` | true | Status line in the top-left corner |

Push notifications require your MetaQuotes ID in **Tools → Options → Notifications**;
e-mail requires the E-mail tab to be configured.

## 4. Trading the signals with the EA

The EA reads the indicator's buffers via `iCustom` once per bar (on the last closed
bar) and then:

* **BUY signal** → closes open shorts (if `InpCloseOnOpposite`) and opens one long.
* **SELL signal** → closes open longs and opens one short.
* Exits: opposite signal, stop loss, take profit, or optional trailing stop.

Key trading inputs:

| Input | Default | Meaning |
|---|---|---|
| `InpAllowBuy` / `InpAllowSell` | true | Enable each direction |
| `InpLotMode` | Fixed | `LOT_FIXED` or `LOT_RISK` (% of balance vs SL distance) |
| `InpFixedLot` / `InpRiskPercent` | 0.10 / 1.0 | Lot size / risk per trade |
| `InpSLMode` | ATR | `SL_FIXED` (points) or `SL_ATR` |
| `InpSLPoints` / `InpTPPoints` | 300 / 400 | Fixed distances in **points** (30/40 pips on 5-digit FX) |
| `InpATRMultSL` / `InpATRMultTP` | 2.0 / 3.0 | ATR-based SL/TP multipliers |
| `InpUseTrailing` / `InpTrailPoints` | false / 250 | Trailing stop |
| `InpMaxSpreadPoints` | 40 | Skip entries when spread exceeds this (0 = off) |
| `InpMagic` | 20260828 | Magic number (change per chart if running multiple) |

**Important:** the EA's *Signal indicator settings* block must match the indicator's
settings — the values are passed straight into `iCustom()`. Leave the indicator's
`InpSignalOnClose = true`.

> **ECN/STP note:** most MT4 brokers accept SL/TP directly in `OrderSend`. If yours
> rejects it (error 130), send the order without SL/TP and add them with `OrderModify`.

## 5. Suggested usage

* **Charts:** EURUSD/GBPUSD/USDJPY, **M30–H4**. Mean reversion works best on higher
  timeframes with decent range behaviour.
* **Range markets:** turn the trend filter off, tighten exits (TP near the middle band).
* **Trending markets:** keep the 200-SMA filter on — it skips counter-trend fades.
* **Backtest:** Strategy Tester → Expert = `BuyLowSellHigh_EA`, model = *Every tick*,
  and verify the indicator file is compiled in `MQL4/Indicators/` (the tester needs
  the compiled `.ex4`).
* Tune levels with the Strategy Tester's optimizer before going live.

## 6. FAQ

**Do the arrows repaint?** No — with the default `InpSignalOnClose = true` signals are
computed on closed bars only.

**Can I use the signals in my own EA?** Yes — read the buffers:
`iCustom(Symbol(), 0, "BuyLowSellHigh", <17 signal inputs…>, 0, shift)` for buys and
`…, 1, shift` for sells; `EMPTY_VALUE` means no signal.

**Why didn't it buy an obvious dip?** The trend filter was on (dip below the 200 SMA),
or the alert/bar had already signalled. Lower `InpTrendPeriod` or disable the filter.

**Does it hedge / grid / martingale?** No — one position per side, fixed or
risk-based sizing, hard stop loss on every trade.
