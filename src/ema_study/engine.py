"""EMA + single-pair backtest primitives (shared by the grid search and the reports).

Conventions
-----------
* ``ema`` is the recursive exponential average (``alpha = 2/(span+1)``, seed = first value),
  i.e. pandas ``ewm(span, adjust=False)`` and equivalent to TradingView's ``ta.ema`` once
  the seed washes out.  All performance statistics drop the first ``slow`` bars, so the
  seeding choice cannot flatter long slow periods.
* ``r[t]`` is the return of the bar that starts at close ``t``.  ``w[t]`` is the position
  held over that bar, decided by the crossover known at close ``t-1`` -> no lookahead.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

__all__ = ["ema", "ema_matrix", "sma_matrix", "position_from_state", "metrics",
           "evaluate_pair", "trade_stats", "buy_and_hold"]


def ema(x, span: int) -> np.ndarray:
    x = np.asarray(x, dtype=np.float64)
    n = x.size
    if n == 0:
        return x.copy()
    span = max(int(span), 1)
    if span == 1:
        return x.copy()
    alpha = 2.0 / (span + 1.0)
    beta = 1.0 - alpha
    out = np.empty(n, np.float64)
    prev = x[0]
    out[0] = prev
    for i in range(1, n):
        prev = beta * prev + alpha * x[i]
        out[i] = prev
    return out


def ema_matrix(x, periods) -> np.ndarray:
    """Stacked EMAs: row i is ``ema(x, periods[i])`` -> (len(periods), len(x)).

    Uses pandas' C implementation, which is identical to :func:`ema` (``adjust=False``)
    - verified to 0.0 max-abs difference in the tests - but ~100x faster.
    """
    sr = pd.Series(np.asarray(x, dtype=np.float64))
    return np.vstack([sr.ewm(span=int(p), adjust=False, ignore_na=False).mean().to_numpy()
                      for p in periods])


def sma_matrix(x, periods) -> np.ndarray:
    """Stacked simple moving averages (for the EMA-vs-SMA comparison)."""
    sr = pd.Series(np.asarray(x, dtype=np.float64))
    return np.vstack([sr.rolling(int(p), min_periods=1).mean().to_numpy() for p in periods])


def position_from_state(state: np.ndarray, mode: str = "long") -> tuple[np.ndarray, np.ndarray]:
    """Map "fast above slow at close of bar t" to (weight held over bar t+1, change flags).

    ``state`` has the same length as the return vector.  ``trans`` is True on bars where the
    target position changed, i.e. the bars on which transaction cost is paid.
    """
    B, N = state.shape
    long_only = mode == "long"
    tgt = state.astype(np.float64) if long_only else np.where(state, 1.0, -1.0)
    w = np.zeros((B, N), np.float64)
    w[:, 1:] = tgt[:, :-1]
    trans = np.zeros((B, N), bool)
    trans[:, 1:] = w[:, 1:] != w[:, :-1]
    trans[:, 0] = False          # the first bar is inside warm-up for every legal pair
    return w, trans


def metrics(r: np.ndarray, ann: int, pos: np.ndarray | None = None,
            changes: np.ndarray | None = None, unit: float = 1.0, min_bars: int = 250) -> pd.DataFrame:
    """Batch summary statistics for daily return vectors (one row per input row)."""
    r = np.atleast_2d(np.asarray(r, np.float64))
    n = r.shape[1]
    mu = r.mean(1)
    sd = r.std(ddof=1, axis=1)
    logcum = np.log1p(np.clip(r, -0.999999, None)).cumsum(1)
    dd = np.expm1((logcum - np.maximum.accumulate(logcum, axis=1)).min(axis=1))
    tot = np.expm1(logcum[:, -1])
    cagr = np.expm1(logcum[:, -1] / max(n, 1) * ann)
    neg = np.where(r < 0, r, 0.0)
    dvar = np.sqrt((neg ** 2).mean(1))
    # a degenerate (never-traded) book has an undefined Sharpe but a perfectly well
    # defined P&L, so only the ratio metrics get nulled out
    ok = (n >= min_bars) & np.isfinite(mu)
    out = pd.DataFrame({
        "n_bars": float(n), "ann_vol": sd * np.sqrt(ann),
        "sharpe": np.where(sd > 0, mu * np.sqrt(ann) / np.maximum(sd, 1e-18), np.nan),
        "sortino": np.where(dvar > 0, mu * np.sqrt(ann) / np.maximum(dvar, 1e-18), np.nan),
        "cagr": cagr, "max_dd": dd, "total_return": tot,
        "calmar": np.where(dd < -1e-9, cagr / np.abs(dd), np.nan),
        "exposure": np.abs(pos).mean(1) if pos is not None else np.nan,
        "round_trips": changes.sum(1) / unit if changes is not None else np.nan,
    })
    out[~ok] = np.nan
    return out


def evaluate_pair(close: pd.Series, fast: int, slow: int, *, adjustment: str = "raw",
                  ann: int = 252, cost_bps: float = 0.0, mode: str = "long",
                  warmup: bool = True) -> tuple[pd.DataFrame, pd.Series, np.ndarray, np.ndarray]:
    """Backtest a single pair on a price series.

    Returns ``(metrics_row, daily_strategy_returns, weights, transitions)``.
    """
    from .data import _returns

    close = close.astype(np.float64)
    rets = _returns(close, adjustment)
    state = (ema(close, fast)[1:] > ema(close, slow)[1:])
    w, trans = position_from_state(state[None, :], mode)
    w, trans = w[0], trans[0]
    unit = 1.0 if mode == "long" else 2.0
    r = w * rets - trans * (cost_bps / 1e4) * unit
    warm = int(slow) if warmup else 0
    m = metrics(r[warm:][None, :], ann, pos=w[warm:][None, :], changes=trans[warm:][None, :], unit=unit)
    m = m.iloc[0].copy()
    m["fast"], m["slow"] = fast, slow
    return m, pd.Series(r, index=close.index[1:]), w, trans


def trade_stats(r: np.ndarray, w: np.ndarray, warm: int = 0) -> dict:
    """Split a daily curve into trades: hit rate, profit factor, average trade."""
    wa, ra = np.asarray(w)[warm:], np.asarray(r)[warm:]
    if wa.size < 3:
        return {}
    # a trade = a maximal run with a non-zero position (flat stretches are not trades)
    ch = np.flatnonzero(np.abs(np.diff(wa)) > 1e-12)
    bnds = np.unique(np.concatenate([[0], ch + 1, [wa.size]])).astype(int)
    starts = wa[bnds[:-1]]
    keep = np.abs(starts) > 1e-12
    if not keep.any():
        return dict(n_trades=0, hit_rate=np.nan, profit_factor=np.nan, avg_trade=np.nan,
                    best_trade=np.nan, worst_trade=np.nan, trades_per_year=np.nan,
                    avg_win=np.nan, avg_loss=np.nan)
    seg_lo, seg_hi = bnds[:-1][keep], bnds[1:][keep]
    if bnds.size < 3:
        return dict(n_trades=0, hit_rate=np.nan, profit_factor=np.nan, avg_trade=np.nan,
                    best_trade=np.nan, worst_trade=np.nan, trades_per_year=np.nan,
                    avg_win=np.nan, avg_loss=np.nan)
    c = np.concatenate([[0.0], np.cumsum(np.log1p(np.clip(ra, -0.999999, None)))])
    pnl = np.expm1(c[seg_hi] - c[seg_lo])
    pnl = pnl[np.abs(pnl) > 1e-10]
    if pnl.size == 0:
        return dict(n_trades=0, hit_rate=np.nan, profit_factor=np.nan, avg_trade=np.nan,
                    best_trade=np.nan, worst_trade=np.nan, trades_per_year=np.nan,
                    avg_win=np.nan, avg_loss=np.nan)
    wins, losses = pnl[pnl > 0], pnl[pnl <= 0]
    return dict(n_trades=int(pnl.size), hit_rate=float(wins.size / pnl.size),
                profit_factor=float(wins.sum() / -losses.sum()) if losses.size else np.inf,
                avg_trade=float(pnl.mean()), best_trade=float(pnl.max()), worst_trade=float(pnl.min()),
                avg_win=float(wins.mean()) if wins.size else np.nan,
                avg_loss=float(losses.mean()) if losses.size else np.nan,
                trades_per_year=float(pnl.size / max(ra.size, 1) * 252.0))


def buy_and_hold(rets, ann: int = 252, warmup: int = 0) -> dict:
    r = np.atleast_1d(np.asarray(rets))[warmup:][None, :]
    return metrics(r, ann, pos=np.ones_like(r), changes=np.zeros(r.shape, bool),
                   min_bars=min(250, max(r.shape[1], 1))).iloc[0].to_dict()


def evaluate_pair_next_open(px: pd.DataFrame, fast: int, slow: int, *, ann: int = 252,
                            cost_bps: float = 0.0, mode: str = "long", warmup: int | None = None) -> dict:
    """Execution-robustness variant: signal on close *t*, trade at the **next day's open**.

    This is the realistic retail version of the same rule.  A pair that only works when you
    get filled at the exact close of the signal bar is not a tradeable edge, so the shortlist
    is scored on both conventions.  ``px`` needs ``close`` (for the EMAs) and ``open``.
    """
    close = px["close"].astype(float).to_numpy()
    o = px["open"].astype(float).to_numpy()
    if np.allclose(o, close):
        return {}
    st = ema(close, fast) > ema(close, slow)          # known at close of bar t
    n = len(close)
    unit = 1.0 if mode == "long" else 2.0
    long_only = mode == "long"
    tgt = st.astype(float) if long_only else np.where(st, 1.0, -1.0)
    w = np.zeros(n)
    w[1:] = tgt[:-1]                                   # enter at open[t+1]
    trans = np.zeros(n, bool)
    trans[1:] = w[1:] != w[:-1]
    # held from open[t+1] to open[t+2]  (one full session per signal bar)
    orr = o[2:] / o[1:-1] - 1.0
    ww = w[1:-1]
    tt = trans[1:-1]
    r = ww * orr - tt * (cost_bps / 1e4) * unit
    warm = int(slow if warmup is None else warmup)
    m = metrics(r[warm:][None, :], ann, pos=ww[warm:][None, :], changes=tt[warm:][None, :], unit=unit)
    if m.empty or not np.isfinite(m["sharpe"].iloc[0]):
        return {}
    out = m.iloc[0].to_dict()
    out["fast"], out["slow"] = fast, slow
    return out
