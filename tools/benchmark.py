#!/usr/bin/env python3
"""
benchmark.py - how fast is the engine, and does it stay O(1) per bar?

An indicator that is correct but slow is not usable: MT4 recomputes on every
tick, and a VWAP that re-scans the session is a VWAP that freezes the terminal.

This script measures the *compiled engine* (not a reimplementation): it runs
tests/dump_bars over a synthetic stream of 1M bars, at several history lengths,
and reports the per-bar cost.  A truly O(1) per-bar engine shows a flat ns/bar
column; anything that grows with the anchor's length shows up immediately.

    python3 tools/benchmark.py            # default: up to 1M bars
    python3 tools/benchmark.py --max 2000000
"""

import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def build(root):
    candidates = [os.path.join(root, "build", "dump_bars"),
                  os.path.join(root, "tests", "dump_bars")]
    for c in candidates:
        if os.path.exists(c):
            return c
    print("building dump_bars ...")
    subprocess.check_call(["make", "dump"], cwd=root)
    for c in candidates:
        if os.path.exists(c):
            return c
    sys.exit("could not build tests/dump_bars")


def make_stream(path, bars, seed=7):
    """A plain M1 random walk in the fixture format - generated in Python so the
    benchmark does not depend on the numpy-only fixture generator."""
    import random
    rnd = random.Random(seed)
    price = 1.1000
    t = 1700000000
    with open(path, "w") as fh:
        fh.write("time,open,high,low,close,tick_volume,real_volume\n")
        for i in range(bars):
            o = price
            c = price * (1.0 + 4e-5 * rnd.gauss(0, 1))
            h = max(o, c) * (1.0 + 2e-5 * abs(rnd.gauss(0, 1)))
            l = min(o, c) * (1.0 - 2e-5 * abs(rnd.gauss(0, 1)))
            tv = rnd.randint(50, 900)
            fh.write("%d,%.6f,%.6f,%.6f,%.6f,%d,0\n" % (t, o, h, l, c, tv))
            price = c
            t += 60


def time_run(exe, csv_path, repeats=3, quiet=False):
    """Best-of-N wall time.  quiet=True suppresses the CSV dump so the number
    is the engine's cost, not printf's."""
    args = [exe, csv_path]
    if quiet:
        args += ["1", "7", "0", "0", "1", "0", "0", "1"]   # ..., zeroVol=0, quiet=1
    best = None
    for _ in range(repeats):
        with open(os.devnull, "wb") as devnull:
            t0 = time.perf_counter()
            subprocess.check_call(args, stdout=devnull, stderr=devnull)
            dt = time.perf_counter() - t0
        best = dt if best is None else min(best, dt)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=1000000, help="largest stream (bars)")
    ap.add_argument("--root", default=ROOT)
    args = ap.parse_args()

    exe = build(args.root)
    print(f"engine: {exe}\n")
    tmp = os.path.join(ROOT, "build", "bench_stream.csv")
    os.makedirs(os.path.dirname(tmp), exist_ok=True)

    sizes = [n for n in (10000, 100000, 1000000, args.max) if n <= args.max]
    sizes = sorted(set(sizes))

    # process startup cost: time the binary on a 1-bar file (it refuses an
    # empty one), then subtract that from every measurement.
    one = os.path.join(ROOT, "build", "one.csv")
    make_stream(one, 1)
    startup = time_run(exe, one, repeats=5)

    startup_q = time_run(exe, one, repeats=5, quiet=True)
    os.remove(one)

    print("  bars        wall (s)    ns/bar   bars/s     (engine only)")
    print("  ---------- ---------- --------- --------  -------------")
    for n in sizes:
        make_stream(tmp, n)
        dt = time_run(exe, tmp, quiet=True)
        net = max(dt - startup_q, 1e-4)
        ns = net / n * 1e9
        print(f"  {n:>10,} {dt:>10.3f} {ns:>9.0f} {n / net:>8.0f}")
    print("\n  Flat ns/bar across a 100x size range == O(1) per bar (the design goal).")
    print("  A per-bar cost that grows with history is the classic VWAP bug:")
    print("  it looks fine on a demo chart and freezes the terminal on M1.")

    #--- the pathological comparison: does re-scanning the session cost more?
    print("\n  For scale: the engine also runs with a rolling sigma window")
    print("  (--zwin 512), which IS O(window) by definition:")
    with open(os.devnull, "wb") as devnull:
        t0 = time.perf_counter()
        subprocess.check_call([exe, tmp, "1", "7", "1", "512", "1", "0", "0", "1"],
                              stdout=devnull)
        dt = time.perf_counter() - t0
    net = max(dt - startup_q, 1e-4)
    print(f"    {sizes[-1]:,} bars with a 512-bar window: {dt:.3f}s "
          f"({net / sizes[-1] * 1e9:.0f} ns/bar)")
    print("\n  (These are engine-only timings: dump_bars' CSV printing is")
    print("   suppressed, and the process startup cost is subtracted.  The")
    print("   per-bar figure includes the ATR/ADX/regression/moment updates)")
    print("   that a real tick would trigger.)")
    os.remove(tmp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
