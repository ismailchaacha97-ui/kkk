#!/usr/bin/env python3
"""
study.py - research harness around tools/backtest.py

Three modes:

  matrix    the same configuration across symbols and presets
  sweep     a parameter grid on one symbol, with an out-of-sample split
  walk      a specific candidate configuration across every symbol and fold

The point of the harness is discipline, not discovery: a configuration is only
considered interesting if it survives on data it was not chosen on. Every table
therefore prints the training fold and the validation folds side by side, and a
candidate is rejected unless it has enough trades in each.

Usage:
  python3 research/study.py matrix
  python3 research/study.py sweep --symbol EURUSD --train 2025 --param threshold
  python3 research/study.py walk --config "threshold=0.55,sl_atr=1.5"
"""
import argparse
import itertools
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import backtest as bt

SYMBOLS = ["EURUSD", "XAUUSD", "US500.cash"]
TFS = ["m15"]


def slice_bars(bars, start=None, end=None):
    keep = [i for i, d in enumerate(bars["dt"])
            if (start is None or d >= start) and (end is None or d < end)]
    lo, hi = keep[0], keep[-1] + 1
    sub = {k: (v[lo:hi] if hasattr(v, "__len__") and not isinstance(v, str) else v)
           for k, v in bars.items()}
    sub["n"] = len(sub["c"])
    return sub


def evaluate(symbol, tf, preset, overrides=None, start=None, end=None, verbose=False):
    bars = bt.load_bars(symbol, tf)
    if start or end:
        bars = slice_bars(bars, start, end)
    p = dict(bt.BASE)
    p.update(bt.PRESETS[preset])
    if overrides:
        p.update(overrides)
    res = bt.run(bars, p, bt.SPECS[symbol], verbose)
    res["symbol"] = symbol
    res["preset"] = preset
    return res


def fmt_row(label, res, width=14):
    pf = res["profit_factor"]
    pfs = "  inf" if pf == float("inf") else f"{pf:5.2f}"
    return (f"{label:<{width}} n={res['n_trades']:>4}  exp={res['expectancy_r']:+.3f}R  "
            f"tot={res['total_r']:+6.1f}R  PF={pfs}  net={res['net_pct']:+6.2f}%  "
            f"DD={res['max_dd_pct']:+6.2f}%  win={res['win_rate']:4.1f}%  "
            f"worstday={res['worst_day_loss_pct']:4.2f}%")


def mode_matrix(args):
    print(f"{'config':<32} {'trades':>10} {'exp R':>8} {'PF':>7} {'net %':>8} {'maxDD %':>8}")
    for sym in SYMBOLS:
        for preset in ("conservative", "balanced", "active"):
            r = evaluate(sym, "m15", preset)
            print(fmt_row(f"{sym} {preset}", r))


def mode_walk(args):
    overrides = {}
    if args.config:
        for kv in args.config.split(","):
            k, v = kv.split("=")
            try:
                v = float(v)
            except ValueError:
                pass
            overrides[k.strip()] = v
    print(f"config: preset={args.preset} overrides={overrides}\n")
    print(f"{'fold':<34} {'n':>5} {'expR':>8} {'PF':>6} {'net%':>8} {'DD%':>7}")
    for sym in SYMBOLS:
        for name, (s, e) in {"2025 (train)": (datetime(2025, 1, 1), datetime(2025, 12, 31)),
                             "2026 (test)": (datetime(2026, 1, 1), datetime(2026, 6, 1)),
                             "all": (None, None)}.items():
            r = evaluate(sym, "m15", args.preset, overrides, s, e)
            print(fmt_row(f"{sym} {name}", r, width=34))


