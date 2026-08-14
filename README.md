# Anchored VWAP (M15) — pullback setup for MT4

Session-anchored VWAP **computed on 15-minute data** and **displayed on the 5-minute chart**,
with automatic Long/Short pullback signals.

## Files

| File | What it is |
|---|---|
| `MQL4/Indicators/VWAP_Anchored_M15_Setup.mq4` | Indicator: draws the M15-anchored VWAP on the M5 chart + entry arrows + alerts |
| `MQL4/Experts/VWAP_Anchored_M15_EA.mq4` | Optional EA that trades exactly the same rules (market orders) |

## Install

1. In MT4: **File → Open Data Folder**.
2. Copy `VWAP_Anchored_M15_Setup.mq4` into `MQL4/Indicators/`,
   `VWAP_Anchored_M15_EA.mq4` into `MQL4/Experts/`.
3. Restart MT4 (or right-click Navigator → Refresh), then compile each file in MetaEditor (F7).
4. Open an **M5 chart** of NQ / NAS100 and drag the indicator on. Enable *Allow live trading* if you use the EA.

## VWAP

- Anchored at the market open (`AnchorHour` / `AnchorMinute`, **broker server time** — for the
  US cash open at 09:30 New York, set the hour to whatever 09:30 NY is on your server clock).
- Re-anchors every session (`AnchorEveryDay = true`), i.e. cumulative sums reset at the open.
- `VWAP = Σ(typical price × volume) / Σ(volume)` over M15 bars since the anchor
  (`VwapPrice` selects the price; tick volume is used, as usual in MT4).
- The M15 value is mapped onto every M5 bar, so the line is a proper step-wise M15 VWAP on the M5 chart.

## Long setup

1. Price is **above** VWAP.
2. VWAP is **rising** over the last 15 minutes (`VwapSlopeBars = 1` M15 bar).
3. Price has increased **≥ +0.1%** over the last hour (`MomentumBars = 4` M15 bars, `MomentumPercent = 0.10`).
4. **Trigger:** the **first red (down) candle** of the pullback (previous candle was not red) that
   moves back toward VWAP → **buy at the OPEN of the next bar** (green arrow is plotted on that entry bar).

## Short setup

1. Price is **below** VWAP.
2. VWAP is **falling** over the last 15 minutes.
3. Price has decreased **≤ −0.1%** over the last hour.
4. **Trigger:** the **first green (up) candle** of the pullback that moves back toward VWAP →
   **sell at the OPEN of the next bar** (red arrow).

"First" candle = the trigger candle is red/green while the candle before it was not, so only the
first pullback candle of a sequence fires. `RequireCloserToVwap = true` additionally demands that
the candle actually closed nearer to VWAP than the previous one, and price must still be on the
correct side of VWAP at the entry open.

## No trading in the first hour

`NoTradeMinutes = 60`: no signal/order is produced during the first 60 minutes after the anchor,
so the VWAP has time to establish. `SessionMinutes` (0 = off) optionally closes the signal window
later in the day (e.g. 390 for a full US cash session).

## Key inputs

| Input | Default | Meaning |
|---|---|---|
| `AnchorHour` / `AnchorMinute` | 9 / 30 | Market open in server time |
| `CalcTimeframe` | M15 | Timeframe for VWAP, slope and momentum |
| `TriggerTF` | current (M5) | Timeframe of the pullback trigger candle |
| `VwapSlopeBars` | 1 | VWAP slope lookback (15 min) |
| `MomentumBars` | 4 | Momentum lookback (1 hour) |
| `MomentumPercent` | 0.10 | Required % move (±0.1%) |
| `NoTradeMinutes` | 60 | Dead zone after the open |
| `AlertPopup` / `AlertPush` | false | Popup / mobile alert on a fresh signal |

EA extras: `Lots`, `UseRiskPercent` + `RiskPercent`, `StopLossPoints` (0 = trigger-candle extreme
± `SlBufferPoints`), `TakeProfitPoints` or `RiskRewardTP` (default 2R), `MaxTradesPerDay`,
`OneTradeAtATime`, `MagicNumber`.

## Notes

- Signals are evaluated on **closed** bars only; the arrow appears on the entry bar as soon as it opens.
- MT4 uses tick volume, not real exchange volume — normal for CFD/futures feeds.
- Backtest the EA in *Every tick* mode on M5; the M15 series must be available in your history.
