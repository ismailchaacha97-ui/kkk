#!/usr/bin/env python3
"""Stage 2 - turn the raw grids into conclusions, tables, figures and a summary.

Reads results/grid_<ma>_<mode><tag>.parquet produced by scripts/run_all.sh and writes:
  results/tables/*.csv|*.md     every table quoted in REPORT.md
  results/figs/*.png            every figure
  results/summary.json          headline numbers (so the report cannot drift from the data)

Selection rule (fixed before looking at the rankings, to keep the search honest):
  * the *headline* pair is the argmax of ``nb_min_sharpe`` = the worst cross-market median
    Sharpe found anywhere inside a +/-4 fast / +/-16 slow neighbourhood of the consensus
    surface.  Maximising the worst neighbour is a max-min rule: it can only be won by a
    broad plateau, never by a spike.
  * the argmax of the raw median Sharpe is reported next to it as the overfit benchmark.
"""
from __future__ import annotations

import json
import os
import sys
import time

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "src"))

from ema_study.data import load_universe, families, hygiene_report, _returns          # noqa: E402
from ema_study.engine import (ema, ema_matrix, metrics, buy_and_hold, trade_stats,     # noqa: E402
                             evaluate_pair, evaluate_pair_next_open, position_from_state)
from ema_study.grid import pair_grid, grid_for_series                                   # noqa: E402
from ema_study import robust as RB                                                      # noqa: E402
from ema_study import plots as PL                                                       # noqa: E402

RES = os.environ.get("KKK_RESULTS", os.path.join(HERE, "results"))
TAB, FIG = os.path.join(RES, "tables"), os.path.join(RES, "figs")
S: dict = {}


def wtable(df: pd.DataFrame, name: str, md: bool = True) -> pd.DataFrame:
    df.to_csv(os.path.join(TAB, f"{name}.csv"), index=False)
    if md:
        try:
            txt = df.to_markdown(index=False)
        except Exception:                                     # tabulate missing
            txt = df.to_string(index=False)
        with open(os.path.join(TAB, f"{name}.md"), "w") as fh:
            fh.write(txt + "\n")
    return df


def load_variant(mode, ma="ema", tag=""):
    p = os.path.join(RES, f"grid_{ma}_{mode}{tag}.parquet")
    return pd.read_parquet(p) if os.path.exists(p) else pd.DataFrame()


