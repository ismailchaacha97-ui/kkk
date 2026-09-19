"""OHLC data loading, cleaning and session tagging.

The sandbox this project lives in has no access to market-data APIs, so
prices come from CSV files you export yourself (see `docs/data.md`).
MetaTrader 5 and TradingView exports are both handled.
"""

from __future__ import annotations

import io
import re
from pathlib import Path

import numpy as np
import pandas as pd

OHLC = ["open", "high", "low", "close"]

# MT5 exports are tab-separated; TradingView uses commas; many brokers use ';'.
_SEPARATORS = ["\t", ";", ","]


def _sniff_separator(sample: str) -> str:
    first_line = sample.splitlines()[0]
    counts = {sep: first_line.count(sep) for sep in _SEPARATORS}
    best = max(counts, key=counts.get)
    return best if counts[best] > 0 else ","


def _parse_timestamps(df: pd.DataFrame) -> pd.DatetimeIndex:
    """Handle MT5's split <DATE> <TIME> columns and single-column stamps."""
    cols = {c.lower().strip("<> "): c for c in df.columns}

    if "date" in cols and "time" in cols:
        stamps = (
            df[cols["date"]].astype(str).str.strip()
            + " "
            + df[cols["time"]].astype(str).str.strip()
        )
    elif "datetime" in cols:
        stamps = df[cols["datetime"]].astype(str)
    elif "date" in cols:
        stamps = df[cols["date"]].astype(str)
    elif "time" in cols:
        # TradingView / generic exports use a single `time` column
        stamps = df[cols["time"]].astype(str)
    elif "timestamp" in cols:
        stamps = df[cols["timestamp"]].astype(str)
    else:
        raise ValueError(
            f"no date/time column found. Columns present: {list(df.columns)}"
        )

    # MT5 sometimes writes 2024.01.02 rather than 2024-01-02
    stamps = stamps.str.replace(".", "-", regex=False).str.strip()

    parsed = pd.to_datetime(stamps, format="mixed", dayfirst=False, errors="coerce")
    if parsed.isna().any():
        parsed = pd.to_datetime(stamps, format="mixed", dayfirst=True, errors="coerce")
    if parsed.isna().any():
        bad = stamps[parsed.isna()].head(3).tolist()
        raise ValueError(f"could not parse {parsed.isna().sum()} timestamps, e.g. {bad}")
    return pd.DatetimeIndex(parsed)


def load_csv(
    path: str | Path,
    *,
    tz: str | None = "UTC",
    drop_weekends: bool = True,
) -> pd.DataFrame:
    """Read an OHLC CSV into a tidy frame indexed by UTC timestamp.

    Returns columns: open, high, low, close, (volume), rounded floats.
    """
    path = Path(path)
    raw = path.read_text(encoding="utf-8-sig", errors="replace")
    if not raw.strip():
        raise ValueError(f"{path} is empty")

    sep = _sniff_separator(raw)

    # European exports use ',' as the decimal mark; if the separator is ';'
    # that is almost certainly the case.
    decimal = "," if sep == ";" else "."

    df = pd.read_csv(
        io.StringIO(raw),
        sep=sep,
        decimal=decimal,
        engine="python",
        skipinitialspace=True,
    )
    df.columns = [str(c).strip().strip("<>").lower() for c in df.columns]

    # Some exports prefix columns with '<' e.g. '<OPEN>'
    rename = {
        c: c.strip("<> ") for c in df.columns
    }
    df = df.rename(columns=rename)

    idx = _parse_timestamps(df)
    df = df.drop(
        columns=[c for c in ("date", "time", "datetime", "timestamp") if c in df.columns]
    )
    df.index = idx
    df.index.name = "time"

    missing = [c for c in OHLC if c not in df.columns]
    if missing:
        raise ValueError(
            f"{path.name}: missing OHLC columns {missing}. "
            f"Found: {list(df.columns)}"
        )

    keep = OHLC + [c for c in ("volume", "tickvol", "tick_volume", "vol") if c in df.columns]
    df = df[keep].copy()
    if "volume" not in df.columns:
        for alt in ("tickvol", "tick_volume", "vol"):
            if alt in df.columns:
                df = df.rename(columns={alt: "volume"})
                break
    df = df[[c for c in ("open", "high", "low", "close", "volume") if c in df.columns]]

    for c in OHLC:
        df[c] = pd.to_numeric(df[c], errors="coerce")

    df = df.dropna(subset=OHLC)
    df = df[~df.index.duplicated(keep="last")].sort_index()

    if tz is not None:
        df.index = (
            df.index.tz_localize(tz)
            if df.index.tz is None
            else df.index.tz_convert(tz)
        )

    if drop_weekends:
        df = _drop_stale_bars(df)

    _validate(df)
    return df


