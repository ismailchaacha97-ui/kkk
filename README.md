# Adaptive SMC Dashboard for MetaTrader 4

An MT4 indicator modeled on the functionality demonstrated in the referenced video: Smart Money Concepts (SMC) structure signals, order blocks, entry/stop/target levels, a weighted multi-timeframe scanner, historical statistics, recovery simulations, alerts, and an on-chart optimizer.

> **Important:** this is an original functional reconstruction, not the video's proprietary source code. It does not contact an AI service. The **OPTIMIZE** button runs a bounded, deterministic search over historical parameters on the local MT4 terminal.

## Files

- `MQL4/Indicators/Adaptive_SMC_Dashboard.mq4` — indicator source
- `MQL4/Presets/Adaptive_SMC_Gold_H4.set` — H4 gold-style starting preset
- `MQL4/Presets/Adaptive_SMC_Conservative.set` — stricter CHoCH + MTF preset

## Main features

- Closed-candle BOS and CHoCH market-structure signals
- Confirmed swing points, so a signal is not moved after it is generated
- Last-opposite-candle order-block zones
- Buy/sell arrows plus Entry, SL, TP1, TP2, and TP3 levels
- Five stop modes:
  - last opposite swing
  - behind order block
  - recent high/low
  - fixed points
  - ATR distance
- Risk/reward or ATR targets
- Weighted M5/M15/M30/H1/H4/D1 scanner
- Optional MTF agreement filter; rejected setups can remain visible in gray
- Broker-time session and weekday filters
- Dashboard showing:
  - active settings and current structure
  - MTF direction and weighted buy/sell strength
  - TP1 test results, win rate, and profit factor
  - latest accepted entry, stop, and targets
  - gross/net money simulation and growth
  - signal-to-signal simulation
  - fixed-add or multiplier recovery simulation
- Popup and MT4 push notifications
- **OPTIMIZE**, **RESET**, and collapse controls
- Four indicator buffers for EA/iCustom integration

## Installation

1. In MT4, select **File → Open Data Folder**.
2. Copy `Adaptive_SMC_Dashboard.mq4` into `MQL4/Indicators/`.
3. Open MetaEditor, open the file, and press **Compile**.
4. Return to MT4 and refresh **Navigator → Indicators**.
5. Drag **Adaptive SMC Dashboard** onto a chart.
6. Optionally copy the `.set` files into `MQL4/Presets/`, then use **Load** in the indicator Inputs tab.

For the setup closest to the video, start with `Adaptive_SMC_Gold_H4.set` on XAUUSD H4. Broker symbols and point sizes vary, so verify all prices and results on a demo account.

## Signal rules

The indicator processes bars from oldest to newest and only evaluates closed bars (`shift >= 1`). A pivot becomes usable after `SwingStrength` bars have closed to its right.

- A close above the most recent confirmed, unbroken swing high creates a bullish structure break.
- A close below the most recent confirmed, unbroken swing low creates a bearish structure break.
- A break in the existing direction is labeled **BOS**.
- A break against the existing direction is labeled **CHoCH**.
- `SignalOnCHoCHOnly=true` suppresses continuation BOS entries.
- `ReverseSignals=true` reverses the final trade direction for research; it does not change historical prices.

The MTF filter independently reconstructs the latest completed structure state on each enabled timeframe. Enabled timeframe weights are converted to buy/sell percentages. A setup is accepted only when its directional percentage reaches `MinimumMTFAgreement`.

## Dashboard test assumptions

The dashboard is an indicator-side simulation, not MT4 Strategy Tester execution:

- signals are tested independently against TP1 and SL;
- if TP1 and SL are both inside the same candle, SL is counted first (conservative assumption);
- spread, optional extra spread, and round-turn commission are deducted;
- tick size and tick value come from the broker;
- tests can include overlapping signals;
- `MaximumTradeBars=0` means a setup remains open until TP1, SL, or the present;
- the signal-to-signal model exits only on the next accepted opposite signal;
- recovery figures are hypothetical and do not place orders.

Different broker history, spreads, sessions, and XAUUSD contract specifications will produce different figures from the video.

## On-chart optimizer

Press **OPTIMIZE** to test a bounded sample of combinations involving:

- swing strength;
- structural/ATR stop mode;
- ATR stop multiplier;
- ATR TP1 multiplier;
- BOS + CHoCH versus CHoCH-only signals;
- MTF threshold.

Search depth controls the test count:

- Fast: 24
- Normal: 72
- Full: 180

The best runtime configuration is saved in MT4 terminal global variables for the current symbol and timeframe. **RESET** removes those saved values and restores the Inputs-tab settings. Optimized runtime values are shown in the dashboard and Experts log.

Optimization is in-sample and can overfit. Recheck the result on unseen dates and a demo account.

## Indicator buffers

For `iCustom` consumers:

| Buffer | Meaning | Empty value |
|---:|---|---|
| 0 | accepted buy arrow price | `EMPTY_VALUE` |
| 1 | accepted sell arrow price | `EMPTY_VALUE` |
| 2 | rejected buy arrow price | `EMPTY_VALUE` |
| 3 | rejected sell arrow price | `EMPTY_VALUE` |

Use closed candle shift `1`, not shift `0`, when an EA consumes a signal.

## Risk notice

This project is a technical-analysis and research tool. It does not guarantee profit, execute trades, or provide financial advice. Historical and optimized results are not evidence of future performance. Recovery/martingale sizing can increase drawdown very quickly; leave it off unless you fully understand the risk and always test on demo first.