def mode_sweep(args):
    grid = {
        "threshold": [0.35, 0.45, 0.55, 0.65],
        "sl_atr": [1.0, 1.5, 2.0, 2.5, 3.0],
        "exit_mode": ["meanrev", "rmult"],
        "rr": [1.0, 1.5, 2.0, 2.5, 3.0],
        "trail": [True, False],
        "hl_stop_mult": [1.5, 3.0, 6.0],
        "min_atr_pct": [0.10, 0.25, 0.40],
        "max_atr_pct": [0.75, 0.95],
        "min_abs_z": [0.0, 0.75, 1.0, 1.25],
        "max_bars": [24, 48, 96],
        "session": [None, (1, 8), (7, 12), (8, 20), (13, 21), (22, 7)],
        "vr_threshold": [0.0, 0.08, 0.20],
        "hl_t_min": [0.0, 1.65, 2.86],
        "require_hl_gate": [True, False],
        "strategy": ["adaptive", "meanrev", "momentum"],
        "exit_on_z": [True, False],
        "mom_lookback": [4, 8, 16],
        "z_period": [10, 20, 40],
        "w_fib": [0.0, 0.4, 0.8],
    }[args.param]

    train = (datetime(2025, 1, 1), datetime(2025, 12, 31))
    test = (datetime(2026, 1, 1), datetime(2026, 6, 1))
    print(f"sweeping {args.param} on {args.symbol} (train 2025 / test 2026)\n")
    print(f"{'value':<16} {'n_tr':>5} {'exp_tr':>8} {'PF_tr':>6} {'n_te':>5} {'exp_te':>8} {'PF_te':>6} {'verdict'}")
    rows = []
    for v in grid:
        try:
            tr = evaluate(args.symbol, "m15", args.preset, {args.param: v}, *train)
            te = evaluate(args.symbol, "m15", args.preset, {args.param: v}, *test)
        except Exception as exc:                        # noqa: BLE001
            print(f"{str(v):<16}  error: {exc}")
            continue
        ok = (tr["n_trades"] >= args.min_trades and te["n_trades"] >= args.min_trades
              and tr["expectancy_r"] > 0 and te["expectancy_r"] > 0)
        verdict = "keep" if ok else ""
        print(f"{str(v):<16} {tr['n_trades']:>5} {tr['expectancy_r']:+8.3f} "
              f"{tr['profit_factor']:6.2f} {te['n_trades']:>5} {te['expectancy_r']:+8.3f} "
              f"{te['profit_factor']:6.2f} {verdict}")
        rows.append((v, tr, te, ok))
    kept = [r for r in rows if r[3]]
    print(f"\n{len(kept)}/{len(rows)} values survive train+test with >= {args.min_trades} trades")
    if kept:
        best = max(kept, key=lambda r: min(r[1]["expectancy_r"], r[2]["expectancy_r"]))
        print(f"most robust: {args.param}={best[0]}  "
              f"train {best[1]['expectancy_r']:+.3f}R / test {best[2]['expectancy_r']:+.3f}R")


def mode_years(args):
    """Run one configuration over every independent yearly file and pool it."""
    overrides = {}
    if args.config:
        for kv in args.config.split(","):
            k, v = kv.split("=")
            try:
                v = float(v)
            except ValueError:
                pass
            overrides[k.strip()] = v
    p = dict(bt.BASE)
    p.update(bt.PRESETS[args.preset])
    p.update(overrides)
    files = sorted(f for f in os.listdir(bt.DATA) if f.startswith("EURUSD_")
                   and f.endswith("_m15.csv"))
    if not files:
        raise SystemExit("no yearly files found - run tools/prepare_data.py hist")
    print(f"config: preset={args.preset} overrides={overrides}")
    print(f"{'file':<26} {'n':>5} {'exp R':>8} {'PF':>6} {'net %':>8} {'DD %':>7} {'win %':>6}")
    tot_r, tot_n = 0.0, 0
    pos_years = 0
    for f in files:
        bars = bt.load_bars("EURUSD", "m15", os.path.join(bt.DATA, f))
        res = bt.run(bars, p, bt.SPECS["EURUSD"])
        pf = res["profit_factor"]
        pfs = "   inf" if pf == float("inf") else f"{pf:6.2f}"
        print(f"{f:<26} {res['n_trades']:>5} {res['expectancy_r']:+8.3f} {pfs} "
              f"{res['net_pct']:+8.2f} {res['max_dd_pct']:+7.2f} {res['win_rate']:6.1f}")
        tot_r += res["total_r"]
        tot_n += res["n_trades"]
        pos_years += 1 if res["total_r"] > 0 else 0
    pooled = tot_r / tot_n if tot_n else 0.0
    print(f"\npooled: {tot_n} trades, {tot_r:+.1f} R, expectancy {pooled:+.3f} R, "
          f"{pos_years}/{len(files)} profitable years")


TRAIN_YEARS = ["2008", "2010", "2012"]
TEST_YEARS = ["2014", "2016", "2018"]


