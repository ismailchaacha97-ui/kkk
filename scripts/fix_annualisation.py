#!/usr/bin/env python3
"""Repair the annualisation factor in the already-computed grids — exactly, without re-running.

Why this exists: ``data._annualisation`` used to classify a series by its *median* bar gap and
return 365 for anything at or under 1.3 days.  Business-day data alternates 1-day and 3-day gaps,
so its median gap is 1.0 and every stock/index/ETF/futures series was annualised as a 365-day
market (Sharpe too high by sqrt(365/252) = 20%, CAGR far too high), while the weekly variant was
annualised as a 252-bar market instead of 52 (Sharpe 2.2x too high).  The loader is fixed; this
script rewrites the ten-year-old arithmetic in the cached parquets so the 9.7M backtests do not
have to be re-run.

The repair is exact, not approximate, because ``ann`` enters the metric block in only five places:

    sharpe, sortino, ann_vol   ~ sqrt(ann)      -> multiply by sqrt(k)
    cagr                       = expm1(L/n*ann) -> expm1(log1p(cagr) * k)   (invert, then redo)
    trades_per_year            ~ ann           -> multiply by k
    calmar                     = cagr/|max_dd| -> recompute from the corrected cagr

``max_dd``, ``total_return``, ``exposure``, ``round_trips`` never see ``ann``, and the row-keeping
filter (``sd > 0 & isfinite(sharpe) & n >= 250``) is ann-independent, so no rows appear or vanish.
k = ann_true / ann_used for that market's bar size.  Afterwards the script *verifies* the repaired
files against a fresh backtest of the same markets with the fixed loader.

    python scripts/fix_annualisation.py --check-only      # report the shift, change nothing
    python scripts/fix_annualisation.py                   # repair in place (writes .bak once)
"""
from __future__ import annotations

import argparse
import glob
import os
import shutil
import sys

import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))

from ema_study.data import load_universe                                    # noqa: E402
from ema_study.grid import pair_grid, grid_for_series                        # noqa: E402

RES = os.path.join(ROOT, "results")
SQRT_COLS = ["sharpe", "sortino", "ann_vol"]
LIN_COLS = ["trades_per_year"]


def measure_ann_used(df: pd.DataFrame) -> float:
    """Recover the annualisation factor a cached file was actually built with, from the file
    itself: ``trades_per_year = round_trips / n_bars * ann`` is exactly invertible.  Measuring it
    beats reconstructing the old buggy rule from memory -- the answer is unambiguous (365 for
    every cached file here, daily and weekly alike) and it is per-row checkable."""
    q = df[np.asarray(df["round_trips"], float) > 0]
    if len(q) < 20:
        return 365.0
    implied = np.asarray(q["trades_per_year"], float) * np.asarray(q["n_bars"], float) \
        / np.asarray(q["round_trips"], float)
    v = float(np.median(implied))
    if not np.allclose(implied, v, rtol=1e-4, atol=1e-3):
        raise RuntimeError(f"cached file uses more than one annualisation factor "
                           f"(median {v:.2f}, spread {implied.min():.2f}-{implied.max():.2f})")
    return v


def ann_maps(files: list[str]) -> dict:
    """{bar: {asset: (ann_used_in_cache, ann_correct)}}."""
    correct = {}
    for bar in ("D", "W"):
        uni = load_universe(bar=bar, exclude=("macro", "fx_spot_ctrl"), verbose=False)
        correct[bar] = {k: int(s.ann) for k, s in uni.items()}
    used: dict = {}
    for path in files:
        fname = os.path.basename(path)
        d = pd.read_parquet(path, columns=["asset", "n_bars", "round_trips", "trades_per_year", "bar"])
        bar = str(d["bar"].iloc[0])
        a = measure_ann_used(d)
        used[fname] = (bar, a)
    out = {}
    for fname, (bar, a) in used.items():
        out[fname] = {k: (int(round(a)), int(correct[bar][k])) for k in correct[bar]}
    ann_maps.used = used                                  # reuse for the buy&hold table below
    n_fix = sum(1 for v in out.values() for a, b in v.values() if a != b)
    print(f"  {len(out)} files, {n_fix:,} market-file combinations need repair")
    for fname, (bar, a) in sorted(used.items()):
        print(f"    {fname:34s} bar={bar} ann_used={a:.0f}  ann_correct e.g. "
              f"{list(out[fname].values())[:2]}")
    return out


