"""Performance statistics for a backtest."""

from __future__ import annotations

from dataclasses import dataclass, asdict

import numpy as np
import pandas as pd

from .engine import BacktestResult


@dataclass
class Stats:
    trades: int
    wins: int
    losses: int
    win_rate: float          # %
    avg_win_r: float
    avg_loss_r: float
    expectancy_r: float      # average R per trade — the number that matters
    profit_factor: float
    total_r: float
    net_pnl: float
    return_pct: float
    max_drawdown_r: float
    max_drawdown_pct: float
    max_consec_losses: int
    sharpe_r: float
    avg_bars_held: float
    best_r: float
    worst_r: float
    skipped: int

    def as_dict(self) -> dict:
        return asdict(self)

    def table(self) -> str:
        rows = [
            ("Trades", f"{self.trades}"),
            ("Win rate", f"{self.win_rate:.1f}%  ({self.wins}W / {self.losses}L)"),
            ("Expectancy", f"{self.expectancy_r:+.3f} R per trade"),
            ("Profit factor", f"{self.profit_factor:.2f}"),
            ("Total", f"{self.total_r:+.1f} R  |  {self.net_pnl:+,.2f}"),
            ("Return", f"{self.return_pct:+.1f}%"),
            ("Avg win / loss", f"{self.avg_win_r:+.2f} R / {self.avg_loss_r:+.2f} R"),
            ("Best / worst", f"{self.best_r:+.2f} R / {self.worst_r:+.2f} R"),
            ("Max drawdown", f"{self.max_drawdown_r:.1f} R  ({self.max_drawdown_pct:.1f}%)"),
            ("Max consec. losses", f"{self.max_consec_losses}"),
            ("Sharpe (per trade)", f"{self.sharpe_r:.2f}"),
            ("Avg bars held", f"{self.avg_bars_held:.1f}"),
        ]
        width = max(len(k) for k, _ in rows)
        return "\n".join(f"  {k:<{width}}  {v}" for k, v in rows)


def _max_drawdown(equity: np.ndarray) -> tuple[float, float]:
    if len(equity) == 0:
        return 0.0, 0.0
    peak = np.maximum.accumulate(equity)
    dd_abs = peak - equity
    dd_pct = np.divide(dd_abs, peak, out=np.zeros_like(dd_abs), where=peak > 0)
    return float(dd_abs.max()), float(dd_pct.max() * 100)


def compute_stats(result: BacktestResult) -> Stats:
    tr = result.trades
    n = len(tr)
    if n == 0:
        return Stats(0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                     0.0, 0.0, 0, 0.0, 0.0, 0.0, 0.0, result.skipped)

    r = np.array([t.r_multiple for t in tr], float)
    pnl = np.array([t.pnl for t in tr], float)
    wins = r > 0
    losses = r <= 0

    gross_win = float(pnl[wins].sum())
    gross_loss = float(-pnl[losses].sum())
    if gross_loss == 0:
        pf = float("inf") if gross_win > 0 else 0.0
    else:
        pf = gross_win / gross_loss

    # max consecutive losers
    streak = best = 0
    for w in wins:
        streak = 0 if w else streak + 1
        best = max(best, streak)

    eq = result.equity.to_numpy(float)
    eq = eq[~np.isnan(eq)]
    start = result.config.risk.initial_equity
    # express equity drawdown in R using the average cash risk per trade
    risks = [t.risk_amount for t in tr if t.risk_amount > 0]
    avg_risk = float(np.mean(risks)) if risks else start * 0.01
    dd_abs, dd_pct = _max_drawdown(eq if len(eq) else np.array([start]))

    sd = float(r.std(ddof=1)) if n > 1 else 0.0
    sharpe = float(r.mean() / sd) if sd > 0 else 0.0

    return Stats(
        trades=n,
        wins=int(wins.sum()),
        losses=int(losses.sum()),
        win_rate=float(wins.mean() * 100),
        avg_win_r=float(r[wins].mean()) if wins.any() else 0.0,
        avg_loss_r=float(r[losses].mean()) if losses.any() else 0.0,
        expectancy_r=float(r.mean()),
        profit_factor=pf,
        total_r=float(r.sum()),
        net_pnl=float(pnl.sum()),
        return_pct=float(pnl.sum() / start * 100),
        max_drawdown_r=float(dd_abs / avg_risk) if avg_risk > 0 else 0.0,
        max_drawdown_pct=dd_pct,
        max_consec_losses=best,
        sharpe_r=sharpe,
        avg_bars_held=float(np.mean([t.bars_held for t in tr])),
        best_r=float(r.max()),
        worst_r=float(r.min()),
        skipped=result.skipped,
    )


def compare(results: dict[str, BacktestResult]) -> pd.DataFrame:
    """Side-by-side comparison table, sorted by expectancy."""
    rows = {name: compute_stats(res).as_dict() for name, res in results.items()}
    df = pd.DataFrame(rows).T
    if df.empty:
        return df
    return df.sort_values("expectancy_r", ascending=False)


def random_baseline(df: pd.DataFrame, config, n_trials: int = 200, seed: int = 0):
    """Sanity check: what does a coin-flip strategy score on this data?

    If your real strategy does not clearly beat this distribution, you have
    not found an edge — you have found noise.
    """
    from .engine import Engine, Signal

    rng = np.random.default_rng(seed)
    exp = []
    for _ in range(n_trials):
        bars = rng.integers(50, len(df) - 50, size=max(10, len(df) // 100))
        sigs = []
        for b in bars:
            sign = 1 if rng.random() < 0.5 else -1
            entry_ref = float(df["close"].iloc[b])
            dist = float(df["close"].iloc[b] * 0.005)
            stop = entry_ref - sign * dist
            target = entry_ref + sign * dist * 1.5
            sigs.append(
                Signal(
                    direction="long" if sign > 0 else "short",
                    stop=stop,
                    target=target,
                    bar=int(b),
                )
            )
        res = Engine(config).run(df, sigs)
        if res.trades:
            exp.append(compute_stats(res).expectancy_r)
    exp = np.array(exp)
    if len(exp) == 0:
        return {"mean": 0.0, "p5": 0.0, "p95": 0.0, "n": 0}
    return {
        "mean": float(exp.mean()),
        "p5": float(np.percentile(exp, 5)),
        "p95": float(np.percentile(exp, 95)),
        "n": int(len(exp)),
    }
