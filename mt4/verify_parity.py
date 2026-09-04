"""Parity check: reimplement the MQL4 bar loop literally, compare to the
Python strategy used in the search. They must produce identical positions.

Run:  python3 mt4/verify_parity.py
"""
import os
import sys
import numpy as np
import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "src"))
from indicators import Cache
from strategies import make

MA_PERIOD = 200
VOL_WINDOW = 120
SIZE_VOL_WINDOW = 60
VOL_MAX = 0.12
VOL_TARGET = 0.10
LEV_CAP = 3.0
ANN = 252.0


def mql4_port(close):
    """Literal transcription of OnCalculate() in TrendVolFilter.mq4.

    Index convention is MT4's: shift 0 = newest bar. We build a series in
    that orientation, run the same loop, then flip it back to time order.
    """
    c = close.to_numpy()[::-1]          # c[0] = newest, like MT4's Close[]
    n = len(c)
    state = np.zeros(n)
    scale = np.zeros(n)

    def sma(shift, period):
        if shift + period > n:
            return -1.0
        return c[shift:shift + period].mean()

    def ann_vol(shift, window):
        # iterate i = shift .. shift+window-1, r = Close[i]/Close[i+1]-1
        if window < 2 or shift + window + 1 >= n:
            return -1.0
        r = c[shift:shift + window] / c[shift + 1:shift + window + 1] - 1.0
        if len(r) < 2:
            return -1.0
        var = r.var(ddof=1)
        if var <= 0:
            return 0.0
        return np.sqrt(var) * np.sqrt(ANN)

    for i in range(n - 1, -1, -1):
        s = i + 1                       # 1-bar lag: signal from previous bar
        ma_s = sma(s, MA_PERIOD)
        vol_s = ann_vol(s, VOL_WINDOW)
        if ma_s <= 0 or vol_s < 0:
            continue
        trend_ok = c[s] > ma_s
        calm_ok = vol_s < VOL_MAX
        in_pos = trend_ok and calm_ok
        vol_z = ann_vol(s + 1, SIZE_VOL_WINDOW)
        sc = 0.0
        if in_pos and vol_z > 0:
            sc = min(VOL_TARGET / vol_z, LEV_CAP)
        state[i] = 1.0 if in_pos else 0.0
        scale[i] = sc

    idx = close.index
    return (pd.Series(state[::-1], index=idx),
            pd.Series(scale[::-1], index=idx))


def main():
    panels = {f.capitalize(): pd.read_parquet(
        os.path.join(ROOT, "data", f"{f}.parquet"))
        for f in ["open", "high", "low", "close", "volume"]}
    cache = Cache(panels)

    # Python strategy #1, as scored in the search
    py_pos = make("trend_vol_filter",
                  dict(ma=MA_PERIOD, volw=VOL_WINDOW, volmax=VOL_MAX,
                       mode="lo", sizing="vt10"), cache)

    print(f"{'symbol':8s} {'bars':>6s} {'state match':>12s} {'size maxdiff':>13s}")
    print("-" * 44)
    worst_state, worst_size = 1.0, 0.0
    for sym in panels["Close"].columns:
        close = panels["Close"][sym]
        st, sc = mql4_port(close)

        # Python side: the backtester lags pos by 1 day, so compare the
        # MT4 bar-i decision against Python's pos.shift(1) at bar i.
        py_lagged = py_pos[sym].shift(1)
        both = pd.concat([st, sc, py_lagged], axis=1,
                         keys=["st", "sc", "py"]).dropna()
        # ignore the warm-up window where MT4 has no data yet
        warm = MA_PERIOD + VOL_WINDOW + 5
        both = both.iloc[warm:]
        if both.empty:
            continue

        py_state = (both.py.abs() > 1e-12).astype(float)
        agree = (py_state == both.st).mean()
        size_diff = (both.sc - both.py).abs().max()
        worst_state = min(worst_state, agree)
        worst_size = max(worst_size, size_diff)
        print(f"{sym:8s} {len(both):6d} {agree:11.2%} {size_diff:13.2e}")

    print("-" * 44)
    print(f"worst state agreement : {worst_state:.4%}")
    print(f"worst size difference : {worst_size:.3e}")
    ok = worst_state > 0.9999 and worst_size < 1e-9
    print("\nPARITY:", "PASS - the .mq4 reproduces the backtest exactly" if ok
          else "FAIL - logic drift between MQL4 and Python")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
