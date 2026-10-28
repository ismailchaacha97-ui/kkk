"""
Feature construction for the ORB-Sweep strategy.

Everything here is *causal*: a value attached to bar ``i`` only depends on bars
``<= i``.  ``backtest/test_causality.py`` enforces that property automatically.

The strategy is deliberately indicator-light.  It only uses

* raw price geometry (previous day / week extremes, confirmed swing pivots,
  candle shape),
* market structure (sequence of swing highs/lows, i.e. Dow theory),
* tick-volume participation compared with its own rolling median.

No moving averages, no oscillators, no lagging smoothers take part in the entry
decision (the only EMA in the whole project is the equity filter used for risk
management, not for signals).

All functions return float/int numpy arrays of the same length as the series so
that the MQL4 implementation can mirror them index by index.
"""
from __future__ import annotations

from dataclasses import dataclass, field, asdict

import numpy as np
import pandas as pd

from . import data as D


@dataclass
class Params:
    # --- structure ------------------------------------------------------
    pivot_k: int = 2               # bars on each side that confirm a swing pivot
    sweep_scan: int = 3            # the sweep must be the current bar or the one before
    level_cooldown: int = 12       # bar must not have traded through the level in N bars
    require_htf_trend: int = 0     # 1 = only trade with H4-structure direction
    # --- candle confirmation -------------------------------------------
    min_range_atr: float = 0.60    # signal bar range in ATR units
    close_frac: float = 0.55       # close must be in the top/bottom x of bar range
    # --- volume ---------------------------------------------------------
    vol_lookback: int = 50
    vol_mult: float = 1.30         # rejection must come with volume >= mult * median
    vol_confirm: int = 1           # 1 = volume filter on, 0 = off
    # --- risk ------------------------------------------------------------
    atr_period: int = 14
    sl_atr_buffer: float = 0.35    # stop distance beyond sweep extreme, in ATR
    min_sl_atr: float = 0.55       # stop distance bounds in ATR units (symbol agnostic)
    max_sl_atr: float = 3.20
    rr: float = 1.8                # take-profit in R multiples
    be_at_r: float = 0.9           # move stop to break-even at +xR (0 = off)
    trail_atr: float = 0.0         # chandelier trail multiple of ATR (0 = off)
    max_hold_bars: int = 48        # time stop
    # --- session ---------------------------------------------------------
    session_start: int = 7         # UTC hour, inclusive
    session_end: int = 18          # UTC hour, exclusive
    trade_friday: int = 1
    trade_monday: int = 1
    max_penetration: float = 99.0  # reject raids that go deeper than x*ATR beyond the level
    level_mode: int = 1            # 0 = sweep of the composite extreme level, 1 = sweep of any level
    max_signals_per_day: int = 2
    # --- cost / execution realism ---------------------------------------
    entry_slippage_pips: float = 0.2


@dataclass
class Features:
    """Per-bar arrays shared by the backtest engine and the research tools."""

    time: np.ndarray
    atr: np.ndarray
    pdh: np.ndarray
    pdl: np.ndarray
    pwh: np.ndarray
    pwl: np.ndarray
    swing_hi_1: np.ndarray
    swing_hi_2: np.ndarray
    swing_lo_1: np.ndarray
    swing_lo_2: np.ndarray
    structure: np.ndarray          # +1 up, -1 down, 0 undefined
    rng: np.ndarray
    vol_med: np.ndarray
    hour: np.ndarray
    weekday: np.ndarray
    day: np.ndarray
    ok_long: np.ndarray
    ok_short: np.ndarray
    extra: dict = field(default_factory=dict)


def _pivot_series(high: np.ndarray, low: np.ndarray, k: int):
    """Confirmed pivot highs / lows as two sparse event series.

    A pivot high at ``j`` is only *known* at bar ``j + k``, which is the index it
    is stamped at.  We then keep, for every bar, the last and second-to-last
    confirmed pivot value - this is the market-structure state an EA can observe
    in real time.
    """
    n = len(high)
    ph_ev = np.full(n, np.nan)
    pl_ev = np.full(n, np.nan)
    for j in range(k, n - k):
        h, l = high[j], low[j]
        if h >= high[j - k:j].max() and h >= high[j + 1:j + k + 1].max():
            ph_ev[j + k] = h
        if l <= low[j - k:j].min() and l <= low[j + 1:j + k + 1].min():
            pl_ev[j + k] = l

    def seq(ev):
        a1 = np.full(n, np.nan)  # most recent confirmed pivot value
        a2 = np.full(n, np.nan)  # the one before it
        cur, prev = np.nan, np.nan
        for i in range(n):
            if not np.isnan(ev[i]):
                prev, cur = cur, ev[i]
            a1[i], a2[i] = cur, prev
        return a1, a2

    ph1, ph2 = seq(ph_ev)
    pl1, pl2 = seq(pl_ev)
    return (ph2, ph1), (pl2, pl1)


