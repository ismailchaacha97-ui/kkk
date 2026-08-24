# Price Action Sentinel

A full-chart **MetaTrader 4** price-action indicator. It reads the market the way a discretionary PA trader does: floors and ceilings, swing structure, auto trendlines, breaks and retests, candlestick triggers, then a confluence score for long vs short.

Drop one file on a chart. It scans hundreds of bars (default 800) and keeps a live dashboard of bias, nearest support/resistance, last candle pattern, and the current trade plan.

```
MQL4/Indicators/PriceActionSentinel.mq4
```

---

## What it analyses

| Layer | What you see | How it thinks |
| --- | --- | --- |
| **Support / Resistance** | Teal *floor* and crimson *ceiling* zones | Clusters swing highs/lows, previous day/week/month H-L, and round numbers. Strength = touches + recency + proximity. |
| **Trend / structure** | `HH` `HL` `LH` `LL` plus `EQH` `EQL` | Bullish = higher highs **and** higher lows. Bearish = lower highs **and** lower lows. Sideways = mixed → wait. Equals mark liquidity pools. |
| **BOS / CHoCH** | Label on the broken swing | Break of Structure = continuation. Change of Character = first break against the trend. |
| **Trendlines** | Blue rays on swing pairs | Scores candidate lines by touches, violations, slope and recency. Broken lines go dotted grey. |
| **TL breaks + retests** | Gold `BREAK`, yellow `RETEST` | A close through the line is the break. A return that rejects is the retest (classic second-chance entry). |
| **Candlesticks** | Pattern name on the bar | Pin/hammer, engulfing, inside/outside, harami, piercing/dark cloud, morning/evening star, soldiers/crows, tweezers, marubozu, doji, **fakey**. |
| **Setups** | Lime ▲ long / tomato ▼ short + R:R box | Scores confluence (trend + S/R + TL + candle + structure + EMA). Only fires at your minimum score. Stop beyond the signal candle; target next opposing level or N·R. |
| **EMA confluence** | Gold 50, cyan 13, purple 21 | Optional **50 EMA** filter/bounce and optional **13/21 ribbon**. Full stack `13>21>50` (or the inverse) adds extra score. |
| **Dashboard** | Live panel | Bias, regime, structure text, last event, EMA stack, ceiling / price / floor, last candle, last setup, and a one-line plan. |

**Plan the indicator writes**

- **Uptrend:** buy dips into the floor (long).
- **Downtrend:** sell rallies into the ceiling (short).
- **Range:** stand aside until a clear break and retest.

---

## Install (MT4)

1. Open MetaTrader 4.
2. **File → Open Data Folder**.
3. Copy `MQL4/Indicators/PriceActionSentinel.mq4` into `MQL4/Indicators/`.
4. In MetaEditor (`F4`) open the file and press **Compile** (`F7`). You want `0 error(s)`.
5. In the Navigator, right-click **Indicators → Refresh**.
6. Drag **Price Action Sentinel** onto any chart.

Use it on H1 / H4 / D1 first. M1–M15 work, but you will want a smaller lookback and a higher swing strength so the chart does not drown in labels.

---

## How to read a chart

1. **Read the dashboard bias** before anything else. Do not fade a clean HH+HL tape.
2. **Mark the floor and ceiling** that actually matter — the nearest teal and crimson zones, plus yesterday’s high/low.
3. **Wait for a trigger at the level**, not in the middle of the range:
   - pin bar / engulfing / fakey into support in an uptrend → long
   - pin bar / engulfing / fakey into resistance in a downtrend → short
   - broken trendline that comes back and fails (`RETEST`) is the highest-quality continuation
4. **Place risk where the idea is wrong.** The red box is the stop (beyond the signal wick / zone). The green box is the projected target at your R-multiple, clipped to the next opposing S/R.
5. **Ignore isolated candles** in chop. If the dashboard says `CONSOLIDATION`, let the next BOS print first.

---

## Inputs

### Structure
| Input | Default | Meaning |
| --- | --- | --- |
| Bars to scan | `800` | Whole-chart depth. Raise on D1, cut on M5 if MT4 stutters. |
| Swing pivot strength | `5` | Bars on each side of a pivot. `3` = more swings, `8` = only major ones. |
| Equal H/L tolerance | `3` pips | Inside this, two swings print `EQH` / `EQL` (liquidity). |

