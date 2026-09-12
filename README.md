# Holy Grail VWAP SSL Flip

`HolyGrail_VWAP_SSL_Flip.mq4` is a production-oriented MT4 indicator based on the supplied anchored High/Low VWAP SSL idea.

## What is improved

- Chronological, single-pass VWAP calculation with no look-ahead from future candles.
- Stable weighted online variance for the Typical VWAP bands.
- Tick volume or real volume with a safe tick-volume fallback.
- Daily, weekly, monthly, quarterly, yearly, broker-time session, and one-time custom-time anchors.
- Explicit choice to carry the hysteresis state across anchors or initialize each anchor independently.
- Closed-candle-only arrows and alerts by default, so live-bar signal movement is not mistaken for a confirmed signal.
- Wilder ATR is calculated once per pass for consistent arrow placement rather than calling `iATR()` for every bar.
- Preserves the active SSL line and bridges a flip candle to avoid visual gaps.
- Popup, sound, email, push, and a polished chart-object HUD with configurable corner, sizing, colors, and font; stale-on-attach alerts are suppressed by default.

## Install

1. Copy `HolyGrail_VWAP_SSL_Flip.mq4` into the terminal's `MQL4/Indicators` folder.
2. Open it in MetaEditor and compile it.
3. Attach **Holy Grail VWAP SSL** to a chart.
4. Session times are interpreted in the broker/server time shown by MT4. Adjust London, New York, and Asia inputs for the broker's timezone and daylight-saving changes.
5. The HUD is a chart panel rather than a chart-global comment. Use `HUDCorner`, `HUDX`, `HUDY`, colors, and `HUDFont` to match your template. If several copies run on one chart, give each a different `HUDInstanceTag`.

## Signal model

The state is hysteretic: a bearish state changes to bullish only when a candle closes above the anchored High VWAP, and a bullish state changes to bearish only when a candle closes below the anchored Low VWAP. Price between those levels leaves the state unchanged.

No indicator can guarantee a 1% return, a win rate, or profitability. Validate the settings with spread, commission, slippage, out-of-sample, and forward testing before using real money; the indicator is a signal/visualization tool, not financial advice.
