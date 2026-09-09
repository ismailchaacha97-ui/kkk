#!/usr/bin/env python3
"""Stage 1 - compute the full (fast, slow) EMA grid on every market, both modes.

Writes results/grid_long.parquet and results/grid_ls.parquet which every later analysis
step reads (so the expensive part runs once).
"""
from __future__ import annotations

import argparse
import os
import sys
import time

import pandas as pd

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src"))

from ema_study.data import load_universe, families                      # noqa: E402
from ema_study.grid import pair_grid, run_grid                            # noqa: E402
from ema_study.engine import ema_matrix, position_from_state, metrics, buy_and_hold  # noqa: E402
from ema_study.data import _returns                                       # noqa: E402

OUT = os.environ.get("KKK_RESULTS", "/home/user/kkk/results")


def bh_table(universe) -> pd.DataFrame:
    rows = []
    for k, s in universe.items():
        warm = 400                                        # comparable warm-up for every pair
        m = buy_and_hold(s.rets, s.ann, warmup=min(warm, max(s.n - 260, 0)))
        rows.append(dict(asset=k, asset_class=s.asset_class, bh_sharpe=m["sharpe"], bh_cagr=m["cagr"],
                         bh_dd=m["max_dd"], bh_calmar=m["calmar"], n_bars=m["n_bars"],
                         start=str(s.start.date()), end=str(s.end.date()), ann=s.ann,
                         adjustment=s.adjustment, cost_bps=s.cost_bps))
    return pd.DataFrame(rows)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast-max", type=int, default=120)
    ap.add_argument("--slow-max", type=int, default=400)
    ap.add_argument("--step", type=int, default=2)
    ap.add_argument("--ratio", type=float, default=1.5)
    ap.add_argument("--bar", default="D", choices=["D", "W"])
    ap.add_argument("--cost-mult", type=float, default=1.0)
    ap.add_argument("--ma", default="ema", choices=["ema", "sma"])
    ap.add_argument("--out-tag", default="")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    t0 = time.time()
    print(f"loading universe ({args.bar} bars) ...", flush=True)
    uni = load_universe(bar=args.bar, exclude=("macro", "fx_spot_ctrl"))
    fam = families(uni)
    print(f"  {len(uni)} markets across {len(fam)} families")
    for f, ks in fam.items():
        print(f"    {f:<28} {len(ks):>3}")

    f_idx, s_idx = pair_grid(args.fast_max, args.slow_max, args.step, args.step, args.ratio)
    print(f"\ngrid: {f_idx.size} (fast,slow) pairs  x  {len(uni)} markets  =  {f_idx.size*len(uni):,} backtests", flush=True)

    bh = bh_table(uni)
    bh.to_csv(f"{OUT}/buy_and_hold{args.out_tag}.csv", index=False)

    for mode in ("long", "ls"):
        t = time.time()
        print(f"\n== mode={mode}  (cost x{args.cost_mult})", flush=True)
        g = run_grid(uni, f_idx, s_idx, mode=mode, cost_mult=args.cost_mult, ma=args.ma)
        g["bar"] = args.bar
        g["cost_mult"] = args.cost_mult
        try:
            g.to_parquet(f"{OUT}/grid_{args.ma}_{mode}{args.out_tag}.parquet", index=False)
        except Exception:
            g.to_csv(f"{OUT}/grid_{args.ma}_{mode}{args.out_tag}.csv.gz", index=False)
        print(f"   -> {len(g):,} rows  in {time.time()-t:.0f}s", flush=True)

    print(f"\ntotal {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
