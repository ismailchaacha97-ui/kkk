#!/usr/bin/env python3
"""Evaluate a handful of pre-declared variants on three windows at once.

The point is to reject variants that only work in one regime, not to find the
best curve fit.  Windows are fixed in advance:
    2013-2019  (in-sample, used for the original search)
    2020-2021  (COVID + recovery, EURUSD excluded - data gap)
    2022-2026  (out-of-sample, post-search)
"""
import json, os, sys
from dataclasses import replace
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pandas as pd
from backtest import data as D
from backtest.features import Params, build
from backtest.engine import EngineCfg, run

SYMS = ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"]
WINDOWS = [("is_2013_2019", "2013-01-01", "2019-12-31", SYMS),
           ("covid_2020_2021", "2020-01-01", "2021-12-31", [s for s in SYMS if s != "EURUSD"]),
           ("oos_2022_2026", "2022-01-01", "2026-03-01", SYMS)]

def main():
    base = Params(**{k: v for k, v in json.load(open("presets/validated.json")).items()
                     if not k.startswith("_")})
    variants = {
        "A baseline (pen .25, k3, htf)": base,
        "B no structure filter": replace(base, require_htf_trend=0),
        "C penetration .15": replace(base, max_penetration=0.15),
        "D penetration .40": replace(base, max_penetration=0.40),
        "E no penetration cap": replace(base, max_penetration=99.0),
        "F pivot_k=2": replace(base, pivot_k=2),
        "G session 10-18": replace(base, session_start=10, session_end=18),
        "H low RR 1.2": replace(base, rr=1.2, be_at_r=0.0),
        "I volume filter on": replace(base, vol_confirm=1),
        "J no time stop": replace(base, max_hold_bars=0),
    }
    series = {s: D.load(s) for s in SYMS}
    cache = {}
    rows = []
    for name, p in variants.items():
        row = {"variant": name}
        for wname, a, b, syms in WINDOWS:
            key = (p.pivot_k, p.level_mode, p.max_penetration, p.min_range_atr, p.close_frac,
                   p.require_htf_trend, p.session_start, p.session_end, p.vol_confirm, p.max_hold_bars)
            if key not in cache:
                cache.clear()
                cache[key] = {s: build(series[s], p) for s in syms}
            feats = cache[key]
            r = run({s: series[s] for s in syms}, feats, {s: p for s in syms},
                    EngineCfg(risk_pct=0.25, max_positions=3), start=a, end=b)
            st = r.stats
            row[f"{wname}_cagr"] = round(st["cagr_pct"], 2)
            row[f"{wname}_dd"] = round(st["max_dd_pct"], 2)
            row[f"{wname}_exp"] = round(st.get("expectancy_r", 0), 3)
            row[f"{wname}_n"] = st["trades"]
        rows.append(row)
        print(f"{name}: " + "  ".join(f"{w.split('_')[0]}: {row[w+'_cagr']}%/{row[w+'_exp']}R"
                                      for w, _, _, _ in WINDOWS), flush=True)
    df = pd.DataFrame(rows)
    df.to_csv("reports/robustness_variants.csv", index=False)
    pd.set_option("display.width", 250)
    print(df.to_string(index=False))

if __name__ == "__main__":
    main()
