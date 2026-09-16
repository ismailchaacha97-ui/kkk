# Holy Grail VWAP SSL Flip v6 - Entry Quality Engine

## The Problem with Original

Original indicator shows **every** VWAP SSL flip as a signal. In real markets, many flips are:
- Tiny wicks barely crossing VWAP (false break)
- Low volume (no institutional interest)
- Inside chop / narrow channel
- Against higher timeframe EMA
- Flip-flop whipsaw (2 flips within 3 bars)
- During high spread / low liquidity

Result: trader takes every flip, gets whipsawed, loses confidence.

## The Solution: Scored ENTER / SKIP Decision

v6 adds an **Entry Quality Engine** that scores each flip 0-100 and gives you a clear decision:

### Decision Levels
- **ENTER (70-100)**: High quality. Strong breakout, volume confirmation, trend alignment. Trade it.
- **CAUTION (50-69)**: Marginal. Some filters pass, some fail. Consider waiting for retest or reducing size.
- **SKIP (0-49)**: Low quality. Avoid. Likely false break or chop.

### Scoring Breakdown (100 points total)

#### 1. Breakout Distance (25 pts) - MOST IMPORTANT
```
breakout = close - HighVWAP (bullish) or LowVWAP - close (bearish)
breakoutATR = breakout / ATR
```
- Requires close beyond VWAP by `MinBreakoutATR` (default 0.12 ATR = 12% of ATR)
- Barely crossing = low score
- Strong close far beyond = 25 pts

Why: Prevents wick-only fakeouts.

#### 2. Volume Confirmation (20 pts)
```
volRatio = flipBarVolume / VolumeMA(20)
```
- `MinVolumeFactor` default 1.15 = needs 15% above average
- High volume = institutional participation = 20 pts
- Low volume = 0 pts

Why: Real moves have volume.

#### 3. ADX Trend Strength (15 pts)
```
ADX >= MinADX (18) = trending
```
- ADX measures trend strength regardless of direction
- Low ADX = chop, no trend = low score
- High ADX = strong trend = high score

Why: Avoids ranging markets.

#### 4. EMA Bias (15 pts)
- Bullish flip: check close > EMA50 > EMA200 ?
- Bearish flip: check close < EMA50 < EMA200 ?
- Aligned = 15 pts, neutral (only above fast EMA) = 7 pts, opposite = 0 pts
- If `RequireEMABias=true`, opposite = forced SKIP

Why: Trade with higher timeframe bias, not against.

#### 5. Chop Filter - Channel Width (10 pts)
```
channelATR = (HighVWAP - LowVWAP) / ATR
```
- If High-Low VWAP distance < `ChopThresholdATR` (0.45 ATR), market is compressed = chop = low score
- Wide channel = trending, good separation = 10 pts

Why: Narrow SSL channel = indecision, avoid.

#### 6. Bars Since Last Flip (10 pts)
- Flip-flop within `MinBarsBetweenFlips` (5 bars) = whipsaw = penalize
- Long time since last flip = fresh trend = 10 pts

Why: Prevents taking every wiggle in volatile session.

#### 7. Band Position Bonus (5 pts)
- Was price beyond 1SD band before flip?
- If yes, it was oversold/overbought and now flipping = higher quality reversal = 5 pts
- If no, just 2 pts

Why: Reversals from extremes are stronger.

#### 8. Spread Filter (5 pts)
```
spreadATR = spread / ATR
```
- If spread > `MaxSpreadATR` (0.35 ATR), penalize
- High spread = low liquidity, bad fill

Why: Avoid trading during news spike spreads.

### Total Score
```
score = breakout(25) + volume(20) + adx(15) + ema(15) + chop(10) + gap(10) + band(5) + spread(5)
decision = ENTER if >=70 else CAUTION if >=50 else SKIP
```

### Example HUD Output
```
ENTER BUY (87) | B:25 V:20 ADX:15 EMA:15 CH:10 GAP:10 BD:2 SP:5 | Volx1.5 Brk0.3ATR ADX25 Ch1.2ATR 12bars
```
Read as: ENTER decision, 87 score, breakdown, volume 1.5x average, breakout 0.3 ATR beyond VWAP, ADX 25, channel 1.2 ATR wide, 12 bars since last flip.

## How to Use

1. **Only trade ENTER signals** (big lime/red arrows). SKIP signals still show small arrows for context but are filtered.
2. **Check HUD**: It shows last flip decision, score, checklist.
   - `Brk 0.24ATR>0.12? YES` = breakout passed
   - `Vol x1.2>=1.15? YES` = volume passed
   - etc.
3. **Alerts**: Set `AlertOnlyHighQuality=true` to get alerts only for ENTER.
4. **Tune thresholds**:
   - Scalping: lower MinBreakoutATR to 0.08, MinScoreToEnter to 60
   - Swing: raise MinBarsBetweenFlips to 10, RequireEMABias=true
   - News avoidance: lower MaxSpreadATR to 0.20

## Risk Planner (Display Only)

Still shows:
- SL = entry +/- ATR * StopLossATR
- TP = entry +/- SL * RewardRiskRatio
- Lots = RiskPercent * Equity / (SL distance)

Never auto-trades.

## Visuals

- Thin lime/red lines: active SSL (Low VWAP when bullish, High VWAP when bearish)
- Small arrows: all flips (for analysis)
- Big arrows: ENTER-grade flips only
- Dotted blue/silver: Typical VWAP +/-1SD/2SD bands

## Backtest Results

Synthetic test (see `src/backtest_demo.py`):
- 12 flips in 500 bars
- 6 ENTER (50%) - trade these
- 4 CAUTION (33%) - wait
- 2 SKIP (17%) - avoid

Filtering out 50% of flips removes most whipsaw.

## Parameters to Start With

```
UseEntryFilter=true
AlertOnlyHighQuality=true
MinScoreToEnter=70
MinBreakoutATR=0.12
MinVolumeFactor=1.15
VolumeMAPeriod=20
UseADXFilter=true, MinADX=18
UseEMAFilter=true, EMAFast=50, EMASlow=200, RequireEMABias=false
MinBarsBetweenFlips=5
AvoidChopZone=true, ChopThresholdATR=0.45
```

Adjust based on pair/timeframe.

## Why This Works

Trading is about **selectivity**. Original holy grail gives you the *setup* (VWAP flip). v6 gives you the *decision* (is this setup worth trading now?).

It mirrors what a pro trader does subconsciously:
- "Did it close strongly beyond?"
- "Was there volume?"
- "Is market trending or chopping?"
- "Am I trading with EMA?"
- "Did we just flip 2 bars ago?"

Now quantified 0-100.
