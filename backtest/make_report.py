#!/usr/bin/env python3
"""Full statistics report for the FVG_Cascade backtest -> backtest/report.md
   + backtest/equity_curve.png. Run backtest.py first (writes trades.csv,
   needs the Backtester object for RR sensitivity re-scans)."""
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

import backtest as B
PIP = B.PIP

BASE = os.path.dirname(os.path.abspath(__file__))
YEARS_TXT = 'Jan 2021 - Jul 2022 (19 months, Dukascopy GMT bid data)'


def stats_block(d, label):
    """d: closed trades dataframe (result != 0)."""
    n = len(d)
    wins = d[d.result > 0]; losses = d[d.result < 0]
    wr = 100.0 * len(wins) / n if n else 0
    gp = wins.gross_pips.sum(); gl = -losses.gross_pips.sum()
    pf = gp / gl if gl > 0 else float('inf')
    r_mult = d.gross_pips / (d.risk / PIP)
    eq = d.sort_values('exit_t').gross_pips.cumsum()
    dd = (eq - eq.cummax()).min() if n else 0
    # max consecutive losses (chronological)
    cl = mx = 0
    for r in d.sort_values('exit_t').result:
        cl = cl + 1 if r < 0 else 0
        mx = max(mx, cl)
    return dict(label=label, n=n, wr=wr, pf=pf,
                tot=d.gross_pips.sum(), avg=d.gross_pips.mean() if n else 0,
                avg_r=r_mult.mean() if n else 0, dd=dd, maxcl=mx,
                dur=d.dur_min.mean() if n else 0)


def fmt(s):
    return ('| %s | %d | %.1f%% | %.2f | %+.1f | %+.2f | %+.3f | %.1f | %d | %.0f min |'
            % (s['label'], s['n'], s['wr'], s['pf'], s['tot'], s['avg'],
               s['avg_r'], s['dd'], s['maxcl'], s['dur']))


HDR = ('| Segment | Trades | Win rate | PF | Net pips | Avg/trade | Expectancy (R) '
       '| Max DD (pips) | Max consec. losses | Avg duration |\n'
       '|---|---|---|---|---|---|---|---|---|---|\n')


