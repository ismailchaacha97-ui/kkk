"""Intraday market data utilities.

Two data sources are supported:

1. :func:`generate_synthetic_bars` – a deterministic, dependency-free generator
   of realistic 1-minute US-equity sessions. It models an overnight gap, an
   opening volatility burst, U-shaped intraday volume, trend regimes and
   mean-reverting intraday deviations. This makes the repository usable with no
   API keys, no vendor subscriptions and no network access, which matters for
   reproducibility and CI.
2. :func:`load_bars` – load *your own* 1-minute OHLCV CSV into NautilusTrader
   ``Bar`` objects.

Synthetic data is for testing infrastructure, not for claiming an edge. Point
``--data-dir`` at real vendor data (Databento, Polygon, IB, Binance, ...) with
the same CSV schema to research real markets.
"""

from __future__ import annotations

import json
import zlib
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from datetime import time as dtime
from pathlib import Path

import numpy as np
import pandas as pd
from nautilus_trader.model.data import Bar, BarType
from nautilus_trader.model.instruments.base import Instrument
from nautilus_trader.persistence.wranglers import BarDataWrangler

from daytrader import MARKET_TZ

__all__ = [
    "SESSION_MINUTES",
    "SymbolProfile",
    "generate_dataset",
    "generate_synthetic_bars",
    "load_bars",
    "resample_bars",
    "save_bars",
]

SESSION_START = dtime(9, 30)
SESSION_MINUTES = 390  # 09:30-15:59 inclusive

# A few liquid, well-known tickers with plausible price/volume scales.
DEFAULT_PROFILES: dict[str, SymbolProfile] = {}


@dataclass(frozen=True)
class SymbolProfile:
    """Per-symbol statistical profile used by the synthetic generator."""

    symbol: str
    base_price: float
    avg_daily_volume: int = 25_000_000
    beta: float = 1.0
    idio_vol: float = 0.00055  # per-minute log-return std-dev


DEFAULT_PROFILES.update(
    {
        "AAPL": SymbolProfile("AAPL", 225.0, 55_000_000, beta=1.05),
        "MSFT": SymbolProfile("MSFT", 430.0, 22_000_000, beta=0.95),
        "NVDA": SymbolProfile("NVDA", 135.0, 300_000_000, beta=1.55, idio_vol=0.00085),
        "AMZN": SymbolProfile("AMZN", 210.0, 40_000_000, beta=1.15),
        "SPY": SymbolProfile("SPY", 580.0, 70_000_000, beta=1.0, idio_vol=0.00030),
        "TSLA": SymbolProfile("TSLA", 340.0, 90_000_000, beta=1.75, idio_vol=0.00105),
    },
)

_GAP_SIGMA = 0.0035
_MARKET_VOL = 0.00045
_TREND_DRIFT = 0.00016
_MEAN_REVERSION = 0.96


def _trading_days(start: date, count: int) -> list[date]:
    """Return ``count`` weekdays starting at ``start`` (weekends skipped)."""
    days: list[date] = []
    current = start
    while len(days) < count:
        if current.weekday() < 5:
            days.append(current)
        current += timedelta(days=1)
    return days


def _profile(symbol: str) -> SymbolProfile:
    return DEFAULT_PROFILES.get(
        symbol,
        SymbolProfile(
            symbol=symbol,
            base_price=100.0,
            avg_daily_volume=10_000_000,
            beta=1.0,
        ),
    )


def _symbol_seed(seed: int, symbol: str) -> int:
    """Stable per-symbol seed so results do not depend on symbol ordering."""
    return (seed * 1_000_003 + zlib.crc32(symbol.encode("utf-8"))) % (2**32)


def _u_shaped_volume(n: int, average_total: float, rng: np.random.Generator) -> np.ndarray:
    """U-shaped intraday volume profile with log-normal noise."""
    t = np.arange(n, dtype=float)
    shape = 1.0 + 0.95 * np.exp(-t / 25.0) + 0.55 * np.exp(-(n - 1 - t) / 22.0)
    normaliser = shape.mean()
    base = (average_total / n) / normaliser
    noise = rng.lognormal(mean=-0.5 * 0.35**2, sigma=0.35, size=n)
    return np.maximum((base * shape * noise).round(), 100.0)


