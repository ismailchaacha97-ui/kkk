#!/usr/bin/env python3
"""
Statistical reality check for the "1% a day with <4% drawdown" objective.

Takes the trade list of the validated configuration and answers three questions:

1. RISK SWEEP - at which risk-per-trade does the strategy reach a 4% maximum
   drawdown, and what annual return does that imply?
2. MONTE CARLO - bootstrap the trade sequence (with replacement) to get the
   distribution of drawdown and of the fraction of days that reach +1%, instead
   of relying on the single historical path.
3. TARGET MATH - what Sharpe ratio / win rate would actually be required for a
   genuine 1% per day at a 4% drawdown, and how likely is a 4% drawdown at that
   return level if returns are even approximately normal?

Outputs reports/robot_check.json and prints a readable summary.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.features import Params, build
from backtest.engine import EngineCfg, run

ALL_SYMBOLS = ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"]


def load_run(symbols, params, cfg, start, end):
    series, feats = {}, {}
    for s in symbols:
        ser = D.load(s, "H1")
        series[s] = ser
        feats[s] = build(ser, params)
    return run(series, feats, {s: params for s in symbols}, cfg, start=start, end=end)


def risk_sweep(symbols, params, start, end, risks):
    rows = []
    for r in risks:
        res = load_run(symbols, params, EngineCfg(risk_pct=r, max_positions=3), start, end)
        st = res.stats
        rows.append(dict(risk_pct=r, cagr=st["cagr_pct"], max_dd=st["max_dd_pct"],
                         total=st["total_return_pct"], sharpe=st["sharpe"],
                         avg_day=st["avg_daily_pct"], worst_day=st["worst_day_pct"],
                         pf=st["profit_factor"]))
        print(f"  risk {r:4.2f}%  CAGR {st['cagr_pct']:7.2f}%  maxDD {st['max_dd_pct']:6.2f}%  "
              f"Sharpe {st['sharpe']:5.2f}  worst day {st['worst_day_pct']:6.2f}%", flush=True)
    return pd.DataFrame(rows)


def monte_carlo(trades: pd.DataFrame, risk_pct: float, n_paths: int = 4000,
                start_equity: float = 10_000.0, periods_per_year: int = 250, seed: int = 11):
    """Bootstrap trade R-multiples with replacement, compounding at risk_pct."""
    rng = np.random.default_rng(seed)
    r = trades["r_multiple"].to_numpy()
    n = len(r)
    max_dd = np.empty(n_paths)
    total = np.empty(n_paths)
    worst_day = np.empty(n_paths)
    for k in range(n_paths):
        draw = r[rng.integers(0, n, n)]
        eq = start_equity
        peak = eq
        dd = 0.0
        for x in draw:
            eq *= (1.0 + risk_pct / 100.0 * x)
            if eq > peak:
                peak = eq
            d = 1.0 - eq / peak
            if d > dd:
                dd = d
            if eq <= start_equity * 0.05:
                break
        max_dd[k] = 100 * dd
        total[k] = 100 * (eq / start_equity - 1.0)
    trades_per_year = len(trades) / max((trades.close_time.max() - trades.open_time.min()).days / 365.25, 1e-9)
    return dict(
        trades_per_year=trades_per_year,
        dd_median=float(np.median(max_dd)), dd_p95=float(np.percentile(max_dd, 95)),
        dd_p99=float(np.percentile(max_dd, 99)),
        p_dd_gt_4=float(np.mean(max_dd > 4)), p_dd_gt_10=float(np.mean(max_dd > 10)),
        total_median=float(np.median(total)), total_p5=float(np.percentile(total, 5)),
        total_p95=float(np.percentile(total, 95)),
    )


def target_math(bars_per_day: int = 24, days_per_year: float = 258.0) -> dict:
    """What is actually needed for +1%/day at <=4% drawdown?"""
    daily_target = 0.01
    annual_target = (1 + daily_target) ** days_per_year - 1
    # For a given Sharpe S, the expected max drawdown of a continuous random walk
    # scales roughly as sigma * sqrt(T) with a constant, or more usefully:
    # maxDD/annReturn ~ 1/S * f(T). Empirically for 1y, E[maxDD] ~ 0.8 * sigma_ann
    # when drift is small; with strong drift the ratio drops but stays > 0.15.
    out = {}
    for sharpe in (2, 3, 4, 6, 8, 10):
        sigma_ann = annual_target / sharpe
        sigma_daily = sigma_ann / np.sqrt(days_per_year)
        # expected worst daily loss for a 4% monthly-ish drawdown budget
        out[f"sharpe_{sharpe}"] = dict(
            required_annual_vol_pct=100 * sigma_ann,
            required_daily_vol_pct=100 * sigma_daily,
            empirical_maxdd_pct=100 * 0.65 * sigma_ann,   # ~1y, zero-drift approximation
        )
    out["annual_target_pct"] = 100 * annual_target
    out["note"] = ("A 250%/yr return with a 4% peak-to-trough cap implies an annualised "
                   "Sharpe far above 10 and a daily volatility near zero - i.e. a "
                   "riskless, deterministic edge, which no price-based strategy has.")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbols", default="ALL")
    ap.add_argument("--start", default="2013-01-01")
    ap.add_argument("--end", default="2026-01-01")
    ap.add_argument("--params", default=None)
    ap.add_argument("--risks", default="0.10,0.25,0.50,0.75,1.00,1.50,2.00,3.00")
    ap.add_argument("--paths", type=int, default=4000)
    ap.add_argument("--out", default="reports/robot_check.json")
    ap.add_argument("--trades-out", default="reports/robot_check_trades.csv")
    a = ap.parse_args()

    symbols = ALL_SYMBOLS if a.symbols == "ALL" else a.symbols.split(",")
    params = Params()
    if a.params:
        raw = {k: v for k, v in json.load(open(a.params)).items() if not k.startswith("_")}
        params = Params(**raw)

    print("Risk sweep (historical path)")
    risks = [float(x) for x in a.risks.split(",")]
    df = risk_sweep(symbols, params, a.start, a.end, risks)
    print(df.to_string(index=False))

    # Monte Carlo from the lowest-risk run (R multiples do not depend on risk size)
    res = load_run(symbols, params, EngineCfg(risk_pct=0.10, max_positions=3), a.start, a.end)
    res.trades.to_csv(a.trades_out, index=False)
    print(f"\nMonte Carlo ({a.paths} bootstrap paths, {len(res.trades)} trades)")
    mc = {}
    for r in (0.25, 0.5, 1.0, 2.0):
        m = monte_carlo(res.trades, r, n_paths=a.paths)
        mc[f"risk_{r}"] = m
        print(f"  risk {r:4.2f}%: median DD {m['dd_median']:5.2f}%  P95 DD {m['dd_p95']:5.2f}%  "
              f"P99 DD {m['dd_p99']:6.2f}%  P(DD>4%) {100*m['p_dd_gt_4']:5.1f}%  "
              f"P(DD>10%) {100*m['p_dd_gt_10']:5.1f}%  median total {m['total_median']:8.1f}%")

    tm = target_math()
    print("\nTarget math for +1%/day:", json.dumps({k: v for k, v in tm.items() if k != 'note'}, indent=2))

    out = dict(config=dict(start=a.start, end=a.end, symbols=symbols),
               risk_sweep=df.to_dict(orient="records"),
               monte_carlo=mc, target_math=tm,
               historical_stats=res.stats)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(out, open(a.out, "w"), indent=2, default=str)
    print("\nwrote", a.out)


if __name__ == "__main__":
    main()
