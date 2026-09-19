"""Method B — the "Liquidity Candle" sweep method.

Rule set
--------
1.  Reference level: the lowest low (for longs) of the previous `lookback`
    bars — i.e. where resting sell stops sit.
2.  Sweep: bar i pierces that low (`low[i] < level - min_pierce_atr x ATR`)
    but **closes back above it**. The liquidity was taken and rejected.
3.  Reclaim quality filter: close must finish in the upper
    `reclaim_frac` of the bar's range (mirror for shorts).
4.  Optional location filter: only take the sweep if it happens inside a
    session killzone (`sessions` param, requires the `session` column).
5.  Entry: market at next open.
6.  Stop: beyond the sweep extreme + `stop_buffer_atr` x ATR.
7.  Target: `rr` x risk.

Set `pierce_close_only=True` to make the sweep require a *close* beyond the
level instead of a wick — that is the "liquidity run / continuation" variant,
which trades in the opposite direction of the wick version.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from ..engine import Signal
from ..primitives import atr

NAME = "liquidity_candle"
TITLE = "Liquidity Candle (sweep of resting stops + reclaim)"
DESCRIPTION = __doc__

DEFAULT_PARAMS = {
    "lookback": 20,
    "min_pierce_atr": 0.0,
    "reclaim_frac": 0.5,
    "atr_period": 14,
    "stop_buffer_atr": 0.2,
    "rr": 2.0,
    "valid_for": 1,
    "sessions": None,          # e.g. ("london", "overlap")
    "pierce_close_only": False,
    "trend_filter": "none",
    "ema_period": 200,
}

SWEEP = {
    "lookback": [10, 20, 40],
    "rr": [1.5, 2.0, 3.0],
    "min_pierce_atr": [0.0, 0.1, 0.25],
    "reclaim_frac": [0.3, 0.5, 0.7],
}

WARMUP = 220


def generate(df: pd.DataFrame, **params) -> list[Signal]:
    p = {**DEFAULT_PARAMS, **params}
    n = len(df)
    atr_s = atr(df, int(p["atr_period"])).to_numpy(float)
    o = df["open"].to_numpy(float)
    h = df["high"].to_numpy(float)
    l = df["low"].to_numpy(float)
    c = df["close"].to_numpy(float)

    sessions = p["sessions"]
    has_session = "session" in df.columns
    sess = df["session"].to_numpy() if has_session else None

    ema_s = None
    if p["trend_filter"] == "ema":
        ema_s = (
            df["close"]
            .ewm(span=int(p["ema_period"]), adjust=False, min_periods=int(p["ema_period"]))
            .mean()
            .to_numpy(float)
        )

    lb = int(p["lookback"])
    signals: list[Signal] = []

    for i in range(max(WARMUP, lb + 1), n):
        a = atr_s[i]
        if not np.isfinite(a) or a <= 0:
            continue
        if sessions is not None:
            if not has_session:
                raise ValueError("sessions filter needs data.add_sessions()")
            if sess[i] not in sessions:
                continue

        rng = h[i] - l[i]
        if rng <= 0:
            continue

        ref_low = float(l[i - lb : i].min())
        ref_high = float(h[i - lb : i].max())
        pierce = p["min_pierce_atr"] * a

        # --- bullish sweep: took sell-side liquidity below the range low ---
        if not p["pierce_close_only"]:
            swept_low = l[i] < ref_low - pierce and c[i] > ref_low
        else:
            swept_low = c[i] < ref_low - pierce
        pos_in_bar = (c[i] - l[i]) / rng
        if swept_low and pos_in_bar >= p["reclaim_frac"]:
            aligned = ema_s is None or not np.isfinite(ema_s[i]) or c[i] >= ema_s[i]
            if not aligned:
                pass  # counter-trend sweep — filtered out below
            stop = l[i] - p["stop_buffer_atr"] * a
            entry = c[i]
            risk = entry - stop
            if risk > 0 and aligned:
                signals.append(
                    Signal(
                        direction="long",
                        stop=float(stop),
                        target=float(entry + p["rr"] * risk),
                        entry=None,
                        valid_for=int(p["valid_for"]),
                        tag="lc-sweep-low",
                        bar=i,
                    )
                )
                continue

        # --- bearish sweep: took buy-side liquidity above the range high ---
        if not p["pierce_close_only"]:
            swept_high = h[i] > ref_high + pierce and c[i] < ref_high
        else:
            swept_high = c[i] > ref_high + pierce
        pos_in_bar_down = (h[i] - c[i]) / rng
        if swept_high and pos_in_bar_down >= p["reclaim_frac"]:
            aligned = ema_s is None or not np.isfinite(ema_s[i]) or c[i] <= ema_s[i]
            stop = h[i] + p["stop_buffer_atr"] * a
            entry = c[i]
            risk = stop - entry
            if risk > 0 and aligned:
                signals.append(
                    Signal(
                        direction="short",
                        stop=float(stop),
                        target=float(entry - p["rr"] * risk),
                        entry=None,
                        valid_for=int(p["valid_for"]),
                        tag="lc-sweep-high",
                        bar=i,
                    )
                )

    return signals