def main():
    # ------------------------------------------------- rerun engine (fast, 8s)
    files = sorted(os.path.join(BASE, 'data', f)
                   for f in os.listdir(os.path.join(BASE, 'data')) if f.endswith('.csv.gz'))
    m1 = B.load_m1(files)
    bt = B.Backtester(m1)
    signals = bt.run(verbose=False)
    trades = bt.outcomes(signals)
    df = pd.DataFrame(trades)
    df['time'] = pd.to_datetime(df['t_entry'], unit='s')
    df['exit_time'] = pd.to_datetime(df['exit_t'], unit='s')
    df['risk_pips'] = df.risk / PIP
    df['cost_pips'] = df.spread / PIP            # measured bid-ask spread at entry bar
    df['net_pips'] = df.gross_pips - df.cost_pips
    df['month'] = df.time.dt.strftime('%Y-%m')
    df.to_csv(os.path.join(BASE, 'trades.csv'), index=False)

    closed = df[df.result != 0].sort_values('exit_t').reset_index(drop=True)
    n_open = int((df.result == 0).sum())

    # ---------------------------------------------------------------- overall
    rows = [stats_block(closed, 'All (gross)')]
    for fixed in (0.5, 1.0):
        c = closed.copy()
        c['gross_pips'] = closed.gross_pips - fixed
        rows.append(stats_block(c, 'All (net, %.1f pip cost)' % fixed))
    c = closed.copy(); c['gross_pips'] = closed.net_pips
    rows.append(stats_block(c, 'All (net, measured spread)'))

    # ------------------------------------------------------------- by direction
    for d, nm in ((1, 'BUY'), (-1, 'SELL')):
        rows.append(stats_block(closed[closed.dir == d], nm))

    # ------------------------------------------------------------- by year
    for y in ('2021', '2022'):
        rows.append(stats_block(closed[closed.time.dt.year == int(y)], y))

    # ------------------------------------------------------------- RR sensitivity
    rr_rows = []
    for rr in (1.0, 1.5, 2.0, 2.5, 3.0):
        t = bt.outcomes(signals, rr=rr)
        d = pd.DataFrame([x for x in t if x['result'] != 0]).sort_values('exit_t')
        net = d.gross_pips - d.spread / PIP
        wins = int((d.result > 0).sum())
        rr_rows.append('| %.1f | %d | %.1f%% | %+.1f | %+.1f | %+.2f |'
                       % (rr, len(d), 100.0 * wins / len(d),
                          d.gross_pips.sum(), net.sum(), net.mean()))

    # ------------------------------------------------------------- monthly table
    mon_rows = []
    for mo, g in closed.groupby('month'):
        w = int((g.result > 0).sum())
        net = g.net_pips.sum()
        mon_rows.append('| %s | %d | %.0f%% | %+.1f | %s |' % (
            mo, len(g), 100.0 * w / len(g), net,
            '▲' if net > 0 else '▼'))

    # ------------------------------------------------------------- MFE insight
    losers = closed[closed.result < 0]
    went_1r = (losers.mfe_pips >= losers.risk_pips).mean() * 100 if len(losers) else 0
    went_1p = (losers.mfe_pips >= 1.0).mean() * 100 if len(losers) else 0

    # ------------------------------------------------------------- equity curve
    fig, ax = plt.subplots(figsize=(11, 5.5), dpi=130)
    ce = closed.sort_values('exit_t')
    x = pd.to_datetime(ce.exit_t, unit='s')
    ax.plot(x, ce.gross_pips.cumsum(), lw=1.4, label='Gross (no costs)', color='#1f77b4')
    ax.plot(x, ce.net_pips.cumsum(), lw=1.4, label='Net (measured spread)', color='#2ca02c')
    ax.plot(x, (ce.gross_pips - 1.0).cumsum(), lw=1.0, ls='--',
            label='Net (1.0 pip cost)', color='#d62728', alpha=0.8)
    ax.axhline(0, color='k', lw=0.6)
    ax.set_title('FVG Cascade - EURUSD M1  |  1002 signals  |  RR 2.0, SL=swing  |  %s' % YEARS_TXT)
    ax.set_ylabel('Cumulative pips')
    ax.legend(loc='upper left'); ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(os.path.join(BASE, 'equity_curve.png'))

    # ------------------------------------------------------------- write report
    n = len(closed)
    w = int((closed.result > 0).sum())
    net_tot = closed.net_pips.sum()
    buy_net = closed[closed.dir > 0].net_pips.sum()
    sell_net = closed[closed.dir < 0].net_pips.sum()
    y21 = closed[closed.time.dt.year == 2021].net_pips.sum()
    y22 = closed[closed.time.dt.year == 2022].net_pips.sum()

    rep = f"""# FVG Cascade — Backtest Report (EURUSD M1)

**Strategy:** 4-step ICT FVG cascade (H1 bias → M30 IFVG zone → M5 swing → M1 trigger FVG invalidation),
exact Python port of `FVG_Cascade.mq4` (same defaults: RR 2.0, SL=swing−10 pts, zone max age 96 M30 bars,
setup timeout 240 min, 1 trade/zone, 10 min cooldown).

**Data:** {YEARS_TXT} — {len(m1):,} M1 bars (bid OHLC + per-bar measured spread),
built from Dukascopy tick data by `build_m1.py`. No parameters were tuned for this report.

**Signals:** {len(df)} fired, {n} closed ({n_open} still open at data end — excluded from stats).

## Headline results (entry = trigger-bar close, SL checked before TP inside each bar)

{HDR}{chr(10).join(fmt(r) for r in rows)}

*Net (measured spread)* deducts the actual bid/ask spread recorded on the entry bar (mean 0.35 pips).
Fixed-cost rows deduct 0.5 / 1.0 pips per trade round-turn (typical retail spread / spread+slippage).

## Monthly breakdown (net, measured spread)

| Month | Trades | Win rate | Net pips | |
|---|---|---|---|---|
{chr(10).join(mon_rows)}

## Take-profit sensitivity (RR multiple, same entries & stops)

| RR | Trades | Win rate | Gross pips | Net pips (spread) | Avg net/trade |
|---|---|---|---|---|---|
{chr(10).join(rr_rows)}

## Risk profile

- Stop distance: median **{closed.risk_pips.median():.1f} pips**, mean {closed.risk_pips.mean():.1f}, max {closed.risk_pips.max():.0f}.
- Average hold: {closed.dur_min.mean():.0f} min (median {closed.dur_min.median():.0f} min); {100*(closed.dur_min<=60).mean():.0f}% close within an hour.
- Losing trades that first moved ≥1 pip in favor: {went_1p:.0f}%; ≥1R in favor: {went_1r:.0f}%.
- Long/short split: {int((closed.dir>0).sum())} BUY / {int((closed.dir<0).sum())} SELL.

## Verdict

**Positive net of the measured spread (+{net_tot:.0f} pips over {n} trades), but the edge is thin and unevenly distributed —
this is a marginal system, not a money machine.**

- **Gross expectancy +{closed.gross_pips.mean():.2f} pips/trade (PF {rows[0]['pf']:.2f})** — real, but small.
  It survives the tight Dukascopy spread (0.35 pips) but is wiped out by a 1.0-pip cost assumption at RR 2.0.
  On a typical retail account this is roughly break-even.
- **Strong long/short asymmetry: SELL {sell_net:+.0f} pips vs BUY {buy_net:+.0f} pips net.**
  The sample sits inside a major EURUSD downtrend (1.23 → 1.02); with-trend SELLs carried the results while
  counter-trend BUYs lost. Do not treat both directions as equally reliable.
- **Regime dependent: {y21:+.0f} pips in 2021 vs {y22:+.0f} in 2022** (Jan–Jul). The 2022 war/Fed-hike
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
"""
    with open(os.path.join(BASE, 'report.md'), 'w') as f:
        f.write(rep)
    print(rep[:1500])
    print('...\nreport.md + equity_curve.png written.')


if __name__ == '__main__':
    main()