def _ohlc_from_path(
    path: np.ndarray,
    open_price: float,
    rng: np.random.Generator,
    spread_sigma: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Build open/high/low/close arrays from a close-price path."""
    opens = np.empty_like(path)
    opens[0] = open_price
    opens[1:] = path[:-1]

    wick = np.abs(rng.normal(0.0, spread_sigma, size=len(path))) + spread_sigma * 0.35
    highs = np.maximum(opens, path) * (1.0 + wick)
    lows = np.minimum(opens, path) * (1.0 - wick)

    # Round to the 0.01 tick and keep OHLC coherent after rounding.
    opens = np.round(opens, 2)
    closes = np.round(path, 2)
    highs = np.round(highs, 2)
    lows = np.round(lows, 2)
    highs = np.maximum.reduce([highs, opens, closes])
    lows = np.minimum.reduce([lows, opens, closes])
    lows = np.maximum(lows, 0.01)
    return opens, highs, lows, closes


def generate_synthetic_bars(
    symbols: tuple[str, ...] | list[str],
    start_date: str | date = "2026-01-05",
    days: int = 60,
    seed: int = 42,
    bar_minutes: int = 1,
) -> dict[str, pd.DataFrame]:
    """Generate synthetic intraday OHLCV bars for several correlated symbols.

    Parameters
    ----------
    symbols : sequence of str
        Ticker symbols. Known symbols get realistic starting prices and volumes
        (AAPL, MSFT, NVDA, AMZN, SPY, TSLA); anything else uses sensible
        defaults.
    start_date : str | date
        First session date (weekends are skipped).
    days : int
        Number of trading sessions to generate.
    seed : int
        Master random seed; per-symbol streams are derived deterministically.
    bar_minutes : int
        Bar size in minutes. Must divide 30 so bars stay aligned to 09:30.

    Returns
    -------
    dict[str, pandas.DataFrame]
        Mapping symbol -> DataFrame indexed by tz-aware
        ``America/New_York`` timestamps with columns
        ``open, high, low, close, volume``.
    """
    if isinstance(start_date, str):
        start = date.fromisoformat(start_date)
    else:
        start = start_date
    if days < 1:
        raise ValueError("days must be >= 1")
    if 30 % bar_minutes != 0:
        raise ValueError("bar_minutes must divide 30 (1, 2, 3, 5, 6, 10, 15 or 30)")

    sessions = _trading_days(start, days)
    rng_market = np.random.default_rng(seed)

    # Pre-generate the common market factor for every session.
    market_paths: list[np.ndarray] = []
    for _ in sessions:
        regime = rng_market.random()
        drift = _TREND_DRIFT if regime < 0.18 else (-_TREND_DRIFT if regime < 0.34 else 0.0)
        returns = rng_market.normal(drift, _MARKET_VOL, SESSION_MINUTES)
        returns[:5] *= 1.5
        market_paths.append(np.cumprod(1.0 + returns))

    frames: dict[str, pd.DataFrame] = {}
    for symbol in symbols:
        profile = _profile(symbol)
        rng = np.random.default_rng(_symbol_seed(seed, symbol))
        prev_close = profile.base_price
        session_frames: list[pd.DataFrame] = []

        for day, market_path in zip(sessions, market_paths, strict=True):
            gap = profile.beta * rng.normal(0.0, _GAP_SIGMA) + rng.normal(0.0, _GAP_SIGMA * 0.5)
            open_price = max(prev_close * (1.0 + gap), 1.0)

            # Correlate the symbol path with the shared market factor.
            market_returns = np.diff(np.concatenate([[1.0], market_path]))
            returns = profile.beta * market_returns + rng.normal(
                0.0,
                profile.idio_vol,
                SESSION_MINUTES,
            )
            fair = open_price * np.cumprod(1.0 + returns)

            # Transient dislocation around fair value -> mean-reversion setups.
            epsilon = rng.normal(0.0, profile.idio_vol * 1.4, SESSION_MINUTES)
            dislocation = np.zeros(SESSION_MINUTES)
            for i in range(1, SESSION_MINUTES):
                dislocation[i] = _MEAN_REVERSION * dislocation[i - 1] + epsilon[i]
            path = fair * (1.0 + dislocation)

            opens, highs, lows, closes = _ohlc_from_path(
                path,
                open_price,
                rng,
                spread_sigma=max(profile.idio_vol * 0.32, 0.00018),
            )
            volumes = _u_shaped_volume(
                SESSION_MINUTES,
                profile.avg_daily_volume,
                rng,
            ).astype(np.int64)

            index = pd.date_range(
                datetime.combine(day, SESSION_START),
                periods=SESSION_MINUTES,
                freq="1min",
                tz=MARKET_TZ,
            )
            session_frames.append(
                pd.DataFrame(
                    {
                        "open": opens,
                        "high": highs,
                        "low": lows,
                        "close": closes,
                        "volume": volumes,
                    },
                    index=index,
                ),
            )
            prev_close = float(closes[-1])

        frame = pd.concat(session_frames)
        frame.index.name = "timestamp"
        if bar_minutes > 1:
            frame = resample_bars(frame, bar_minutes)
        frames[symbol] = frame

    return frames


def resample_bars(frame: pd.DataFrame, minutes: int) -> pd.DataFrame:
    """Aggregate bars into ``minutes`` buckets without crossing sessions."""
    if minutes < 1:
        raise ValueError("minutes must be >= 1")
    if minutes == 1:
        return frame
    resampled = frame.resample(
        f"{minutes}min",
        label="left",
        closed="left",
        origin="start_day",
    ).agg(
        {"open": "first", "high": "max", "low": "min", "close": "last", "volume": "sum"},
    )
    return resampled.dropna(subset=["open", "high", "low", "close"])


def save_bars(frame: pd.DataFrame, path: Path) -> Path:
    """Write bars to CSV using UTC ISO timestamps (portable and unambiguous)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    out = frame.copy()
    out.index = out.index.tz_convert("UTC")
    out.index.name = "timestamp"
    out.to_csv(path, float_format="%.2f")
    return path


def _marker_matches(
    marker: Path,
    symbols: tuple[str, ...] | list[str],
    start_date: str | date,
    days: int,
    seed: int,
    bar_minutes: int,
) -> bool:
    """True when the existing synthetic dataset was built with these settings."""
    try:
        meta = json.loads(marker.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    return (
        meta.get("seed") == seed
        and meta.get("days") == days
        and str(meta.get("start_date")) == str(start_date)
        and meta.get("bar_minutes") == bar_minutes
        and set(symbols).issubset(set(meta.get("symbols", [])))
    )


def generate_dataset(
    symbols: tuple[str, ...] | list[str],
    data_dir: Path | str = Path("data"),
    start_date: str | date = "2026-01-05",
    days: int = 60,
    seed: int = 42,
    bar_minutes: int = 1,
    force: bool = False,
) -> dict[str, Path]:
    """Generate and persist a synthetic dataset, reusing existing files.

    A ``.synthetic.json`` marker records how the files were produced. If the
    requested settings differ from the marker, the dataset is regenerated so
    that ``--days``/``--seed`` never silently reuse stale bars. Directories
    without the marker are treated as user-supplied CSV data and are never
    overwritten unless ``force`` is explicitly set.
    """
    data_dir = Path(data_dir)
    marker = data_dir / ".synthetic.json"
    managed = marker.exists()

    if (
        managed
        and not force
        and not _marker_matches(
            marker,
            symbols,
            start_date,
            days,
            seed,
            bar_minutes,
        )
    ):
        force = True

    paths: dict[str, Path] = {}
    missing = [
        symbol
        for symbol in symbols
        if force or not (data_dir / f"{symbol}_{bar_minutes}min.csv").exists()
    ]
    if missing:
        frames = generate_synthetic_bars(
            symbols=missing,
            start_date=start_date,
            days=days,
            seed=seed,
            bar_minutes=bar_minutes,
        )
        for symbol, frame in frames.items():
            path = data_dir / f"{symbol}_{bar_minutes}min.csv"
            save_bars(frame, path)
            paths[symbol] = path
        # Only claim the whole directory when it is already generator-managed,
        # or when every requested file came from the generator in this call.
        # Mixed directories keep their user CSVs safe from regeneration.
        if managed or len(missing) == len(symbols):
            data_dir.mkdir(parents=True, exist_ok=True)
            marker.write_text(
                json.dumps(
                    {
                        "generator": "daytrader.data.generate_synthetic_bars",
                        "symbols": list(symbols),
                        "days": days,
                        "seed": seed,
                        "start_date": str(start_date),
                        "bar_minutes": bar_minutes,
                    },
                    indent=2,
                ),
            )
    for symbol in symbols:
        paths.setdefault(symbol, data_dir / f"{symbol}_{bar_minutes}min.csv")
    return paths


def _read_candles(path: Path) -> pd.DataFrame:
    """Read a user CSV and normalise it to a tz-aware UTC OHLCV frame."""
    raw = pd.read_csv(path)
    raw.columns = [str(c).strip().lower().replace(" ", "_") for c in raw.columns]

    time_columns = ["timestamp", "timestamp_utc", "datetime", "date_time", "time"]
    column = next((c for c in time_columns if c in raw.columns), None)
    combined_date_time = False
    if column is None and {"date", "time"}.issubset(raw.columns):
        raw["timestamp"] = raw["date"].astype(str) + " " + raw["time"].astype(str)
        column = "timestamp"
        combined_date_time = True
    if column is None:
        raise ValueError(
            f"{path}: no timestamp column found; expected one of {time_columns} "
            "or both 'date' and 'time'",
        )

    missing = {"open", "high", "low", "close"} - set(raw.columns)
    if missing:
        raise ValueError(f"{path}: missing required columns {sorted(missing)}")
    if "volume" not in raw.columns:
        raw["volume"] = 0.0

    parsed = (
        pd.to_datetime(raw[column], format="%Y-%m-%d %H:%M:%S", errors="raise")
        if combined_date_time
        else pd.to_datetime(raw[column], errors="raise")
    )
    if getattr(parsed.dt, "tz", None) is None:
        # Naive timestamps are assumed to be exchange-local wall-clock time.
        parsed = parsed.dt.tz_localize(MARKET_TZ, ambiguous="NaT", nonexistent="shift_forward")
        parsed = parsed.ffill().bfill()
    parsed = parsed.dt.tz_convert("UTC")

    frame = pd.DataFrame(
        {
            "open": pd.to_numeric(raw["open"], errors="raise").to_numpy(dtype=float),
            "high": pd.to_numeric(raw["high"], errors="raise").to_numpy(dtype=float),
            "low": pd.to_numeric(raw["low"], errors="raise").to_numpy(dtype=float),
            "close": pd.to_numeric(raw["close"], errors="raise").to_numpy(dtype=float),
            "volume": pd.to_numeric(raw["volume"], errors="coerce")
            .fillna(0.0)
            .to_numpy(dtype=float),
        },
        index=pd.DatetimeIndex(parsed, name="timestamp"),
    )
    frame = frame.sort_index()
    frame = frame[~frame.index.duplicated(keep="last")]
    return frame


def infer_bar_minutes(frame: pd.DataFrame) -> int:
    """Infer the bar interval in minutes from the median timestamp delta."""
    if len(frame) < 3:
        return 1
    deltas = frame.index.to_series().diff().dropna()
    deltas = deltas[deltas > pd.Timedelta(0)]
    if deltas.empty:
        return 1
    return max(1, round(deltas.median().total_seconds() / 60.0))


def validate_bars(frame: pd.DataFrame, path: Path | str = "<dataframe>") -> None:
    """Validate OHLCV invariants and raise a precise error when violated."""
    if frame.empty:
        raise ValueError(f"{path}: no rows")
    if frame.isna().any().any():
        raise ValueError(f"{path}: contains NaN values")
    if not frame.index.is_monotonic_increasing:
        raise ValueError(f"{path}: timestamps are not sorted")
    if (frame["high"] < frame[["open", "close", "low"]].max(axis=1)).any():
        raise ValueError(f"{path}: high < max(open, close, low) on some bars")
    if (frame["low"] > frame[["open", "close", "high"]].min(axis=1)).any():
        raise ValueError(f"{path}: low > min(open, close, high) on some bars")
    if (frame[["open", "high", "low", "close"]] <= 0).any().any():
        raise ValueError(f"{path}: non-positive prices")
    if (frame["volume"] < 0).any():
        raise ValueError(f"{path}: negative volume")


def load_bars(
    path: Path | str,
    instrument: Instrument,
    bar_type: BarType,
) -> list[Bar]:
    """Load 1-minute OHLCV CSV data into NautilusTrader bars.

    Expected columns (case-insensitive): ``timestamp``, ``open``, ``high``,
    ``low``, ``close``, ``volume``. Timestamps may be tz-aware (any offset) or
    naive exchange-local time. A ``date`` + ``time`` column pair also works.
    """
    path = Path(path)
    frame = _read_candles(path)
    validate_bars(frame, path)

    expected_minutes = getattr(getattr(bar_type, "specification", None), "step", None)
    actual_minutes = infer_bar_minutes(frame)
    if expected_minutes is not None and actual_minutes != expected_minutes:
        raise ValueError(
            f"{path}: bars are ~{actual_minutes}-minute but the bar type expects "
            f"{expected_minutes}-minute data; pass a matching --bar-minutes",
        )

    wrangler = BarDataWrangler(bar_type, instrument)
    bars = wrangler.process(frame)
    if not bars:
        raise ValueError(f"{path}: no bars produced")
    return bars
