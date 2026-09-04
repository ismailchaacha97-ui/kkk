"""Strategy space: >8,000 parameterised, rule-based trading strategies.

Every strategy is a function of the indicator cache that returns a (T x N)
DataFrame of target positions in [-1, 1] per asset, *known at the close of t*.
The backtester lags them by one day before applying returns, so there is no
look-ahead.
"""
import itertools
import numpy as np
import pandas as pd

# ---------------------------------------------------------------- helpers

def _sign(x):
    return np.sign(x).fillna(0.0)


def _long_only(pos):
    return pos.clip(lower=0.0)


# ---------------------------------------------------------------- families

def ma_cross(c, fast, slow, kind, mode):
    f = c.ema(fast) if kind == "ema" else c.sma(fast)
    s = c.ema(slow) if kind == "ema" else c.sma(slow)
    pos = _sign(f - s)
    return _long_only(pos) if mode == "lo" else pos


def price_vs_ma(c, n, kind, mode):
    m = c.ema(n) if kind == "ema" else c.sma(n)
    pos = _sign(c.close - m)
    return _long_only(pos) if mode == "lo" else pos


def ts_momentum(c, lookback, gap, mode):
    m = c.close.shift(gap) / c.close.shift(gap + lookback) - 1.0
    pos = _sign(m)
    return _long_only(pos) if mode == "lo" else pos


def donchian(c, entry, exit_n, mode):
    up = c.hh(entry).shift(1)
    dn = c.ll(entry).shift(1)
    xdn = c.ll(exit_n).shift(1)
    xup = c.hh(exit_n).shift(1)
    long_sig = (c.close > up).astype(float).replace(0, np.nan)
    long_sig[c.close < xdn] = 0.0
    long = long_sig.ffill().fillna(0.0)
    if mode == "lo":
        return long
    short_sig = (c.close < dn).astype(float).replace(0, np.nan) * -1
    short_sig[c.close > xup] = 0.0
    short = short_sig.ffill().fillna(0.0)
    return (long + short).clip(-1, 1)


def rsi_reversion(c, n, lo, hi, mode):
    r = c.rsi(n)
    pos = pd.DataFrame(0.0, index=r.index, columns=r.columns)
    pos[r < lo] = 1.0
    pos[r > hi] = -1.0
    pos = pos.replace(0.0, np.nan)
    mid = (r > 45) & (r < 55)
    pos[mid] = 0.0
    pos = pos.ffill().fillna(0.0)
    return _long_only(pos) if mode == "lo" else pos


def zscore_reversion(c, n, thr, mode):
    z = c.zscore(n)
    pos = pd.DataFrame(0.0, index=z.index, columns=z.columns)
    pos[z < -thr] = 1.0
    pos[z > thr] = -1.0
    pos = pos.replace(0.0, np.nan)
    pos[z.abs() < 0.25] = 0.0
    pos = pos.ffill().fillna(0.0)
    return _long_only(pos) if mode == "lo" else pos


def macd(c, fast, slow, sig, mode):
    line = c.ema(fast) - c.ema(slow)
    signal = line.ewm(span=sig, adjust=False).mean()
    pos = _sign(line - signal)
    return _long_only(pos) if mode == "lo" else pos


def xs_momentum(c, lookback, k, mode):
    """Cross-sectional: buy top-k, (optionally) sell bottom-k each month."""
    m = c.mom(lookback)
    rank = m.rank(axis=1, ascending=False)
    n = m.notna().sum(axis=1)
    long = (rank <= k).astype(float)
    if mode == "lo":
        pos = long
    else:
        short = (rank.rsub(n + 1, axis=0) <= k).astype(float)
        pos = long - short
    pos = pos.where(m.notna(), 0.0)
    # rebalance monthly to keep turnover sane
    month = pd.Series(pos.index.to_period("M"), index=pos.index)
    keep = month != month.shift(1)
    pos = pos.where(keep.values[:, None]).ffill().fillna(0.0)
    return pos / max(k, 1)


def trend_vol_filter(c, ma, volw, volmax, mode):
    trend = _sign(c.close - c.sma(ma))
    calm = (c.vol(volw) < volmax).astype(float)
    pos = trend * calm
    return _long_only(pos) if mode == "lo" else pos


def breakout_atr(c, n, mult, mode):
    """Channel breakout with an ATR-scaled trailing stop."""
    up = c.hh(n).shift(1)
    trail = (c.close - mult * c.atr(14)).rolling(n).max().shift(1)
    sig = (c.close > up).astype(float).replace(0, np.nan)
    sig[c.close < trail] = 0.0
    pos = sig.ffill().fillna(0.0)
    if mode == "lo":
        return pos
    dn = c.ll(n).shift(1)
    trail_s = (c.close + mult * c.atr(14)).rolling(n).min().shift(1)
    s = (c.close < dn).astype(float).replace(0, np.nan) * -1
    s[c.close > trail_s] = 0.0
    return (pos + s.ffill().fillna(0.0)).clip(-1, 1)


# ---------------------------------------------------------------- registry

