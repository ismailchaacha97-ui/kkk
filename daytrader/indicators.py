"""Small, dependency-light indicator helpers used by the strategies.

Everything here is pure pandas/numpy so it can be unit tested without
NautilusTrader and reused for research notebooks or vectorised screening.
All functions expect a DataFrame whose index is a timezone-aware
``DatetimeIndex`` (session grouping is done in the exchange timezone).
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from daytrader import MARKET_TZ

__all__ = [
    "atr",
    "opening_range",
    "rolling_median_volume",
    "session_vwap",
    "session_vwap_bands",
    "true_range",
]


def _market_index(index: pd.Index) -> pd.DatetimeIndex:
    """Return ``index`` as a tz-aware DatetimeIndex in market time."""
    if not isinstance(index, pd.DatetimeIndex):
        raise TypeError("expected a pandas DatetimeIndex")
    if index.tz is None:
        return index.tz_localize(MARKET_TZ)
    return index.tz_convert(MARKET_TZ)


def session_ids(index: pd.Index) -> pd.Index:
    """Session (calendar-day in market time) label for every bar."""
    return _market_index(index).normalize()


def true_range(high: pd.Series, low: pd.Series, close: pd.Series) -> pd.Series:
    """Wilder's true range, using the previous close within the same series."""
    previous_close = close.shift(1)
    ranges = pd.concat(
        [
            high - low,
            (high - previous_close).abs(),
            (low - previous_close).abs(),
        ],
        axis=1,
    )
    tr = ranges.max(axis=1)
    tr.iloc[0] = float(high.iloc[0] - low.iloc[0])
    return tr


def atr(
    high: pd.Series,
    low: pd.Series,
    close: pd.Series,
    period: int = 14,
) -> pd.Series:
    """Average true range using Wilder's smoothing (EMA with alpha=1/period)."""
    if period < 1:
        raise ValueError("period must be >= 1")
    tr = true_range(high, low, close)
    return tr.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean()


def session_vwap(df: pd.DataFrame) -> pd.Series:
    """Cumulative session VWAP of the typical price, reset each session."""
    if not {"high", "low", "close", "volume"}.issubset(df.columns):
        raise ValueError("df must contain high, low, close and volume")
    sessions = session_ids(df.index)
    typical = (df["high"] + df["low"] + df["close"]) / 3.0
    notional = (typical * df["volume"]).groupby(sessions).cumsum()
    volume = df["volume"].groupby(sessions).cumsum().replace(0, np.nan)
    return (notional / volume).rename("vwap")


def session_vwap_bands(
    df: pd.DataFrame,
    band_k: float = 2.0,
) -> pd.DataFrame:
    """Session VWAP plus ``band_k`` cumulative volume-weighted std bands.

    Returns a DataFrame with columns ``vwap``, ``upper``, ``lower`` and
    ``band_width``. Values are NaN until the first bar with volume.
    """
    if band_k <= 0:
        raise ValueError("band_k must be > 0")
    sessions = session_ids(df.index)
    typical = (df["high"] + df["low"] + df["close"]) / 3.0
    volume = df["volume"].astype(float)

    grouped_volume = volume.groupby(sessions)
    cumulative_volume = grouped_volume.cumsum().replace(0, np.nan)
    vwap = (typical * volume).groupby(sessions).cumsum() / cumulative_volume

    squared_deviation = (typical - vwap) ** 2 * volume
    variance = squared_deviation.groupby(sessions).cumsum() / cumulative_volume
    std = np.sqrt(variance.clip(lower=0.0))

    return pd.DataFrame(
        {
            "vwap": vwap,
            "upper": vwap + band_k * std,
            "lower": vwap - band_k * std,
            "band_width": 2.0 * band_k * std,
        },
        index=df.index,
    )


def opening_range(
    high: pd.Series,
    low: pd.Series,
    n_bars: int,
) -> tuple[float, float]:
    """High/low of the first ``n_bars`` of the session.

    Raises ``ValueError`` when fewer than ``n_bars`` observations are supplied,
    which forces callers to wait for the range to be complete.
    """
    if n_bars < 1:
        raise ValueError("n_bars must be >= 1")
    if len(high) < n_bars or len(low) < n_bars:
        raise ValueError(f"need at least {n_bars} bars to build the opening range")
    return float(high.iloc[:n_bars].max()), float(low.iloc[:n_bars].min())


def rolling_median_volume(volume: pd.Series, window: int = 20) -> pd.Series:
    """Rolling median volume, used as the volume-expansion yardstick."""
    if window < 1:
        raise ValueError("window must be >= 1")
    return volume.rolling(window=window, min_periods=1).median()
