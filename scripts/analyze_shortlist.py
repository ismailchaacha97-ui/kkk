#!/usr/bin/env python3
"""Stage 4 - decision-level detail for the shortlist: per-class behaviour, rolling-window
consistency, calendar-year hit rate, the cost of using one global pair, and the price of
using a popular-but-wrong pair.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "src"))
from ema_study.data import load_universe, _returns                                        # noqa: E402
from ema_study.engine import evaluate_pair, evaluate_pair_next_open, metrics               # noqa: E402
from ema_study import robust as RB, plots as PL                                           # noqa: E402

RES = os.path.join(HERE, "results")
TAB, FIG = os.path.join(RES, "tables"), os.path.join(RES, "figs")
_FAMOUS = [(12, 26), (9, 21), (20, 50), (50, 200), (10, 20), (21, 55), (5, 35), (200, 400),
           (32, 384), (100, 300)]


def _study_pairs() -> list:
    """The pairs this study actually chose, so the shortlist never lags behind the search.

    Hard-coding the candidates here once left the per-class and consistency tables reviewing
    58/160 after the corrected run had moved the answer to 60/132 - the tables below are only
    evidence if they are computed on the pair the study is recommending.
    """
    out: list = []
    p = os.path.join(RES, "summary.json")
    if os.path.exists(p):
        S = json.load(open(p))
        for k in ("robust_best_long", "raw_best_long", "robust_best_ls", "raw_best_ls"):
            d = S.get(k) or {}
            if d.get("fast"):
                out.append((int(d["fast"]), int(d["slow"])))
        t = os.path.join(TAB, "top40_robust_long.csv")
        if os.path.exists(t):
            q = pd.read_csv(t).head(6)
            out += list(zip(q["fast"].astype(int), q["slow"].astype(int)))
    return out


PAIRS = sorted(set(_study_pairs()) | set(_FAMOUS))
OUT: dict = {}


def w(df, name):
    df.to_csv(os.path.join(TAB, f"{name}.csv"), index=False)
    try:
        open(os.path.join(TAB, f"{name}.md"), "w").write(df.to_markdown(index=False) + "\n")
    except Exception:
        open(os.path.join(TAB, f"{name}.md"), "w").write(df.to_string(index=False) + "\n")
    return df


def main():
    os.makedirs(TAB, exist_ok=True)
    os.makedirs(FIG, exist_ok=True)
    uni = load_universe(exclude=("macro", "fx_spot_ctrl"), verbose=False)
    bh = pd.read_csv(os.path.join(RES, "buy_and_hold.csv")).set_index("asset")
    # carry the buy&hold benchmark onto every grid row so any block can ask "did timing pay?"
    grid = {m: pd.read_parquet(os.path.join(RES, f"grid_ema_{m}.parquet")).merge(
                bh[["bh_sharpe", "bh_cagr", "bh_calmar"]], left_on="asset", right_index=True,
                how="left")
            for m in ("long", "ls")}

    # ---------------------------------------------------- 1. per-pair, per-asset-class table
    rows = []
    for (f_, s_) in PAIRS:
        for mode in ("long", "ls"):
            g = grid[mode]
            q = g[(g["fast"] == f_) & (g["slow"] == s_)].copy()
            if q.empty:
                continue
            q["cls"] = q["asset_class"]
            for cls, d in q.groupby("cls"):
                rows.append(dict(pair=f"{f_}/{s_}", mode=mode, asset_class=cls, markets=len(d),
                                 med_sharpe=float(d["sharpe"].median()),
                                 share_pos=float((d["sharpe"] > 0).mean()),
                                 med_cagr=float(d["cagr"].median()), med_dd=float(d["max_dd"].median()),
                                 med_calmar=float(d["calmar"].median()),
                                 med_bh_sharpe=float(d["bh_sharpe"].median()) if "bh_sharpe" in d else np.nan,
                                 beat_bh=float((d["sharpe"] > d["bh_sharpe"]).mean()) if "bh_sharpe" in d else np.nan))
    pc = pd.DataFrame(rows)
    w(pc.round(3), "pair_by_asset_class")
    OUT["pair_by_class_long"] = (pc[pc["mode"] == "long"].pivot_table(index="asset_class", columns="pair",
                                                                      values="med_sharpe").round(2).to_dict())

    # ------------------------------------------------- 2. rolling 3y consistency per market
    rows = []
    for (f_, s_) in [(58, 160), (40, 116), (60, 130), (12, 26), (9, 21), (20, 50), (50, 200)]:
        for mode in ("long", "ls"):
            for k, s in uni.items():
                px = s.close
                r = []
                lo = px.index[0]
                while lo + pd.DateOffset(years=3) <= px.index[-1]:
                    hi = lo + pd.DateOffset(years=3)
                    seg = px[(px.index >= lo) & (px.index < hi)]
                    if len(seg) > 700:
                        m, *_ = evaluate_pair(seg, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                              cost_bps=s.cost_bps, mode=mode, warmup=False)
                        if np.isfinite(m["sharpe"]):
                            r.append(float(m["sharpe"]))
                    lo = lo + pd.DateOffset(years=1)
                if len(r) >= 3:
                    rows.append(dict(pair=f"{f_}/{s_}", mode=mode, asset=k, windows=len(r),
                                     med_3y_sharpe=float(np.median(r)),
                     share_pos_3y=float(np.mean(np.array(r) > 0)),
                     share_3y_above_0p5=float(np.mean(np.array(r) > 0.5))))
    rw = pd.DataFrame(rows)
    agg = (rw.groupby(["pair", "mode"]).agg(markets=("asset", "nunique"),
                                            med_of_median_3y=("med_3y_sharpe", "median"),
                                            share_windows_positive=("share_pos_3y", "mean")).reset_index())
    w(agg.round(3), "rolling_3y_consistency")
    OUT["rolling3y"] = agg.round(3).to_dict("records")
    print("\nrolling 3-year windows, median over markets:")
    print(agg.round(3).to_string(index=False))

    # ------------------------------------------- 3. calendar-year hit rate of the trend book
    W = None   # full history, equal weight among the markets alive each day
    rows, curves = [], {}
    for (f_, s_) in PAIRS:
        for mode in ("long", "ls"):
            m, cur = RB.trend_book(uni, f_, s_, mode=mode, span=W, vol_target=0.10)
            if not m:
                continue
            yr = cur.groupby(cur.index.year).apply(lambda x: float(np.prod(1 + x) - 1))
            rows.append(dict(pair=f"{f_}/{s_}", mode=mode, sharpe=m["sharpe"], cagr=m["cagr"], max_dd=m["max_dd"],
                             calmar=m["calmar"], vol=m["ann_vol"], years=len(yr),
                             share_years_positive=float((yr > 0).mean()), worst_year=float(yr.min()),
                             best_year=float(yr.max()), median_year=float(yr.median())))
    bt = pd.DataFrame(rows)
    w(bt.round(3), "trend_book_years")
    print("\nequal-weight vol-targeted trend book (full history per market), by calendar year:")
    print(bt[bt["mode"] == "long"].sort_values("sharpe", ascending=False).round(3).to_string(index=False))
    OUT["trend_book_years"] = bt.round(3).to_dict("records")

    # --------------------------------- 4. what one global pair costs vs per-market optimisers
    b_long = RB.per_market_best(grid["long"], "sharpe")
    q = grid["long"]
    _S = json.load(open(os.path.join(RES, "summary.json"))) if os.path.exists(
        os.path.join(RES, "summary.json")) else {}
    cmp_pairs = []
    for key, lab in (("robust_best_long", "study robust pick"), ("raw_best_long", "study raw best Sharpe")):
        d = _S.get(key) or {}
        if d.get("fast"):
            cmp_pairs.append(((int(d["fast"]), int(d["slow"])), lab))
    cmp_pairs += [((12, 26), "12/26 MACD"), ((50, 200), "50/200 golden cross"), ((20, 50), "20/50")]
    for pair, lab in cmp_pairs:
        s_ = q[(q["fast"] == pair[0]) & (q["slow"] == pair[1])]
        if not len(s_):
            continue
        merged = s_.merge(b_long[["asset", "sharpe"]].rename(columns={"sharpe": "is_best_sharpe"}), on="asset")
        OUT.setdefault("global_vs_per_market", []).append(dict(
            pair=f"{pair[0]}/{pair[1]}", label=lab, markets=len(merged),
            med_sharpe_global=float(merged["sharpe"].median()),
            med_sharpe_per_market_is_best=float(merged["is_best_sharpe"].median()),
            share_as_good_as_own_best=float((merged["sharpe"] >= 0.9 * merged["is_best_sharpe"]).mean()),
            median_capture_ratio=float((merged["sharpe"] / merged["is_best_sharpe"].abs().clip(lower=1e-6)).median())))
    w(pd.DataFrame(OUT["global_vs_per_market"]).round(3), "global_vs_per_market")
    print("\none global pair vs each market's own in-sample optimum:")
    print(pd.DataFrame(OUT["global_vs_per_market"]).round(3).to_string(index=False))

    # ---------------------------------------------------- 5. SPY/QQQ style "home market" view
    home = [k for k in ("index/^GSPC", "index/^IXIC", "etf/SPY", "etf/QQQ", "stock/AAPL", "stock/MSFT",
                        "fut_equity/DAX", "fut_commodity/GOLD", "fx_futures/JPY", "crypto/BTC_20_26") if k in uni]
    rows = []
    for k in home:
        s = uni[k]
        for (f_, s_) in PAIRS:
            for mode in ("long", "ls"):
                m, *_ = evaluate_pair(s.close, f_, s_, adjustment=s.adjustment, ann=s.ann,
                                      cost_bps=s.cost_bps, mode=mode)
                rows.append(dict(asset=k, pair=f"{f_}/{s_}", mode=mode, sharpe=m["sharpe"], cagr=m["cagr"],
                                 max_dd=m["max_dd"], calmar=m["calmar"], trades=float(m["round_trips"]),
                                 years=round(s.n / s.ann, 1)))
        b = buyhold_row(s)
        rows.append(dict(asset=k, pair="buy & hold", mode="-", sharpe=b["sharpe"], cagr=b["cagr"],
                         max_dd=b["max_dd"], calmar=b["calmar"], trades=np.nan, years=round(s.n / s.ann, 1)))
    hm = pd.DataFrame(rows)
    w(hm.round(3), "home_markets")
    print("\nthe markets people actually ask about (long/flat):")
    print(hm[hm["mode"] == "long"].pivot_table(index="asset", columns="pair", values="sharpe").round(2).to_string())
    json.dump(OUT, open(os.path.join(RES, "summary_shortlist.json"), "w"), indent=2, default=str)


def buyhold_row(s):
    r = s.rets
    n = 400
    m = metrics(r[n:][None, :], s.ann, min_bars=250, pos=np.ones((1, len(r) - n)),
                changes=np.zeros((1, len(r) - n), bool)).iloc[0]
    return m.to_dict()


if __name__ == "__main__":
    sys.exit(main())
