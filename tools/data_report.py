#!/usr/bin/env python3
"""Coverage report for the local H1 data: bars per year, gaps, price ranges."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import numpy as np, pandas as pd
from backtest import data as D

def main():
    syms = sys.argv[1:] or ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"]
    rows = []
    for s in syms:
        try:
            ser = D.load(s, "H1")
        except FileNotFoundError as e:
            print(e); continue
        ts = pd.DatetimeIndex(ser.time)
        per_year = pd.Series(1, index=ts).groupby(ts.year).sum()
        gaps = pd.Series(ts).diff().dt.total_seconds().div(3600)
        big = gaps[gaps > 24]
        rows.append(dict(symbol=s, bars=len(ser), start=str(ts[0].date()), end=str(ts[-1].date()),
                         low=float(np.nanmin(ser.low)), high=float(np.nanmax(ser.high)),
                         years_below_4000=int((per_year < 4000).sum()),
                         gaps_over_24h=int(len(big)),
                         max_gap_h=float(big.max()) if len(big) else 0.0))
        print(f"\n{s}: bars/year " + " ".join(f"{y}:{n}" for y, n in per_year.items()))
    print("\n" + pd.DataFrame(rows).to_string(index=False))

if __name__ == "__main__":
    main()