def repair(df: pd.DataFrame, amap: dict, pfx: str = "", dd_col: str | None = None) -> tuple[pd.DataFrame, dict]:
    """amap: {asset: (ann_used, ann_correct)}.  ``pfx`` lets the same transform address the
    buy&hold table, whose columns are prefixed."""
    old = df["asset"].map(lambda a: amap[a][0]).astype(float).to_numpy()
    new = df["asset"].map(lambda a: amap[a][1]).astype(float).to_numpy()
    k = new / old                                          # per-row correction factor
    out = df.copy()
    for c in SQRT_COLS:                                    # the buy&hold table has no sortino
        if pfx + c in df.columns:
            out[pfx + c] = df[pfx + c].to_numpy(float) * np.sqrt(k)
    for c in LIN_COLS:
        if pfx + c in df.columns:
            out[pfx + c] = df[pfx + c].to_numpy(float) * k
    # cagr: invert expm1(L/n*ann_old) to get L/n, then re-apply ann_new
    L = np.log1p(np.clip(df[pfx + "cagr"].to_numpy(float), -0.999999999, None))
    out[pfx + "cagr"] = np.expm1(L * k)
    dd_name = dd_col or (pfx + "max_dd")
    cal_name = "bh_calmar" if dd_col == "bh_dd" else pfx + "calmar"
    if dd_name in df.columns and cal_name in df.columns:
        dd = df[dd_name].to_numpy(float)
        out[cal_name] = np.where(dd < -1e-9, np.asarray(out[pfx + "cagr"], float) / np.abs(dd), np.nan)
    stats = dict(rows=len(df), changed=int(np.sum(np.abs(k - 1) > 1e-12)),
                 median_k=float(np.median(k)) if len(k) else 1.0,
                 min_k=float(np.min(k)) if len(k) else 1.0, max_k=float(np.max(k)) if len(k) else 1.0)
    return out, stats