### Support / resistance
| Input | Default | Meaning |
| --- | --- | --- |
| Max S/R zones | `10` | Strongest zones only. |
| Cluster width | `0.35 × ATR` | How close two swings must be to count as one level. |
| Previous D/W/M H-L | on | Institutional reference points. |
| Psychological rounds | on | Big figures (1.0800, 2650, …). |

### Trendlines
| Input | Default | Meaning |
| --- | --- | --- |
| Minimum touches | `2` | A line needs at least this many tests. |
| Touch / break buffer | `0.28 × ATR` | Wiggle room so wicks do not fake a break. |

### Candles / setups
| Input | Default | Meaning |
| --- | --- | --- |
| Pattern bars | `60` | How far back names are printed. |
| Min confluence score | `5` | Raise to `7` if you only want A+ signals. |
| Reward : risk | `2.0` | Height of the green target box. |

### EMA confluence
| Input | Default | Meaning |
| --- | --- | --- |
| Use 50 EMA as confluence | on | Longs want close above the 50; shorts below. A wick into the 50 that closes back is an `EMA50-bounce` / `EMA50-reject`. |
| Draw 50 EMA | on | Gold line. Period is editable (default 50). |
| Use 13/21 EMA ribbon | on | Fast above slow = bull ribbon. Pullbacks into the band score `ribbon-hold`. A fresh cross adds `13/21-cross`. |
| Draw 13/21 EMA ribbon | on | Cyan 13 (solid) and purple 21 (dashed). Periods are editable. |
| EMA bounce width | `0.35 × ATR` | How close a wick must come to count as a tag. |

Turn **Use 13/21** off if you only want the 50 as a trend filter. Turn **Use 50** off if you only want the ribbon. Both on is the full stack: `13>21>50 BULL` or `13<21<50 BEAR`.

Alerts: popup, sound, and optional push on a **freshly closed** setup bar or a trendline break.

---

## Buffers (for an EA)

`iCustom` name: `"PriceActionSentinel"` (or the path under `Indicators` if you nest it).

| Buffer | Contents |
| --- | --- |
| 0 | Long setup price (arrow), else `EMPTY_VALUE` |
| 1 | Short setup price |
| 2 | Nearest support |
| 3 | Nearest resistance |
| 4 | Trend bias: `1` bull, `-1` bear, `0` range |
| 5 | Pattern code (signed by direction) |
| 6 | 50 EMA |
| 7 | 13 EMA (fast) |
| 8 | 21 EMA (slow) |

Pattern codes (absolute): `1` doji, `10/11` pin, `20/21` engulf, `22/23` harami, `24/25` pierce/cloud, `30` inside, `31` outside, `40/41` star, `42/43` soldiers/crows, `50/51` tweezer, `60/61` marubozu, `70/71` fakey.

Example — take a long only with the trend, on the bar that just closed:

```mq4
double longSig = iCustom(NULL, 0, "PriceActionSentinel", 0, 1);
double bias    = iCustom(NULL, 0, "PriceActionSentinel", 4, 1);
if(longSig != EMPTY_VALUE && bias > 0)
   // place a buy with SL at Low[1]
```

When you pass explicit inputs to `iCustom`, they must follow the input order in the `.mq4` file (skip the section-header strings or pass them as empty).

---

## Recommended starting profiles

**Swing / position (H4–D1)**  
Lookback `1200`, swing `6`, max S/R `8`, min score `6`.

**Intraday (M15–H1)**  
Lookback `600`, swing `5`, min score `5`, pattern bars `40`.

**Scalp (M1–M5)**  
Lookback `300`, swing `7`, show zones on, hide pattern names if the chart is noisy, min score `7`.

---

## Notes

- Swings confirm only after `SwingStrength` bars print to the right. The live candle is never a pivot.
- Objects are prefixed `PAS_` and are wiped on timeframe / symbol change.
- This is a map, not an autotrader. A high score is confluence, not a guarantee.
- Past S/R and trendlines can break. That is information — trade the retest, do not marry the line.

---

## License

Use and modify freely for personal trading. No warranty. Markets can and will do the opposite of a pretty chart.