def build(s: D.Series, p: Params) -> Features:
    n = len(s)
    ts = pd.DatetimeIndex(s.time)

    atr = D.atr(s.high, s.low, s.close, p.atr_period)
    pdh, pdl, pwh, pwl = D.daily_levels(s)
    (ph2, ph1), (pl2, pl1) = _pivot_series(s.high, s.low, p.pivot_k)

    rng = s.high - s.low
    with np.errstate(invalid="ignore", divide="ignore"):
        vol_med = D.rolling_median(s.volume, p.vol_lookback)

    hour = ts.hour.to_numpy()
    weekday = ts.weekday.to_numpy()
    day = ts.floor("D").astype("int64").to_numpy()

    # ---- market structure (Dow): higher highs and higher lows vs previous pivot
    structure = np.zeros(n, dtype=np.int8)
    up = (ph1 > ph2) & (pl1 > pl2)
    dn = (ph1 < ph2) & (pl1 < pl2)
    structure[up] = 1
    structure[dn] = -1

    # ---- session / day filters
    in_session = (hour >= p.session_start) & (hour < p.session_end)
    dow_ok = np.ones(n, dtype=bool)
    if not p.trade_friday:
        dow_ok &= weekday != 4
    if not p.trade_monday:
        dow_ok &= weekday != 0

    # ---- candle geometry
    with np.errstate(invalid="ignore", divide="ignore"):
        upper = (s.close - s.low) / rng      # where the close sits in the bar (0=low,1=high)
        lower = (s.high - s.close) / rng
    big_enough = rng >= p.min_range_atr * atr
    vol_ok = (s.volume >= p.vol_mult * vol_med) if p.vol_confirm else np.ones(n, dtype=bool)

    base = atr > 0
    base &= in_session & dow_ok & big_enough & vol_ok
    if p.require_htf_trend:
        base_long = base & (structure >= 0)
        base_short = base & (structure <= 0)
    else:
        base_long = base_short = base

    # ---- liquidity levels -------------------------------------------------
    # resistance candidates (a raid above them that fails = short setup)
    # support candidates (a raid below them that fails = long setup)
    if p.level_mode == 0:
        lvl_h_list = [np.maximum.reduce([pdh, pwh, ph1])]
        lvl_l_list = [np.minimum.reduce([pdl, pwl, pl1])]
    else:
        lvl_h_list = [pdh, pwh, ph1, ph2]
        lvl_l_list = [pdl, pwl, pl1, pl2]

    cd = p.level_cooldown
    short_cond = np.zeros(n, dtype=bool)
    long_cond = np.zeros(n, dtype=bool)
    best_h = np.full(n, np.nan)
    best_l = np.full(n, np.nan)
    for L in lvl_h_list:
        L = np.asarray(L, dtype=float)
        valid = np.isfinite(L)
        touched = _recent_touch_against(s.high, L, cd)   # price already traded at/above L
        c = valid & (s.high > L) & (s.close < L) & (~touched)
        if p.max_penetration < 90.0:
            c &= ((s.high - L) <= p.max_penetration * atr)
        short_cond |= c
        best_h = np.where(c, np.fmax(best_h, L), best_h)
    for L in lvl_l_list:
        L = np.asarray(L, dtype=float)
        valid = np.isfinite(L)
        touched = _recent_touch_against(s.low, L, cd, above=False)
        c = valid & (s.low < L) & (s.close > L) & (~touched)
        if p.max_penetration < 90.0:
            c &= ((L - s.low) <= p.max_penetration * atr)
        long_cond |= c
        best_l = np.where(c, np.fmin(best_l, L), best_l)

    ok_short = base_short & short_cond & (lower >= p.close_frac)
    ok_long = base_long & long_cond & (upper >= p.close_frac)
    both = ok_long & ok_short
    ok_long &= ~both
    ok_short &= ~both

    lvl_h = np.where(np.isfinite(best_h), best_h, np.nan)
    lvl_l = np.where(np.isfinite(best_l), best_l, np.nan)

    return Features(
        time=s.time, atr=atr, pdh=pdh, pdl=pdl, pwh=pwh, pwl=pwl,
        swing_hi_1=ph1, swing_hi_2=ph2, swing_lo_1=pl1, swing_lo_2=pl2,
        structure=structure, rng=rng, vol_med=vol_med,
        hour=hour, weekday=weekday, day=day, ok_long=ok_long, ok_short=ok_short,
        extra=dict(lvl_h=lvl_h, lvl_l=lvl_l),
    )


def _recent_touch_against(x: np.ndarray, level: np.ndarray, n: int, above: bool = True) -> np.ndarray:
    """True where a previous bar (last ``n``) already traded through ``level``."""
    xs = pd.Series(x)
    if above:
        prev = xs.shift(1).rolling(n, min_periods=1).max().to_numpy()
        return prev >= level
    prev = xs.shift(1).rolling(n, min_periods=1).min().to_numpy()
    return prev <= level


def _recent_touch(x: np.ndarray, n: int, above: bool) -> np.ndarray:
    """True where the running extreme of the previous ``n`` bars reached ``x``.

    Used as a cooldown: we want the *first* raid of a level, not a level price
    has been chewing through for hours.
    """
    s = pd.Series(x)
    if above:
        prev_max = s.shift(1).rolling(n, min_periods=1).max().to_numpy()
        return prev_max >= x
    prev_min = s.shift(1).rolling(n, min_periods=1).min().to_numpy()
    return prev_min <= x
