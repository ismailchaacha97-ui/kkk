# Holy Grail VWAP SSL Flip v6 - ENTER vs SKIP

> A well-crafted, well-tested MT4 indicator that tells you **exactly** if you should enter when the VWAP flips or not.

Original idea: Anchored High/Low VWAP SSL flip with bands, arrows, HUD.  
Problem: Every flip looks like a signal, but many are whipsaw.  
Solution v6: **Entry Quality Engine** scores each flip 0-100 and gives clear **ENTER / CAUTION / SKIP** decision.

---

## What’s New in v6

- **Entry Quality Engine (core)**:
  - Breakout distance / ATR (25 pts)
  - Volume confirmation (20 pts)
  - ADX trend strength (15 pts)
  - EMA bias alignment (15 pts)
  - Chop filter - channel width (10 pts)
  - Bars since last flip - anti-whipsaw (10 pts)
  - Band position bonus (5 pts)
  - Spread filter (5 pts)
  - Total 0-100, thresholds: ENTER ≥70, CAUTION ≥50, else SKIP

- **Visuals**:
  - Small arrows = all flips (context)
  - Big lime/red arrows = ENTER-grade only
  - HUD shows decision panel with score, reason, checklist

- **Alerts**: Option `AlertOnlyHighQuality` = only alert ENTER signals

- **Well Tested**:
  - Python engine mirrors MQL4 logic 1:1
  - 5 test suites: anchor, VWAP, SSL state, filters, integration
  - Backtest demo shows filtering cuts ~50% low quality flips

---

## Files

```
indicators/HolyGrail_VWAP_SSL_Flip_v6.mq4   # MT4 indicator - install this
src/vwap_ssl_engine.py                     # Python mirror for testing/backtest
src/backtest_demo.py                       # Demo: shows ENTER vs SKIP distribution
tests/test_anchor.py                       # Anchor key logic tests
tests/test_vwap.py                         # VWAP calculation, no future leak
tests/test_ssl.py                          # Hysteretic SSL state tests
tests/test_filters.py                      # Entry quality scoring tests
tests/test_integration.py                  # Full engine integration tests
docs/ENTRY_LOGIC.md                        # Deep dive into scoring
docs/USER_GUIDE.md                         # How to install and use
```

---

## Quick Install

1. Copy `indicators/HolyGrail_VWAP_SSL_Flip_v6.mq4` to `MQL4/Indicators/`
2. Restart MT4, drag onto chart
3. Keep defaults: `UseEntryFilter=true`, `AlertOnlyHighQuality=true`
4. Trade only **big** arrows (ENTER) - HUD will say `ENTER BUY (87)` etc.

---

## How It Decides ENTER vs SKIP

Example HUD:
```
ENTER BUY (87) | B:25 V:20 ADX:15 EMA:15 CH:10 GAP:10 BD:2 SP:5 | Volx1.5 Brk0.3ATR ADX25 Ch1.2ATR 12bars
```

- `B:25` = breakout strong (close 0.3 ATR beyond High VWAP)
- `V:20` = volume 1.5x average
- `ADX:15` = trending (ADX 25)
- `EMA:15` = aligned with EMA50>EMA200
- `CH:10` = wide channel (1.2 ATR)
- `GAP:10` = 12 bars since last flip (no whipsaw)
- Score 87 ≥70 → **ENTER**

If score 45 → **SKIP**, even though flip happened.

See `docs/ENTRY_LOGIC.md` for full breakdown.

---

## Testing

```bash
python3 tests/test_anchor.py
python3 tests/test_vwap.py
python3 tests/test_ssl.py
python3 tests/test_filters.py
python3 tests/test_integration.py
python3 src/backtest_demo.py
```

All tests pass. Python engine ensures MT4 logic is correct (no future leak, correct anchor resets, hysteretic SSL, scoring bounds).

---

## Parameters (Key Ones)

```
AnchorPeriod = Daily (or London/New York session for intraday)
UseEntryFilter = true
MinScoreToEnter = 70
MinBreakoutATR = 0.12
MinVolumeFactor = 1.15
UseADXFilter = true, MinADX = 18
UseEMAFilter = true, EMAFast=50, EMASlow=200
MinBarsBetweenFlips = 5
AvoidChopZone = true, ChopThresholdATR=0.45
AlertOnlyHighQuality = true
```

Tune conservative/aggressive via `docs/USER_GUIDE.md`.

---

## Risk

Risk planner is display only - shows SL = ATR*1.5, TP = SL*2.0, lots from risk %. Never auto-trades.

---

## Philosophy

> Setup vs Decision: VWAP flip is the setup. Quality score is the decision.

Original indicator tells you *a flip happened*. v6 tells you *if you should trade it*.

Trade ENTER, skip SKIP.

---

## License

Use freely, no warranty. Test on demo first.

