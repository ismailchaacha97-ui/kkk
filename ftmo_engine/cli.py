"""Command line: size a trade, check a plan, or print the go/no-go gate.

  python3 -m ftmo_engine.cli size  --balance 100000 --risk 0.5 --stop-pips 25
  python3 -m ftmo_engine.cli check --win-rate 0.45 --rr 1.8 --risk 0.5
  python3 -m ftmo_engine.cli gate  --win-rate 0.45 --rr 1.8
"""

from __future__ import annotations

import argparse

from .mc import EdgeProfile, evaluate_plan, monte_carlo_phase
from .rules import PHASE_1, PLANS
from .risk import EURUSD, lots_for_risk


def cmd_size(args: argparse.Namespace) -> None:
    spec = EURUSD
    lots = lots_for_risk(args.balance, args.risk, args.stop_pips, spec)
    risk_money = args.balance * args.risk / 100
    print(f"balance      : ${args.balance:,.0f}")
    print(f"risk         : {args.risk:.2f}% = ${risk_money:,.0f}")
    print(f"stop         : {args.stop_pips:.0f} pips on {spec.name} "
          f"(${spec.pip_value_per_lot:.2f}/pip/lot)")
    print(f"lots         : {lots:.2f}")
    if lots == 0.0:
        print("  -> size rounds below the broker minimum: skip the trade or widen risk")
    print(f"check        : {args.stop_pips:.0f} pips x {lots:.2f} lots x "
          f"${spec.pip_value_per_lot:.2f} = ${args.stop_pips * lots * spec.pip_value_per_lot:,.0f}")


def cmd_check(args: argparse.Namespace) -> None:
    plan = PLANS[args.account]
    edge = EdgeProfile(win_prob=args.win_rate, win_R=args.rr, trades_per_day=args.trades_per_day)
    res = evaluate_plan(plan, edge, args.risk, daily_stop_R=2.0, n_trials=4000,
                        funded_cycles=12, payout_buffer_pct=15.0)
    print(f"edge         : {edge.expectancy_R:+.3f}R per trade, PF {edge.profit_factor:.2f}")
    print(f"P(pass P1)   : {res['phase1']['p_pass'] * 100:5.1f}%   "
          f"median {res['phase1']['median_days_to_pass']:.0f} trading days")
    print(f"P(pass P2)   : {res['phase2']['p_pass'] * 100:5.1f}%")
    print(f"P(funded)    : {res['p_reach_funded'] * 100:5.1f}%")
    print(f"EV/attempt   : ${res['ev_per_attempt']:,.0f}   "
          f"(fee ${plan.fee}, expected purchases {res['expected_challenge_purchases']:.2f})")
    verdict = "GO" if res["ev_per_attempt"] > 0 and edge.expectancy_R >= 0.10 else "NO-GO"
    print(f"verdict      : {verdict}")
    if verdict == "NO-GO":
        print("               edge below 0.10R/trade or EV negative -- do not buy the evaluation")


def cmd_gate(args: argparse.Namespace) -> None:
    edge = EdgeProfile(win_prob=args.win_rate, win_R=args.rr, trades_per_day=args.trades_per_day)
    e0 = edge.win_prob_for_expectancy(0.0)
    e10 = edge.win_prob_for_expectancy(0.10)
    print(f"win rate for 0.00R/trade : {e0 * 100:.1f}%   <- absolute floor")
    print(f"win rate for 0.10R/trade : {e10 * 100:.1f}%   <- minimum worth trading")
    print(f"your win rate            : {edge.win_prob * 100:.1f}% "
          f"({edge.expectancy_R:+.3f}R per trade)")
    for risk in (0.5, 1.0, 2.0):
        r = monte_carlo_phase(PHASE_1, PLANS["100K"], edge, risk, n_trials=2000,
                              daily_stop_R=2.0, max_days=200)
        print(f"  at {risk:.1f}% risk -> P(pass Phase 1) {r['p_pass'] * 100:.1f}%, "
              f"median {r['median_days_to_pass']:.0f} days")


def main() -> None:
    p = argparse.ArgumentParser(prog="ftmo_engine", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("size", help="position size for a given stop")
    s.add_argument("--balance", type=float, default=100_000)
    s.add_argument("--risk", type=float, default=0.5)
    s.add_argument("--stop-pips", type=float, default=25)
    s.set_defaults(func=cmd_size)

    c = sub.add_parser("check", help="Monte Carlo one configuration")
    c.add_argument("--win-rate", type=float, default=0.45)
    c.add_argument("--rr", type=float, default=1.8)
    c.add_argument("--risk", type=float, default=0.5)
    c.add_argument("--trades-per-day", type=float, default=2.0)
    c.add_argument("--account", default="100K", choices=list(PLANS))
    c.set_defaults(func=cmd_check)

    g = sub.add_parser("gate", help="minimum edge required")
    g.add_argument("--win-rate", type=float, default=0.45)
    g.add_argument("--rr", type=float, default=1.8)
    g.add_argument("--trades-per-day", type=float, default=2.0)
    g.set_defaults(func=cmd_gate)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