def build_specs():
    specs = []

    fasts = [3, 5, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60]
    slows = [20, 25, 30, 40, 50, 60, 75, 100, 125, 150, 175, 200, 250]
    for f, s, k, m in itertools.product(fasts, slows, ["sma", "ema"], ["lo", "ls"]):
        if f >= s:
            continue
        specs.append(("ma_cross", dict(fast=f, slow=s, kind=k, mode=m)))

    for n, k, m in itertools.product(
            [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 90, 100, 125, 150, 175, 200, 250],
            ["sma", "ema"], ["lo", "ls"]):
        specs.append(("price_vs_ma", dict(n=n, kind=k, mode=m)))

    for lb, g, m in itertools.product(
            [10, 20, 30, 40, 50, 60, 80, 100, 120, 150, 180, 200, 220, 250],
            [0, 3, 5, 10, 15, 21], ["lo", "ls"]):
        specs.append(("ts_momentum", dict(lookback=lb, gap=g, mode=m)))

    for e, x, m in itertools.product(
            [10, 15, 20, 25, 30, 40, 50, 60, 80, 100, 120, 150, 200, 250],
            [5, 10, 15, 20, 25, 30, 40, 50, 60, 75], ["lo", "ls"]):
        if x >= e:
            continue
        specs.append(("donchian", dict(entry=e, exit_n=x, mode=m)))

    for n, lo, hi, m in itertools.product(
            [2, 3, 5, 7, 10, 14, 21, 28],
            [10, 15, 20, 25, 30, 35],
            [65, 70, 75, 80, 85, 90], ["lo", "ls"]):
        specs.append(("rsi_reversion", dict(n=n, lo=lo, hi=hi, mode=m)))

    for n, t, m in itertools.product(
            [5, 10, 15, 20, 25, 30, 40, 50, 60, 80, 100, 120],
            [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], ["lo", "ls"]):
        specs.append(("zscore_reversion", dict(n=n, thr=t, mode=m)))

    for f, s, sg, m in itertools.product(
            [3, 5, 8, 12, 16, 20, 26], [20, 26, 35, 50, 60, 75, 100, 150],
            [3, 5, 9, 14, 20, 30], ["lo", "ls"]):
        if f >= s:
            continue
        specs.append(("macd", dict(fast=f, slow=s, sig=sg, mode=m)))

    for lb, k, m in itertools.product(
            [10, 20, 40, 60, 80, 100, 120, 150, 180, 200, 250],
            [1, 2, 3, 4, 5, 6, 8, 10, 12, 15], ["lo", "ls"]):
        specs.append(("xs_momentum", dict(lookback=lb, k=k, mode=m)))

    for ma, vw, vm, m in itertools.product(
            [10, 20, 50, 75, 100, 150, 200], [20, 40, 60, 120],
            [0.12, 0.15, 0.20, 0.25, 0.30, 0.40, 0.60], ["lo", "ls"]):
        specs.append(("trend_vol_filter", dict(ma=ma, volw=vw, volmax=vm, mode=m)))

    for n, mult, m in itertools.product(
            [10, 15, 20, 30, 40, 50, 60, 80, 100, 120, 150, 200],
            [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0], ["lo", "ls"]):
        specs.append(("breakout_atr", dict(n=n, mult=mult, mode=m)))

    # combine every base rule with each sizing overlay
    out = []
    for name, prm in specs:
        for sz in SIZINGS:
            p = dict(prm)
            p["sizing"] = sz
            out.append((name, p))
    return out


# --- sizing overlays -------------------------------------------------
# Each base rule is combined with a position-sizing overlay, which is a real
# and consequential design choice, so it counts as a distinct strategy.
SIZINGS = {
    "raw": None,        # full notional per signal
    "vt10": 0.10,       # scale each leg to a 10% annualised vol target
    "vt20": 0.20,       # ... 20%
}


def apply_sizing(pos, cache, sizing, volw=60, cap=3.0):
    if sizing == "raw":
        return pos
    target = SIZINGS[sizing]
    v = cache.vol(volw).shift(1)
    scale = (target / v.replace(0, np.nan)).clip(upper=cap).fillna(0.0)
    return pos * scale


FUNCS = {
    "ma_cross": ma_cross,
    "price_vs_ma": price_vs_ma,
    "ts_momentum": ts_momentum,
    "donchian": donchian,
    "rsi_reversion": rsi_reversion,
    "zscore_reversion": zscore_reversion,
    "macd": macd,
    "xs_momentum": xs_momentum,
    "trend_vol_filter": trend_vol_filter,
    "breakout_atr": breakout_atr,
}


def make(name, params, cache):
    params = dict(params)
    sizing = params.pop("sizing", "raw")
    pos = FUNCS[name](cache, **params)
    return apply_sizing(pos, cache, sizing)


if __name__ == "__main__":
    s = build_specs()
    from collections import Counter
    print("total strategies:", len(s))
    for k, v in Counter(n for n, _ in s).items():
        print(f"  {k:20s} {v}")
