#!/usr/bin/env python3
"""
mt4_export_to_fixture.py - turn *your broker's* history into a test fixture.

The test suite in this repository ships one synthetic fixture, and
tools/fetch_data.py can pull real exchange history.  Neither is your broker's
feed - and the whole point of VWAP Pro is that broker feeds differ (constant
tick volume, missing real volume, gaps at the roll).  So the proper test is the
one this script enables: export your own MT4 history, drop the resulting CSV
into tests/fixtures/, and run `make test`.

How to export from MetaTrader 4
-------------------------------
1. Open the chart you care about and let the history download fully
   (Tools -> Options -> Charts -> "Max bars in history" and "Max bars in
   chart" as large as you can afford).
2. Use the bundled exporter script:
       MQL4/Scripts/VpExportHistory.mq4
   (or any script that walks Bars and prints
    Time[i],Open[i],High[i],Low[i],Close[i],Volume[i])
   and write it to a file, e.g. EURUSD_M1.csv.
3. Run this tool:

       python3 tools/mt4_export_to_fixture.py EURUSD_M1.csv \
                --out tests/fixtures/eurusd_m1_real.csv --symbol EURUSD

   and then `make test`.  Every suite that touches the fixture battery
   (tests/test_data.cpp) will pick the new file up automatically, and the
   numbers it prints will be *your* feed's numbers.

Accepted input layouts (auto-detected)
--------------------------------------
    Time,Open,High,Low,Close,Volume                      (MT4 statement export)
    Date,Time,Open,High,Low,Close,Volume                (MT4 "Save as" CSV)
    <tab> separated versions of the above               (MT4 copy/paste)
    time,open,high,low,close,tick_volume,real_volume    (this repo's format)
    unix_seconds,o,h,l,c,vol[,vol]
    unix_ms,o,h,l,c,vol[,vol]

Time columns may be
    YYYY.MM.DD HH:MM                (MT4 uses dots)
    YYYY-MM-DD HH:MM:SS
    YYYY-MM-DD
    unix seconds or milliseconds (10 or 13 digits)

Output: the canonical fixture format used by the whole repository

    # VWAP Pro test fixture
    # source: ...   symbol: ...
    # columns: unix_seconds,open,high,low,close,tick_volume,real_volume
    time,open,high,low,close,tick_volume,real_volume
    1736121600,1.084200,1.084339,1.084109,1.084226,195,0

The script reports the feed diagnostics VWAP Pro cares about (constant tick
volume? real volume present? gaps? duplicate timestamps? out-of-order bars?)
so that you know what you are testing before you run the suites.
"""

import argparse
import datetime as dt
from collections import Counter
import math
import os
import sys

#--------------------------------------------------------------------------
# time parsing
#--------------------------------------------------------------------------
def _from_unix(v):
    if v > 1e12:            # milliseconds
        v /= 1000.0
    return int(v)


def parse_time(text):
    """Parse one time cell into unix seconds (UTC), or None."""
    s = text.strip().strip('"')
    if not s:
        return None
    if s.lstrip("-").isdigit():
        return _from_unix(int(s))
    s = s.replace(".", "-").replace("/", "-")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S",
                "%Y-%m-%d", "%d-%m-%Y %H:%M", "%m-%d-%Y %H:%M"):
        try:
            t = dt.datetime.strptime(s, fmt)
            return int(t.replace(tzinfo=dt.timezone.utc).timestamp())
        except ValueError:
            continue
    return None


def split_row(line, delimiter):
    if delimiter is None:
        delimiter = "\t" if "\t" in line else (";" if ";" in line else ",")
    return [c.strip().strip('"') for c in line.split(delimiter)]


def to_float(text):
    try:
        return float(text)
    except ValueError:
        return float("nan")


#--------------------------------------------------------------------------
# load
#--------------------------------------------------------------------------
def load(path):
    with open(path, "r", errors="replace") as fh:
        raw = fh.read()

    rows = []
    skipped = 0
    for line in raw.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cells = split_row(line, None)
        if len(cells) < 6:
            skipped += 1
            continue

        #--- locate the time column: the first cell that parses as a
        #--- timestamp (or, if a separate Date column exists, the first two)
        t = parse_time(cells[0])
        rest = cells[1:]
        if t is None:
            t = parse_time(cells[0] + " " + cells[1]) if len(cells) >= 7 else None
            if t is not None:
                rest = cells[2:]
        if t is None:
            skipped += 1            # header, junk, or unsupported layout
            continue

        nums = [to_float(c) for c in rest[:6]]
        while len(nums) < 6:
            nums.append(0.0)
        o, h, l, c, tv, rv = nums
        if math.isnan(o) or math.isnan(h) or math.isnan(l) or math.isnan(c):
            skipped += 1
            continue
        rows.append((t, o, h, l, c, tv, rv))
    return rows, skipped


