#!/usr/bin/env python3
"""
Parameter research harness.

Two-stage search (structure first, then trade management) with the *portfolio*
as the unit of evaluation, because the target metric is a portfolio-level daily
return with a portfolio-level drawdown.

Feature arrays are cached by the subset of parameters that actually affect them,
so varying stop/target/trailing costs one engine pass instead of a full rebuild.

Usage examples
--------------
  python tools/research.py --stage structure --symbols GBPUSD,XAUUSD
  python tools/research.py --stage trade --symbols ALL
"""
from __future__ import annotations

import argparse
import itertools
import json
import os
import sys
import time
from dataclasses import replace

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.features import Params, build
from backtest.engine import EngineCfg, run

ALL_SYMBOLS = ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"]
# features depend on these only
FEATURE_FIELDS = ("pivot_k", "level_cooldown", "min_range_atr", "close_frac", "vol_lookback",
                  "vol_mult", "vol_confirm", "atr_period", "session_start", "session_end",
                  "trade_friday", "trade_monday", "level_mode", "require_htf_trend",
                  "max_penetration")

_CACHE: dict = {}
_SERIES: dict = {}


def get_series(symbols):
    for s in symbols:
        if s not in _SERIES:
            _SERIES[s] = D.load(s, "H1")
    return _SERIES


def get_features(symbols, params: Params):
    """One-entry cache: feature arrays are ~20 MB per symbol, so caching every
    configuration would blow up memory.  Consecutive configs that only change
    trade-management parameters therefore reuse the same arrays."""
    key = (tuple(sorted(symbols)),) + tuple(getattr(params, f) for f in FEATURE_FIELDS)
    if _CACHE.get("key") != key:
        ser = get_series(symbols)
        _CACHE.clear()
        _CACHE["key"] = key
        _CACHE["data"] = {s: build(ser[s], params) for s in symbols}
        del ser
    return _CACHE["data"]


def evaluate(symbols, params: Params, cfg: EngineCfg, start, end):
    ser = get_series(symbols)
    feats = get_features(symbols, params)
    prm = {s: params for s in symbols}
    res = run({s: ser[s] for s in symbols}, feats, prm, cfg, start=start, end=end)
    st = res.stats
    st["score"] = _score(st)
    return res, st


def _score(st):
    """Robustness-first ranking: we want the best risk-adjusted return, not the
    highest raw return.  Penalise tiny sample sizes and fat tails."""
    if st.get("trades", 0) < 40:
        return -1e9
    pf = min(st.get("profit_factor", 0) or 0, 6.0)
    sharpe = st.get("sharpe", 0.0)
    dd = max(st.get("max_dd_pct", 100.0), 0.05)
    return st.get("cagr_pct", 0) / dd * 0.5 + sharpe * 0.5 + np.log(max(pf, 0.1))


def stage_structure(symbols, start, end, base: Params, cfg):
    grid = dict(
        level_mode=[0, 1],
        max_penetration=[99.0, 0.25],
        pivot_k=[2, 3],
        vol_confirm=[0, 1],
        min_range_atr=[0.35, 0.55, 0.8],
        close_frac=[0.45, 0.6],
        require_htf_trend=[0, 1],
    )
    rows = []
    keys = list(grid)
    for combo in itertools.product(*[grid[k] for k in keys]):
        p = replace(base, **dict(zip(keys, combo)))
        t0 = time.time()
        _, st = evaluate(symbols, p, cfg, start, end)
        rows.append(dict(zip(keys, combo), **{k: st.get(k) for k in
                    ("trades", "trades_per_day", "cagr_pct", "max_dd_pct", "profit_factor",
                     "win_rate_pct", "expectancy_r", "sharpe", "score")}, secs=round(time.time() - t0, 1)))
        print(f"[{len(rows)}] {dict(zip(keys, combo))} -> trades={st.get('trades')} "
              f"pf={st.get('profit_factor'):.2f} dd={st.get('max_dd_pct'):.2f} cagr={st.get('cagr_pct'):.2f}",
              flush=True)
    df = pd.DataFrame(rows).sort_values("score", ascending=False)
    return df


def stage_trade(symbols, start, end, base: Params, cfg):
    grid = dict(
        rr=[2.0, 2.5, 3.0, 4.0],
        sl_atr_buffer=[0.2, 0.3],
        be_at_r=[0.9],
        trail_atr=[0.0, 2.0, 3.0],
        max_hold_bars=[48],
    )
    rows = []
    keys = list(grid)
    for combo in itertools.product(*[grid[k] for k in keys]):
        p = replace(base, **dict(zip(keys, combo)))
        _, st = evaluate(symbols, p, cfg, start, end)
        rows.append(dict(zip(keys, combo), **{k: st.get(k) for k in
                    ("trades", "trades_per_day", "cagr_pct", "max_dd_pct", "profit_factor",
                     "win_rate_pct", "expectancy_r", "sharpe", "score")}))
        print(f"[{len(rows)}] {dict(zip(keys, combo))} -> trades={st.get('trades')} "
              f"pf={st.get('profit_factor'):.2f} dd={st.get('max_dd_pct'):.2f} cagr={st.get('cagr_pct'):.2f}",
              flush=True)
    df = pd.DataFrame(rows).sort_values("score", ascending=False)
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default="structure", choices=["structure", "trade"])
    ap.add_argument("--symbols", default="ALL")
    ap.add_argument("--start", default="2013-01-01")
    ap.add_argument("--end", default="2026-01-01")
    ap.add_argument("--risk", type=float, default=0.25)
    ap.add_argument("--max-pos", type=int, default=3)
    ap.add_argument("--params", default=None, help="json file with base Params overrides")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    symbols = ALL_SYMBOLS if a.symbols == "ALL" else [s.strip() for s in a.symbols.split(",")]
    base = Params()
    if a.params:
        raw = {k: v for k, v in json.load(open(a.params)).items() if not k.startswith("_")}
        base = replace(base, **raw)
    cfg = EngineCfg(risk_pct=a.risk, max_positions=a.max_pos)
    t0 = time.time()
    if a.stage == "structure":
        df = stage_structure(symbols, a.start, a.end, base, cfg)
    else:
        df = stage_trade(symbols, a.start, a.end, base, cfg)
    out = a.out or f"reports/research_{a.stage}.csv"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    df.to_csv(out, index=False)
    pd.set_option("display.width", 200)
    print(df.head(25).to_string(index=False))
    print(f"\n{len(df)} configs in {time.time()-t0:.0f}s -> {out}")


if __name__ == "__main__":
    main()
