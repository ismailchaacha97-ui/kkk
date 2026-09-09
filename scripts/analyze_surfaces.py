#!/usr/bin/env python3
"""Stage 3 - the shape of the answer: marginals, ridge, constrained practical optimum,
vol-scaled periods, cost/execution shifts and (if available) the extended grid.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "src"))
from ema_study.data import load_universe, _returns                       # noqa: E402
from ema_study.engine import evaluate_pair, ema                          # noqa: E402
from ema_study import robust as RB, plots as PL                          # noqa: E402

RES = os.path.join(HERE, "results")
TAB, FIG = os.path.join(RES, "tables"), os.path.join(RES, "figs")
OUT: dict = {}


def w(df, name):
    df.to_csv(os.path.join(TAB, f"{name}.csv"), index=False)
    try:
        md = df.to_markdown(index=False)
    except Exception:
        md = df.to_string(index=False)
    open(os.path.join(TAB, f"{name}.md"), "w").write(md + "\n")
    return df


def band_table(a, mode):
    a = a.copy()
    a["fb"] = pd.cut(a["fast"], [1, 4, 9, 19, 39, 69, 121],
                     labels=["2-4", "5-9", "10-19", "20-39", "40-69", "70-120"])
    a["sb"] = pd.cut(a["slow"], [5, 15, 30, 60, 120, 200, 300, 401, 701, 1001],
                     labels=["6-15", "16-30", "31-60", "61-120", "121-200", "201-300", "301-400",
                             "401-700", "701-1000"])
    tabs = {}
    for val, lab in [("med_sharpe", "median cross-market Sharpe"), ("share_pos", "share of markets with Sharpe>0"),
                     ("med_calmar", "median cross-market Calmar"), ("med_dd", "median max drawdown"),
                     ("med_rt_yr", "median round trips / year")]:
        t = a.pivot_table(index="fb", columns="sb", values=val, aggfunc="mean", observed=True).round(3)
        t = t.dropna(axis=0, how="all").dropna(axis=1, how="all")
        t.to_csv(os.path.join(TAB, f"band_{val}_{mode}.csv"))
        tabs[lab] = t
    return tabs


def ridge(a, mode):
    """For every slow period, the best fast (and vice versa) -> is there an interior peak?"""
    r1 = a.loc[a.groupby("slow")["med_sharpe"].idxmax(), ["slow", "fast", "med_sharpe", "nb_min_sharpe",
                                                           "share_pos", "med_rt_yr"]]
    r2 = a.loc[a.groupby("fast")["med_sharpe"].idxmax(), ["fast", "slow", "med_sharpe", "nb_min_sharpe",
                                                           "share_pos", "med_rt_yr"]]
    w(r1, f"ridge_best_fast_per_slow_{mode}")
    w(r2, f"ridge_best_slow_per_fast_{mode}")
    return r1, r2


def constrained_best(a, mode, min_rt=0.75, max_rt=14.0, min_share_pos=0.75, interior=1):
    """Interior, sufficiently-active maximum of the worst-neighbour criterion."""
    x = a.dropna(subset=["nb_min_sharpe"]).copy()
    lo_f, hi_f = x["fast"].min(), x["fast"].max()
    lo_s, hi_s = x["slow"].min(), x["slow"].max()
    pm_f, pm_s = 4, 16
    edge = ((x["fast"] - pm_f >= lo_f) & (x["fast"] + pm_f <= hi_f) &
            (x["slow"] - pm_s >= lo_s) & (x["slow"] + pm_s <= hi_s))
    act = (x["med_rt_yr"].between(min_rt, max_rt)) & (x["share_pos"] >= min_share_pos)
    sel = x[edge & act]
    res = {}
    if len(sel):
        b = sel.sort_values("nb_min_sharpe", ascending=False).iloc[0]
        res = dict(rule="max-min over +/-4 fast, +/-16 slow, interior, 0.75-14 trades/yr, >=75% markets positive",
                   fast=int(b["fast"]), slow=int(b["slow"]), nb_min_sharpe=float(b["nb_min_sharpe"]),
                   med_sharpe=float(b["med_sharpe"]), share_pos=float(b["share_pos"]),
                   share_beat_bh=float(b.get("share_beat_bh", np.nan)), med_calmar=float(b["med_calmar"]),
                   med_dd=float(b["med_dd"]), trades_yr=float(b["med_rt_yr"]), n_considered=int(len(sel)))
    unc = x.sort_values("nb_min_sharpe", ascending=False).iloc[0]
    res["unconstrained"] = dict(fast=int(unc["fast"]), slow=int(unc["slow"]),
                                nb_min_sharpe=float(unc["nb_min_sharpe"]), med_sharpe=float(unc["med_sharpe"]),
                                trades_yr=float(unc["med_rt_yr"]))
    rawbest = x.sort_values("med_sharpe", ascending=False).iloc[0]
    res["raw_median_sharpe_best"] = dict(fast=int(rawbest["fast"]), slow=int(rawbest["slow"]),
                                         med_sharpe=float(rawbest["med_sharpe"]),
                                         nb_min_sharpe=float(rawbest["nb_min_sharpe"]),
                                         trades_yr=float(rawbest["med_rt_yr"]))
    # same thing judged on Calmar
    if "nb_min_calmar" in x:
        y = x[edge & act].dropna(subset=["nb_min_calmar"])
        if len(y):
            c = y.sort_values("nb_min_calmar", ascending=False).iloc[0]
            res["calmar_rule"] = dict(fast=int(c["fast"]), slow=int(c["slow"]), nb_min_calmar=float(c["nb_min_calmar"]),
                                       med_calmar=float(c["med_calmar"]), med_sharpe=float(c["med_sharpe"]),
                                       share_pos=float(c["share_pos"]), trades_yr=float(c["med_rt_yr"]))
    OUT[f"best_{mode}"] = res
    print(f"\n[{mode}] constrained practical optimum: {res.get('fast')}/{res.get('slow')} "
          f"(nb_min {res.get('nb_min_sharpe'):.3f}); unconstrained {res['unconstrained']['fast']}/"
          f"{res['unconstrained']['slow']}; raw-best {res['raw_median_sharpe_best']['fast']}/"
          f"{res['raw_median_sharpe_best']['slow']}")
    return res


POPULAR_FAST = [5, 8, 9, 10, 12, 13, 15, 20, 21, 25, 30, 35, 40, 50, 55, 60, 80, 100, 120]
POPULAR_SLOW = [20, 26, 30, 50, 55, 60, 100, 120, 150, 200, 210, 250, 300, 380, 400]


def given_your(a, mode):
    """If you insist on THIS fast line, what slow line is best (and what does it buy you)?"""
    rows = []
    for f_ in POPULAR_FAST:
        d = a[a["fast"] == f_]
        if d.empty:
            continue
        bb = d.sort_values("nb_min_sharpe", ascending=False).iloc[0]
        rb = d.sort_values("med_sharpe", ascending=False).iloc[0]
        wrst = d.sort_values("med_sharpe").iloc[0]
        rows.append(dict(fast=f_, best_slow_robust=int(bb["slow"]), nb_min_robust=round(float(bb["nb_min_sharpe"]), 3),
                         med_sharpe_robust=round(float(bb["med_sharpe"]), 3), share_pos_robust=round(float(bb["share_pos"]), 3),
                         best_slow_raw=int(rb["slow"]), med_sharpe_raw=round(float(rb["med_sharpe"]), 3),
                         trades_yr=round(float(rb["med_rt_yr"]), 2),
                         worst_slow_on_surface=int(wrst["slow"]), med_sharpe_worst=round(float(wrst["med_sharpe"]), 3)))
    w(pd.DataFrame(rows), f"given_your_fast_{mode}")
    rows = []
    for s_ in POPULAR_SLOW:
        d = a[a["slow"] == s_]
        if d.empty:
            continue
        bb = d.sort_values("nb_min_sharpe", ascending=False).iloc[0]
        rb = d.sort_values("med_sharpe", ascending=False).iloc[0]
        rows.append(dict(slow=s_, best_fast_robust=int(bb["fast"]), nb_min_robust=round(float(bb["nb_min_sharpe"]), 3),
                         med_sharpe_robust=round(float(bb["med_sharpe"]), 3), best_fast_raw=int(rb["fast"]),
                         med_sharpe_raw=round(float(rb["med_sharpe"]), 3),
                         share_pos_robust=round(float(bb["share_pos"]), 3),
                         trades_yr=round(float(rb["med_rt_yr"]), 2)))
    w(pd.DataFrame(rows), f"given_your_slow_{mode}")


def vol_scaling(uni, grids_by_mode):
    """Express each market's favourite slow period in units of its own noise scale."""
    rows = []
    g = grids_by_mode["long"]
    best = RB.per_market_best(g, "sharpe")
    for _, r in best.iterrows():
        s = uni.get(r["asset"])
        if s is None:
            continue
        vol = float(pd.Series(s.rets).std() * np.sqrt(s.ann))
        ac1 = float(pd.Series(s.rets).autocorr(1))
        # "noise half-life" style scale: bars for a 1-sigma move to appear (1/vol^2 in bars)
        rows.append(dict(asset=r["asset"], asset_class=s.asset_class, fast=int(r["fast"]), slow=int(r["slow"]),
                         ann_vol=round(vol, 4), lag1_autocorr=round(ac1, 4),
                         slow_x_vol=round(float(r["slow"]) * vol, 3),
                         slow_over_fast=round(float(r["slow"]) / float(r["fast"]), 2),
                         months_slow=round(float(r["slow"]) * (s.ann / 252) / 21.0, 2),
                         sharpe=round(float(r["sharpe"]), 3)))
    d = pd.DataFrame(rows)
    w(d.sort_values("slow", ascending=False), "per_market_optimum_scaled")
    OUT["scaling"] = dict(corr_slow_vol=float(d[["slow", "ann_vol"]].corr().iloc[0, 1]),
                          corr_slow_x_vol_autocorr=float(d[["slow_x_vol", "lag1_autocorr"]].corr().iloc[0, 1]),
                          slow_x_vol_median=float(d["slow_x_vol"].median()),
                          slow_x_vol_iqr=[float(d["slow_x_vol"].quantile(.25)), float(d["slow_x_vol"].quantile(.75))],
                          months_slow_median=float(d["months_slow"].median()),
                          months_slow_iqr=[float(d["months_slow"].quantile(.25)), float(d["months_slow"].quantile(.75))],
                          ratio_median=float(d["slow_over_fast"].median()),
                          ratio_iqr=[float(d["slow_over_fast"].quantile(.25)), float(d["slow_over_fast"].quantile(.75))],
                          best_sharpe_by_class=d.groupby("asset_class")["sharpe"].median().round(2).to_dict())
    print("\nvol-scaled: median best slow = %.1f months (IQR %.1f-%.1f); median slow/fast ratio %.1f; "
          "slow x vol median %.2f (IQR %.2f-%.2f)"
          % (OUT["scaling"]["months_slow_median"], *OUT["scaling"]["months_slow_iqr"],
             OUT["scaling"]["ratio_median"], OUT["scaling"]["slow_x_vol_median"], *OUT["scaling"]["slow_x_vol_iqr"]))
    return d