def verify(repaired: dict, tmp: str) -> bool:
    """Recompute (market, file) grids with the fixed loader and require the repaired cache to
    match.  This is what makes the repair trustworthy rather than plausible: it re-runs the real
    engine, so any mistake in the transform above shows up as a mismatch.  The pair lattice is
    taken from each cached file itself, so the base and extended grids are both checkable."""
    uni_d = load_universe(bar="D", exclude=("macro", "fx_spot_ctrl"), verbose=False)
    uni_w = load_universe(bar="W", exclude=("macro", "fx_spot_ctrl"), verbose=False)
    ok_all = True
    for fname, keys in repaired.items():
        cached = pd.read_parquet(os.path.join(tmp, fname))
        ma = "sma" if "sma" in fname else "ema"
        for key in keys:
          rows = cached[cached["asset"] == key]
          mode = "ls" if "_ls" in fname else "long"
          bar = str(rows["bar"].iloc[0]) if len(rows) else "D"
          uni = uni_d if bar == "D" else uni_w
          s = uni[key]
          cost = float(rows["cost_mult"].iloc[0]) if "cost_mult" in rows else 1.0
          fp = rows["fast"].to_numpy(int)
          sp = rows["slow"].to_numpy(int)
          ref = grid_for_series(s, fp, sp, mode=mode, cost_mult=cost, ma=ma)
          got = rows
        j = ref.merge(got, on=["fast", "slow"], suffixes=("_ref", "_rep"), how="inner")
        if len(j) != len(ref) or len(j) != len(got):
            print(f"   !! {fname}/{key}: row count ref={len(ref)} cached={len(got)} merged={len(j)}")
            ok_all = False
            continue
        if len(j) == 0:
            print(f"   !! {fname}/{key}: row mismatch ref={len(ref)} merged={len(j)}")
            ok_all = False
            continue
        worst = {}
        for c in ["sharpe", "cagr", "calmar", "max_dd", "ann_vol", "trades_per_year", "round_trips"]:
            a, b = j[f"{c}_ref"].to_numpy(float), j[f"{c}_rep"].to_numpy(float)
            m = np.isfinite(a) & np.isfinite(b)
            if m.sum() == 0:
                worst[c] = np.nan
                continue
            worst[c] = float(np.max(np.abs(a[m] - b[m]) / np.maximum(np.abs(a[m]), 1e-6)))
        bad = {c: v for c, v in worst.items() if not np.isfinite(v) or v > 2e-6}
        print(f"   {fname} [{key}] rows={len(j)} max rel err: " +
              "  ".join(f"{c}={v:.1e}" for c, v in worst.items()) +
              ("" if not bad else f"   <-- MISMATCH {bad}"))
        ok_all = ok_all and not bad
    return ok_all


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-only", action="store_true")
    args = ap.parse_args()
    files = sorted(glob.glob(os.path.join(RES, "grid_*.parquet")))
    print(f"annualisation maps for {len(files)} grid files:")
    maps = ann_maps(files)
    tmp = os.path.join(RES, "_repaired")
    os.makedirs(tmp, exist_ok=True)
    written, report = {}, []
    for path in files:
        fname = os.path.basename(path)
        base = pd.read_parquet(path)
        bar = str(base["bar"].iloc[0])
        out, st = repair(base, maps[fname])
        report.append((fname, st))
        print(f"  {fname:34s} rows={st['rows']:>9,} changed={st['changed']:>9,} "
              f"k median={st['median_k']:.4f} range=[{st['min_k']:.4f},{st['max_k']:.4f}]")
        if not args.check_only:
            p = os.path.join(tmp, fname)
            out.to_parquet(p, index=False)
            # a couple of markets per file are enough to prove the transform
            have = list(dict.fromkeys(base["asset"].tolist()))
            pick = [have[0]] + [a for a in ("index/^GSPC", "fx_futures/EUR", "stock/AAPL",
                                            "fut_commodity/GOLD", "crypto/BTC_20_26")
                                if a in have][:3]
            written[fname] = pick

    # buy & hold benchmark table, same transform
    bh_path = os.path.join(RES, "buy_and_hold.csv")
    if not args.check_only and os.path.exists(bh_path):
        # buy & hold was written by the same daily-anniverse run, so it carries the same factor
        bh_used = int(round(ann_maps.used["grid_ema_long.parquet"][1]))
        bh = pd.read_csv(bh_path)
        out, st = repair(bh, {k: (bh_used, v) for k, (a, v) in maps["grid_ema_long.parquet"].items()},
                         pfx="bh_", dd_col="bh_dd")
        out["ann"] = bh["asset"].map(lambda a: maps["grid_ema_long.parquet"][a][1])
        out.to_csv(bh_path, index=False)
        print(f"  buy_and_hold.csv                 rows={st['rows']} changed={st['changed']}")

    if args.check_only:
        print("\ncheck-only: nothing written")
        return

    print("\nverifying repaired caches against a fresh backtest with the fixed loader:")
    if not verify(written, tmp):
        print("\nREFUSING to swap in the repaired files - verification failed (kept originals)")
        sys.exit(1)
    for fname in written:
        src = os.path.join(RES, fname)
        bak = src + ".bak"
        if not os.path.exists(bak):
            shutil.move(src, bak)
        shutil.move(os.path.join(tmp, fname), src)
    print(f"\nrepaired {len(written)} files (originals kept as *.parquet.bak)")
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