def main() -> None:
    def _fig(fn, *a, **kw):
        try:
            fn(*a, **kw)
        except Exception as e:                                      # noqa: BLE001
            print(f"   !! figure {fn.__name__} failed: {type(e).__name__}: {str(e)[:120]}")

    for d in (TAB, FIG):
        os.makedirs(d, exist_ok=True)
    t0 = time.time()
    uni = load_universe(exclude=("macro", "fx_spot_ctrl"), verbose=False)
    bh = pd.read_csv(os.path.join(RES, "buy_and_hold.csv"))
    S["n_markets"] = len(uni)
    S["families"] = {k: len(v) for k, v in families(uni).items()}
    S["bars_per_market_median"] = float(np.median([s.n for s in uni.values()]))
    S["history_span"] = [str(min(s.close.index[0].date() for s in uni.values())),
                         str(max(s.close.index[-1].date() for s in uni.values()))]
    print(f"universe: {len(uni)} markets  ({S['families']})")

    grids = {}
    for mode in ("long", "ls"):
        g = load_variant(mode)
        if g.empty:
            sys.exit(f"!! missing grid for mode={mode} - run scripts/run_all.sh first")
        grids[mode] = g
        S[f"rows_{mode}"] = int(len(g))
        S[f"pairs"] = int(g[["fast", "slow"]].drop_duplicates().shape[0])
        S[f"bt_tests_{mode}"] = int(len(g))
        print(f"  grid[{mode}]: {len(g):,} backtests over {S['pairs']} pairs x {g['asset'].nunique()} markets")
    S["total_backtests"] = int(sum(S[f"bt_tests_{m}"] for m in grids))

    wtable(hygiene_report(), "data_hygiene", md=False)

    # -------------------------------------------------- 1. what each market would pick alone
    g = grids["ls"]
    best_mkt = RB.per_market_best(g, "sharpe").merge(bh[["asset", "bh_sharpe", "bh_cagr", "bh_dd"]],
                                                    on="asset", how="left")
    best_mkt["ann_vol"] = best_mkt["asset"].map({k: s.rets.std() * np.sqrt(s.ann) for k, s in uni.items()})
    best_mkt["lag1_autocorr"] = best_mkt["asset"].map({k: float(pd.Series(s.rets).autocorr(1)) for k, s in uni.items()})
    best_mkt["years"] = best_mkt["asset"].map({k: round(s.n / s.ann, 1) for k, s in uni.items()})
    best_mkt["ratio"] = (best_mkt["slow"] / best_mkt["fast"]).round(2)
    cols = ["asset", "asset_class", "fast", "slow", "ratio", "sharpe", "cagr", "max_dd", "calmar",
            "bh_sharpe", "bh_cagr", "ann_vol", "lag1_autocorr", "years"]
    wtable(best_mkt[cols].round(3), "best_pair_per_market")
    S["per_market"] = dict(
        best_slow_median=float(best_mkt["slow"].median()), best_slow_min=int(best_mkt["slow"].min()),
        best_slow_max=int(best_mkt["slow"].max()),
        best_slow_iqr=[float(best_mkt["slow"].quantile(.25)), float(best_mkt["slow"].quantile(.75))],
        best_fast_median=float(best_mkt["fast"].median()),
        share_slow_ge_100=float((best_mkt["slow"] >= 100).mean()),
        share_slow_le_30=float((best_mkt["slow"] <= 30).mean()),
        share_beats_bh_at_own_best=float((best_mkt["sharpe"] > best_mkt["bh_sharpe"]).mean()),
        median_sharpe_of_is_winner=float(best_mkt["sharpe"].median()),
        corr_slow_vs_vol=float(best_mkt[["slow", "ann_vol"]].corr().iloc[0, 1]),
        corr_slow_vs_autocorr=float(best_mkt[["slow", "lag1_autocorr"]].corr().iloc[0, 1]),
    )
    print("\nper-market in-sample winner: slow median %.0f bars (IQR %.0f-%.0f, max %d). "
          "%.0f%% of markets pick slow>=100, %.0f%% pick slow<=30."
          % (S["per_market"]["best_slow_median"], *S["per_market"]["best_slow_iqr"],
             S["per_market"]["best_slow_max"], 100 * S["per_market"]["share_slow_ge_100"],
             100 * S["per_market"]["share_slow_le_30"]))

    # ---------------------------------------------- 2. cross-market consensus + plateau rule
    robust_tbl, agg_tbl = {}, {}
    for mode, gg in grids.items():
        agg = RB.aggregate(gg, bh, min_markets=max(20, int(0.5 * len(uni))))
        plat = RB.plateau_stats(agg, "med_sharpe", fast_pm=4, slow_pm=16)
        plcal = RB.plateau_stats(agg, "med_calmar", fast_pm=4, slow_pm=16)
        plsh = RB.plateau_stats(agg, "med_sharpe", fast_pm=8, slow_pm=32).rename(
            columns={"nb_min": "nb_min_wide", "nb_median": "nb_median_wide"})
        qs = RB.top_quartile_share(gg)
        a = (agg.merge(plat[["fast", "slow", "nb_min", "nb_median", "spike"]], on=["fast", "slow"], how="left")
                .rename(columns={"nb_min": "nb_min_sharpe", "nb_median": "nb_med_sharpe", "spike": "spike_sharpe"})
                .merge(plcal[["fast", "slow", "nb_min"]].rename(columns={"nb_min": "nb_min_calmar"}),
                       on=["fast", "slow"], how="left")
                .merge(plsh[["fast", "slow", "nb_min_wide", "nb_median_wide"]], on=["fast", "slow"], how="left")
                .merge(qs, on=["fast", "slow"], how="left"))
        a["robust_score"] = a["nb_min_sharpe"]
        a["is_rank"] = a["med_sharpe"].rank(ascending=False).astype(int)
        a["robust_rank"] = a["robust_score"].rank(ascending=False).astype(int)
        robust_tbl[mode] = a
        agg_tbl[mode] = agg
        wtable(a.round(4), f"pair_robustness_{mode}", md=False)
        S[f"surface_smoothness_{mode}"] = RB.surface_smoothness(a, "med_sharpe")
        show = ["fast", "slow", "nb_min_sharpe", "med_sharpe", "share_pos", "share_beat_bh",
                "med_calmar", "med_dd", "med_rt_yr", "markets", "robust_rank", "is_rank"]
        top = a.sort_values("robust_score", ascending=False)
        print(f"\n=== mode={mode}: top 10 by the max-min plateau rule ===")
        print(top[show].head(10).round(3).to_string(index=False))
        raw = a.sort_values("med_sharpe", ascending=False)
        print(f"--- top 6 by raw median Sharpe (what a naive grid search would hand you) ---")
        print(raw[show].head(6).round(3).to_string(index=False))
        wtable(top[show].head(40).round(4), f"top40_robust_{mode}")
        wtable(raw[show].head(40).round(4), f"top40_insample_{mode}", md=False)
        for key, row in ((f"robust_best_{mode}", top.iloc[0]), (f"raw_best_{mode}", raw.iloc[0])):
            S[key] = dict(fast=int(row["fast"]), slow=int(row["slow"]), med_sharpe=float(row["med_sharpe"]),
                          nb_min=float(row["nb_min_sharpe"]), share_pos=float(row["share_pos"]),
                          share_beat_bh=float(row.get("share_beat_bh", np.nan)),
                          med_calmar=float(row["med_calmar"]), med_dd=float(row["med_dd"]),
                          med_cagr=float(row["med_cagr"]), trades_per_year=float(row["med_rt_yr"]),
                          spike=float(row["spike_sharpe"]))
        # how far apart are the two answers?
        S[f"is_vs_robust_gap_{mode}"] = dict(
            med_sharpe_of_robust_pick=float(top.iloc[0]["med_sharpe"]),
            best_possible=float(raw.iloc[0]["med_sharpe"]),
            rank_of_robust_pick_in_raw=int(top.iloc[0]["is_rank"]),
            rank_of_raw_pick_in_robust=int(raw.iloc[0]["robust_rank"]),
            nb_min_of_raw_pick=float(raw.iloc[0]["nb_min_sharpe"]))

    # ------------------------------------------------------- 3. famous pairs vs the found pair
    rows = []
    for f_, s_, lab in PL.FAMOUS:
        for mode in ("long", "ls"):
            sub = grids[mode]
            q = sub[(sub["fast"] == f_) & (sub["slow"] == s_)]
            if q.empty:
                continue
            a = robust_tbl[mode]
            r = a[(a["fast"] == f_) & (a["slow"] == s_)]
            rows.append(dict(pair=f"{f_}/{s_}", label=lab, fast=f_, slow=s_, mode=mode,
                             med_sharpe=float(q["sharpe"].median()),
                             share_pos=float((q["sharpe"] > 0).mean()),
                             share_beat_bh=float(r["share_beat_bh"].iloc[0]) if len(r) else np.nan,
                             med_cagr=float(q["cagr"].median()), med_dd=float(q["max_dd"].median()),
                             med_calmar=float(q["calmar"].median()),
                             nb_min_sharpe=float(r["nb_min_sharpe"].iloc[0]) if len(r) else np.nan,
                             rank_raw=int(r["is_rank"].iloc[0]) if len(r) else -1,
                             rank_robust=int(r["robust_rank"].iloc[0]) if len(r) else -1))
    for mode, a in robust_tbl.items():                       # add the study's own picks
        for _, r in pd.concat([a.sort_values("robust_score", ascending=False).head(3),
                              a.sort_values("med_sharpe", ascending=False).head(2)]).iterrows():
            rows.append(dict(pair=f"{int(r['fast'])}/{int(r['slow'])}",
                             label=("STUDY robust pick" if r["robust_rank"] == 1 else
                                    ("study top-3 robust" if r["robust_score"] > 0 else "study IS-best")),
                             fast=int(r["fast"]), slow=int(r["slow"]), mode=mode,
                             med_sharpe=float(r["med_sharpe"]), share_pos=float(r["share_pos"]),
                             share_beat_bh=float(r["share_beat_bh"]), med_cagr=float(r["med_cagr"]),
                             med_dd=float(r["med_dd"]), med_calmar=float(r["med_calmar"]),
                             nb_min_sharpe=float(r["nb_min_sharpe"]), rank_raw=int(r["is_rank"]),
                             rank_robust=int(r["robust_rank"])))
    ftab = pd.DataFrame(rows).drop_duplicates(subset=["pair", "mode"]).sort_values(
        ["mode", "nb_min_sharpe"], ascending=[True, False])
    wtable(ftab.round(3), "famous_vs_found")
    print("\n=== famous settings vs the study's picks (long/short) ===")
    print(ftab[ftab["mode"] == "ls"][["pair", "label", "med_sharpe", "nb_min_sharpe", "share_pos",
                                     "share_beat_bh", "med_calmar", "rank_raw", "rank_robust"]]
          .round(3).to_string(index=False))

    # ---------------------------------------------------------------- 4. walk-forward OOS
    cand = {}
    for mode, a in robust_tbl.items():
        for _, r in pd.concat([a.sort_values("robust_score", ascending=False).head(12),
                              a.sort_values("med_sharpe", ascending=False).head(6)]).iterrows():
            cand.setdefault((int(r["fast"]), int(r["slow"])), f"cand_{mode}")
    for f_, s_, _lab in PL.FAMOUS:
        cand.setdefault((f_, s_), "famous")
    print(f"\nwalk-forward over {len(uni)} markets x {len(cand)} candidate pairs ...", flush=True)
    f_idx, s_idx = pair_grid(120, 400, 4, 6, 1.5)
    # the walk-forward must judge OUR picks, not just the alphabetically-first candidates
    priority = [(S["robust_best_ls"]["fast"], S["robust_best_ls"]["slow"]),
                (S["robust_best_long"]["fast"], S["robust_best_long"]["slow"]),
                (S["raw_best_ls"]["fast"], S["raw_best_ls"]["slow"]),
                (S["raw_best_long"]["fast"], S["raw_best_long"]["slow"])]
    priority += [(f_, s_) for f_, s_, _l in PL.FAMOUS]
    priority += [(40, 100), (100, 200), (200, 400), (60, 180), (50, 150), (30, 90)]
    fixed = [p for p in dict.fromkeys(priority) if p in cand]
    rest = [p for p in sorted(cand) if p not in fixed]
    fixed = (fixed + rest)[:24]
    print(f"   walk-forward judging {len(fixed)} fixed pairs + the per-fold grid optimum")
    wf = {}
    t = time.time()
    for mode in grids:
        ft, fs = RB.walk_forward(uni, f_idx, s_idx, n_folds=6, mode=mode, fixed_pairs=fixed, progress=True)
        wf[mode] = (ft, fs)
        ft.to_csv(os.path.join(TAB, f"walk_forward_folds_{mode}.csv"), index=False)
        wtable(fs.round(3), f"walk_forward_summary_{mode}")
        print(f"\n[{mode}] walk-forward summary:\n" + fs.round(3).to_string(index=False))
    S["walk_forward"] = {m: wf[m][1].to_dict("records") for m in wf}
    ft_ls = wf["ls"][0]
    S["wf_stats"] = dict(
        folds=len(ft_ls), markets=int(ft_ls["asset"].nunique()),
        is_winner_med_oos=float(ft_ls["oos_of_is_best"].median()),
        is_winner_med_is=float(ft_ls["is_sharpe"].median()),
        oracle_med_oos=float(ft_ls["oos_oracle"].median()),
        median_pair_med_oos=float(ft_ls["oos_median"].median()),
        decay_pct=float(1 - ft_ls["oos_of_is_best"].median() / max(ft_ls["is_sharpe"].median(), 1e-9)),
        share_oos_positive=float((ft_ls["oos_of_is_best"] > 0).mean()),
        share_is_winner_positive=float((ft_ls["is_sharpe"] > 0).mean()),
        corr_is_oos=float(ft_ls[["is_sharpe", "oos_of_is_best"]].corr().iloc[0, 1]),
    )
    print(f"   walk-forward took {time.time()-t:.0f}s; IS winner median {S['wf_stats']['is_winner_med_is']:.2f} "
          f"-> OOS {S['wf_stats']['is_winner_med_oos']:.2f} ({S['wf_stats']['decay_pct']:.0%} decay)")
    _fig(PL.is_vs_oos,ft_ls, os.path.join(FIG, "fig_is_oos.png"))
    wtable(ft_ls[["asset", "fold", "test", "best_fast", "best_slow", "is_sharpe", "oos_of_is_best",
                  "oos_oracle", "oos_median"]].round(3), "walk_forward_winners", md=False)

    # ------------------------------------------- 4b. global split-sample: would the RULE work?
    # walk_forward re-selects per market inside short folds, which structurally cannot judge a
    # slow EMA longer than a fold.  This block instead splits every market's *whole* history at
    # 60%, ranks all candidate pairs using only the first 60% with the same cross-market rules
    # used to pick the study's answer, and then reads off what those picks earned on the 40%
    # that was never consulted.  It is the closest thing here to time travel for the headline.
    print("\nsplit-sample OOS (rank on the first 60% of history, score on the last 40%) ...", flush=True)
    cands = {(int(S["robust_best_long"]["fast"]), int(S["robust_best_long"]["slow"])),
             (int(S["raw_best_long"]["fast"]), int(S["raw_best_long"]["slow"])),
             (int(S["robust_best_ls"]["fast"]), int(S["robust_best_ls"]["slow"])),
             (int(S["raw_best_ls"]["fast"]), int(S["raw_best_ls"]["slow"]))}
    cands |= {(f_, s_) for f_, s_, _l in PL.FAMOUS}
    cands |= {(40, 100), (100, 200), (200, 400), (60, 180), (50, 150), (30, 90), (60, 120)}
    cands |= {(30, 200), (10, 30), (20, 60), (5, 20), (100, 250)}          # short / silly controls
    cands |= {(100, 300), (100, 400), (150, 400), (150, 500), (200, 600),  # the slow frontier
              (60, 400), (80, 300), (150, 710), (174, 698), (162, 678), (74, 758), (62, 758)}
    surf_p = os.path.join(RES, "summary_surfaces.json")
    if os.path.exists(surf_p):                                              # ext-grid picks, if run
        try:
            U = json.load(open(surf_p))
            for k in ("best_long", "best_ls"):
                d = U.get(k) or {}
                if "fast" in d:
                    cands.add((int(d["fast"]), int(d["slow"])))
                for sub in ("calmar_rule", "raw_median_sharpe_best"):
                    e = d.get(sub) or {}
                    if "fast" in e:
                        cands.add((int(e["fast"]), int(e["slow"])))
        except Exception as e:                                              # noqa: BLE001
            print(f"   (no surface file: {e})")
    cands = {p for p in cands if p[1] > p[0] >= 2}
    print(f"   {len(cands)} pairs judged on {len(uni)} markets", flush=True)
    t = time.time()
    splits = {}
    for mode in grids:
        sp = RB.split_sample(uni, sorted(cands), mode=mode, cut=0.6, progress=True)
        gsum = RB.summarise_split(sp)
        splits[mode] = (sp, gsum)
        sp.to_csv(os.path.join(TAB, f"split_sample_{mode}.csv"), index=False)
        show = ["fast", "slow", "markets", "med_is", "nb_is", "med_oos", "pos_oos",
                "med_oos_calmar", "med_oos_dd", "med_bh_oos", "rank_is", "rank_oos", "picked"]
        wtable(gsum[show].round(3), f"split_sample_summary_{mode}", md=True)
        print(f"\n[{mode}] split-sample: what a 60%-of-history pick would have earned on the rest\n"
              + gsum[show].head(14).round(3).to_string(index=False))
        S[f"split_{mode}"] = dict(
            pairs=len(gsum), markets=int(sp["asset"].nunique()),
            cut="first 60% of each market's history used for selection",
            med_is_best=float(gsum["med_is"].max()), med_oos_of_is_best=
            float(gsum.loc[int(gsum["med_is"].idxmax()), "med_oos"]),
            med_oos_of_robust_pick=float(gsum.loc[int(gsum["nb_is"].idxmax()), "med_oos"]),
            nb_is_of_robust_pick=float(gsum["nb_is"].max()),
            med_oos_cheating_pick=float(gsum.loc[int(gsum["med_oos"].idxmax()), "med_oos"]),
            median_pair_oos=float(gsum["med_oos"].median()),
            corr_is_oos=float(gsum[["med_is", "med_oos"]].corr().iloc[0, 1]),
            rank_corr_is_oos=float(gsum[["rank_is", "rank_oos"]].corr(method="spearman").iloc[0, 1]),
            bh_oos=float(gsum["med_bh_oos"].median()),
            rows=len(sp),
        )
        pick_row = gsum.loc[int(gsum["nb_is"].idxmax())]
        S[f"split_{mode}"]["picked"] = dict(fast=int(pick_row["fast"]), slow=int(pick_row["slow"]),
                                            picked=str(pick_row["picked"]))
        # annotate each candidate with a group so the scatter is readable
        lab = {}
        for f_, s_, nm in PL.FAMOUS:
            lab[(f_, s_)] = "famous"
        for key in ("robust_best_long", "raw_best_long", "robust_best_ls", "raw_best_ls"):
            d = S[key]
            lab[(int(d["fast"]), int(d["slow"]))] = "study pick"
        gg = gsum.assign(group=[lab.get((int(f_), int(s_)), "other") for f_, s_ in zip(gsum["fast"], gsum["slow"])])
        _fig(PL.scatter_vs_prop, gg, "med_is", "med_oos", os.path.join(FIG, f"fig_split_is_oos_{mode}.png"),
             xlabel="median cross-market Sharpe, first 60% of history",
             ylabel="median cross-market Sharpe, untouched last 40%", label="group",
             title=f"{mode}: picking on the past vs what the past-paid-for pair earned")
    print(f"   split-sample took {time.time()-t:.0f}s")

    # ----------------------------------------------------------- 5. deflated Sharpe (DSR)
    n_lit = S["pairs"]
    eff = max(int(n_lit / 40), 60)
    S["n_trials"] = dict(literal=n_lit, effective=eff, total_backtests=S["total_backtests"])
    drows = []
    for (f_, s_) in sorted(set(cand) | {(S["raw_best_ls"]["fast"], S["raw_best_ls"]["slow"]),
                                       (S["robust_best_ls"]["fast"], S["robust_best_ls"]["slow"])}):
        for mode in grids:
            sub = grids[mode]
            q = sub[(sub["fast"] == f_) & (sub["slow"] == s_)]
            if q.empty:
                continue
            n_obs = int(q["n_bars"].median())
            sr = float(q["sharpe"].median())
            d1 = RB.deflated_sharpe(sr, n_obs, n_lit, ann=252)
            d2 = RB.deflated_sharpe(sr, n_obs, eff, ann=252)
            drows.append(dict(pair=f"{f_}/{s_}", fast=f_, slow=s_, mode=mode, med_sharpe=sr,
                              med_cagr=float(q["cagr"].median()), hurdle=d1["hurdle_sharpe"],
                              dsr_literal=d1["dsr"], dsr_effective=d2["dsr"], n_markets=int(len(q)),
                              n_obs=n_obs, se_ann=d2["se_sr_ann"]))
    dt = pd.DataFrame(drows)
    wtable(dt.round(3), "deflated_sharpe")
    S["dsr"] = dt[dt["mode"] == "ls"].set_index("pair")[["med_sharpe", "hurdle", "dsr_literal",
                                                          "dsr_effective"]].round(3).to_dict("index")
    print("\n=== deflated Sharpe (multiple-testing adjusted; best-of-%d-trials hurdle) ===" % n_lit)
    print(dt[dt["mode"] == "ls"].sort_values("med_sharpe", ascending=False).head(8)
          [["pair", "med_sharpe", "hurdle", "dsr_literal", "dsr_effective"]].round(3).to_string(index=False))

    # ------------------------------------------------------------- 6. diversified trend book
    win = RB.book_window(uni, 0.6)
    S["book_dense_window"] = list(win)
    print(f"\ntrend book: full history (equal weight among markets alive each day); "
          f"dense cross-check window {win[0]}..{win[1]}")
    brows, curves = [], {}
    for (f_, s_) in sorted(cand):
        for mode in ("long", "ls"):
            m, cur = RB.trend_book(uni, f_, s_, mode=mode)            # full history, all markets
            if not m:
                continue
            mv, curv = RB.trend_book(uni, f_, s_, mode=mode, vol_target=0.10)
            brows.append(dict(pair=f"{f_}/{s_}", fast=f_, slow=s_, mode=mode,
                              sharpe=m["sharpe"], cagr=m["cagr"], max_dd=m["max_dd"], calmar=m["calmar"],
                              vol=m["ann_vol"], vt_sharpe=mv["sharpe"], vt_cagr=mv["cagr"], vt_dd=mv["max_dd"],
                              vt_calmar=mv["calmar"], markets=m["markets_available"],
                              active_share=m["market_active_share"], bars=m["overlap_bars"],
                              why=cand.get((f_, s_), "")))
            if (f_, s_) in {(S["robust_best_ls"]["fast"], S["robust_best_ls"]["slow"]),
                            (S["raw_best_ls"]["fast"], S["raw_best_ls"]["slow"]), (12, 26), (9, 21), (50, 200),
                            (20, 50)}:
                curves[f"{f_}/{s_} {mode}"] = curv
    btab = pd.DataFrame(brows)
    wtable(btab.round(3), "trend_book")
    print(btab[btab["mode"] == "ls"].sort_values("vt_sharpe", ascending=False).head(10)
          [["pair", "sharpe", "vt_sharpe", "vt_cagr", "vt_dd", "vt_calmar"]].round(3).to_string(index=False))
    # buy & hold benchmark on the same window
    allr = pd.DataFrame({k: pd.Series(s.rets, index=s.close.index[1:]) for k, s in uni.items()})
    bhd = allr.mean(axis=1, skipna=True)
    bhb = metrics(bhd.to_numpy()[None, :], 252, min_bars=250, pos=np.ones((1, len(bhd))),
                  changes=np.zeros((1, len(bhd)), bool)).iloc[0]
    S["bh_book"] = dict(sharpe=float(bhb["sharpe"]), cagr=float(bhb["cagr"]), max_dd=float(bhb["max_dd"]))
    curves["buy & hold, equal-weight book"] = bhd
    print(f"  buy&hold of the same book: Sharpe {bhb['sharpe']:.2f}  CAGR {bhb['cagr']:.1%}  MaxDD {bhb['max_dd']:.0%}")
    _fig(PL.equity_curves,curves, os.path.join(FIG, "fig_equity.png"),
                     title="Equal-weight trend book across all markets, vol-targeted 10% (log scale)")

    # ------------------------------------------------- 7. execution model: close vs next open
    rows = []
    tradable = {k: v for k, v in uni.items() if v.open_px is not None}
    for (f_, s_) in sorted(cand):
        a, b, c = [], [], []
        for k, s in tradable.items():
            px = pd.DataFrame({"close": s.close, "open": s.open_px})
            m0, *_ = evaluate_pair(s.close, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                   cost_bps=s.cost_bps, mode="ls")
            m1 = evaluate_pair_next_open(px, f_, s_, ann=s.ann, cost_bps=s.cost_bps, mode="ls")
            m2, *_ = evaluate_pair(s.close, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                   cost_bps=s.cost_bps * 0, mode="ls")
            if np.isfinite(m0["sharpe"]):
                a.append(float(m0["sharpe"]))
            if m1 and np.isfinite(m1["sharpe"]):
                b.append(float(m1["sharpe"]))
            if np.isfinite(m2["sharpe"]):
                c.append(float(m2["sharpe"]))
        rows.append(dict(pair=f"{f_}/{s_}", markets=len(tradable), med_sharpe_close_exec=float(np.median(a)),
                         med_sharpe_next_open=float(np.median(b)), med_sharpe_no_cost=float(np.median(c)),
                         open_minus_close=float(np.median(b) - np.median(a))))
    xtab = pd.DataFrame(rows).sort_values("med_sharpe_next_open", ascending=False)
    wtable(xtab.round(3), "execution_model")
    S["execution"] = dict(markets=len(tradable),
                          next_open_best=xtab.iloc[0][["pair", "med_sharpe_next_open"]].to_dict(),
                          median_drop_from_close_to_open=float(xtab["open_minus_close"].median()))
    print("\nexecution check (signal close -> trade next open, %d markets with real opens):" % len(tradable))
    print(xtab.head(6).round(3).to_string(index=False))

    # -------------------------------------------------- 8. negative control: contaminated FX
    ctrl = load_universe(exclude=("macro",), verbose=False)
    ctrl = {k: v for k, v in ctrl.items() if k.startswith("fx_spot_ctrl")}
    if ctrl:
        rows = []
        for (f_, s_) in sorted(cand)[:10]:
            vals, vals_clean = [], []
            for k, s in ctrl.items():
                m, *_ = evaluate_pair(s.close, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                      cost_bps=s.cost_bps, mode="ls")
                if np.isfinite(m["sharpe"]):
                    vals.append(float(m["sharpe"]))
            for k, s in uni.items():
                if s.asset_class == "fx_futures":
                    m, *_ = evaluate_pair(s.close, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                          cost_bps=s.cost_bps, mode="ls")
                    if np.isfinite(m["sharpe"]):
                        vals_clean.append(float(m["sharpe"]))
            rows.append(dict(pair=f"{f_}/{s_}", contaminated_fx_spot_med_sharpe=float(np.median(vals)),
                             n_ctrl=len(vals), fx_futures_med_sharpe=float(np.median(vals_clean)), n_clean=len(vals_clean)))
        ntab = pd.DataFrame(rows)
        ntab["inflation"] = ntab["contaminated_fx_spot_med_sharpe"] - ntab["fx_futures_med_sharpe"]
        wtable(ntab.round(3), "negative_control_fx")
        S["negative_control"] = ntab.round(3).to_dict("records")
        print("\nnegative control (stale-timestamp FX spot vs clean FX futures marks):")
        print(ntab.round(2).to_string(index=False))

    # ------------------------------------------------------- 9. sensitivities: cost/bar/MA type
    pan = []
    for (f_, s_) in sorted(cand):
        row = dict(pair=f"{f_}/{s_}", fast=f_, slow=s_)
        for tag, lab in (("", "base"), ("_c0", "zerocost"), ("_c3", "cost3x"), ("_w", "weekly"), ("_sma", "sma")):
            ma = "sma" if lab == "sma" else "ema"
            for mode in ("long", "ls"):
                gg = load_variant(mode, ma, tag)
                if gg.empty:
                    continue
                q = gg[(gg["fast"] == f_) & (gg["slow"] == s_)]
                if q.empty:
                    continue
                row[f"{lab}_{mode}"] = float(q["sharpe"].median())
                row[f"{lab}_{mode}_pos"] = float((q["sharpe"] > 0).mean())
        pan.append(row)
    ptab = pd.DataFrame(pan)
    wtable(ptab.round(3), "sensitivity_panels")
    S["variants_present"] = sorted({c.split("_")[0] for c in ptab.columns if c != "pair"})
    for lab in ("base", "zerocost", "cost3x", "weekly", "sma"):
        c = f"{lab}_ls"
        if c in ptab:
            S[f"median_{lab}"] = float(ptab[c].median())
            S[f"best_{lab}"] = ptab.loc[ptab[c].idxmax(), "pair"]

    # ------------------------------------------------------------------ 10. per-decade check
    decades = sorted({d for s in uni.values()
                      for d in range((s.close.index.min().year // 10) * 10,
                                     (s.close.index.max().year // 10) * 10 + 10, 10)})
    era_rows = []
    for (f_, s_) in sorted(cand):
        r = dict(pair=f"{f_}/{s_}")
        for dec in decades:
            for mode in ("long", "ls"):
                vals = []
                for k, s in uni.items():
                    px = s.close[(s.close.index.year >= dec) & (s.close.index.year < dec + 10)]
                    if len(px) < 500:
                        continue
                    m, *_ = evaluate_pair(px, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                          cost_bps=s.cost_bps, mode=mode)
                    if np.isfinite(m["sharpe"]):
                        vals.append(float(m["sharpe"]))
                if len(vals) >= 5:
                    r[f"{dec}s_{mode}"] = float(np.median(vals))
                    r[f"{dec}s_n"] = len(vals)
        era_rows.append(r)
    etab = pd.DataFrame(era_rows).sort_values("pair")
    wtable(etab.round(2), "by_decade")
    dcols = [c for c in etab.columns if c.endswith("_ls")]
    print("\nmedian Sharpe by decade [long/short]:")
    print(etab.set_index("pair")[dcols].dropna(how="all").round(2).to_string())
    S["decades"] = {"columns": dcols, "rows": etab.round(2).to_dict("records")}

    # --------------------------------------------------------------------------- 11. figures
    with open(os.path.join(RES, "summary.json"), "w") as fh:      # dump BEFORE plotting:
        json.dump(S, fh, indent=2, default=str)                    # a bad figure must not
        print("  summary.json written", flush=True)                # cost a re-run of the study
    print("\nfigures ...", flush=True)
    for mode, a in robust_tbl.items():
        _fig(PL.surface,a, ("med_sharpe", "nb_min_sharpe", "nb_min_calmar"),
                   title={"med_sharpe": f"Median Sharpe across markets  [{mode}]",
                          "nb_min_sharpe": "Worst neighbour (+/-4 fast, +/-16 slow)  [robust rule]",
                          "nb_min_calmar": "Worst-neighbour median Calmar  [robust]"},
                   fname=os.path.join(FIG, f"fig_surface_{mode}.png"))
        _fig(PL.line_by_slow,a, "med_sharpe", os.path.join(FIG, f"fig_lines_{mode}.png"),
                        title=f"Median cross-market Sharpe vs slow EMA  [{mode}]")
        _fig(PL.line_by_slow,a, "nb_min_sharpe", os.path.join(FIG, f"fig_lines_nbmin_{mode}.png"),
                        fasts=(5, 8, 12, 20, 40, 60), title=f"Worst-neighbour Sharpe vs slow  [{mode}]")
    heat = pd.concat([grids[m].assign(mode=m)[["asset", "fast", "slow", "sharpe", "mode"]] for m in grids],
                     ignore_index=True)
    keep = [(f_, s_) for f_, s_ in sorted(cand)][:16]
    heat = heat[heat.set_index(["fast", "slow"]).index.isin(keep)]
    heat["asset"] = heat["asset"] + " [" + heat["mode"] + "]"
    _fig(PL.heat_by_market,heat, keep, os.path.join(FIG, "fig_heat.png"),
                      title="Per-market Sharpe of the robust plateau vs the famous settings")
    _fig(PL.scatter_vs_prop,best_mkt, "ann_vol", "slow", os.path.join(FIG, "fig_optimal_vs_vol.png"),
                       xlabel="annualised volatility of the market", ylabel="in-sample best slow EMA (bars)",
                       label="asset_class", title="The IS-optimal slow period tracks the market, not a magic number")
    _fig(PL.scatter_vs_prop,best_mkt, "lag1_autocorr", "fast", os.path.join(FIG, "fig_optimal_vs_autocorr.png"),
                       xlabel="lag-1 autocorrelation of daily returns", ylabel="in-sample best fast EMA (bars)",
                       label="asset_class", title="How fast your fast line should be depends on serial structure")
    fb = ftab[ftab["mode"] == "ls"].copy()
    fb["label"] = fb["pair"] + "   " + fb["label"].astype(str)
    wtable(fb[["label", "nb_min_sharpe", "med_sharpe"]].sort_values("nb_min_sharpe", ascending=False)
           .round(3), "famous_bars_chart_data", md=False)
    _fig(PL.bar_compare,fb[["label", "nb_min_sharpe"]].dropna(), "nb_min_sharpe",
                   os.path.join(FIG, "fig_famous_bars.png"),
                   title="Worst-neighbour robustness: famous settings vs found ones", hline=0)

    with open(os.path.join(RES, "summary.json"), "w") as fh:
        json.dump(S, fh, indent=2, default=str)
    print(f"\nwrote tables to {TAB}, figures to {FIG}, summary.json ({time.time()-t0:.0f}s)")
    print("\nHEADLINE:", json.dumps({k: S[k] for k in ("robust_best_long", "robust_best_ls", "raw_best_ls",
                                                       "wf_stats", "bh_book", "per_market") if k in S},
                                    indent=2, default=str)[:2000])


if __name__ == "__main__":
    main()
