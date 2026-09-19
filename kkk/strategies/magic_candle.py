"""Method A — the "Magic Candle" long-body / 50%-retracement method.

Rule set (parameterised so the runner can sweep it)
---------------------------------------------------
1.  Signal candle: a *long body* candle — body/range >= `min_body_ratio`
    AND body >= `body_atr_mult` x ATR. This is the "magic candle": evidence
    of one-sided intent.
2.  Optional momentum filter: no opposite-direction magic candle in the
    previous `no_opposite_lookback` bars (kills the chop that this family
    of strategies is famous for).
3.  Entry: a limit order at the **50% of the candle body**
    (`entry_mode='body_mid'`) or of the full range (`entry_mode='range_mid'`).
    The pullback into the midpoint is what makes the risk small.
4.  Stop: `stop_buffer` x ATR beyond the candle's extreme (one tick in the
    original teaching; ATR-scaled here so it travels across instruments).
5.  Target: `rr` x risk.

Every rule above is a parameter so the sweep can find out which parts
actually carry the edge — or whether none of them do.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from ..engine import Signal
from ..primitives import atr, candle_at

NAME = "magic_candle"
TITLE = "Magic Candle (long-body candle + 50% retracement entry)"
DESCRIPTION = __doc__

DEFAULT_PARAMS = {
    "min_body_ratio": 0.70,
    "body_atr_mult": 1.2,
    "atr_period": 14,
    "entry_mode": "body_mid",
    "stop_buffer_atr": 0.15,
    "rr": 3.0,
    "valid_for": 5,
    "no_opposite_lookback": 0,
    "trend_filter": "none",     # none | ema
    "ema_period": 200,
}

SWEEP = {
    "min_body_ratio": [0.6, 0.7, 0.8],
    "body_atr_mult": [1.0, 1.2, 1.5],
    "rr": [2.0, 3.0, 4.0],
    "stop_buffer_atr": [0.0, 0.15, 0.35],
}

WARMUP = 220


def generate(df: pd.DataFrame, **params) -> list[Signal]:
    p = {**DEFAULT_PARAMS, **params}
    n = len(df)
    atr_s = atr(df, int(p["atr_period"])).to_numpy(float)
    o = df["open"].to_numpy(float)
    c = df["close"].to_numpy(float)
    h = df["high"].to_numpy(float)
    l = df["low"].to_numpy(float)

    ema_s = None
    if p["trend_filter"] == "ema":
        ema_s = (
            df["close"]
            .ewm(span=int(p["ema_period"]), adjust=False, min_periods=int(p["ema_period"]))
            .mean()
            .to_numpy(float)
        )

    signals: list[Signal] = []
    recent_sign: list[int] = []

    for i in range(WARMUP, n):
        a = atr_s[i]
        if not np.isfinite(a) or a <= 0:
            continue
        rng = h[i] - l[i]
        if rng <= 0:
            continue
        body = abs(c[i] - o[i])
        if body / rng < p["min_body_ratio"]:
            continue
        if body < p["body_atr_mult"] * a:
            continue

        sign = 1 if c[i] > o[i] else -1

        if p["trend_filter"] == "ema" and ema_s is not None and np.isfinite(ema_s[i]):
            if sign > 0 and c[i] < ema_s[i]:
                continue
            if sign < 0 and c[i] > ema_s[i]:
                continue

        if p["no_opposite_lookback"]:
            lb = int(p["no_opposite_lookback"])
            if any(s == -sign for s in recent_sign[-lb:]):
                continue

        cnd = candle_at(df, i)
        level = cnd.mid if p["entry_mode"] == "body_mid" else (h[i] + l[i]) / 2.0

        buffer = p["stop_buffer_atr"] * a
        if sign > 0:
            stop = l[i] - buffer
            if stop >= level:                       # degenerate geometry
                continue
            target = level + p["rr"] * (level - stop)
        else:
            stop = h[i] + buffer
            if stop <= level:
                continue
            target = level - p["rr"] * (stop - level)

        signals.append(
            Signal(
                direction="long" if sign > 0 else "short",
                stop=float(stop),
                target=float(target),
                entry=float(level),
                valid_for=int(p["valid_for"]),
                tag=f"mc{sign:+d}",
                bar=i,
            )
        )
        recent_sign.append(sign)

    return signals