def _drop_stale_bars(df: pd.DataFrame) -> pd.DataFrame:
    """Remove weekend/holiday filler bars (zero-range, repeated close)."""
    if df.empty:
        return df
    zero_range = (df["high"] - df["low"]) == 0
    flat = df["close"].diff() == 0
    stale = zero_range & (flat | flat.shift(-1).fillna(False))
    if stale.mean() > 0.5:          # don't nuke a legitimately quiet file
        return df
    return df[~stale]


def _validate(df: pd.DataFrame) -> None:
    if df.empty:
        raise ValueError("no rows left after cleaning")
    bad = (
        (df["high"] < df["low"])
        | (df["high"] < df[["open", "close"]].max(axis=1))
        | (df["low"] > df[["open", "close"]].min(axis=1))
    )
    if bad.any():
        n = int(bad.sum())
        raise ValueError(f"{n} bars violate OHLC invariants (high/low out of range)")
    if len(df) < 50:
        raise ValueError(f"only {len(df)} bars — need at least 50 to backtest")


def resample(df: pd.DataFrame, rule: str) -> pd.DataFrame:
    """Aggregate bars, e.g. rule='4h' or '1D'. Anchored to the index origin."""
    out = df.resample(rule, label="left", closed="left").agg(
        {
            "open": "first",
            "high": "max",
            "low": "min",
            "close": "last",
            **({"volume": "sum"} if "volume" in df.columns else {}),
        }
    )
    return out.dropna(subset=OHLC)


def add_sessions(df: pd.DataFrame) -> pd.DataFrame:
    """Tag each bar with the trading session it belongs to (UTC hours).

    Asian   00:00-07:00   London  07:00-16:00   New York 12:00-21:00
    Overlap 12:00-16:00 is the London/NY killzone most methods focus on.
    """
    hours = df.index.hour
    session = np.select(
        [hours < 7, (hours >= 7) & (hours < 12), (hours >= 12) & (hours < 16), hours >= 16],
        ["asia", "london", "overlap", "newyork"],
        default="closed",
    )
    out = df.copy()
    out["session"] = session
    return out


def train_test_split(
    df: pd.DataFrame, split: float = 0.7
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Time-ordered split. Never shuffle price data."""
    cut = int(len(df) * split)
    return df.iloc[:cut], df.iloc[cut:]


def summarize(df: pd.DataFrame) -> str:
    if df.empty:
        return "empty frame"
    span = df.index[-1] - df.index[0]
    step = pd.Series(df.index).diff().dropna().mode()
    freq = step.iloc[0] if len(step) else "?"
    return (
        f"{len(df):,} bars | {df.index[0]} -> {df.index[-1]} "
        f"({span.days} days) | step {freq} | "
        f"close {df['close'].iloc[0]:.5g} -> {df['close'].iloc[-1]:.5g}"
    )


def frame_to_csv(df: pd.DataFrame, path: str | Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path)
    return path


def make_synthetic(
    n: int = 5_000,
    *,
    start: str = "2023-01-02",
    freq: str = "1h",
    start_price: float = 2000.0,
    volatility: float = 0.0015,
    seed: int = 7,
) -> pd.DataFrame:
    """Deterministic pseudo-market data.

    Used only for smoke-testing the engine when no real CSV is available.
    It is a random walk with volatility clustering — it has NO real edge,
    so a strategy that looks profitable here proves nothing except that the
    plumbing works.
    """
    rng = np.random.default_rng(seed)
    # Weekends are dropped, so oversample and then trim to exactly n bars.
    idx = pd.date_range(start, periods=int(n * 1.6) + 20, freq=freq, tz="UTC")
    idx = idx[idx.dayofweek < 5][:n]

    vol = volatility * (1 + 0.6 * np.sin(np.arange(len(idx)) / 60))
    shocks = rng.normal(0, 1, len(idx)) * vol
    drift = 0.00002 * np.sin(np.arange(len(idx)) / 500)
    close = start_price * np.exp(np.cumsum(shocks + drift))

    open_ = np.concatenate([[start_price], close[:-1]])
    wick = np.abs(rng.normal(0, 1, len(idx))) * vol * close * 0.8
    high = np.maximum(open_, close) + wick
    low = np.minimum(open_, close) - wick

    return pd.DataFrame(
        {"open": open_, "high": high, "low": low, "close": close,
         "volume": rng.integers(100, 1000, len(idx)).astype(float)},
        index=idx,
    )
