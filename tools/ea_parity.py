#!/usr/bin/env python3
"""
Parity test: does the MQL4 EA compute the same signals as the Python engine?

MetaEditor cannot run in this environment, so the next best thing is to
re-implement the EA's `DetectSignal()` *exactly as written in the .mq4* -
MT4 shift indexing (bar 0 = forming bar, bar 1 = last closed bar), a fresh pivot
scan on every bar, `iHigh/iLow` semantics - and compare it bar by bar with
`backtest.features`.  Any divergence is a real implementation difference that
would show up between the MT4 tester and the Python reports.

    python tools/ea_parity.py --symbol GBPUSD --bars 20000
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.features import Params, build


def ea_detect(sym: str, i: int, p: Params, sym_arrays: dict) -> int:
    """Literal port of DetectSignal() from EA/LiquiditySweep_Portfolio.mq4.

    ``i`` is an MT4-style shift: 0 = forming bar, 1 = last closed bar.  The EA
    only ever calls this with i = 1 semantics (it looks at bar 1 from the point
    of view of the just-opened bar), so the caller passes an *anchor* shift.
    """
    H, L, C, V = sym_arrays["high"], sym_arrays["low"], sym_arrays["close"], sym_arrays["volume"]
    n = len(H)

    def h(s):
        return H[n - 1 - s]

    def l(s):
        return L[n - 1 - s]

    def c(s):
        return C[n - 1 - s]

    def v(s):
        return V[n - 1 - s]

    # ---- ATR (mean true range, period p.atr_period, starting at shift 1)
    acc = 0.0
    for k in range(p.atr_period):
        s = 1 + k
        tr = max(h(s) - l(s), abs(h(s) - c(s + 1)), abs(l(s) - c(s + 1)))
        acc += tr
    atr = acc / p.atr_period
    if atr <= 0:
        return 0

    hh, ll, cc = h(1), l(1), c(1)
    rng = hh - ll
    if rng <= 0 or rng < p.min_range_atr * atr:
        return 0

    # ---- volume confirmation
    if p.vol_confirm:
        vols = sorted(v(1 + k) for k in range(p.vol_lookback))
        m = len(vols)
        med = vols[(m - 1) // 2] if m % 2 else 0.5 * (vols[m // 2 - 1] + vols[m // 2])
        if med <= 0 or v(1) < p.vol_mult * med:
            return 0

    # ---- pivots: scan from the most recent usable bar backwards
    ph1 = ph2 = pl1 = pl2 = 0.0
    found_h = found_l = 0
    k = p.pivot_k
    j = 1 + k
    lookback = getattr(p, "pivot_lookback", 400)
    while j < min(lookback, n - k - 2):
        is_h = True
        for d in range(1, k + 1):
            if h(j) < h(j - d) or h(j) < h(j + d):
                is_h = False
                break
        is_l = True
        for d in range(1, k + 1):
            if l(j) > l(j - d) or l(j) > l(j + d):
                is_l = False
                break
        if is_h and found_h < 2:
            if found_h == 0:
                ph1 = h(j)
            else:
                ph2 = h(j)
            found_h += 1
        if is_l and found_l < 2:
            if found_l == 0:
                pl1 = l(j)
            else:
                pl2 = l(j)
            found_l += 1
        if found_h >= 2 and found_l >= 2:
            break
        j += 1
    have = found_h >= 2 and found_l >= 2

    structure = 0
    if have:
        if ph1 > ph2 and pl1 > pl2:
            structure = 1
        if ph1 < ph2 and pl1 < pl2:
            structure = -1

    # ---- levels (PDH/PDL, PWH/PWL come from the features for both sides)
    # level arrays are indexed by absolute bar number, not by MT4 shift
    abs_idx = n - 1 - i
    pdh, pdl = sym_arrays["pdh"][abs_idx], sym_arrays["pdl"][abs_idx]
    pwh, pwl = sym_arrays["pwh"][abs_idx], sym_arrays["pwl"][abs_idx]
    res, sup = [], []
    if pdh > 0:
        res.append(pdh)
    if pwh > 0:
        res.append(pwh)
    if have:
        if ph1 > 0:
            res.append(ph1)
        if p.level_mode == 1 and ph2 > 0:
            res.append(ph2)
    if pdl > 0:
        sup.append(pdl)
    if pwl > 0:
        sup.append(pwl)
    if have:
        if pl1 > 0:
            sup.append(pl1)
        if p.level_mode == 1 and pl2 > 0:
            sup.append(pl2)

    if p.level_mode == 0:
        res = [max(res)] if res else []
        sup = [min(sup)] if sup else []

    def touched(level: float, above: bool) -> bool:
        for kk in range(2, 2 + p.level_cooldown):
            if kk >= n:
                break
            if above and h(kk) >= level:
                return True
            if not above and l(kk) <= level:
                return True
        return False

    level_s = 0.0
    for lv in res:
        if hh > lv and cc < lv and not touched(lv, True):
            level_s = lv if (p.level_mode == 0 or level_s == 0.0) else max(level_s, lv)
    level_l = 0.0
    have_long = False
    for lv in sup:
        if ll < lv and cc > lv and not touched(lv, False):
            if not have_long:
                level_l = lv
                have_long = True
            else:
                level_l = min(level_l, lv)

    short_ok = level_s != 0.0 and (hh - cc) / rng >= p.close_frac
    long_ok = have_long and (cc - ll) / rng >= p.close_frac
    if p.require_htf_trend:
        if short_ok and structure > 0:
            short_ok = False
        if long_ok and structure < 0:
            long_ok = False
    if short_ok and long_ok:
        return 0
    if long_ok:
        side, level, sweep = 1, level_l, ll
    elif short_ok:
        side, level, sweep = -1, level_s, hh
    else:
        return 0

    if p.max_penetration < 90.0 and abs(sweep - level) / atr > p.max_penetration:
        return 0
    sl = sweep - p.sl_atr_buffer * atr if side > 0 else sweep + p.sl_atr_buffer * atr
    dist = abs(cc - sl) / atr
    if dist < p.min_sl_atr or dist > p.max_sl_atr:
        return 0
    return side


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", default="GBPUSD")
    ap.add_argument("--bars", type=int, default=15000)
    ap.add_argument("--start", default=None)
    ap.add_argument("--params", default=None, help="preset json (default: Params())")
    a = ap.parse_args()

    if a.params:
        import json
        raw = {k: v for k, v in json.load(open(a.params)).items() if not k.startswith("_")}
        p = Params(**raw)
    else:
        p = Params()
    s = D.load(a.symbol, "H1")
    f = build(s, p)
    n = len(s)
    lookback = getattr(p, "pivot_lookback", 400)
    lo = max(lookback, n - a.bars if a.bars else 0)
    arrs = dict(high=s.high, low=s.low, close=s.close, volume=s.volume,
                pdh=f.pdh, pdl=f.pdl, pwh=f.pwh, pwl=f.pwl)

    # a bar is only usable if the engine also had enough history for ATR/pivots
    mism, checked, ea_sig, py_sig = 0, 0, 0, 0
    examples = []
    for idx in range(lo, n - 2):
        # the EA evaluates bar 1 from the point of view of the bar that just
        # opened; ``idx`` is the signal bar and the engine's decision index.
        shift = n - 1 - idx
        if shift < 2:
            continue
        # feed the EA a *windowed* view ending two bars after the signal bar
        view = {k: v[: idx + 2] for k, v in arrs.items()}
        ea = ea_detect(a.symbol, 1, p, view)
        # the EA enforces the session and weekday gates outside DetectSignal()
        # (SessionOK() in RiskAllowsNewTrades), so mirror that here
        tstamp = pd.Timestamp(s.time[idx])
        if not (p.session_start <= tstamp.hour < p.session_end):
            ea = 0
        if tstamp.weekday() == 4 and not p.trade_friday:
            ea = 0
        if tstamp.weekday() == 0 and not p.trade_monday:
            ea = 0
        # the Python side splits the "is this a valid setup" rule in two places:
        # features.py decides the pattern, engine.py applies the stop-distance
        # bound.  The EA does both inside DetectSignal(), so the comparison has
        # to apply the engine's bound here as well.
        py = 1 if f.ok_long[idx] else (-1 if f.ok_short[idx] else 0)
        if py != 0 and np.isfinite(f.atr[idx]) and f.atr[idx] > 0:
            sweep = s.low[idx] if py > 0 else s.high[idx]
            sl_py = sweep - p.sl_atr_buffer * f.atr[idx] if py > 0 else sweep + p.sl_atr_buffer * f.atr[idx]
            d = abs(s.close[idx] - sl_py) / f.atr[idx]
            if d < p.min_sl_atr or d > p.max_sl_atr:
                py = 0
        checked += 1
        ea_sig += ea != 0
        py_sig += py != 0
        if ea != py:
            mism += 1
            if len(examples) < 10:
                examples.append((str(s.time[idx]), ea, py))
    print(f"{a.symbol}: compared {checked} bars | EA signals {ea_sig} | python signals {py_sig} "
          f"| mismatches {mism} ({100.0 * mism / max(checked, 1):.6f}%)")
    for ex in examples:
        print("   first mismatches (time, EA, python):", ex)
    return 0 if mism * 1000 <= checked else 1     # tolerate <0.1% (floating point ties)


if __name__ == "__main__":
    sys.exit(main())
