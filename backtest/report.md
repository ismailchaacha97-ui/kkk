# FVG Cascade — Backtest Report (EURUSD M1)

**Strategy:** 4-step ICT FVG cascade (H1 bias → M30 IFVG zone → M5 swing → M1 trigger FVG invalidation),
exact Python port of `FVG_Cascade.mq4` (same defaults: RR 2.0, SL=swing−10 pts, zone max age 96 M30 bars,
setup timeout 240 min, 1 trade/zone, 10 min cooldown).

**Data:** Jan 2021 - Jul 2022 (19 months, Dukascopy GMT bid data) — 554,071 M1 bars (bid OHLC + per-bar measured spread),
built from Dukascopy tick data by `build_m1.py`. No parameters were tuned for this report.

**Signals:** 1002 fired, 1002 closed (0 still open at data end — excluded from stats).

## Headline results (entry = trigger-bar close, SL checked before TP inside each bar)

| Segment | Trades | Win rate | PF | Net pips | Avg/trade | Expectancy (R) | Max DD (pips) | Max consec. losses | Avg duration |
|---|---|---|---|---|---|---|---|---|---|
| All (gross) | 1002 | 42.4% | 1.17 | +985.4 | +0.98 | +0.272 | -735.8 | 13 | 343 min |
| All (net, 0.5 pip cost) | 1002 | 42.4% | 1.08 | +484.4 | +0.48 | +0.185 | -855.3 | 13 | 343 min |
| All (net, 1.0 pip cost) | 1002 | 42.4% | 1.00 | -16.6 | -0.02 | +0.097 | -982.6 | 13 | 343 min |
| All (net, measured spread) | 1002 | 42.4% | 1.11 | +636.6 | +0.64 | +0.211 | -832.4 | 13 | 343 min |
| BUY | 492 | 37.8% | 0.86 | -416.5 | -0.85 | +0.134 | -642.1 | 9 | 298 min |
| SELL | 510 | 46.9% | 1.51 | +1401.9 | +2.75 | +0.406 | -347.4 | 11 | 386 min |
| 2021 | 647 | 43.9% | 1.39 | +1143.8 | +1.77 | +0.317 | -222.8 | 13 | 310 min |
| 2022 | 355 | 39.7% | 0.94 | -158.4 | -0.45 | +0.192 | -735.8 | 9 | 403 min |

*Net (measured spread)* deducts the actual bid/ask spread recorded on the entry bar (mean 0.35 pips).
Fixed-cost rows deduct 0.5 / 1.0 pips per trade round-turn (typical retail spread / spread+slippage).

## Monthly breakdown (net, measured spread)

| Month | Trades | Win rate | Net pips | |
|---|---|---|---|---|
| 2021-01 | 45 | 47% | +59.4 | ▲ |
| 2021-02 | 52 | 48% | +193.7 | ▲ |
| 2021-03 | 55 | 36% | -10.3 | ▼ |
| 2021-04 | 57 | 51% | +101.5 | ▲ |
| 2021-05 | 58 | 48% | +35.5 | ▲ |
| 2021-06 | 51 | 39% | +63.8 | ▲ |
| 2021-07 | 57 | 51% | +127.9 | ▲ |
| 2021-08 | 40 | 40% | -1.0 | ▼ |
| 2021-09 | 51 | 47% | +138.8 | ▲ |
| 2021-10 | 72 | 35% | -133.1 | ▼ |
| 2021-11 | 44 | 43% | +110.1 | ▲ |
| 2021-12 | 65 | 43% | +247.8 | ▲ |
| 2022-01 | 50 | 52% | +178.3 | ▲ |
| 2022-02 | 61 | 44% | +137.4 | ▲ |
| 2022-03 | 64 | 27% | -370.4 | ▼ |
| 2022-04 | 51 | 37% | -201.3 | ▼ |
| 2022-05 | 54 | 41% | -15.5 | ▼ |
| 2022-06 | 65 | 40% | -183.8 | ▼ |
| 2022-07 | 10 | 40% | +157.8 | ▲ |

## Take-profit sensitivity (RR multiple, same entries & stops)

| RR | Trades | Win rate | Gross pips | Net pips (spread) | Avg net/trade |
|---|---|---|---|---|---|
| 1.0 | 1002 | 61.3% | +769.7 | +420.9 | +0.42 |
| 1.5 | 1002 | 49.2% | +857.5 | +508.7 | +0.51 |
| 2.0 | 1002 | 42.4% | +985.4 | +636.6 | +0.64 |
| 2.5 | 1000 | 36.6% | +745.7 | +397.5 | +0.40 |
| 3.0 | 1000 | 31.7% | +723.3 | +375.1 | +0.38 |

## Risk profile

- Stop distance: median **6.5 pips**, mean 9.1, max 122.
- Average hold: 343 min (median 66 min); 49% close within an hour.
- Losing trades that first moved ≥1 pip in favor: 84%; ≥1R in favor: 33%.
- Long/short split: 492 BUY / 510 SELL.

## Verdict

**Positive net of the measured spread (+637 pips over 1002 trades), but the edge is thin and unevenly distributed —
this is a marginal system, not a money machine.**

- **Gross expectancy +0.98 pips/trade (PF 1.17)** — real, but small.
  It survives the tight Dukascopy spread (0.35 pips) but is wiped out by a 1.0-pip cost assumption at RR 2.0.
  On a typical retail account this is roughly break-even.
- **Strong long/short asymmetry: SELL +1219 pips vs BUY -582 pips net.**
  The sample sits inside a major EURUSD downtrend (1.23 → 1.02); with-trend SELLs carried the results while
  counter-trend BUYs lost. Do not treat both directions as equally reliable.
- **Regime dependent: +934 pips in 2021 vs -297 in 2022** (Jan–Jul). The 2022 war/Fed-hike
  volatility produced the worst stretch (Mar–Jun 2022, four red months) and the max drawdown.
- **RR 1.5–2.0 is the sweet spot**; RR ≥ 2.5 gives back most of the edge (see sensitivity table).
- Everything here is **descriptive backtesting of the alert logic**, not an optimisation: all inputs are the
  indicator defaults, no parameter was tuned on this data.

## Assumptions & caveats

1. **Bid prices, GMT.** MT4 brokers quote broker time (often GMT+2/+3) — H1/M30/M5/M1 bar boundaries
   differ, so exact signals on your broker will differ somewhat. Dukascopy spread is institutional-tight;
   your broker's spread will be wider.
2. **Entry at the close of the M1 trigger bar** — in live use the alert arrives at that close, so a manual
   market order seconds later matches this closely.
3. **Intra-bar rule:** if a bar touches both SL and TP, **SL is counted first** (conservative).
4. Every fired alert is treated as a taken trade (1 unit risk per trade, no position sizing),
   independent of each other — you can of course filter signals manually.
5. No news filter, no swap/rollover costs, no requotes. Weekends/holidays as present in the data.

## Reproduce

```bash
cd backtest
python3 backtest.py        # engine + trades.csv  (~8 s)
python3 make_report.py     # this report + equity_curve.png
```

Files: `trades.csv` (all trades with cascade context: tap, pivot, zone, swing, spread),
`equity_curve.png`, `build_m1.py` (tick→M1), `backtest.py` (engine), `make_report.py` (this report).
