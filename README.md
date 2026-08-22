# XARD-style Confirmation Indicator for MT4

`Indicators/Xard_Confirmation.mq4` is a conservative **confirmation** indicator inspired by the public XARD method. It is an independent MQL4 implementation, not an official XARD release and not a promise of profitable trades.

It deliberately avoids importing XARD's visual Semafor/ZigZag signals. Instead, it turns the method's core idea into a transparent, closed-bar rule:

1. **Trend alignment:** default 13 EMA is above/below 55 EMA.
2. **Location filter:** price is above/below the broker's Daily Open.
3. **Higher-timeframe filter:** the previous completed H1 candle agrees with the direction by default.
4. **Structure:** a *confirmed* higher low creates a buy candidate; a *confirmed* lower high creates a sell candidate.
5. **Confirmation:** the current candle must close in the trend direction on the correct side of the fast EMA.

The structural condition is the indicator's non-repainting approximation of the XARD **“2nd Dot”** idea:

```text
Buy:  prior swing low → later higher swing low → bullish confirmation
Sell: prior swing high → later lower swing high → bearish confirmation
```

## What makes it conservative?

The indicator does **not** print a pivot arrow as soon as price touches a high or low. A pivot is recognised only after `PivotStrength` closed candles have formed to its right. Consequently, its arrows come later than a live ZigZag or Semafor dot, but the structure used for the signal does not rely on future candles after the signal bar.

A green arrow requires all of the following:

- a newly confirmed **higher low**;
- Fast EMA > Slow EMA and closing price > Fast EMA;
- bullish closed candle;
- price above the Daily Open if that filter is enabled;
- bullish completed H1 state if the higher-timeframe filter is enabled;
- price no farther than the configured ATR distance above the fast EMA.

A red arrow is the exact inverse.

## Install in MetaTrader 4

1. In MT4 select **File → Open Data Folder**.
2. Copy `Xard_Confirmation.mq4` into `MQL4/Indicators/`.
3. Restart MT4, or right-click **Indicators** in the Navigator and select **Refresh**.
4. Open the indicator in MetaEditor and press **Compile**. MT4 will create `Xard_Confirmation.ex4` if compilation succeeds.
5. Drag **Xard_Confirmation** from Navigator → Indicators onto a chart.
6. Start with **H1 direction / M15 execution**, or use it on M15 with `BiasTimeframe = PERIOD_H1` as supplied.

The indicator displays the broker Daily Open as a dotted gold line. This can be hidden with `ShowDailyOpen = false`.

> For FX, the XARD thread typically uses a New York-close broker. A broker that starts its daily candle at another time will produce a different Daily Open and may not match thread screenshots.

## Inputs

| Input | Default | Purpose |
|---|---:|---|
| `FastEMAPeriod` / `SlowEMAPeriod` | 13 / 55 | Main trend confirmation. |
| `UseDailyOpenFilter` | `true` | Longs must close above Daily Open; shorts below. |
| `UseHigherTimeframeFilter` | `true` | Requires the previously completed `BiasTimeframe` candle to agree. |
| `BiasTimeframe` | H1 | Directional roadmap timeframe. |
| `PivotStrength` | 2 | Bars required on each side to confirm a swing. Increase for fewer, stronger signals. |
| `PriorPivotSearchBars` | 80 | How far back to find the earlier swing high/low. |
| `MinimumStructureGapATR` | 0.10 | Minimum ATR difference required for a higher low / lower high. |
| `MaximumEntryDistanceATR` | 1.00 | Rejects a confirmation candle that is too extended away from the fast EMA. |
| `MaximumBarsToProcess` | 1500 | Performance guard for lower-spec MT4 installations. |

## Indicator buffers

The visible arrows are deliberately simple. The other buffers are available in MT4's **Data Window** and for an EA to read; they are not trade instructions.

| Buffer | Meaning |
|---:|---|
| 0 | Buy confirmation arrow price |
| 1 | Sell confirmation arrow price |
| 2 | Long structural stop guide: confirmed higher-low price |
| 3 | Short structural stop guide: confirmed lower-high price |
| 4 | Trend state: `1` buy, `-1` sell, `0` no signal |
| 5 | Broker Daily Open |

The stop guide identifies the structure that made the trade idea valid. It is **not automatically a safe stop-loss**: account risk, spread, volatility, symbol contract size, and a protective buffer remain the trader's responsibility.

## Important limitations

- This is a **confirmation indicator**, not an automated strategy and not financial advice.
- It cannot know the future. A confirmed pivot is deliberately delayed by `PivotStrength` bars.
- Different XARD/XU releases use different colours, EMAs, semafor levels, and filters. Do not combine indicator screenshots and rules from several versions without testing one complete rule set.
- Test in MT4 Strategy Tester visual mode and then on demo/forward data. Do not evaluate it only from historical arrows or static charts.
- Check high-impact news, spreads, session liquidity, and total exposure. Never add to a losing position simply because another visual dot appears.

## Suggested learning workflow

1. Run the default settings on M15 with H1 bias.
2. Mark every arrow manually as **valid**, **late**, or **invalid in context**.
3. Record entry price, structural stop, target, Daily Open location, session, and news context for at least 50–100 signals.
4. Change only one input at a time. For example, test `PivotStrength = 3` before changing EMA values.
5. Only after the results are understood should you consider alerts, an EA, or funded trading.

## Related XARD reading

- [Original XARD trading-system thread](https://forex-station.com/xard-simple-trend-following-trading-system-t8416709.html)
- [Xard's 2nd DOT explanation](https://forex-station.com/post1295421123.html#p1295421123)
- [Xard's later intraday-rule example](https://forex-station.com/post1295538535.html#p1295538535)
