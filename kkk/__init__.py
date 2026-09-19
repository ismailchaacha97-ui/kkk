"""kkk — a small, honest backtesting toolkit for three discretionary
candle methods, plus the tooling to find out which of them actually holds up.

Nothing here is financial advice. A backtest is a hypothesis test, not a
promise. Read `docs/METHODS.md` before trusting any number this prints.
"""

__version__ = "0.1.0"

from .config import BacktestConfig, Costs, Instrument, RiskConfig, PRESETS
from .engine import Engine, Signal, Trade, BacktestResult, run_backtest
from .metrics import Stats, compute_stats, compare, random_baseline

__all__ = [
    "BacktestConfig",
    "Costs",
    "Instrument",
    "RiskConfig",
    "PRESETS",
    "Engine",
    "Signal",
    "Trade",
    "BacktestResult",
    "run_backtest",
    "Stats",
    "compute_stats",
    "compare",
    "random_baseline",
]
