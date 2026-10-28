#!/usr/bin/env python3
"""
Build the validation report: in-sample / out-of-sample / stress-window runs,
walk-forward folds, figures and a markdown summary.

    python tools/report.py --params presets/validated.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.features import Params, build
from backtest.engine import EngineCfg, run

FIG = "reports/figures"
ALL_SYMBOLS = ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"]


def backtest(symbols, params, cfg, start, end, cache=None):
    series, feats = {}, {}
    for s in symbols:
        ser = D.load(s, "H1")
        series[s] = ser
        key = (s, tuple(sorted((k, v) for k, v in vars(params).items())))
        if cache is not None and key in cache:
            feats[s] = cache[key]
        else:
            feats[s] = build(ser, params)
            if cache is not None:
                cache[key] = feats[s]
    return run(series, feats, {s: params for s in symbols}, cfg, start=start, end=end)


def plot_equity(res, path, title):
    fig, ax = plt.subplots(2, 1, figsize=(11, 6.4), sharex=True,
                           gridspec_kw=dict(height_ratios=[2.4, 1]))
    eq = res.equity
    ax[0].plot(eq.index, eq.values, lw=1.1, color="#1565c0")
    ax[0].set_title(title)
    ax[0].set_ylabel("equity, USD")
    ax[0].grid(alpha=0.3)
    peak = eq.cummax()
    dd = 100 * (eq / peak - 1)
    ax[1].fill_between(dd.index, dd.values, 0, color="#c62828", alpha=0.55, lw=0)
    ax[1].set_ylabel("drawdown, %")
    ax[1].grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def plot_monthly(res, path):
    m = res.equity.resample("ME").last().pct_change().dropna() * 100
    if len(m) < 6:
        return
    tab = m.groupby([m.index.year, m.index.month]).sum().unstack()
    fig, ax = plt.subplots(figsize=(11, 0.45 * len(tab) + 1.8))
    vmax = np.nanmax(np.abs(tab.values))
    im = ax.imshow(tab.values, cmap="RdYlGn", vmin=-vmax, vmax=vmax, aspect="auto")
    ax.set_xticks(range(tab.shape[1]), [f"{c:02d}" for c in tab.columns])
    ax.set_yticks(range(tab.shape[0]), [str(i) for i in tab.index])
    for i in range(tab.shape[0]):
        for j in range(tab.shape[1]):
            v = tab.values[i, j]
            if np.isfinite(v):
                ax.text(j, i, f"{v:.1f}", ha="center", va="center", fontsize=7)
    ax.set_title("monthly return, %")
    fig.colorbar(im, ax=ax, shrink=0.7)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def plot_r_dist(res, path):
    if not len(res.trades):
        return
    fig, ax = plt.subplots(1, 2, figsize=(11, 3.4))
    ax[0].hist(res.trades.r_multiple, bins=40, color="#1565c0", alpha=0.85)
    ax[0].axvline(0, color="k", lw=0.8)
    ax[0].set_title("trade R-multiple distribution")
    by = res.trades.groupby("symbol").r_multiple.agg(["sum", "count"])
    ax[1].bar(by.index, by["sum"], color="#2e7d32")
    ax[1].set_title("total R by symbol")
    for i, (k, v) in enumerate(by.iterrows()):
        ax[1].text(i, v["sum"], f"{v['count']:.0f} tr", ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def walk_forward(symbols, base: Params, cfg, start, end, folds=5, span_years=2.0):
    """Anchored walk-forward: optimise rr/be/trail on everything before the fold,
    then trade the fold untouched."""
    t0, t1 = pd.Timestamp(start), pd.Timestamp(end)
    total_years = (t1 - t0).days / 365.25
    step = total_years / (folds + 1)
    grid = [(rr, be, trail) for rr in (1.2, 1.8, 2.5) for be in (0.0, 0.9) for trail in (0.0, 2.0)]
    rows, agg = [], []
    for k in range(folds):
        tr_end = t0 + pd.Timedelta(days=365.25 * step * (k + 1))
        te_end = tr_end + pd.Timedelta(days=365.25 * step)
        if te_end > t1:
            te_end = t1
        best = None
        for rr, be, trail in grid:
            p = Params(**{**vars(base), "rr": rr, "be_at_r": be, "trail_atr": trail})
            r = backtest(symbols, p, cfg, str(tr_end.date()) if False else tr_end, te_end)
            # training uses the *preceding* window only
            r = backtest(symbols, p, cfg, t0, tr_end)
            st = r.stats
            if st.get("trades", 0) < 30:
                continue
            score = st["cagr_pct"] / max(st["max_dd_pct"], 0.5)
            if best is None or score > best[0]:
                best = (score, p, st)
        if best is None:
            continue
        p = best[1]
        r = backtest(symbols, p, cfg, tr_end, te_end)
        st = r.stats
        rows.append(dict(fold=k + 1, train_end=str(tr_end.date()), test_end=str(te_end.date()),
                         best_rr=p.rr, best_be=p.be_at_r, best_trail=p.trail_atr,
                         train_cagr=best[2]["cagr_pct"], train_dd=best[2]["max_dd_pct"],
                         test_trades=st["trades"], test_cagr=st["cagr_pct"],
                         test_dd=st["max_dd_pct"], test_pf=st["profit_factor"]))
        agg.append(1 + st["total_return_pct"] / 100.0)
        print(f"  fold {k+1}: rr={p.rr} be={p.be_at_r} trail={p.trail_atr} "
              f"-> test CAGR {st['cagr_pct']:.2f}% DD {st['max_dd_pct']:.2f}% "
              f"trades {st['trades']}", flush=True)
    df = pd.DataFrame(rows)
    if agg:
        total = np.prod(agg)
        df.attrs["wf_total_return"] = 100 * (total - 1)
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", default="presets/validated.json")
    ap.add_argument("--risk", type=float, default=0.25)
    ap.add_argument("--is", dest="is_", default="2013-01-01:2019-12-31")
    ap.add_argument("--oos", default="2024-01-01:2026-03-01")
    ap.add_argument("--stress", default="2020-01-01:2021-12-31")
    ap.add_argument("--skip-wf", action="store_true")
    a = ap.parse_args()

    if os.path.exists(a.params):
        raw = {k: v for k, v in json.load(open(a.params)).items() if not k.startswith("_")}
        params = Params(**raw)
    else:
        params = Params()
    cfg = EngineCfg(risk_pct=a.risk, max_positions=3)
    os.makedirs(FIG, exist_ok=True)

    out = {"params": vars(params), "risk_pct": a.risk}
    segs = {"in_sample": a.is_, "out_of_sample": a.oos, "stress_2020": a.stress}
    for name, spec in segs.items():
        s, e = spec.split(":")
        syms = ALL_SYMBOLS
        if name == "stress_2020":
            syms = [x for x in ALL_SYMBOLS if x != "EURUSD"]   # EURUSD data gap 2020-2023
        print(f"\n== {name} {s} .. {e} ({len(syms)} symbols)")
        res = backtest(syms, params, cfg, s, e)
        out[name] = dict(stats=res.stats, symbols=syms)
        print(pd.Series(res.stats).to_string())
        plot_equity(res, f"{FIG}/equity_{name}.png", f"{name}  {s} .. {e}")
        plot_monthly(res, f"{FIG}/monthly_{name}.png")
        plot_r_dist(res, f"{FIG}/rdist_{name}.png")
        res.trades.to_csv(f"reports/trades_{name}.csv", index=False)

    if not a.skip_wf:
        print("\n== walk-forward")
        wf = walk_forward(ALL_SYMBOLS, params, cfg, a.is_.split(":")[0], a.oos.split(":")[1])
        wf.to_csv("reports/walk_forward.csv", index=False)
        out["walk_forward"] = wf.to_dict(orient="records")
        out["walk_forward_total_return_pct"] = float(wf.attrs.get("wf_total_return", np.nan))
        print(wf.to_string(index=False))

    json.dump(out, open("reports/validation.json", "w"), indent=2, default=str)
    print("\nwrote reports/validation.json")


if __name__ == "__main__":
    main()