#--------------------------------------------------------------------------
# diagnostics - the numbers that decide whether the feed can support a VWAP
#--------------------------------------------------------------------------
def diagnose(rows):
    if not rows:
        return {}
    d = {}
    n = len(rows)
    d["bars"] = n
    d["from"] = dt.datetime.fromtimestamp(rows[0][0], dt.timezone.utc)
    d["to"] = dt.datetime.fromtimestamp(rows[-1][0], dt.timezone.utc)

    raw_steps = [rows[i + 1][0] - rows[i][0] for i in range(n - 1)]
    steps = [s for s in raw_steps if s > 0]
    if steps:
        step = Counter(steps).most_common(1)[0][0]
        d["bar_seconds"] = step
        d["gaps"] = sum(1 for s in steps if s > step * 1.5)
        d["max_gap_hours"] = max(steps) / 3600.0
    d["out_of_order"] = sum(1 for s in raw_steps if s <= 0)
    d["duplicate_times"] = n - len(set(r[0] for r in rows))

    tv = [r[5] for r in rows]
    rv = [r[6] for r in rows]
    d["tick_constant"] = len(set(tv)) == 1
    d["tick_zero_bars"] = sum(1 for v in tv if not v > 0)
    d["tick_min"], d["tick_max"] = min(tv), max(tv)
    d["real_used_bars"] = sum(1 for v in rv if v > 0)

    bad = 0
    for (t, o, h, l, c, _, _) in rows:
        if not (o > 0 and c > 0 and h >= l and h > 0) or (h - l) > c:
            bad += 1
    d["bars_rejected_by_engine"] = bad
    return d


def report(d, path):
    def f(x, nd=0):
        return f"{x:.{nd}f}"

    print(f"\n{os.path.basename(path)}")
    print(f"  bars                 {d.get('bar_seconds', 0) and d['bars'] or 0}")
    if "from" in d:
        print(f"  span                 {d['from']:%Y-%m-%d %H:%M} .. {d['to']:%Y-%m-%d %H:%M} UTC")
    if "bar_seconds" in d:
        print(f"  bar size             {d['bar_seconds']}s")
        print(f"  gaps                 {d['gaps']} (largest {f(d['max_gap_hours'], 1)}h)")
    print(f"  out-of-order bars    {d.get('out_of_order', 0)}")
    print(f"  duplicate timestamps {d.get('duplicate_times', 0)}")
    print(f"  tick volume          min {f(d.get('tick_min', 0))}  max {f(d.get('tick_max', 0))}"
          f"  zero-bars {d.get('tick_zero_bars', 0)}"
          f"  {'CONSTANT (no information)' if d.get('tick_constant') else 'varies (usable)'}")
    print(f"  real volume          on {d.get('real_used_bars', 0)} bars")
    print(f"  bars the engine will reject outright: {d.get('bars_rejected_by_engine', 0)}")
    if d.get("tick_constant") or d.get("tick_zero_bars", 0) > d.get("bars", 1) // 2:
        print("  -> VWAP Pro will fall back to the volatility clock on this feed.")
        print("     That is the documented, scale-free degradation - not an error.")


#--------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="CSV exported from MT4 (or any OHLCV CSV)")
    ap.add_argument("--out", required=True, help="destination fixture .csv")
    ap.add_argument("--symbol", default="", help="symbol label for the header")
    ap.add_argument("--reverse", action="store_true",
                    help="input is newest-first (MT4 exports often are)")
    ap.add_argument("--max-bars", type=int, default=0)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args(argv)

    rows, skipped = load(args.input)
    if not rows:
        print(f"error: no OHLC rows recognised in {args.input}", file=sys.stderr)
        return 2
    if args.reverse:
        rows.reverse()
    rows.sort(key=lambda r: r[0])
    if args.max_bars > 0:
        rows = rows[-args.max_bars:]

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", newline="\n") as fh:
        fh.write("# VWAP Pro test fixture\n")
        fh.write(f"# source: {os.path.basename(args.input)} (converted by "
                 f"tools/mt4_export_to_fixture.py)\n")
        if args.symbol:
            fh.write(f"# symbol: {args.symbol}  bars: {len(rows)}\n")
        fh.write("# columns: unix_seconds,open,high,low,close,tick_volume,real_volume\n")
        fh.write("time,open,high,low,close,tick_volume,real_volume\n")
        for (t, o, h, l, c, tv, rv) in rows:
            fh.write(f"{t},{o:.6f},{h:.6f},{l:.6f},{c:.6f},{tv:.0f},{rv:.0f}\n")

    if not args.quiet:
        report(diagnose(rows), args.input)
        if skipped:
            print(f"  ({skipped} lines ignored: header / unrecognised layout)")
        print(f"\nwrote {len(rows)} bars to {args.out}")
        print("now run:  make test")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