def main():
    os.makedirs(TAB, exist_ok=True)
    os.makedirs(FIG, exist_ok=True)
    uni = load_universe(exclude=("macro", "fx_spot_ctrl"), verbose=False)
    grids, aggs = {}, {}
    tags = {"": "base", "_ext": "ext"}
    for tag, lab in tags.items():
        p = os.path.join(RES, f"grid_ema_long{tag}.parquet")
        if not os.path.exists(p):
            print(f"  (skipping {lab}: not computed yet)")
            continue
        for mode in ("long", "ls"):
            g = pd.read_parquet(os.path.join(RES, f"grid_ema_{mode}{tag}.parquet"))
            bh = pd.read_csv(os.path.join(RES, "buy_and_hold.csv"))
            a = RB.aggregate(g, bh, min_markets=max(20, int(0.5 * len(uni))))
            plat = RB.plateau_stats(a, "med_sharpe", 4, 16)
            plcal = RB.plateau_stats(a, "med_calmar", 4, 16)
            a = (a.merge(plat[["fast", "slow", "nb_min", "nb_median", "spike"]], on=["fast", "slow"])
                  .rename(columns={"nb_min": "nb_min_sharpe", "nb_median": "nb_med_sharpe", "spike": "spike_sharpe"})
                  .merge(plcal[["fast", "slow", "nb_min"]].rename(columns={"nb_min": "nb_min_calmar"}),
                         on=["fast", "slow"], how="left"))
            grids[f"{lab}_{mode}"] = g
            aggs[f"{lab}_{mode}"] = a
            if lab == "base":
                band_table(a, mode)
                ridge(a, mode)
                given_your(a, mode)
                constrained_best(a, mode)
            else:
                constrained_best(a, mode, min_rt=0.25, max_rt=14.0)
                band_table(a, mode)

    if "base_long" in aggs:
        vol_scaling(uni, {"long": grids["base_long"], "ls": grids["base_ls"]})

    # extended-grid ridge: where does "slower is better" stop?
    if "ext_ls" in aggs:
        for mode in ("long", "ls"):
            a = aggs[f"ext_{mode}"]
            r = a.groupby("slow")["med_sharpe"].max()
            d = pd.DataFrame(dict(slow=r.index, med_sharpe_top_fast=r.to_numpy(),
                                  best_fast=a.loc[a.groupby("slow")["med_sharpe"].idxmax(), "fast"].to_numpy()))
            d["nb_min"] = a.groupby("slow")["nb_min_sharpe"].max().to_numpy()
            w(d.round(4), f"ext_ridge_{mode}")
            OUT[f"ext_ridge_{mode}"] = dict(
                peak_med_sharpe=float(d["med_sharpe_top_fast"].max()),
                peak_slow=int(d.loc[d["med_sharpe_top_fast"].idxmax(), "slow"]),
                last_monotone_slow=int(d[d["med_sharpe_top_fast"] >= d["med_sharpe_top_fast"].max() - 0.01]["slow"].max()),
                at_slow_400=float(d.iloc[(d["slow"] - 400).abs().argsort().iloc[0]]["med_sharpe_top_fast"]))
            print(f"\nextended ridge [{mode}]: peak median Sharpe {OUT[f'ext_ridge_{mode}']['peak_med_sharpe']:.3f} at "
                  f"slow={OUT[f'ext_ridge_{mode}']['peak_slow']}, still >=peak-0.01 up to slow="
                  f"{OUT[f'ext_ridge_{mode}']['last_monotone_slow']}")
            # figure: cross-market median Sharpe vs slow, best fast, for base+ext

    json.dump(OUT, open(os.path.join(RES, "summary_surfaces.json"), "w"), indent=2, default=str)
    print("\nsaved results/summary_surfaces.json")
    print(json.dumps(OUT, indent=2, default=str)[:2500])


if __name__ == "__main__":
    main()
