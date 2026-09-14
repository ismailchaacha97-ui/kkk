#!/usr/bin/env python3
"""Print the InpMacroDates string for TaylorCycle.mq4 from data/*.csv.

Usage:
  python mt4_cal_input.py [FROM_DATE]   # FROM_DATE = YYYY-MM-DD, default today
Example output (paste into the indicator's InpMacroDates input):
  2026.10.02,2026.10.14,2026.10.28,2026.11.06
"""
import csv
import os
import sys
from datetime import date

BASE = os.path.dirname(os.path.abspath(__file__))
frm = sys.argv[1] if len(sys.argv) > 1 else date.today().isoformat()

dates = set()
for fn in ("data/fomc_dates.csv", "data/macro_dates.csv"):
    p = os.path.join(BASE, fn)
    if not os.path.exists(p):
        continue
    with open(p) as f:
        for r in csv.DictReader(f):
            d = r["date"].strip()
            if d >= frm:
                dates.add(d.replace("-", "."))

print(",".join(sorted(dates)))
