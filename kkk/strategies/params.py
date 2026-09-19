"""Grid search / parameter sweep with an explicit overfitting guard.

The output deliberately reports both the in-sample and the out-of-sample
result for every combination. A parameter set that only wins in-sample is
noise, and the report says so out loud.
"""

from __future__ import annotations

import itertools
import sys
from dataclasses import dataclass

import pandas as pd

from ..config import BacktestConfig
from ..engine import Engine
from ..metrics import compute_stats


@dataclass
class SweepResult:
    table: pd.DataFrame

    def best(self, metric: str = "expectancy_is") -> pd.Series:
        return self.table.sort_values(metric, ascending=False).iloc[0]

    def top(self, n: int = 10, metric: str = "expectancy_is") -> pd.DataFrame:
        cols = [c for c in self.table.columns if not c.startswith("signal_")]
        return self.table.sort_values(metric, ascending=False).head(n)[cols]


def _combos(grid: dict) -> list[dict]:
    keys = list(grid)
    return [dict(zip(keys, vals)) for vals in itertools.product(*(grid[k] for k in keys))]


def sweep(
    module,
    df,
    config: BacktestConfig,
    *,
    grid: dict | None = None,
    split: float = 0.7,
    metric: str = "expectancy_is",
    min_trades: int = 20,
    verbose: bool = True,
) -> SweepResult:
    """Run `module.generate` over a parameter grid, in-sample and out-of-sample.

    `split` is applied as a hard time cut: parameters are chosen on the first
    `split` of the data and then measured once on the rest.
    """
    grid = grid or module.SWEEP
    cut = int(len(df) * split)
    is_df, oos_df = df.iloc[:cut], df.iloc[cut:]

    rows = []
    combos = _combos(grid)
    # Only animate on a real terminal — a carriage-return bar turns into
    # thousands of junk lines when output is piped to a file.
    animate = verbose and sys.stdout.isatty()
    if verbose and not animate:
        print(f"  running {len(combos)} parameter combinations...", flush=True)
    for k, params in enumerate(combos, 1):
        if animate:
            print(f"  [{k}/{len(combos)}] {params}", end="\r", flush=True)
        row = dict(params)
        for label, part in (("is", is_df), ("oos", oos_df)):
            sigs = module.generate(part, **params)
            res = Engine(config).run(part, sigs)
            st = compute_stats(res)
            row[f"trades_{label}"] = st.trades
            row[f"expectancy_{label}"] = st.expectancy_r
            row[f"winrate_{label}"] = st.win_rate
            row[f"pf_{label}"] = st.profit_factor
            row[f"total_r_{label}"] = st.total_r
            row[f"maxdd_r_{label}"] = st.max_drawdown_r
        row["signals_is"] = row["trades_is"]
        rows.append(row)
    if animate:
        print(" " * 90, end="\r")

    table = pd.DataFrame(rows)
    if table.empty:
        return SweepResult(table)

    # Flag the classic trap: good in-sample, bad out-of-sample.
    table["robust"] = (
        (table["trades_is"] >= min_trades)
        & (table["trades_oos"] >= max(5, min_trades // 4))
        & (table["expectancy_is"] > 0)
        & (table["expectancy_oos"] > 0)
    )
    table = table.sort_values(["robust", metric], ascending=False).reset_index(drop=True)
    return SweepResult(table)
