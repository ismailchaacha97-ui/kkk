"""Command line interface.

    python -m kkk.cli list
    python -m kkk.cli demo                      # synthetic data, plumbing check
    python -m kkk.cli compare data/XAUUSD_H1.csv --symbol XAUUSD
    python -m kkk.cli sweep   data/XAUUSD_H1.csv --symbol XAUUSD -s magic_candle
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

from . import data as kdata
from .config import PRESETS, BacktestConfig, Costs, Instrument, RiskConfig
from .engine import Engine
from .metrics import compare, compute_stats, random_baseline
from .strategies import get as get_strategy
from .strategies import names as strategy_names


def _load(args) -> pd.DataFrame:
    if args.demo:
        df = kdata.make_synthetic(n=args.demo_bars)
        print(f"[demo] {kdata.summarize(df)}")
    else:
        df = kdata.load_csv(args.csv)
        print(f"[data] {kdata.summarize(df)}")
    df = kdata.add_sessions(df)
    if args.timeframe:
        df = kdata.resample(df, args.timeframe)
        print(f"[data] resampled to {args.timeframe}: {len(df):,} bars")
    return df


def _config(args) -> BacktestConfig:
    symbol = (args.symbol or "XAUUSD").upper()
    if symbol in PRESETS:
        cfg = BacktestConfig.for_symbol(symbol)
    else:
        cfg = BacktestConfig(instrument=Instrument(symbol, point_value_per_lot=100.0))
        print(f"[warn] {symbol} is not a preset — assuming 100 USD per 1.0 price move per lot")
    cfg.risk = RiskConfig(
        initial_equity=args.equity,
        risk_pct=args.risk,
        compound=not args.no_compound,
    )
    if args.spread is not None:
        cfg.costs = Costs(
            spread=args.spread,
            slippage=args.slippage,
            commission_per_lot=args.commission,
        )
    elif args.slippage or args.commission:
        cfg.costs.slippage = args.slippage
        cfg.costs.commission_per_lot = args.commission
    if args.optimistic_fill:
        cfg.stop_first_on_ambiguous_bar = False
    return cfg


def cmd_list(_args) -> int:
    print("Available methods:\n")
    for name in strategy_names():
        mod = get_strategy(name)
        print(f"  {name}")
        print(f"      {mod.TITLE}")
        print(f"      default params: {json.dumps(mod.DEFAULT_PARAMS, default=str)}")
        print()
    print("Symbol presets:", ", ".join(sorted(PRESETS)))
    return 0


def cmd_compare(args) -> int:
    df = _load(args)
    cfg = _config(args)
    sel = args.strategies or strategy_names()

    results = {}
    for name in sel:
        mod = get_strategy(name)
        sigs = mod.generate(df, **(_parse_overrides(args.param) if args.param else {}))
        res = Engine(cfg).run(df, sigs)
        results[mod.NAME] = res
        print(f"\n=== {mod.NAME} — {mod.TITLE} ===")
        print(compute_stats(res).table())

    print("\n=== comparison (sorted by expectancy) ===")
    table = compare(results)
    cols = ["trades", "win_rate", "expectancy_r", "profit_factor", "total_r",
            "return_pct", "max_drawdown_r", "max_consec_losses", "sharpe_r"]
    if not table.empty:
        with pd.option_context("display.width", 160, "display.max_columns", 40):
            print(table[cols].round(3).to_string())

    print("\n=== reality check: coin-flip baseline on the same data ===")
    base = random_baseline(df, cfg, n_trials=args.baseline_trials)
    print(
        f"  random entries, same risk model -> expectancy mean {base['mean']:+.3f} R, "
        f"5-95% range [{base['p5']:+.3f}, {base['p95']:+.3f}] over {base['n']} trials"
    )
    best = table.index[0] if not table.empty else None
    if best is not None:
        e = table.loc[best, "expectancy_r"]
        if e <= base["p95"]:
            print(
                f"  >>> WARNING: best method ({best}, {e:+.3f} R) does NOT clear the "
                f"noise band. On this data it has no demonstrated edge."
            )
        else:
            print(
                f"  >>> {best} clears the noise band ({e:+.3f} R vs p95 {base['p95']:+.3f} R)."
            )

    if args.out:
        out = Path(args.out)
        out.mkdir(parents=True, exist_ok=True)
        table.round(4).to_csv(out / "comparison.csv")
        for name, res in results.items():
            res.to_frame().to_csv(out / f"trades_{name}.csv", index=False)
        print(f"\n[saved] trades + comparison -> {out}/")
    return 0


def cmd_sweep(args) -> int:
    from .strategies.params import sweep

    df = _load(args)
    cfg = _config(args)
    mod = get_strategy(args.strategy)
    print(f"[sweep] {mod.NAME} over {len(df):,} bars, 70/30 time split\n")
    res = sweep(mod, df, cfg, split=args.split, min_trades=args.min_trades)
    if res.table.empty:
        print("no results")
        return 1
    cols = [c for c in res.table.columns if c in
            ("robust", "trades_is", "expectancy_is", "trades_oos", "expectancy_oos",
             "winrate_oos", "pf_oos", "total_r_oos", "maxdd_r_oos")]
    with pd.option_context("display.width", 200, "display.max_columns", 50):
        print(res.top(args.top).to_string(index=False))
    n_robust = int(res.table["robust"].sum())
    print(
        f"\n  {n_robust} / {len(res.table)} parameter sets survived out-of-sample.\n"
        f"  >>> If that number is small, the method is fragile — the good-looking\n"
        f"      in-sample rows are curve fits."
    )
    best = res.top(1)
    if not best.empty:
        print(f"\n  best by in-sample expectancy: {best.iloc[0].to_dict()}")
    return 0


def _parse_overrides(pairs) -> dict:
    """--param rr=2.5 --param valid_for=3  ->  {'rr': 2.5, 'valid_for': 3}

    argparse gives us a list of lists because of `action="append"`, so flatten
    before parsing.
    """
    flat: list[str] = []
    for item in pairs or []:
        if isinstance(item, (list, tuple)):
            flat.extend(item)
        else:
            flat.append(item)

    out = {}
    for item in flat:
        if "=" not in item:
            raise SystemExit(f"--param needs key=value, got {item!r}")
        k, v = item.split("=", 1)
        try:
            out[k] = json.loads(v)
        except json.JSONDecodeError:
            out[k] = v
    return out


def cmd_demo(args) -> int:
    args.demo = True
    return cmd_compare(args)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="kkk",
        description="Backtest three candle methods and find out which one holds up.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp):
        sp.add_argument("csv", nargs="?", help="OHLC csv (MT5 / TradingView export)")
        sp.add_argument("--demo", action="store_true", help="use synthetic data")
        sp.add_argument("--demo-bars", type=int, default=6000)
        sp.add_argument("--symbol", default="XAUUSD")
        sp.add_argument("--timeframe", help="resample, e.g. 4h or 1D")
        sp.add_argument("--equity", type=float, default=10_000.0)
        sp.add_argument("--risk", type=float, default=1.0, help="percent per trade")
        sp.add_argument("--no-compound", action="store_true",
                        help="risk a fixed %% of the initial balance")
        sp.add_argument("--spread", type=float, default=None)
        sp.add_argument("--slippage", type=float, default=0.0)
        sp.add_argument("--commission", type=float, default=0.0, help="per lot, per side")
        sp.add_argument("--optimistic-fill", action="store_true",
                        help="assume target hit first on ambiguous bars (don't)")
        sp.add_argument("--out", help="directory for trade logs and csv output")

    sp = sub.add_parser("list", help="show the available methods")
    sp.set_defaults(func=cmd_list)

    sp = sub.add_parser("demo", help="run everything on synthetic data")
    common(sp)
    sp.add_argument("--strategies", nargs="*")
    sp.add_argument("--param", nargs="*", action="append")
    sp.add_argument("--baseline-trials", type=int, default=200)
    sp.set_defaults(func=cmd_demo)

    sp = sub.add_parser("compare", help="backtest all methods on one dataset")
    common(sp)
    sp.add_argument("--strategies", nargs="*")
    sp.add_argument("--param", nargs="*", action="append")
    sp.add_argument("--baseline-trials", type=int, default=200)
    sp.set_defaults(func=cmd_compare)

    sp = sub.add_parser("sweep", help="parameter sweep with out-of-sample check")
    common(sp)
    sp.add_argument("-s", "--strategy", required=True)
    sp.add_argument("--split", type=float, default=0.7)
    sp.add_argument("--top", type=int, default=12)
    sp.add_argument("--min-trades", type=int, default=20)
    sp.set_defaults(func=cmd_sweep)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.cmd in ("compare", "demo"):
        if args.cmd == "demo":
            args.demo = True
        if not args.demo and not args.csv:
            print("error: give a CSV path, or use `kkk demo`", file=sys.stderr)
            return 2
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
