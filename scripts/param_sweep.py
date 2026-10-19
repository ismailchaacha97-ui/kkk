#!/usr/bin/env python3
"""Small in-sample parameter sweep for the reference strategies.

This is a research convenience, not an optimiser with a holdout. It exists to
show how to drive :func:`daytrader.backtest.run_backtest` over a grid and to
make the cost/parameter sensitivity visible. Any parameter set selected by
looking at these results is in-sample and should be validated walk-forward on
unseen data before it is trusted.

Usage
-----
    python scripts/param_sweep.py --strategy orb --days 60
    python scripts/param_sweep.py --strategy all --symbols AAPL MSFT NVDA

Outputs
-------
``reports/sweep_<strategy>.csv`` (all runs, sorted by net PnL) and
``reports/sweep_<strategy>.md`` (top rows + caveat).
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import asdict, replace
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from daytrader.backtest import run_backtest
from daytrader.config import (
    BacktestConfig,
    ORBParams,
    VWAPParams,
)

GRIDS: dict[str, dict[str, list[object]]] = {
    "orb": {
        "opening_range_minutes": [15, 30],
        "reward_risk": [1.5, 2.0, 3.0],
        "volume_mult": [0.0, 1.2],
    },
    "vwap": {
        "band_k": [1.5, 2.0, 2.5],
        "atr_stop_mult": [1.0, 1.5, 2.0],
        "min_reward_risk": [0.8, 1.0],
    },
}

METRICS = (
    "net_pnl",
    "return_pct",
    "trades",
    "win_rate_pct",
    "profit_factor",
    "max_drawdown_pct",
    "sharpe",
)


def _combinations(grid: dict[str, list[object]]) -> list[dict[str, object]]:
    keys = list(grid)
    combos: list[dict[str, object]] = [{}]
    for key in keys:
        combos = [{**combo, key: value} for combo in combos for value in grid[key]]
    return combos


def _markdown_table(frame: pd.DataFrame) -> str:
    """Render a compact Markdown table without a tabulate dependency."""
    columns = list(frame.columns)
    lines = [
        "| " + " | ".join(columns) + " |",
        "|" + "|".join("---" for _ in columns) + "|",
    ]
    for _, row in frame.iterrows():
        cells = []
        for column in columns:
            value = row[column]
            if isinstance(value, float):
                cells.append(f"{value:.2f}")
            else:
                cells.append(str(value))
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def run_grid(strategy: str, base_config: BacktestConfig, top: int, out_dir: Path) -> pd.DataFrame:
    base_params = ORBParams() if strategy == "orb" else VWAPParams()
    combos = _combinations(GRIDS[strategy])
    rows: list[dict[str, object]] = []

    for index, combo in enumerate(combos, start=1):
        params = replace(base_params, **combo)
        print(f"[{index}/{len(combos)}] {strategy} {combo}")
        result = run_backtest(strategy, base_config, params)
        row: dict[str, object] = {}
        for key, value in asdict(params).items():
            if isinstance(value, dict):
                row.update(value)
            else:
                row[key] = value
        row.update({metric: result.summary.get(metric) for metric in METRICS})
        rows.append(row)

    frame = pd.DataFrame(rows).sort_values("net_pnl", ascending=False).reset_index(drop=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / f"sweep_{strategy}.csv"
    frame.to_csv(csv_path, index=False)

    display = frame.head(top)
    markdown_table = _markdown_table(display)
    markdown = [
        f"# Parameter sweep — {strategy.upper()}",
        "",
        f"{len(frame)} combinations on {', '.join(base_config.symbols)} "
        f"({len(base_config.symbols)} symbols, seed {base_config.seed}).",
        "",
        "> **In-sample only.** The best rows are selected on the same data they "
        "were evaluated on. Validate walk-forward before trusting them.",
        "",
        markdown_table,
        "",
    ]
    (out_dir / f"sweep_{strategy}.md").write_text("\n".join(markdown))
    print(f"\nTop {len(display)} of {len(frame)} — {strategy.upper()}")
    print(display.to_string(index=False))
    print(f"\nWrote {csv_path}")
    return frame


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strategy", choices=["orb", "vwap", "all"], default="all")
    parser.add_argument("--symbols", nargs="+", default=["AAPL", "MSFT", "NVDA"])
    parser.add_argument("--days", type=int, default=60)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--start-date", default="2026-01-05")
    parser.add_argument("--data-dir", default="data")
    parser.add_argument("--out", default="reports")
    parser.add_argument("--top", type=int, default=8)
    parser.add_argument("--balance", type=float, default=100_000.0)
    parser.add_argument("--fee-bps", type=float, default=1.0)
    parser.add_argument("--slippage-prob", type=float, default=0.5)
    args = parser.parse_args(argv)

    out_dir = Path(args.out)
    config = BacktestConfig(
        symbols=tuple(args.symbols),
        days=args.days,
        seed=args.seed,
        start_date=args.start_date,
        starting_balance=args.balance,
        fee_bps=args.fee_bps,
        slippage_prob=args.slippage_prob,
        data_dir=Path(args.data_dir),
        out_dir=out_dir,
    )

    strategies = ["orb", "vwap"] if args.strategy == "all" else [args.strategy]
    for strategy in strategies:
        run_grid(strategy, config, args.top, out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
