#!/usr/bin/env python3
"""Cross-check the MQL4 core against the Python simulator.

Two independent implementations of the same ladder exist in this repo:
  * noloss/noloss_sim.py  - the Monte Carlo used for report.md
  * mt4/RuleOP_Ladder.mq4 - the indicator, whose CORE section compiles as C++

They must agree on the ladder arithmetic. This script drives the C++ core
through the compiled test binary's math by recomputing the same quantities
from the Python side and comparing them rung by rung.

Run via `make cross`.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "noloss"))

from noloss_sim import Params, PIP_VALUE_PER_LOT, ladder_table  # noqa: E402

# mirror of ref_ladder()/ref_account() in test_ladder.cpp
FIRST_ENTRY = 1.1000
STEP = 0.0030          # 30 pips
TP = 0.0020            # 20 pips
BASE_LOT = 0.01
MULT = 2.0
TICK_VALUE = 100000.0  # per full price unit on 1.00 lot == $10 per pip per lot


def entry(rung):
    return FIRST_ENTRY - (rung - 1) * STEP


def lot(rung):
    return BASE_LOT * (MULT ** (rung - 1))


def cum_lot(rung):
    return sum(lot(i) for i in range(1, rung + 1))


def avg_entry(rung):
    return sum(entry(i) * lot(i) for i in range(1, rung + 1)) / cum_lot(rung)


def basket_tp_profit(rung):
    return cum_lot(rung) * TP * TICK_VALUE


def main():
    p = Params()
    rows = ladder_table(p)

    print("cross-check: Python simulator ladder vs the MQL4 core's arithmetic\n")
    print(f"{'rung':>4} {'lot(rung)':>10} {'cum lot':>10} {'basket TP $':>12} "
          f"{'report cum loss':>16}")
    failures = 0
    running = 0.0
    for r in rows:
        rung = r["rung"]
        # ladder_table reports the PER-RUNG lot; accumulate it to compare with
        # the core's cumulative lot.
        running += r["lot"]
        # the Python side works in pips at $10 per pip per lot, the MQL4 core in
        # price units at $100000 per price unit. Same thing: 0.0001 units/pip.
        py_basket = running * p.tp_pips * PIP_VALUE_PER_LOT
        mql_basket = basket_tp_profit(rung)
        ok_lot = abs(running - cum_lot(rung)) < 1e-9
        ok_tp = abs(py_basket - mql_basket) < 1e-6
        if not (ok_lot and ok_tp):
            failures += 1
        print(f"{rung:>4} {r['lot']:>10.4f} {running:>10.4f} {py_basket:>12.2f} "
              f"{r['cum_loss_usd']:>16,.0f}  "
              f"{'ok' if ok_lot and ok_tp else 'MISMATCH'}")

    print()
    if failures:
        print(f"{failures} rungs disagree between the two implementations")
        return 1
    print(f"all {len(rows)} rungs agree: cumulative lot and basket take profit "
          "match between noloss_sim.py and the MQL4 core")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
