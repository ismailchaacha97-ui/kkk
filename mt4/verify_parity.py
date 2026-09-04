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
ADX_PERIOD = 14
ADX_MIN = 25.0
USE_ADX = True


def wilder_adx(high, low, close, n=ADX_PERIOD):
    """Wilder ADX, matching MT4's iADX(MODE_MAIN)."""
    up = high.diff()
    dn = -low.diff()
    plus_dm = up.where((up > dn) & (up > 0), 0.0)
    minus_dm = dn.where((dn > up) & (dn > 0), 0.0)
    pc = close.shift(1)
    tr = np.maximum.reduce([(high - low).abs().values,
                            (high - pc).abs().values,
                            (low - pc).abs().values])
    tr = pd.Series(tr, index=close.index)
    atr = tr.ewm(alpha=1 / n, adjust=False).mean()
    pdi = 100 * plus_dm.ewm(alpha=1 / n, adjust=False).mean() / atr.replace(0, np.nan)
    mdi = 100 * minus_dm.ewm(alpha=1 / n, adjust=False).mean() / atr.replace(0, np.nan)
    dx = 100 * (pdi - mdi).abs() / (pdi + mdi).replace(0, np.nan)
    return dx.ewm(alpha=1 / n, adjust=False).mean()


def mql4_port(close, adx_series=None):
    """Literal transcription of OnCalculate() in TrendVolFilter.mq4.

    Index convention is MT4's: shift 0 = newest bar. We build a series in
    that orientation, run the same loop, then flip it back to time order.
    """
    c = close.to_numpy()[::-1]          # c[0] = newest, like MT4's Close[]
    a = (adx_series.to_numpy()[::-1] if adx_series is not None
         else np.full(len(c), np.nan))
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
        base_ok = trend_ok and calm_ok

        # entry-only ADX gate, with state carried from the newer bar (i+1
        # in MT4 orientation is the OLDER bar, already computed by the loop)
        was_in = state[i + 1] > 0.5 if i + 1 < n else False
        in_pos = False
        if base_ok:
            if was_in:
                in_pos = True
            elif not USE_ADX:
                in_pos = True
            else:
                in_pos = (not np.isnan(a[s])) and a[s] > ADX_MIN
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

    # Python strategy #1 + the same entry-only ADX gate
    py_base = make("trend_vol_filter",
                   dict(ma=MA_PERIOD, volw=VOL_WINDOW, volmax=VOL_MAX,
                        mode="lo", sizing="vt10"), cache)
    if USE_ADX:
        sys.path.insert(0, os.path.join(ROOT, "src"))
        from analyze_ranging import adx as adx_panel
        from ranging_gate_test import entry_gated
        ad, _, _ = adx_panel(panels["High"], panels["Low"], panels["Close"])
        py_pos = entry_gated(py_base, ad > ADX_MIN)
    else:
        py_pos = py_base

    print(f"{'symbol':8s} {'bars':>6s} {'state match':>12s} {'size maxdiff':>13s}")
    print("-" * 44)
    worst_state, worst_size = 1.0, 0.0
    for sym in panels["Close"].columns:
        close = panels["Close"][sym]
        adx_s = wilder_adx(panels["High"][sym], panels["Low"][sym], close)
        st, sc = mql4_port(close, adx_s)

        # Python side: the backtester lags pos by 1 day, so compare the
        # MT4 bar-i decision against Python's pos.shift(1) at bar i.
        py_lagged = py_pos[sym].shift(1)
        both = pd.concat([st, sc, py_lagged], axis=1,
                         keys=["st", "sc", "py"]).dropna()
        # ignore the warm-up window where MT4 has no data yet
        warm = MA_PERIOD + VOL_WINDOW + ADX_PERIOD + 30
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
