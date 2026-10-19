"""Typed configuration objects for the day-trading toolkit."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_SYMBOLS: tuple[str, ...] = ("AAPL", "MSFT", "NVDA")


@dataclass(frozen=True)
class RiskConfig:
    """Risk limits shared by every strategy.

    Parameters
    ----------
    risk_per_trade_pct : float
        Percentage of current account equity risked between entry and stop
        (0.5 means 0.5 %).
    max_notional_pct : float
        Hard cap on position notional as a percentage of equity. Protects
        against tiny stop distances producing absurd share counts.
    max_trades_per_day : int
        Maximum number of round trips per symbol per session.
    allow_short : bool
        Whether short entries are permitted.
    """

    risk_per_trade_pct: float = 0.5
    max_notional_pct: float = 25.0
    max_trades_per_day: int = 2
    allow_short: bool = True

    def __post_init__(self) -> None:
        if not 0.0 < self.risk_per_trade_pct <= 5.0:
            raise ValueError("risk_per_trade_pct must be in (0, 5]")
        if not 0.0 < self.max_notional_pct <= 100.0:
            raise ValueError("max_notional_pct must be in (0, 100]")
        if self.max_trades_per_day < 1:
            raise ValueError("max_trades_per_day must be >= 1")


@dataclass(frozen=True)
class ORBParams:
    """Opening-range breakout parameters.

    The opening range (OR) is built from the first ``opening_range_minutes``
    bars of the regular session. A breakout is a bar *close* beyond the OR
    boundary by ``breakout_buffer_bps`` with volume expansion confirmation.
    """

    opening_range_minutes: int = 15
    breakout_buffer_bps: float = 2.0
    min_stop_bps: float = 15.0
    max_stop_bps: float = 80.0
    reward_risk: float = 2.0
    volume_mult: float = 1.2
    max_or_width_pct: float = 3.0
    entry_cutoff: str = "14:30"
    flatten_time: str = "15:55"
    risk: RiskConfig = field(default_factory=RiskConfig)

    def __post_init__(self) -> None:
        if not 5 <= self.opening_range_minutes <= 120:
            raise ValueError("opening_range_minutes must be in [5, 120]")
        if self.reward_risk <= 0:
            raise ValueError("reward_risk must be > 0")
        if self.max_or_width_pct <= 0:
            raise ValueError("max_or_width_pct must be > 0")
        if not 0 < self.min_stop_bps < self.max_stop_bps:
            raise ValueError("require 0 < min_stop_bps < max_stop_bps")
        _validate_hhmm(self.entry_cutoff)
        _validate_hhmm(self.flatten_time)


@dataclass(frozen=True)
class VWAPParams:
    """Session-VWAP mean-reversion parameters.

    Entries trigger when price closes back inside a ``band_k`` standard
    deviation band around the session VWAP (fade of an over-extension), with
    the session VWAP as the profit target and an ATR-based stop.
    """

    band_k: float = 2.0
    atr_period: int = 14
    atr_stop_mult: float = 1.5
    min_reward_risk: float = 1.0
    entry_start: str = "09:45"
    entry_cutoff: str = "15:00"
    flatten_time: str = "15:55"
    risk: RiskConfig = field(
        default_factory=lambda: RiskConfig(max_trades_per_day=3, risk_per_trade_pct=0.4),
    )

    def __post_init__(self) -> None:
        if self.band_k <= 0:
            raise ValueError("band_k must be > 0")
        if self.atr_stop_mult <= 0:
            raise ValueError("atr_stop_mult must be > 0")
        _validate_hhmm(self.entry_start)
        _validate_hhmm(self.entry_cutoff)
        _validate_hhmm(self.flatten_time)


@dataclass(frozen=True)
class BacktestConfig:
    """Everything needed for one reproducible backtest run."""

    symbols: tuple[str, ...] = DEFAULT_SYMBOLS
    days: int = 60
    seed: int = 42
    start_date: str = "2026-01-05"
    starting_balance: float = 100_000.0
    leverage: float = 2.0
    fee_bps: float = 1.0
    slippage_prob: float = 0.5
    data_dir: Path = Path("data")
    out_dir: Path = Path("reports/orb")
    log_level: str = "WARNING"
    bar_minutes: int = 1
    auto_generate: bool = True

    def __post_init__(self) -> None:
        if not self.symbols:
            raise ValueError("at least one symbol is required")
        if self.days < 1:
            raise ValueError("days must be >= 1")
        if self.starting_balance <= 0:
            raise ValueError("starting_balance must be > 0")
        if self.leverage <= 0:
            raise ValueError("leverage must be > 0")
        if self.fee_bps < 0:
            raise ValueError("fee_bps must be >= 0")


def _validate_hhmm(value: str) -> None:
    try:
        hours, minutes = (int(part) for part in value.split(":"))
    except ValueError as exc:  # pragma: no cover - defensive
        raise ValueError(f"invalid HH:MM time: {value!r}") from exc
    if not (0 <= hours <= 23 and 0 <= minutes <= 59):
        raise ValueError(f"invalid HH:MM time: {value!r}")
