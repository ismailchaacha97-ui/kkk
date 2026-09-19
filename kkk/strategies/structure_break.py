"""Method C — structure / break-of-structure (the "Majed Al-Tounsi" family).

Rule set
--------
1.  Build market structure from confirmed fractal swings (a swing only
    exists `swing_right` bars after it prints — no peeking).
2.  Classify the recent structure as up / down / range from the last
    `structure_lookback` swing highs and lows.
3.  Reversal mode (`mode='reversal'`): in a down structure, a close back
    **above the last confirmed swing high** is a change of character ->
    buy. Mirror for a sell. This is the "break the structure, then trade
    the new direction" idea.
4.  Continuation mode (`mode='continuation'`): in an up structure, a close
    above the last swing high continues the trend -> buy.
5.  Entry: market at next open. Stop: beyond the last opposite swing
    (`stop_swing_lookback` swings back), plus `stop_buffer_atr` x ATR.
6.  Target: `rr` x risk.

This is the most subjective of the three methods when taught by hand, so
the code makes each piece of the discretion an explicit switch.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from ..engine import Signal
from ..primitives import SwingIndex, atr

NAME = "structure_break"
TITLE = "Structure Break / BOS (swing structure + change of character)"
DESCRIPTION = __doc__

DEFAULT_PARAMS = {
    "swing_left": 2,
    "swing_right": 2,
    "structure_lookback": 3,
    "mode": "reversal",          # reversal | continuation
    "stop_swing_lookback": 1,
    "stop_buffer_atr": 0.2,
    "atr_period": 14,
    "rr": 2.0,
    "valid_for": 1,
    "min_break_atr": 0.0,
    "sessions": None,
}

SWEEP = {
    "swing_left": [2, 3, 5],
    "mode": ["reversal", "continuation"],
    "rr": [1.5, 2.0, 3.0],
    "stop_swing_lookback": [1, 2, 3],
}

WARMUP = 240


def generate(df: pd.DataFrame, **params) -> list[Signal]:
    p = {**DEFAULT_PARAMS, **params}
    n = len(df)
    atr_s = atr(df, int(p["atr_period"])).to_numpy(float)
    c = df["close"].to_numpy(float)

    si = SwingIndex(df, int(p["swing_left"]), int(p["swing_right"]))
    sessions = p["sessions"]
    has_session = "session" in df.columns
    sess = df["session"].to_numpy() if has_session else None

    signals: list[Signal] = []
    last_break_bar = -10**9

    for i in range(WARMUP, n):
        a = atr_s[i]
        if not np.isfinite(a) or a <= 0:
            continue
        if sessions is not None:
            if not has_session:
                raise ValueError("sessions filter needs data.add_sessions()")
            if sess[i] not in sessions:
                continue

        struct = si.structure(i, int(p["structure_lookback"]))
        if struct == "range":
            continue

        sh = si.last_high(i)
        sl = si.last_low(i)
        if sh is None or sl is None:
            continue
        _, swing_high = sh
        _, swing_low = sl

        min_break = p["min_break_atr"] * a

        direction = 0
        if p["mode"] == "reversal":
            if struct == "down" and c[i] > swing_high + min_break:
                direction = 1
            elif struct == "up" and c[i] < swing_low - min_break:
                direction = -1
        else:
            if struct == "up" and c[i] > swing_high + min_break:
                direction = 1
            elif struct == "down" and c[i] < swing_low - min_break:
                direction = -1

        if direction == 0 or i - last_break_bar < int(p["swing_right"]):
            continue

        if direction > 0:
            stops = si.lows_before(i, int(p["stop_swing_lookback"]) + 1)
            raw_stop = min([swing_low] + stops)
            stop = raw_stop - p["stop_buffer_atr"] * a
            entry = c[i]
            risk = entry - stop
            if risk <= 0:
                continue
            target = entry + p["rr"] * risk
        else:
            stops = si.highs_before(i, int(p["stop_swing_lookback"]) + 1)
            raw_stop = max([swing_high] + stops)
            stop = raw_stop + p["stop_buffer_atr"] * a
            entry = c[i]
            risk = stop - entry
            if risk <= 0:
                continue
            target = entry - p["rr"] * risk

        signals.append(
            Signal(
                direction="long" if direction > 0 else "short",
                stop=float(stop),
                target=float(target),
                entry=None,
                valid_for=int(p["valid_for"]),
                tag=f"bos{struct}",
                bar=i,
            )
        )
        last_break_bar = i

    return signals