def _pool(files, overrides, preset):
    """Pooled stats over a list of yearly files (or 'ftmo' for the FTMO export)."""
    tot_r = tot_n = 0
    wins = losses = 0.0
    dd = 0.0
    for f in files:
        path = os.path.join(bt.DATA, f if f == "EURUSD_m15.csv" else f"EURUSD_{f}_m15.csv")
        bars = bt.load_bars("EURUSD", "m15", path)
        p = dict(bt.BASE); p.update(bt.PRESETS[preset]); p.update(overrides or {})
        res = bt.run(bars, p, bt.SPECS["EURUSD"])
        tot_r += res["total_r"]; tot_n += res["n_trades"]
        wins += res["gross_win"]; losses += res["gross_loss"]
        dd = min(dd, res["max_dd_pct"])
    pf = (wins / losses) if losses > 0 else float("inf")
    return dict(n=tot_n, total_r=tot_r, exp=(tot_r / tot_n if tot_n else 0.0), pf=pf, dd=dd)


def mode_psweep(args):
    """Sweep a parameter, pooled over TRAIN years, verified on TEST years."""
    grid = {
        "session": [None, (1, 8), (7, 12), (8, 20), (13, 21)],
        "exit_mode": ["meanrev", "rmult"],
        "rr": [1.0, 1.5, 2.0, 2.5, 3.0],
        "exit_on_z": [True, False],
        "sl_atr": [1.0, 1.5, 2.0, 2.5, 3.0, 4.0],
        "threshold": [0.30, 0.40, 0.50, 0.55, 0.65, 0.75],
        "min_abs_z": [0.0, 0.75, 1.0, 1.25, 1.5, 2.0],
        "require_hl_gate": [True, False],
        "hl_t_min": [0.0, 1.65, 2.0, 2.86, 3.43],
        "strategy": ["adaptive", "meanrev", "momentum"],
        "max_bars": [16, 24, 48, 96],
        "hl_stop_mult": [1.5, 3.0, 6.0],
        "min_atr_pct": [0.05, 0.10, 0.25, 0.40],
        "max_atr_pct": [0.60, 0.75, 0.90, 0.95],
        "neutral_regime": ["mr", "mo", "none"],
        "w_fib": [0.0, 0.4, 0.8, 1.2],
        "mom_lookback": [3, 6, 8, 12, 20],
        "z_period": [10, 15, 20, 30, 40],
        "vr_threshold": [0.0, 0.05, 0.08, 0.15],
        "trail": [True, False],
        "be": [True, False],
        "max_half_life": [20.0, 40.0, 80.0, 160.0],
        "min_sec_between": [30],
    }[args.param]

    print(f"pooled sweep: {args.param}   train={TRAIN_YEARS}  test={TEST_YEARS}+FTMO\n")
    print(f"{'value':<16} {'n_tr':>5} {'exp_tr':>8} {'PF_tr':>6}  "
          f"{'n_te':>5} {'exp_te':>8} {'PF_te':>6}  {'n_fx':>5} {'exp_fx':>8}  flag")
    for v in grid:
        ov = {args.param: v}
        tr = _pool(TRAIN_YEARS, ov, args.preset)
        te = _pool(TEST_YEARS, ov, args.preset)
        fx = _pool(["EURUSD_m15.csv"], ov, args.preset)
        flag = ""
        if (tr["n"] >= 40 and te["n"] >= 40 and tr["exp"] > 0 and te["exp"] > 0
                and fx["exp"] > 0):
            flag = "ALL3+"
        elif tr["exp"] > 0 and te["exp"] > 0:
            flag = "tr+te"
        print(f"{str(v):<16} {tr['n']:>5} {tr['exp']:+8.3f} {tr['pf']:6.2f}  "
              f"{te['n']:>5} {te['exp']:+8.3f} {te['pf']:6.2f}  "
              f"{fx['n']:>5} {fx['exp']:+8.3f}  {flag}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["matrix", "sweep", "walk", "years", "psweep"])
    ap.add_argument("--symbol", default="EURUSD")
    ap.add_argument("--preset", default="conservative")
    ap.add_argument("--param", default="threshold")
    ap.add_argument("--config", default="")
    ap.add_argument("--min-trades", type=int, default=20)
    args = ap.parse_args()
    {"matrix": mode_matrix, "sweep": mode_sweep, "walk": mode_walk,
     "years": mode_years, "psweep": mode_psweep}[args.mode](args)


if __name__ == "__main__":
    main()
