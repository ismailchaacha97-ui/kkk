"""
Market-data loading and normalisation.

The CSVs live in ``<repo>/data`` as ``<SYMBOL>_<TF>.csv`` with the header
``time,open,high,low,close,volume`` and UTC timestamps (see tools/fetch_data.py).

Everything downstream works on plain numpy arrays so the event loop stays fast
and, more importantly, so the Python reference engine maps 1:1 onto the MQL4
implementation (which also only ever sees OHLC + tick volume arrays).
"""
from __future__ import annotations

import os
from dataclasses import dataclass

import numpy as np
import pandas as pd

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")

# pip size / contract specifics used by the copy-trading-free reference backtest
INSTRUMENTS = {
    #             pip     contract   typical  round-trip cost (pips, incl. commission)
    "EURUSD": dict(pip=0.0001, contract=100000, cost_pips=1.0, spread_pips=0.8),
    "GBPUSD": dict(pip=0.0001, contract=100000, cost_pips=1.2, spread_pips=0.9),
    "AUDUSD": dict(pip=0.0001, contract=100000, cost_pips=1.2, spread_pips=0.9),
    "USDJPY": dict(pip=0.01, contract=100000, cost_pips=1.0, spread_pips=0.8),
    "XAUUSD": dict(pip=0.01, contract=100, cost_pips=4.0, spread_pips=2.5),
}


@dataclass
class Series:
    """OHLCV arrays for one symbol, plus derived time helpers."""

    symbol: str
    time: np.ndarray  # datetime64[ns] UTC
    open: np.ndarray
    high: np.ndarray
    low: np.ndarray
    close: np.ndarray
    volume: np.ndarray

    def __len__(self) -> int:
        return len(self.close)


def load(symbol: str, timeframe: str = "H1") -> Series:
    path = os.path.join(DATA_DIR, f"{symbol}_{timeframe}.csv")
    if not os.path.exists(path):
        raise FileNotFoundError(
            f"{path} missing - run:  python tools/fetch_data.py --symbols {symbol} --timeframes {timeframe}"
        )
    df = pd.read_csv(path, parse_dates=["time"])
    df = df.drop_duplicates(subset="time").sort_values("time").reset_index(drop=True)
    # basic sanity: drop bars with non-positive prices or inverted ranges
    ok = (
        (df.open > 0)
        & (df.high > 0)
        & (df.low > 0)
        & (df.close > 0)
        & (df.high >= df.low)
    )
    df = df[ok].reset_index(drop=True)
    return Series(
        symbol=symbol,
        time=df["time"].values.astype("datetime64[ns]"),
        open=df["open"].to_numpy(float),
        high=df["high"].to_numpy(float),
        low=df["low"].to_numpy(float),
        close=df["close"].to_numpy(float),
        volume=df["volume"].to_numpy(float),
    )


def true_range(high: np.ndarray, low: np.ndarray, close: np.ndarray) -> np.ndarray:
    prev_close = np.concatenate([[close[0]], close[:-1]])
    tr = np.maximum(high - low, np.maximum(np.abs(high - prev_close), np.abs(low - prev_close)))
    return tr


def sma(x: np.ndarray, n: int) -> np.ndarray:
    """Simple moving average that never looks forward; NaN until n samples exist."""
    out = np.full(len(x), np.nan)
    if len(x) < n:
        return out
    c = np.concatenate([[0.0], np.cumsum(x)])
    out[n - 1:] = (c[n:] - c[:-n]) / n
    return out


def atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, n: int) -> np.ndarray:
    """Mean true range (arithmetic, not Wilder) - intentionally the same
    formula the EA uses so that the two implementations agree bar for bar."""
    return sma(true_range(high, low, close), n)


def rolling_median(x: np.ndarray, n: int) -> np.ndarray:
    out = np.full(len(x), np.nan)
    if len(x) < n:
        return out
    # only called on tick-volume, which is small; a strided median is fine
    from numpy.lib.stride_tricks import sliding_window_view

    out[n - 1:] = np.median(sliding_window_view(x, n), axis=1)
    return out


def daily_levels(s: Series) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Previous-day high/low and previous-week high/low, aligned to each bar.

    Day/week boundaries are UTC, which is what a broker-neutral strategy should
    use; in the EA the same rollover is reproduced from server time plus a
    configurable GMT offset.
    """
    ts = pd.DatetimeIndex(s.time)
    day = ts.floor("D")
    week = ts.to_period("W-SUN").start_time  # Monday 00:00 of each week

    df = pd.DataFrame({"day": day, "week": week, "high": s.high, "low": s.low})
    d = df.groupby("day").agg(dh=("high", "max"), dl=("low", "min")).shift(1)
    w = df.groupby("week").agg(wh=("high", "max"), wl=("low", "min")).shift(1)

    pdh = df["day"].map(d["dh"]).to_numpy(float)
    pdl = df["day"].map(d["dl"]).to_numpy(float)
    pwh = df["week"].map(w["wh"]).to_numpy(float)
    pwl = df["week"].map(w["wl"]).to_numpy(float)
    return pdh, pdl, pwh, pwl
