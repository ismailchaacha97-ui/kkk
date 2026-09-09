#!/usr/bin/env python3
"""Does MT4's `iMA(..., MODE_EMA)` reproduce the EMAs this study backtested?

Platform EMAs are not all defined the same way. This study used the recursive average seeded with the
first observation - pandas ``ewm(span, adjust=False)``, TradingView ``ta.ema``. MetaTrader seeds with a
simple average of the first ``Period`` values and recurses from there, so the two differ early in the
history and converge afterwards, geometrically at rate (1 - 2/(N+1)) per bar.

That matters here for one concrete reason: a crossover system is a *sign* function, so a tiny numeric
difference becomes a different trade when it flips ``fast > slow`` on some bar. This script measures the
whole chain - bars where the two state series disagree, how many round trips that costs, and what it
does to the score - on the study's own universe, so the MT4 port ships with a number instead of a hope.
It also measures the case users actually hit: a chart with only a little history loaded.
"""
from __future__ import annotations

import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "src"))

from ema_study.data import load_universe                      # noqa: E402
from ema_study.engine import ema                               # noqa: E402

TAB = os.path.join(os.path.dirname(HERE), "results", "tables")
FAST, SLOW = 60, 132      # costs and annualisation come from each Series, as in the study


def ema_mt4(x: np.ndarray, period: int) -> np.ndarray:
    """MetaTrader's MODE_EMA: SMA of the first `period` values, then recursive from that anchor."""
    x = np.asarray(x, dtype=np.float64)
    n = x.size
    out = np.full(n, np.nan)
    if n < period or period < 1:
        return out
    if period == 1:
        return x.copy()
    alpha = 2.0 / (period + 1.0)
    beta = 1.0 - alpha
    seed = float(np.mean(x[:period]))
    out[period - 1] = seed
    prev = seed
    for i in range(period, n):
        prev = beta * prev + alpha * x[i]
        out[i] = prev
    return out


def score(close: np.ndarray, state: np.ndarray, start: int, cost_bps: float, ann: float) -> tuple:
    """Sharpe/CAGR/flips of holding `state` over bar returns, from index `start` on."""
    rets = np.full(close.size, np.nan)
    rets[1:] = close[1:] / close[:-1] - 1.0
    w = state[start:]
    r = rets[start + 1:]
    n = min(w.size, r.size)
    if n < 60:
        return (np.nan, np.nan, 0)
    w, r = w[:n], np.nan_to_num(r[:n], nan=0.0)
    trans = np.abs(np.diff(np.concatenate([[0], w])))
    net = w * r - trans * cost_bps / 1e4
    sd = net.std()
    sharpe = float(net.mean() / sd * np.sqrt(ann)) if sd > 0 else np.nan
    prod = float(np.prod(np.clip(1.0 + net, 1e-9, None)))
    cagr = float(prod ** (ann / n) - 1.0)
    flips = int(trans.sum())
    return sharpe, cagr, flips


def run(horizon: int | None) -> pd.DataFrame:
    uni = load_universe()
    rows = []
    for key, s in uni.items():
        close = s.close.to_numpy(dtype=float)
        if horizon:
            close = close[-horizon:]
        n = close.size
        if n < SLOW + 60:
            continue
        warm = min(SLOW * 2, max(SLOW, n - 60))           # the study's warm-up rule, shrunk to fit
        a_f, a_s = ema(close, FAST), ema(close, SLOW)
        b_f, b_s = ema_mt4(close, FAST), ema_mt4(close, SLOW)
        ok = ~np.isnan(b_f) & ~np.isnan(b_s)
        sa, sb = np.where(ok, (a_f > a_s).astype(int), -1), np.where(ok, (b_f > b_s).astype(int), -1)
        # the study drops the first `slow` bars, so only compare the scored region
        cmp_mask = np.zeros(n, bool)
        cmp_mask[warm:] = True
        cmp_mask &= (sa >= 0) & (sb >= 0)
        diff = int((sa[cmp_mask] != sb[cmp_mask]).sum())
        sh_a, cg_a, fl_a = score(close, sa, warm, s.cost_bps, s.ann)
        sh_b, cg_b, fl_b = score(close, sb, warm, s.cost_bps, s.ann)
        max_num = float(np.nanmax(np.abs(np.where(ok, a_f - b_f, np.nan))))
        rows.append(dict(asset=key, bars=n, disagree_bars=diff, scored_bars=int(cmp_mask.sum()),
                         disagree_pct=100.0 * diff / max(1, int(cmp_mask.sum())),
                         max_ema_gap_bp=1e4 * max_num / float(np.nanmean(close[warm:])),
                         sharpe_study=sh_a, sharpe_mt4=sh_b, sharpe_gap=sh_b - sh_a,
                         flips_study=fl_a, flips_mt4=fl_b, cagr_study=cg_a, cagr_mt4=cg_b))
    return pd.DataFrame(rows)


def main() -> int:
    os.makedirs(TAB, exist_ok=True)
    out = []
    for horizon, label in [(None, "full history"), (SLOW * 4, "4x slow (528 bars)"),
                           (SLOW * 3, "3x slow (396 bars)")]:
        d = run(horizon)
        d.insert(0, "history", label)
        out.append(d)
        same = int((d.disagree_bars == 0).sum())
        print(f"\n=== {label}: {len(d)} markets, {same} with byte-identical signals")
        print(f"    median share of scored bars where the two EMAs disagree: "
              f"{d.disagree_pct.median():.3f}%   max: {d.disagree_pct.max():.2f}%")
        print(f"    median |EMA| gap (bp of price): {d.max_ema_gap_bp.median():.2f}   "
              f"median Sharpe gap (MT4 - study): {d.sharpe_gap.median():+.4f}   "
              f"worst: {d.sharpe_gap.min():+.4f} / {d.sharpe_gap.max():+.4f}")
        print(f"    median flips: study {d.flips_study.median():.0f} vs MT4 {d.flips_mt4.median():.0f}   "
              f"median CAGR: {100 * d.cagr_study.median():.2f}% vs {100 * d.cagr_mt4.median():.2f}%")
    res = pd.concat(out, ignore_index=True)
    res.round(4).to_csv(os.path.join(TAB, "mt4_ema_parity.csv"), index=False)
    try:
        md = res.round(4).to_markdown(index=False)
    except Exception:                       # tabulate is not installed here; the repo avoids the dep
        md = res.round(4).to_string(index=False)
    with open(os.path.join(TAB, "mt4_ema_parity.md"), "w") as fh:
        fh.write(md + "\n")
    print("\nwrote results/tables/mt4_ema_parity.{csv,md}")
    print("\nworst 8 markets by |Sharpe gap| (full history):")
    f = res[res.history == "full history"].reindex(res[res.history == "full history"].sharpe_gap.abs()
                                                    .sort_values(ascending=False).index)
    print(f.head(8)[["asset", "bars", "disagree_bars", "disagree_pct", "max_ema_gap_bp",
                     "sharpe_study", "sharpe_mt4", "flips_study", "flips_mt4"]].round(3).to_string(index=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
