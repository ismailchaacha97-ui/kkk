"""Shared building blocks: candle anatomy, swings, ranges, session levels."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


# ---------------------------------------------------------------- candles
@dataclass(frozen=True)
class Candle:
    o: float
    h: float
    l: float
    c: float

    @property
    def body(self) -> float:
        return abs(self.c - self.o)

    @property
    def range(self) -> float:
        return self.h - self.l

    @property
    def bullish(self) -> bool:
        return self.c > self.o

    @property
    def bearish(self) -> bool:
        return self.c < self.o

    @property
    def upper_wick(self) -> float:
        return self.h - max(self.o, self.c)

    @property
    def lower_wick(self) -> float:
        return min(self.o, self.c) - self.l

    @property
    def mid(self) -> float:
        return (self.o + self.c) / 2.0

    @property
    def body_top(self) -> float:
        return max(self.o, self.c)

    @property
    def body_bottom(self) -> float:
        return min(self.o, self.c)

    def body_frac(self) -> float:
        return self.body / self.range if self.range > 0 else 0.0


def candle_at(df: pd.DataFrame, i: int) -> Candle:
    r = df.iloc[i]
    return Candle(float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"]))


def body_ratio(df: pd.DataFrame, i: int) -> float:
    """Body / range of bar i, 0..1."""
    r = df.iloc[i]
    rng = float(r["high"]) - float(r["low"])
    if rng <= 0:
        return 0.0
    return abs(float(r["close"]) - float(r["open"])) / rng


def is_pin_bar(df: pd.DataFrame, i: int, wick_frac: float = 0.6) -> tuple[bool, int]:
    """Pin bar: one dominant wick >= `wick_frac` of the range.

    Returns (is_pin, direction) where direction is +1 for a bullish pin
    (long lower wick) and -1 for a bearish pin (long upper wick).
    """
    cnd = candle_at(df, i)
    if cnd.range <= 0:
        return False, 0
    up, lo = cnd.upper_wick / cnd.range, cnd.lower_wick / cnd.range
    if lo >= wick_frac and lo > up:
        return True, 1
    if up >= wick_frac and up > lo:
        return True, -1
    return False, 0


def is_engulfing(df: pd.DataFrame, i: int, min_body_pct: float = 0.0) -> int:
    """Bullish/bearish engulfing at bar i. Returns +1 / -1 / 0."""
    if i < 1:
        return 0
    prev = candle_at(df, i - 1)
    cur = candle_at(df, i)
    if cur.range <= 0 or prev.range <= 0:
        return 0
    if min_body_pct and cur.body < prev.body * min_body_pct:
        return 0
    if (
        cur.bullish
        and prev.bearish
        and cur.c > prev.o
        and cur.o < prev.c
    ):
        return 1
    if (
        cur.bearish
        and prev.bullish
        and cur.c < prev.o
        and cur.o > prev.c
    ):
        return -1
    return 0


def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """Wilder ATR."""
    h, l, c = df["high"], df["low"], df["close"]
    prev_c = c.shift(1)
    tr = pd.concat([h - l, (h - prev_c).abs(), (l - prev_c).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / period, adjust=False, min_periods=period).mean()


def ema(s: pd.Series, period: int) -> pd.Series:
    return s.ewm(span=period, adjust=False, min_periods=period).mean()


# ----------------------------------------------------------------- swings
def swing_points(df: pd.DataFrame, left: int = 2, right: int = 2) -> pd.DataFrame:
    """Fractal swing highs/lows.

    A swing high at bar i requires high[i] to be strictly greater than the
    `left` bars before and the `right` bars after it. Because `right` future
    bars are needed for confirmation, signals built on swings must only ever
    reference swings confirmed at or before the signal bar.
    """
    h, l = df["high"].to_numpy(float), df["low"].to_numpy(float)
    n = len(df)
    sh = np.zeros(n, bool)
    sl = np.zeros(n, bool)
    for i in range(left, n - right):
        window_h = h[i - left : i + right + 1]
        window_l = l[i - left : i + right + 1]
        if h[i] == window_h.max() and (window_h.argmax() == left):
            sh[i] = True
        if l[i] == window_l.min() and (window_l.argmin() == left):
            sl[i] = True
    out = pd.DataFrame({"swing_high": sh, "swing_low": sl}, index=df.index)
    return out


class SwingIndex:
    """O(log n) lookup of confirmed swings — safe to call inside a hot loop.

    A swing printed at bar j only exists for the trader at bar j + `right`,
    so every query subtracts `right` before searching. This is what keeps the
    backtest honest.
    """

    def __init__(self, df: pd.DataFrame, left: int = 2, right: int = 2):
        self.right = right
        self._sw = swing_points(df, left, right)
        self.high_bars = np.flatnonzero(self._sw["swing_high"].to_numpy())
        self.low_bars = np.flatnonzero(self._sw["swing_low"].to_numpy())
        self._high = df["high"].to_numpy(float)
        self._low = df["low"].to_numpy(float)

    def _last(self, bars: np.ndarray, i: int) -> int | None:
        upto = i - self.right
        if upto < 0 or len(bars) == 0:
            return None
        k = np.searchsorted(bars, upto, side="right") - 1
        return int(bars[k]) if k >= 0 else None

    def last_high(self, i: int) -> tuple[int, float] | None:
        j = self._last(self.high_bars, i)
        return None if j is None else (j, float(self._high[j]))

    def last_low(self, i: int) -> tuple[int, float] | None:
        j = self._last(self.low_bars, i)
        return None if j is None else (j, float(self._low[j]))

    def highs_before(self, i: int, n: int) -> list[float]:
        upto = i - self.right
        bars = self.high_bars[self.high_bars <= upto][-n:]
        return [float(self._high[b]) for b in bars]

    def lows_before(self, i: int, n: int) -> list[float]:
        upto = i - self.right
        bars = self.low_bars[self.low_bars <= upto][-n:]
        return [float(self._low[b]) for b in bars]

    def structure(self, i: int, lookback: int = 3) -> str:
        """'up' | 'down' | 'range' from the last `lookback` swings each side."""
        hs = self.highs_before(i, lookback)
        ls = self.lows_before(i, lookback)
        if len(hs) < 2 or len(ls) < 2:
            return "range"
        higher_highs = all(b > a for a, b in zip(hs, hs[1:]))
        higher_lows = all(b > a for a, b in zip(ls, ls[1:]))
        lower_highs = all(b < a for a, b in zip(hs, hs[1:]))
        lower_lows = all(b < a for a, b in zip(ls, ls[1:]))
        if higher_highs and higher_lows:
            return "up"
        if lower_highs and lower_lows:
            return "down"
        return "range"


# ----------------------------------------------------------------- ranges
def rolling_range(df: pd.DataFrame, i: int, lookback: int) -> tuple[float, float]:
    """High/low of the `lookback` bars ending *before* bar i."""
    start = max(0, i - lookback)
    if start >= i:
        return float(df["high"].iloc[i]), float(df["low"].iloc[i])
    win = df.iloc[start:i]
    return float(win["high"].max()), float(win["low"].min())


def session_levels(df: pd.DataFrame, session: str = "asia") -> pd.DataFrame:
    """Per-day high/low of a named session (needs `session` column)."""
    if "session" not in df.columns:
        raise ValueError("call data.add_sessions() first")
    mask = df["session"] == session
    sub = df[mask]
    if sub.empty:
        return pd.DataFrame(columns=["high", "low", "start", "end"])
    days = sub.index.normalize()
    g = sub.groupby(days)
    return pd.DataFrame(
        {
            "high": g["high"].max(),
            "low": g["low"].min(),
            "start": g.apply(lambda x: x.index[0]),
            "end": g.apply(lambda x: x.index[-1]),
        }
    )


def equal_levels(prices: list[float], tolerance: float) -> list[float]:
    """Cluster near-identical levels (equal highs / equal lows = liquidity)."""
    if not prices:
        return []
    prices = sorted(prices)
    clusters, cur = [], [prices[0]]
    for p in prices[1:]:
        if abs(p - cur[-1]) <= tolerance:
            cur.append(p)
        else:
            clusters.append(cur)
            cur = [p]
    clusters.append(cur)
    return [float(np.mean(cl)) for cl in clusters if len(cl) >= 2]


def find_fair_value_gap(df: pd.DataFrame, i: int, sign: int, min_size: float = 0.0):
    """3-candle imbalance ending at bar i.

    Bullish FVG: low[i] > high[i-2]  -> gap between those two wicks.
    Bearish FVG: high[i] < low[i-2].
    Returns the gap (top, bottom) or None.
    """
    if i < 2:
        return None
    if sign > 0:
        bottom, top = float(df["high"].iloc[i - 2]), float(df["low"].iloc[i])
    else:
        bottom, top = float(df["high"].iloc[i]), float(df["low"].iloc[i - 2])
    if top <= bottom:
        return None
    if (top - bottom) < min_size:
        return None
    return (top, bottom)
