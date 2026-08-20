# Dynamic Swing Anchored VWAP for MT4

`DynamicSwingAnchoredVWAP.mq4` is an improved MT4 port of the Dynamic Swing Anchored VWAP concept.

## Main improvements

- Modern `OnCalculate()` implementation.
- Closed-candle mode to reduce intrabar repainting.
- Correct one-time state initialization.
- Anchor bar is not processed twice.
- Proper ATR-RMA seeding with an ATR warm-up average.
- Optional minimum swing size measured in ATRs.
- Tick-volume, real-volume fallback, and price-only modes.
- Configurable ATR/APT limits.
- Labels are anchored to the actual pivot candle with corrected colors.
- Labels are not deleted on every tick.
- Closed-bar mode skips unnecessary recalculation between candles.
- Optional trend-change and VWAP-cross alerts.
- Buy and sell arrows using higher-timeframe EMA trend agreement, a lower-timeframe VWAP pullback, and a closed-candle break of the previous swing structure.

Copy the `.mq4` file into the MT4 `MQL4/Indicators` directory, compile it in MetaEditor, and attach it to a chart.

The original TradingView work is licensed under CC BY-NC-SA 4.0:
https://creativecommons.org/licenses/by-nc-sa/4.0/
