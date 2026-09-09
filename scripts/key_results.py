#!/usr/bin/env python3
"""Print the fact sheet used to write REPORT.md — every number read from the
result files, so the prose can be checked against the data.

    python scripts/key_results.py
"""
from __future__ import annotations

import json
import os

import pandas as pd

RES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "results")
TAB = os.path.join(RES, "tables")


def j(name):
    p = os.path.join(RES, name)
    return json.load(open(p)) if os.path.exists(p) else {}


def t(name, **kw):
    p = os.path.join(TAB, name)
    return pd.read_csv(p, **kw) if os.path.exists(p) else pd.DataFrame()


def head(title):
    print("\n" + "=" * 78 + f"\n{title}\n" + "=" * 78)


S = j("summary.json")
U = j("summary_surfaces.json")
L = j("summary_shortlist.json")

head("1. UNIVERSE / DESIGN")
print(json.dumps({k: S.get(k) for k in ("n_markets", "families", "bars_per_market_median", "history_span",
                                        "pairs", "rows_long", "total_backtests")}, indent=2))
print("median pair Sharpe:", S.get("median_base"), " best pair:", S.get("best_base"))
print("variants present:", S.get("variants_present"))
print("negative control:", json.dumps(S.get("negative_control", {}), indent=2)[:900])
print("execution:", json.dumps(S.get("execution", {}), indent=2)[:900])

head("2. THE PICK (robust surface rule, long/flat and long/short) + EXT CHECK")
for k in ("best_long", "best_ls"):
    print(f"\n{k}: {json.dumps(U.get(k, {}), indent=2)}")
print("\nrobust_best (from summary.json):")
for k in ("robust_best_long", "raw_best_long", "robust_best_ls", "raw_best_ls", "surface_smoothness_long",
          "surface_smoothness_ls"):
    print(f"  {k}: {json.dumps(S.get(k, {}), indent=1, default=str)}")
print("\nEXT (slower EMAs to 1200):")
for k in ("ext_ridge_long", "ext_ridge_ls"):
    e = U.get(k)
    print(f"  {k}: {json.dumps(e[0], indent=2) if isinstance(e, list) and e else e}")
print("\nband tables:")
for m in ("long", "ls"):
    b = U.get(f"band_{m}")
    if b:
        bb = t(f"band_{m}.csv")
        print(f"\nband_{m} (top 5 cells by med_sharpe):\n",
              bb.sort_values("med_sharpe", ascending=False).head(5).to_string(index=False)
              if not bb.empty else b if isinstance(b, str) else "")

head("3. GIVEN YOUR CURRENT SETTINGS")
for m in ("long", "ls"):
    for kind in ("fast", "slow"):
        df = t(f"given_your_{kind}_{m}.csv")
        if not df.empty:
            print(f"\ngiven_your_{kind}_{m}:\n", df.to_string(index=False)[:2600])

print("\nconstrained best (interior, 0.75-14 trades/yr, >=75% markets positive):")
for k in ("constrained_best_long", "constrained_best_ls"):
    c = U.get(k)
    if isinstance(c, pd.DataFrame) or c:
        print(f"  {k}: {json.dumps(c, indent=2, default=str)[:1500]}")

head("4. FAMOUS SETTINGS vs THE GRID")
f = t("famous_vs_found.csv")
if not f.empty:
    cols = [c for c in ["label", "mode", "fast", "slow", "med_sharpe", "nb_min_sharpe",
                         "med_calmar", "share_pos", "trades_per_year", "med_max_dd", "rank_raw", "rank_robust",
                         "med_sharpe", "nb_min_sharpe"] if c in f.columns]
    print(f[cols].to_string(index=False))

head("5. WALK-FORWARD")
print("\nwf_stats:", json.dumps(S.get("wf_stats", {}), indent=2, default=str))
for m in ("long", "ls"):
    print(f"\nsplit_{m}:", json.dumps(S.get(f"split_{m}", {}), indent=2, default=str))

head("6. TREND BOOK vs BUY & HOLD")
print("bh_book:", json.dumps(S.get("bh_book", {}), indent=2, default=str))
print("book_dense_window:", S.get("book_dense_window"))
tb = t("bh_reference.csv")
if not tb.empty:
    print("\nbh_reference (fair, same book/market set/window; vt = 10% vol target):")
    print(tb[["pair","mode","st_sharpe","bh_sharpe","st_dd","bh_dd","vt_sharpe","bhvt_sharpe","vt_dd",
              "bhvt_dd","vt_calmar","bhvt_calmar","exposure","markets","days"]].round(3).to_string(index=False))
for m in ("long", "ls"):
    tb = t(f"trend_book.csv")
    if not tb.empty:
        tt = tb[tb["mode"] == m].sort_values("vt_sharpe", ascending=False).head(10)
        print(f"\n[{m}] best on the diversified book (vt_sharpe):\n", tt[["pair","sharpe","vt_sharpe",
              "vt_cagr","vt_dd","vt_calmar","why"]].round(3).to_string(index=False))

head("7. PER-MARKET WINNERS / VOL SCALING")
print("per_market:", json.dumps(S.get("per_market", {}), indent=2, default=str)[:1400])
vs = t("per_market_optimum_scaled.csv")
print("vol scaling table:\n", vs.head(3).to_string(index=False) if not vs.empty else "n/a")
print("vol scaling (surfaces):", json.dumps(U.get("vol_scaling", {}), indent=2, default=str)[:900])
print("DSR:", json.dumps(S.get("dsr", {}), indent=2, default=str)[:1200])

head("8. COST SENSITIVITY")
cs = t("sensitivity_panels.csv")
print(cs.to_string(index=False) if not cs.empty else "n/a")
print("decades:", json.dumps(S.get("decades", {}), indent=2, default=str)[:1500])

head("9. SHORTLIST: per asset class, consistency, decades, home markets")
for k in ("pair_by_asset_class", "rolling_3y", "decades", "home_markets", "global_vs_per_market",
          "trend_book_years"):
    v = L.get(k)
    if v is None and not os.path.exists(os.path.join(TAB, f"{k}.csv")) and not os.path.exists(os.path.join(TAB, f"{k}_consistency.csv")):
        df = t(f"{k}.csv") if os.path.exists(os.path.join(TAB, f"{k}.csv")) else t(f"{k}_consistency.csv")
        v = df.to_string(index=False)[:2000] if not df.empty else "n/a"
    print(f"\n{k}: {v if isinstance(v, str) else json.dumps(v, indent=2, default=str)[:2000]}")

head("10. FILES")
print("tables:", sorted(os.listdir(TAB))[:80])
print("figures:", sorted(os.listdir(os.path.join(RES, "figs"))))
