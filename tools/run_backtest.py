#!/usr/bin/env python3
"""Run the reference backtest and print / store the performance report."""
from __future__ import annotations
import argparse, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.features import Params, build
from backtest.engine import EngineCfg, run, summary


def build_all(symbols, tf="H1", params=None):
    params = params or {}
    series, feats, used = {}, {}, {}
    for s in symbols:
        ser = D.load(s, tf)
        prm = params.get(s, params.get("default", Params()))
        series[s] = ser
        feats[s] = build(ser, prm)
        used[s] = prm
    return series, feats, used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbols", default="EURUSD,GBPUSD,AUDUSD,USDJPY,XAUUSD")
    ap.add_argument("--start", default="2013-01-01")
    ap.add_argument("--end", default="2026-01-01")
    ap.add_argument("--risk", type=float, default=0.25)
    ap.add_argument("--max-pos", type=int, default=3)
    ap.add_argument("--out", default="reports/backtest.json")
    a = ap.parse_args()
    syms = (["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"] if a.symbols == "ALL"
            else [s.strip() for s in a.symbols.split(",") if s.strip()])
    series, feats, params = build_all(syms)
    cfg = EngineCfg(risk_pct=a.risk, max_positions=a.max_pos)
    res = run(series, feats, params, cfg, start=a.start, end=a.end)
    print(summary(res.stats))
    if res.stats.get("by_symbol"):
        print(res.stats["by_symbol"])
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(res.stats, open(a.out, "w"), indent=2, default=str)
    res.trades.to_csv(a.out.replace(".json", "_trades.csv"), index=False)


if __name__ == "__main__":
    main()
