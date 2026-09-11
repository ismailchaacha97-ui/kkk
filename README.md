# Liquidity EMA 9 / SMA 20 MT4 tools

This repository contains an MT4 indicator and an optional execution EA based on the trading method in the supplied video.

## Files

- `LiquidityEMA9SMA20.mq4` — analysis indicator. It draws moving averages, signals, zones, Fibonacci levels, SL/TP projections, virtual exits and risk estimates. It does **not** place orders.
- `LiquidityEMA9SMA20_EA.mq4` — optional Expert Advisor. It can place and manage trades when `EnableTrading = true`. Trading is disabled by default.

## Indicator features

### Core signal

A buy signal requires:

1. EMA 9 above SMA 20.
2. A bullish candle touching/intersecting EMA 9.
3. The candle sweeps the low of the preceding candle(s), controlled by `SweepLookback`.
4. It closes back above the swept low.

Sell signals use the inverse conditions.

### Added video-method components

- Closed higher-timeframe liquidity setup followed by a lower-timeframe entry filter.
- Higher-timeframe setup zones projected onto the entry chart.
- Supply and demand / order-block approximation.
- Bullish and bearish fair-value-gap approximation.
- Optional rejection of signals near opposing zones.
- Stop levels below/above the signal candle with an ATR buffer.
- Fibonacci projection, including the default 1.25R extension.
- Fixed-pip or risk/reward target alternatives.
- Entry, SL, TP and Fibonacci drawings.
- Inside-bar and accumulation exit approximation.
- Moving-average-flip and opposite-liquidity exit signals.
- Virtual pyramiding/add-on entries for chart analysis.
- Percentage-risk lot estimate displayed beside projected trades.
- Popup, sound and push notifications.

### Important indicator inputs

- `UseMultiTimeframeSetup`: requires a closed `HigherTimeframe` liquidity setup before accepting a lower-timeframe signal.
- `RequireEntryInHTFZone`: requires the entry candle to overlap the higher-timeframe setup candle range.
- `UseZoneFilter`: rejects entries near detected opposing supply/demand or FVG zones.
- `TargetMode`: `0` Fibonacci extension, `1` fixed pips, `2` risk/reward.
- `FibExtension`: default `1.25`.
- `MaxPyramids`: maximum virtual entries in one directional sequence.
- `ShowRiskEstimate`: displays an estimated lot size using the account balance and stop distance. It does not place an order.

## EA safety and usage

1. Compile the indicator and EA in MetaEditor.
2. Test the indicator on historical data and a demo account.
3. Attach the EA with `EnableTrading = false` first.
4. Review its signals, broker minimum stop distance, spread filter and calculated lot size.
5. Only enable live execution after separate forward testing.

The EA includes:

- Risk-based or fixed lots
- Broker lot-step/minimum/max-lot normalization
- Maximum spread filter
- Magic-number isolation
- Market entries after a closed-candle signal
- SL/TP placement
- MTF confirmation and zone filtering
- Pyramiding limit
- MA-flip, inside-bar, accumulation and opposite-signal exits

## Interpretation limitations

The video does not define “liquidity candle,” accumulation, supply/demand, order blocks, fair-value gaps, Fibonacci anchoring, or ranging markets mathematically. This implementation uses explicit approximations so the method can be coded and tested:

- Liquidity candle: same-colour candle that sweeps a prior high/low and closes back through it.
- Demand/supply: an opposite-colour base candle followed by a displacement candle.
- FVG: a three-candle gap between the first and third candle.
- Accumulation: an inside bar or a configurable sequence of small-body candles.
- Stop: signal-candle extreme plus an ATR buffer.
- Target: Fibonacci extension, fixed pips, or risk/reward according to `TargetMode`.

These approximations can produce different results from the original creator's discretionary chart reading. Neither file guarantees profitability. Include spread, commission, slippage, news risk and drawdown in testing.
