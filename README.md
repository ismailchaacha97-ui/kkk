# Holy Grail VWAP SSL Flip v7 - Big Move Edition

> **Weekly/Monthly VWAP on small TF to catch big moves 1:3, 1:5, 1:10+** - tells you exactly ENTER vs SKIP

v6 gave you scored ENTER/SKIP. **v7 adds Big Move Mode** specifically for your use case: weekly/monthly VWAP on M15/H1 to hold for 1:3, 1:5+.

---

## v7 New - Big Move Mode

When you trade **Weekly/Monthly VWAP on M15/H1**, you need to know:
- Is there still time left in week/month for a big move?
- Is there enough room to 2SD/3SD bands for 1:3, 1:5?
- Is price already exhausted beyond 2.5SD?
- Where to scale out for 1:3, 1:5, 1:8?

v7 answers:

### Anchor Progress
- Tracks how far through week/month: Monday 0%, Friday 80%
- Early bonus: entering before 35% of week = +5 pts
- Late penalty: entering after 80% = 0 pts + forced SKIP if RR low
- HUD: `Prog 22%` and `Anchor progress 22%`

### RR to Bands
```
RR_2SD = distance(entry, Typical+2SD) / SL
RR_3SD = distance(entry, Typical+3SD) / SL
```
- HUD: `RR 2.4->2SD 3.9->3SD` = 2.4R to 2SD, 3.9R to 3SD = big move potential
- Score 15 pts if RR>=4.5, 10 pts if RR>=3.0

### Exhaustion Filter
- If price already beyond 2.5SD, skip (move done)
- `CheckBandExhaustion=true`

### Multi-TP
- Old: one TP
- New: **TP1 1.5R, TP2 3R, TP3 5R, TP4 8R** with lines drawn on chart
- Scale: 30% at 1.5R, 30% at 3R, 20% at 5R, 20% runner to 8R+

### SL Modes for Big Moves
- `SL_ATR` (1.5 ATR) - tight
- `SL_OPPOSITE_VWAP` - SL beyond opposite VWAP = wider, more room for 1:5+
- `SL_BAND1` - SL beyond 1SD band = even wider for monthly

---

## Files

```
indicators/HolyGrail_VWAP_SSL_Flip_v7.mq4   # USE THIS for big moves - Weekly/Monthly on small TF
indicators/HolyGrail_VWAP_SSL_Flip_v6.mq4   # v6 without big move (lighter)
src/vwap_ssl_engine_v7.py                  # Python v7 mirror
src/vwap_ssl_engine.py                     # v6 mirror
src/backtest_big_move.py                   # Demo weekly/monthly on M15 for 1:3+
src/backtest_demo.py                       # v6 demo
tests/test_big_move.py                     # Tests anchor progress, early vs late, monthly on M15
tests/test_anchor.py, test_vwap.py, etc.  # v6 tests
docs/BIG_MOVE_GUIDE.md                     # Deep guide for 1:3 1:5+
docs/ENTRY_LOGIC.md                        # v6 scoring
docs/USER_GUIDE.md
```

---

## Quick Start for Big Moves

### Weekly VWAP on M15/H1 for 1:3-1:5

```
AnchorPeriod = Weekly
Timeframe = M15 or H1
UseBigMoveMode = true
BigMoveMinRR = 3.0
AvoidLateAnchor = true, MaxAnchorProgress = 0.80
EarlyAnchorBonusThreshold = 0.35 (bonus Mon-Tue)
SLMode = OPPOSITE_VWAP, StopLossATR = 1.5
RewardRiskRatio = 3.0
TP1 1.5R, TP2 3R, TP3 5R, TP4 8R
MinScoreToEnter = 68
```

**Trade**: ENTER early week (Prog <35%) with RR>=3.0 to 2SD band. Hold to TP2 3R, trail to TP3 5R.

### Monthly VWAP on H1/H4 for 1:5-1:10+

```
AnchorPeriod = Monthly
Timeframe = H1 or H4
MinBarsBetweenFlips = 15
SLMode = BAND1, StopLossATR = 2.0
RewardRiskRatio = 5.0
TP1 2R, TP2 5R, TP3 8R, TP4 12R
BigMoveMinRR = 5.0
MaxAnchorProgress = 0.75
EarlyAnchorBonusThreshold = 0.30 (first 9 days)
MinDistanceToBandATR = 3.0
```

**Trade**: Monthly flip in first 10 days = institutional shift that can run entire month.

See `docs/BIG_MOVE_GUIDE.md` for full.

---

## How v7 Decides

Example HUD:

```
ENTER BUY (77) RR2.4->2SD 3.9->3SD | B:20 V:8 ADX:10 EMA:5 BM:7 AP:5 | Volx1.8 Brk0.3ATR ADX22 Prog22% 12bars
```

- `RR2.4->2SD 3.9->3SD` = 2.4R to 2SD, 3.9R to 3SD = big move potential
- `Prog22%` = 22% through week = early = bonus
- `BM:7` = big move score 7/15
- `AP:5` = anchor progress score 5/5
- Total 77 >=68 = **ENTER**

If same flip on Friday Prog88% with RR0.8 = SKIP.

---

## Testing

```bash
python3 tests/test_anchor.py
python3 tests/test_vwap.py
python3 tests/test_ssl.py
python3 tests/test_filters.py
python3 tests/test_integration.py
python3 tests/test_big_move.py
python3 src/backtest_demo.py
python3 src/backtest_big_move.py
```

All 6 suites pass.

Backtest Big Move Demo:

```
WEEKLY VWAP on M15:
Flips: 2
01-02 02:15 BUY ENTER 77 RR2.4 Prog22% - early week, 2.4R to 2SD
ENTER: 1/2 - has >=3R potential, early, not exhausted
```

---

## Why This Works for 1:3 1:5+

- **Monthly VWAP** on M15: VWAP accumulates entire month. Flip early = shift that can run weeks.
- **Weekly VWAP** on M15: Flip Tue = run to Fri = 3-5R.
- **Bands as targets**: +2SD = 3R target, +3SD = 5R+ target.
- **v7 filters**: early, high RR, not exhausted, volume = only best big move setups.

Trade ENTER, scale at 1.5R/3R/5R/8R.

---

## Risk

Risk planner display only. Never auto-trades. Shows SL/TP1-4 and lots from risk %.

---

## License

Use freely, test on demo first.
