"""Performance metrics computed from NautilusTrader reports.

The engine gives us orders, fills, positions and an account ledger. For a
day-trading system that always flattens before the close, realized PnL per
session is the correct equity series, so metrics are computed from closed
positions rather than from mark-to-market snapshots.
"""

from __future__ import annotations

import math
import re
from collections.abc import Iterable

import numpy as np
import pandas as pd

from daytrader import MARKET_TZ

__all__ = [
    "build_daily_frame",
    "compute_summary",
    "money_to_float",
    "sessions_from_timestamps",
]

_NUMBER = re.compile(r"-?\d[\d,]*(?:\.\d+)?")


def money_to_float(value: object) -> float:
    """Convert ``Money``-like values (``"-28.00 USD"``) to ``float``."""
    if value is None:
        return 0.0
    if isinstance(value, (int, float, np.integer, np.floating)):
        return float(value)
    match = _NUMBER.search(str(value).replace("\u202f", ""))
    if match is None:
        return 0.0
    return float(match.group(0).replace(",", ""))


def sessions_from_timestamps(timestamps: Iterable[int]) -> pd.DatetimeIndex:
    """Unique session dates (market time) from nanosecond UTC timestamps."""
    index = pd.to_datetime(pd.Index(list(timestamps)), unit="ns", utc=True)
    return pd.DatetimeIndex(index.tz_convert(MARKET_TZ).normalize().unique()).sort_values()


def _closed_positions(positions: pd.DataFrame) -> pd.DataFrame:
    if positions.empty:
        return positions
    if "ts_closed" not in positions.columns:
        return positions.iloc[0:0]
    closed = positions[positions["ts_closed"].notna()].copy()
    closed["pnl"] = closed["realized_pnl"].map(money_to_float)
    closed["closed_session"] = (
        pd.to_datetime(closed["ts_closed"], utc=True).dt.tz_convert(MARKET_TZ).dt.normalize()
    )
    return closed.sort_values("ts_closed")


def build_daily_frame(
    positions: pd.DataFrame,
    sessions: pd.DatetimeIndex,
    starting_balance: float,
) -> pd.DataFrame:
    """Daily realized PnL, cumulative equity and drawdown over all sessions."""
    closed = _closed_positions(positions)
    session_index = pd.DatetimeIndex(sessions).sort_values()

    pnl = pd.Series(0.0, index=session_index, name="pnl")
    trades = pd.Series(0, index=session_index, name="trades")
    if not closed.empty:
        grouped = closed.groupby("closed_session")
        pnl = pnl.add(grouped["pnl"].sum().reindex(session_index, fill_value=0.0), fill_value=0.0)
        pnl.name = "pnl"
        trades = grouped.size().reindex(session_index, fill_value=0).astype(int)
        trades.name = "trades"

    equity = starting_balance + pnl.cumsum()
    running_max = equity.cummax()
    drawdown = equity / running_max - 1.0

    frame = pd.DataFrame(
        {
            "pnl": pnl,
            "trades": trades,
            "equity": equity,
            "drawdown_pct": drawdown * 100.0,
        },
    )
    frame.index.name = "session"
    return frame


def compute_summary(
    positions: pd.DataFrame,
    sessions: pd.DatetimeIndex,
    starting_balance: float,
    *,
    strategy: str,
    symbols: tuple[str, ...],
) -> dict[str, object]:
    """Compute a JSON-serialisable performance summary."""
    closed = _closed_positions(positions)
    n_sessions = max(len(sessions), 1)
    pnl = closed["pnl"] if not closed.empty else pd.Series(dtype=float)

    wins = pnl[pnl > 0]
    losses = pnl[pnl < 0]
    gross_profit = float(wins.sum())
    gross_loss = float(-losses.sum())
    net = float(pnl.sum())

    daily = build_daily_frame(positions, sessions, starting_balance)
    daily_returns = daily["equity"].pct_change().dropna()
    downside = daily_returns[daily_returns < 0]

    total_return_pct = net / starting_balance * 100.0
    years = n_sessions / 252.0
    cagr = (
        ((1.0 + net / starting_balance) ** (1.0 / years) - 1.0) * 100.0
        if years > 0 and net > -starting_balance
        else math.nan
    )
    sharpe = (
        float(daily_returns.mean() / daily_returns.std(ddof=1) * math.sqrt(252))
        if len(daily_returns) > 2 and daily_returns.std(ddof=1) > 0
        else math.nan
    )
    sortino = (
        float(daily_returns.mean() / downside.std(ddof=1) * math.sqrt(252))
        if len(downside) > 2 and downside.std(ddof=1) > 0
        else math.nan
    )
    max_drawdown = float(daily["drawdown_pct"].min()) if not daily.empty else math.nan
    avg_hold = (
        float(pd.to_numeric(closed["duration_ns"], errors="coerce").mean() / 60e9)
        if "duration_ns" in closed.columns and not closed.empty
        else math.nan
    )

    summary: dict[str, object] = {
        "strategy": strategy,
        "symbols": list(symbols),
        "sessions": n_sessions,
        "trades": len(closed),
        "wins": len(wins),
        "losses": len(losses),
        "win_rate_pct": float(len(wins) / len(closed) * 100.0) if len(closed) else math.nan,
        "net_pnl": net,
        "gross_profit": gross_profit,
        "gross_loss": gross_loss,
        "profit_factor": (gross_profit / gross_loss) if gross_loss > 0 else math.nan,
        "expectancy": float(pnl.mean()) if len(pnl) else math.nan,
        "avg_win": float(wins.mean()) if len(wins) else math.nan,
        "avg_loss": float(losses.mean()) if len(losses) else math.nan,
        "largest_win": float(wins.max()) if len(wins) else math.nan,
        "largest_loss": float(losses.min()) if len(losses) else math.nan,
        "avg_hold_minutes": avg_hold,
        "trades_per_day": len(closed) / n_sessions,
        "return_pct": total_return_pct,
        "cagr_pct": cagr,
        "sharpe": sharpe,
        "sortino": sortino,
        "max_drawdown_pct": max_drawdown,
        "starting_balance": starting_balance,
        "ending_balance": starting_balance + net,
    }
    return summary
