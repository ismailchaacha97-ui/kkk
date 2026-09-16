# Big Move Guide - Weekly/Monthly VWAP on Small TF for 1:3 1:5+

You said: "im using sometimes monthly and weekly vwap on smaller timeframes to catch big moves for 1.3 1.5 and more"

This is exactly what v7 Big Move Edition is built for.

## Why Weekly/Monthly VWAP on M15/H1 Works for Big Moves

- **Monthly VWAP** on M15: VWAP accumulates entire month's volume. Flip early in month = institutional shift that can run for weeks.
- **Weekly VWAP** on M15/H1: Flip on Tuesday = potential to run to Friday = 3-5R easy.
- **Bands as targets**: Typical VWAP +2SD / +3SD are natural exhaustion levels. If you enter near Typical VWAP, distance to +2SD is your 1:3, to +3SD is 1:5+.

## v7 Big Move Mode - What It Adds

### 1. Anchor Progress Tracking
```
Monday 00:00 = 0% progress
Friday 00:00 = 80% progress
```
- Early week/month bonus: entering at 10% progress = 5 pts, late at 85% = 0 pts
- `AvoidLateAnchor=true` + `MaxAnchorProgress=0.80` = skip if >80% through week/month (no time left for big move)
- HUD shows `Prog 22%` and `Anchor progress 22%`

### 2. RR to Bands Calculation
For each flip:
```
SL = ATR * 1.5 (or opposite VWAP, or band1)
Target 2SD = Typical VWAP + 2*StdDev
RR_2SD = distance(entry, 2SD) / SL
RR_3SD = distance(entry, 3SD) / SL
```
- If RR_2SD = 3.5, that means 2SD band is 3.5R away = potential 1:3.5 move
- HUD: `RR 2.4->2SD 3.9->3SD`
- Big Move Score: 15 pts if RR >= 4.5, 10 pts if RR >=3.0, etc.

### 3. Exhaustion Filter
- If price already beyond 2.5SD from Typical VWAP, move is exhausted = skip
- Prevents buying top / selling bottom
- `CheckBandExhaustion=true`, `ExhaustionSD=2.5`

### 4. Min Distance to Band
- Need at least 2 ATR to opposite band, else no room
- `MinDistanceToBandATR=2.0`

### 5. Multi-TP Risk Planner
Old: SL + one TP (2R)
New: SL + TP1 1.5R, TP2 3R, TP3 5R, TP4 8R

- Draws horizontal lines on chart (if `ShowBigMoveLines=true`)
- HUD:
```
Risk 0.50% $50 Lots 0.12 | SL 1.08400
TP1 1.5R 1.08600 | TP2 3R 1.08800 | TP3 5R 1.09100 | TP4 8R 1.09500
```
- Scale out: close 30% at 1.5R, 30% at 3R, 20% at 5R, 20% runner to 8R+ = perfect for big moves

### 6. SL Modes for Big Moves

- `SL_ATR` (default 1.5 ATR): tight, good for 1:3+
- `SL_OPPOSITE_VWAP`: SL beyond opposite VWAP (High VWAP for shorts, Low for longs) = wider, more room for big moves, avoids wick stops
- `SL_BAND1`: SL beyond 1SD band = even wider, for catching huge monthly moves
- For 1:5+, use `SL_OPPOSITE_VWAP` or `SL_BAND1` with `StopLossATR=2.0`

## Recommended Settings for Big Moves

### Weekly VWAP on M15/H1 for 1:3-1:5

```
AnchorPeriod = Weekly
Timeframe = M15 or H1
CarryTrendAcrossAnchors = true (keeps trend over weekend)
MinScoreToEnter = 68 (slightly lower than 70 to get more big move candidates)
MinBarsBetweenFlips = 5 (M15) or 3 (H1)
SLMode = OPPOSITE_VWAP
StopLossATR = 1.5
RewardRiskRatio = 3.0
TP1_RR = 1.5, TP2_RR = 3.0, TP3_RR = 5.0, TP4_RR = 8.0
UseBigMoveMode = true
BigMoveMinRR = 3.0
AvoidLateAnchor = true
MaxAnchorProgress = 0.80
PreferEarlyAnchor = true
EarlyAnchorBonusThreshold = 0.35 (bonus if entered before 35% of week = Tue)
CheckBandExhaustion = true, ExhaustionSD = 2.5
MinDistanceToBandATR = 2.0
```

