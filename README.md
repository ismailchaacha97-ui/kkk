# Liquidity EMA 9 / SMA 20 MT4 indicator

`LiquidityEMA9SMA20.mq4` is an MT4 custom indicator based on the method in the supplied video.

## What it plots

- Black line: 9-period EMA
- Blue line: 20-period SMA
- Green up arrow: bullish liquidity-sweep setup
- Red down arrow: bearish liquidity-sweep setup

Signals are generated from **closed candles only**. The indicator does not place trades.

## Signal logic

### Buy

1. EMA 9 is above SMA 20.
2. The optional range and higher-timeframe filters pass.
3. The candle is bullish and touches/intersects EMA 9.
4. The candle sweeps the low of the preceding candle(s), based on `SweepLookback`.
5. The candle closes back above the swept low.

### Sell

The inverse conditions are required:

1. EMA 9 is below SMA 20.
2. The optional filters pass.
3. The candle is bearish and touches/intersects EMA 9.
4. It sweeps the high of the preceding candle(s).
5. It closes back below the swept high.

## Installation

1. Copy `LiquidityEMA9SMA20.mq4` to your MT4 data folder under `MQL4/Indicators`.
2. Open MetaEditor and compile the file.
3. Restart MT4 or refresh the Navigator panel.
4. Attach **Liquidity EMA9/SMA20** to a chart.

## Important inputs

- `SweepLookback = 1`: use the immediately preceding candle. Increase it to sweep the highest/lowest level in a larger lookback window.
- `UseRangeFilter = true`: rejects signals when the two moving averages are too close relative to ATR. This is an objective approximation of the video's advice to avoid ranging markets.
- `MinMASpreadATR = 0.10`: increase to filter more consolidation, or set to `0`/disable the filter to use only the raw EMA/SMA relationship.
- `UseHigherTF = false`: optionally require the last fully closed higher-timeframe EMA/SMA trend to agree with the signal.
- `UseADXFilter = false`: optional additional trend-strength filter; not part of the video's core two-average setup.
- `EnableAlerts = true`: alerts only once when a new candle closes with a signal. Sound and push notifications are optional.

## Interpretation and limitations

The video does not define “liquidity candle” mathematically. This implementation interprets it as a candle that takes the prior high/low and then closes back through that level. The video's supply/demand, consolidation, Fibonacci, stop-loss, and take-profit decisions are discretionary and are not automatically drawn by this indicator.

The arrows are signals for research and manual evaluation, not trading advice. Test on historical data and a demo account, include spread/slippage/commission, and define position sizing and exits before using real money.
