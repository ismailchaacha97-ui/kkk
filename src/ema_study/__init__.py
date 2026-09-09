"""EMA fast/slow grid study: data loading, vectorised backtester, robustness analysis."""
from .data import Series, load_universe, families            # noqa: F401
from .engine import ema, ema_matrix, buy_and_hold, trade_stats  # noqa: F401
from .grid import pair_grid, grid_for_series, run_grid       # noqa: F401
