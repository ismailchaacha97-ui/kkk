"""
Causality test: a feature attached to bar i must not change when future bars are
appended or removed.  This is the guard that stops the whole project from being
another beautiful-backtest-with-lookahead story.
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.features import Params, build


def compare(symbol: str, tf: str = "H1", n_cuts: int = 6, seed: int = 7) -> list[str]:
    s = D.load(symbol, tf)
    p = Params()
    full = build(s, p)
    rng = np.random.default_rng(seed)
    problems = []
    n = len(s)
    cuts = sorted(rng.integers(n // 3, n - 10, size=n_cuts))
    fields = ["atr", "pdh", "pdl", "pwh", "pwl", "swing_hi_1", "swing_lo_1",
              "structure", "vol_med", "ok_long", "ok_short"]
    for cut in cuts:
        part = D.Series(symbol=s.symbol, time=s.time[:cut], open=s.open[:cut], high=s.high[:cut],
                        low=s.low[:cut], close=s.close[:cut], volume=s.volume[:cut])
        pf = build(part, p)
        for f in fields:
            a = np.asarray(getattr(full, f)[:cut], dtype=float)
            b = np.asarray(getattr(pf, f), dtype=float)
            same = np.array_equal(np.isnan(a), np.isnan(b)) and np.allclose(a[~np.isnan(a)], b[~np.isnan(b)])
            if not same:
                bad = np.where(~np.isclose(np.nan_to_num(a, nan=-9e9), np.nan_to_num(b, nan=-9e9)))[0]
                problems.append(f"{symbol}@{cut}: field '{f}' differs at bars {bad[:8]}")
    return problems


if __name__ == "__main__":
    allp = []
    for sym in ["GBPUSD", "XAUUSD", "USDJPY"]:
        allp += compare(sym)
    if allp:
        print("LOOKAHEAD DETECTED")
        for x in allp:
            print(" ", x)
        sys.exit(1)
    print("causality OK - no feature depends on future bars")
