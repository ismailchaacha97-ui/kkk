"""Command-line interface for the day-trading toolkit."""

from __future__ import annotations

import argparse
import sys
from dataclasses import replace
from pathlib import Path

from daytrader import __version__
from daytrader.config import DEFAULT_SYMBOLS, BacktestConfig, ORBParams, VWAPParams

__all__ = ["main"]


def _add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--symbols",
        nargs="+",
        default=list(DEFAULT_SYMBOLS),
        help="ticker symbols (default: AAPL MSFT NVDA)",
    )
    parser.add_argument("--days", type=int, default=60, help="number of sessions")
    parser.add_argument("--seed", type=int, default=42, help="random seed")
    parser.add_argument(
        "--start-date",
        default="2026-01-05",
        help="first session date (YYYY-MM-DD)",
    )
    parser.add_argument("--bar-minutes", type=int, default=1, help="bar size in minutes")
    parser.add_argument("--data-dir", default="data", help="directory holding the CSV data")
    parser.add_argument("--balance", type=float, default=100_000.0, help="starting balance")
    parser.add_argument("--leverage", type=float, default=2.0, help="account leverage")
    parser.add_argument("--fee-bps", type=float, default=1.0, help="taker fee in bps")
    parser.add_argument(
        "--slippage-prob",
        type=float,
        default=0.5,
        help="probability of one tick of slippage per fill",
    )
    parser.add_argument("--log-level", default="WARNING", help="NautilusTrader log level")
    parser.add_argument(
        "--force-data",
        action="store_true",
        help="regenerate synthetic data even when CSV files exist",
    )
    parser.add_argument(
        "--no-generate",
        action="store_true",
        help="fail instead of generating synthetic data for missing symbols",
    )


def _add_strategy_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--risk-pct", type=float, help="equity risk per trade, in percent")
    parser.add_argument("--max-trades", type=int, help="max round trips per symbol per day")
    parser.add_argument("--orb-minutes", type=int, help="opening range length in minutes")
    parser.add_argument("--reward-risk", type=float, help="ORB take-profit R multiple")
    parser.add_argument("--band-k", type=float, help="VWAP band width in standard deviations")


def _make_config(args: argparse.Namespace, out_dir: Path) -> BacktestConfig:
    return BacktestConfig(
        symbols=tuple(args.symbols),
        days=args.days,
        seed=args.seed,
        start_date=args.start_date,
        starting_balance=args.balance,
        leverage=args.leverage,
        fee_bps=args.fee_bps,
        slippage_prob=args.slippage_prob,
        data_dir=Path(args.data_dir),
        out_dir=out_dir,
        log_level=args.log_level,
        bar_minutes=args.bar_minutes,
        auto_generate=not args.no_generate,
    )


def _make_params(strategy: str, args: argparse.Namespace):
    if strategy == "orb":
        params = ORBParams()
    else:
        params = VWAPParams()

    if getattr(args, "risk_pct", None) is not None:
        params = replace(
            params,
            risk=replace(params.risk, risk_per_trade_pct=args.risk_pct),
        )
    if getattr(args, "max_trades", None) is not None:
        params = replace(
            params,
            risk=replace(params.risk, max_trades_per_day=args.max_trades),
        )
    if strategy == "orb":
        if getattr(args, "orb_minutes", None) is not None:
            params = replace(params, opening_range_minutes=args.orb_minutes)
        if getattr(args, "reward_risk", None) is not None:
            params = replace(params, reward_risk=args.reward_risk)
    if strategy == "vwap" and getattr(args, "band_k", None) is not None:
        params = replace(params, band_k=args.band_k)
    return params


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="daytrader",
        description=(
            "NautilusTrader-powered day-trading research toolkit: synthetic or "
            "CSV 1-minute data, ORB and VWAP strategies, costs, reports."
        ),
    )
    parser.add_argument("--version", action="version", version=f"daytrader {__version__}")
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser("generate-data", help="generate synthetic 1-minute data")
    _add_common_arguments(generate)

    backtest = subparsers.add_parser("backtest", help="run one strategy")
    _add_common_arguments(backtest)
    _add_strategy_arguments(backtest)
    backtest.add_argument("--strategy", choices=["orb", "vwap"], default="orb")
    backtest.add_argument("--out", default=None, help="output directory")

    compare = subparsers.add_parser("compare", help="run all strategies and compare them")
    _add_common_arguments(compare)
    _add_strategy_arguments(compare)
    compare.add_argument("--out", default="reports", help="output directory")

    return parser


def _run_generate(args: argparse.Namespace) -> int:
    from daytrader.data import generate_dataset, load_bars
    from daytrader.instruments import bar_type_for, make_equity

    paths = generate_dataset(
        symbols=args.symbols,
        data_dir=Path(args.data_dir),
        start_date=args.start_date,
        days=args.days,
        seed=args.seed,
        bar_minutes=args.bar_minutes,
        force=args.force_data,
    )
    print(f"Generated {len(paths)} symbol file(s) in {Path(args.data_dir).resolve()}:")
    for symbol, path in paths.items():
        instrument = make_equity(symbol, fee_bps=args.fee_bps)
        bars = load_bars(path, instrument, bar_type_for(instrument, args.bar_minutes))
        print(f"  {symbol:<6} {len(bars):>7,} bars  {path}")
    return 0


def _run_backtest(args: argparse.Namespace) -> int:
    from daytrader.backtest import run_backtest
    from daytrader.reporting import print_summary_table, write_reports

    out_dir = Path(args.out) if args.out else Path("reports") / args.strategy
    config = _make_config(args, out_dir)
    params = _make_params(args.strategy, args)
    result = run_backtest(
        args.strategy,
        config,
        params,
        refresh_data=args.force_data,
    )
    written = write_reports(result, out_dir)

    print(print_summary_table({args.strategy: result}))
    print(f"\nReports written to {out_dir.resolve()}")
    for name in ("markdown", "stats", "chart"):
        if name in written:
            print(f"  - {written[name].name}")
    return 0


def _run_compare(args: argparse.Namespace) -> int:
    from daytrader.backtest import run_backtest
    from daytrader.reporting import print_summary_table, write_comparison, write_reports

    out_dir = Path(args.out)
    config = _make_config(args, out_dir)
    results = {}

    for index, strategy in enumerate(("orb", "vwap")):
        run_config = replace(
            config,
            out_dir=out_dir / strategy,
        )
        print(f"Running {strategy.upper()} ...")
        result = run_backtest(
            strategy,
            run_config,
            _make_params(strategy, args),
            refresh_data=args.force_data and index == 0,
        )
        write_reports(result, out_dir / strategy)
        results[strategy] = result

    written = write_comparison(results, out_dir)
    print(print_summary_table(results))
    print(f"\nComparison written to {written['markdown'].resolve()}")
    print(f"Per-strategy reports in {out_dir.resolve()}/{{orb,vwap}}/summary.md")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "generate-data":
            return _run_generate(args)
        if args.command == "backtest":
            return _run_backtest(args)
        if args.command == "compare":
            return _run_compare(args)
    except (ValueError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 1