**Logic**: Enter early week (Mon-Wed) when flip has volume and 3R+ to 2SD band. Hold to TP2 3R, scale, runner to 5R/8R.

### Monthly VWAP on M15/H1/H4 for 1:5-1:10+

```
AnchorPeriod = Monthly
Timeframe = H1 or H4 (M15 also works but many bars)
MinBarsBetweenFlips = 15 (monthly needs fewer flips)
SLMode = BAND1
StopLossATR = 2.0
RewardRiskRatio = 5.0
TP1_RR = 2.0, TP2_RR = 5.0, TP3_RR = 8.0, TP4_RR = 12.0
BigMoveMinRR = 5.0
MaxAnchorProgress = 0.75 (avoid entering after 75% of month)
EarlyAnchorBonusThreshold = 0.30 (bonus first 30% of month = first 9 days)
MinDistanceToBandATR = 3.0 (need more room for monthly)
```

**Logic**: Monthly flip in first 10 days = institutional monthly shift. Can run entire month = 1:10+.

## How to Trade 1:3 1:5+

1. **Setup**: Put v7 on M15, Anchor=Weekly, Big Move ON
2. **Wait for ENTER**: Big lime arrow + HUD `ENTER BUY (77) RR2.4->2SD`
   - Check checklist: `RR 2.4>=3.0? NO` but score still 77 because other filters strong. For strict 1:3, set `UseBigMoveRRFilter=true` + `BigMoveMinRR=3.0` will force SKIP if RR<1.5 (see v7 logic)
   - For 1:5, set `BigMoveMinRR=5.0`
3. **Enter**: At close of flip bar (if `SignalsOnClosedBarsOnly=true`)
4. **SL**: As per SLMode (opposite VWAP is good)
5. **TP Management**:
   - TP1 1.5R: close 30%, move SL to breakeven
   - TP2 3R: close 30%, trail SL to 1.5R
   - TP3 5R: close 20%, trail to 3R
   - TP4 8R: runner, trail with Low VWAP (if bullish) or High VWAP (if bearish)
6. **Exit early if**: opposite flip with ENTER quality appears, or anchor progress >80% and you are at 1:2

## Backtest Example (from `src/backtest_big_move.py`)

```
WEEKLY VWAP on M15:
Flips: 2
01-02 02:15 BUY ENTER 77 RR2.4 Prog22% - early week, 2.4R to 2SD, good volume
```

This is Tuesday 02:15 = 22% through week = early = bonus. RR 2.4 to 2SD, 3.9 to 3SD = potential 1:3.9 big move.

## Why Not Trade Late Week/Month?

- If you enter Friday 80% through week, you have only 20% time left = max 0.5R maybe, not 3R
- Big Move Mode penalizes late entries to 0 pts for anchor progress
- `AvoidLateAnchor` forces SKIP if progress >80% and RR < min

## Combining Weekly + Monthly

Pro setup:
- Chart 1: M15, Monthly VWAP v7, Big Move ON, for direction bias (monthly trend)
- Chart 2: M15, Weekly VWAP v7, Big Move ON, for entries in direction of monthly trend
- Only take weekly ENTER that aligns with monthly trend (both bullish)

This gives you monthly big picture + weekly timing = highest RR.

## Summary

v7 answers: "Is this weekly/monthly flip worth holding for 1:3 1:5+?"

- YES if: early in anchor, high RR to bands, not exhausted, volume, ADX
- NO if: late, low RR, exhausted beyond 2.5SD, chop

Trade ENTER, hold to TP2/TP3 for big moves.
