#!/usr/bin/env python3
"""
eventstudy.py - does the data contain anything tradeable after costs?

Before tuning a system it is worth measuring the raw conditional structure of
the market, because a backtest can only ever harvest what is there.

Three measurements, all in ATR units so they are comparable across symbols and
eras:

  1. cost ratio       spread / ATR. If a round trip costs a large fraction of
                      the average bar range, no intraday edge survives. This is
                      a hard ceiling, not a matter of cleverness.
  2. autocorrelation  of k-bar returns. Sign and size of the predictable part.
  3. conditional drift  what happens after a move of x ATR over k bars, split by
                      session, reported per year with t statistics pooled.

Everything is net of an assumed round-trip cost, and reported both per year and
pooled, because a structure that only exists in one era is noise.

Usage: python3 research/eventstudy.py [--symbol EURUSD] [--source years|ftmo]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import backtest as bt


def atr_series(b, period=14):
    h, l, c = b["h"], b["l"], b["c"]
    tr = np.empty(b["n"])
    tr[0] = h[0] - l[0]
    tr[1:] = np.maximum.reduce([h[1:] - l[1:], np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])])
    atr = np.full(b["n"], np.nan)
    cs = np.concatenate(([0.0], np.cumsum(tr)))
    atr[period - 1:] = (cs[period:] - cs[:-period]) / period
    return atr


def server_hour(dt):
    return (dt.hour + bt.server_offset_hours(dt)) % 24


def load_sources(symbol, source, tf="m15"):
    files = []
    if source in ("years", "all"):
        for f in sorted(os.listdir(bt.DATA)):
            if f.startswith(f"{symbol}_") and f.endswith(f"_{tf}.csv"):
                files.append(("hist", os.path.join(bt.DATA, f)))
    if source in ("ftmo", "all"):
        p = os.path.join(bt.DATA, f"{symbol}_{tf}.csv")
        if os.path.exists(p):
            files.append(("ftmo", p))
    return files


def analyse(bars, spec, k, horizon, label):
    atr = atr_series(bars)
    c = bars["c"]
    n = bars["n"]
    move = np.full(n, np.nan)
    move[k:] = (c[k:] - c[:-k]) / atr[k:]
    fwd = np.full(n, np.nan)
    fwd[:-horizon] = (c[horizon:] - c[:-horizon]) / atr[:-horizon]
    cost_atr = bars["sp"] * spec["point"] / atr          # round-turn cost in ATR
    hours = np.array([server_hour(d) for d in bars["dt"]])

    ok = np.isfinite(move) & np.isfinite(fwd) & np.isfinite(cost_atr) & (atr > 0)
    return dict(move=move, fwd=fwd, cost=cost_atr, hour=hours, ok=ok,
                label=label, n=bars["n"])


def report_cost(label, series_list, spec):
    """cost ratio and the size of move needed to pay for it."""
    print(f"\n--- cost ratio: {label} ---")
    for s in series_list:
        cost = s["cost"][s["ok"]]
        if len(cost) == 0:
            continue
        med = float(np.median(cost))
        print(f"  {s['label']:<28} median cost {med*100:5.2f}% of ATR   "
              f"90th pct {np.percentile(cost, 90)*100:5.2f}%   "
              f"=> an edge must beat {med:.3f} ATR per round trip")


def report_autocorr(series_list, ks=(1, 2, 4, 8, 16, 32)):
    print("\n--- return autocorrelation (pooled) ---")
    print(f"{'k bars':>8} {'corr':>8} {'t-stat':>8} {'n':>9}")
    for k in ks:
        vals = []
        for s in series_list:
            r = np.full(s["n"], np.nan)
            r[k:] = (s["c"][k:] - s["c"][:-k]) / s["c"][:-k]
            r2 = r[k:]
            r1 = r[:-k]
            m = np.isfinite(r1) & np.isfinite(r2)
            vals.append((np.corrcoef(r1[m], r2[m])[0, 1], m.sum()))
        # Fisher combine across sources
        zs, w = [], 0
        for corr, m in vals:
            if np.isfinite(corr) and m > 30:
                zs.append(np.arctanh(corr) * np.sqrt(m - 3))
                w += m - 3
        pooled = np.tanh(sum(zs) / np.sqrt(w)) if w > 0 else 0.0
        n_tot = sum(m for _, m in vals)
        t = pooled * np.sqrt(max(n_tot - 3, 1))
        print(f"{k:>8} {pooled:+8.4f} {t:+8.2f} {n_tot:>9}")


def report_conditional(series_list, k, horizon, sessions):
    print(f"\n--- forward return after a {k}-bar move, horizon {horizon} bars "
          f"(net of cost, ATR units) ---")
    print(f"{'session':<12} {'move bucket':<14} {'mean net':>10} {'t-stat':>8} {'n':>8} "
          f"{'win%':>6}")
    for lo, hi, name in sessions:
        for sign, sname in ((-1, "down"), (1, "up")):
            for thr in (1.0, 2.0, 3.0):
                xs = []
                for s in series_list:
                    m = s["ok"] & (s["hour"] >= lo) & (s["hour"] < hi)
                    sel = m & (sign * s["move"] >= thr) if False else m & (s["move"] * sign >= thr)
                    net = sign * s["fwd"][sel] - s["cost"][sel]
                    xs.append(net)
                x = np.concatenate(xs) if xs else np.array([])
                x = x[np.isfinite(x)]
                if len(x) < 100:
                    continue
                mean = x.mean()
                se = x.std(ddof=1) / np.sqrt(len(x))
                t = mean / se if se > 0 else 0.0
                flag = "  <=" if abs(t) > 3 else ""
                print(f"{name:<12} {sname} >{thr:.0f} ATR{'':<4} {mean:+10.4f} {t:+8.2f} "
                      f"{len(x):>8} {100*(x>0).mean():6.1f}{flag}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", default="EURUSD")
    ap.add_argument("--source", default="all", choices=["years", "ftmo", "all"])
    ap.add_argument("--tf", default="m15")
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--horizon", type=int, default=16)
    args = ap.parse_args()
    spec = bt.SPECS[args.symbol]

    series = []
    for kind, path in load_sources(args.symbol, args.source, args.tf):
        bars = bt.load_bars(args.symbol, args.tf, path)
        s = analyse(bars, spec, args.k, args.horizon,
                    os.path.basename(path).replace(".csv", ""))
        s["c"] = bars["c"]
        series.append(s)
        print(f"loaded {s['label']}: {bars['n']} bars")

    report_cost(args.symbol, series, spec)
    report_autocorr(series)
    sessions = [(0, 24, "all day"), (6, 12, "London"), (12, 18, "NY"),
                (18, 24, "late"), (0, 6, "Asia")]
    report_conditional(series, args.k, args.horizon, sessions)


if __name__ == "__main__":
    main()
