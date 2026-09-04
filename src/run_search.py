"""Backtest the full strategy space and rank the survivors.

Protocol
--------
1. In-sample  (IS) : 2007-04 .. 2013-12  -- used to select candidates.
2. Out-of-sample(OOS): 2014-01 .. 2017-11 -- never used for selection.
Strategies are ranked by OOS performance among those that pass IS screens,
which is the only way a 9,600-wide search means anything.
"""
import json
import os
import sys
import time
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from indicators import Cache
from strategies import build_specs, make
import backtest as bt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
RESULTS = os.path.join(ROOT, "results")

IS_END = "2013-12-31"


def load():
    p = {f.capitalize(): pd.read_parquet(os.path.join(DATA, f"{f}.parquet"))
         for f in ["open", "high", "low", "close", "volume"]}
    return p


def main(limit=None):
    panels = load()
    cache = Cache(panels)
    ret = cache.ret
    specs = build_specs()
    if limit:
        specs = specs[:limit]
    print(f"backtesting {len(specs)} strategies on {ret.shape[1]} assets, "
          f"{ret.shape[0]} days", flush=True)

    is_mask = ret.index <= IS_END
    oos_mask = ~is_mask
    rows = []
    curves = {}
    t0 = time.time()
    for i, (name, params) in enumerate(specs):
        try:
            pos = make(name, params, cache)
        except Exception as e:                      # pragma: no cover
            continue
        r, to = bt.run(pos, ret)
        s_is = bt.stats(r[is_mask], to[is_mask])
        s_oos = bt.stats(r[oos_mask], to[oos_mask])
        s_all = bt.stats(r, to)
        if s_is is None or s_oos is None:
            continue
        row = dict(id=i, family=name,
                   params=json.dumps({k: v for k, v in params.items()}))
        row.update({f"is_{k}": v for k, v in s_is.items()})
        row.update({f"oos_{k}": v for k, v in s_oos.items()})
        row.update({f"all_{k}": v for k, v in s_all.items()})
        rows.append(row)
        curves[i] = r.astype(np.float32)
        if (i + 1) % 500 == 0:
            el = time.time() - t0
            print(f"  {i+1}/{len(specs)}  {el:.0f}s  "
                  f"eta {el/(i+1)*(len(specs)-i-1):.0f}s", flush=True)

    df = pd.DataFrame(rows)
    os.makedirs(RESULTS, exist_ok=True)
    df.to_csv(os.path.join(RESULTS, "all_results.csv"), index=False)
    # keep only the best curves -- the full 9,600-column matrix is ~100MB
    top = df.sort_values("oos_sharpe", ascending=False)["id"].head(4000)
    pd.DataFrame({int(i): curves[i] for i in top if i in curves}).to_parquet(
        os.path.join(RESULTS, "top_curves.parquet"))
    print(f"done: {len(df)} strategies in {time.time()-t0:.0f}s")
    return df


if __name__ == "__main__":
    lim = int(sys.argv[1]) if len(sys.argv) > 1 else None
    main(lim)
