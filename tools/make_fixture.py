#!/usr/bin/env python3
"""
make_fixture.py - build the market data fixture used by the test suite.

The fixture is **synthetic**, and it says so in its own header line.  That
is a deliberate choice, not a shortcut:

  * the test suite must be runnable offline, deterministically, by anyone
    who clones the repository - a 400 MB tick archive is not a test suite;
  * a *documented* data generating process is stronger evidence than an
    undocumented real file, because the properties the tests rely on
    (session volatility seasonality, integer autocorrelated tick counts,
    hidden order flow, fat tails, gaps) are known to the tests;
  * real data is one command away: `tools/fetch_data.py` downloads M1
    klines from a public exchange, `tools/mt4_export_to_fixture.py`
    converts an MT4 history export.  Drop any of them into
    tests/fixtures/ and the very same battery runs - test_data.cpp picks
    up every .csv it finds there.

The generator models, in order of importance for a VWAP:

  1. an intraday volatility smile (Asia quiet, London/NY overlap loud),
     so volatility-clock weighting has something to correct for;
  2. tick counts that are integers, positively autocorrelated, driven by
     volatility and by time of day - i.e. *not* proportional to size,
     which is exactly how MT4 tick volume misleads a naive VWAP;
  3. a hidden AR(1) order-flow process that pushes the close towards the
     high or the low of the bar, so the tick-rule estimator can be scored
     against a ground truth;
  4. fat-tailed innovations and weekend gaps.

Usage:
    python3 tools/make_fixture.py --days 15 --symbol EURUSD --seed 20260918 \
        --out tests/fixtures/synth_m1_eurusd.csv
"""

import argparse
import math
import os
import sys

try:
    import numpy as np
except ImportError:  # pragma: no cover
    sys.stderr.write("make_fixture.py needs numpy:  pip install numpy\n")
    raise SystemExit(2)

# Per-hour volatility multiplier (UTC), FX-flavoured: Tokyo morning dip,
# London open ramp, London/NY overlap peak, NY afternoon decay.
HOUR_VOL = np.array([
    0.62, 0.58, 0.55, 0.55, 0.58, 0.65, 0.78, 0.95, 1.18, 1.32, 1.38, 1.36,
    1.30, 1.42, 1.55, 1.60, 1.50, 1.30, 1.05, 0.92, 0.88, 0.80, 0.74, 0.68,
])


def generate(days, start_price, annual_vol, seed, start_utc="2025-01-06 00:00"):
    """Return (time, o, h, l, c, tick_volume, real_volume) arrays of M1 bars."""
    rng = np.random.default_rng(seed)

    import datetime as dt
    t0 = dt.datetime.strptime(start_utc, "%Y-%m-%d %H:%M").replace(tzinfo=dt.timezone.utc)
    t0_epoch = int(t0.timestamp())

    # Per-minute volatility: annual -> per-minute, with a 1.35 fat-tail
    # inflation factor so that |returns| are realistic for M1 FX.
    minutes_per_year = 365.0 * 24 * 60
    sigma_min = annual_vol / math.sqrt(minutes_per_year) * 1.35

    times, opens, highs, lows, closes, ticks, reals = [], [], [], [], [], [], []
    price = float(start_price)
    pressure = 0.0
    tick_level = 250.0
    day = 0
    while day < days:
        base = t0_epoch + day * 86400
        d = dt.datetime.fromtimestamp(base, tz=dt.timezone.utc)
        if d.weekday() == 5:                      # Saturday: market closed
            day += 1
            continue
        if d.weekday() == 6:                      # Sunday: opens 21:00 UTC
            start_min = 21 * 60
        else:
            start_min = 0
        for minute in range(start_min, 1440):
            hour = minute // 60
            vol = sigma_min * HOUR_VOL[hour]
            # Two scheduled news windows per day, both fat-tailed.
            volatile = (12 * 60 <= minute < 12 * 60 + 4) or (14 * 60 <= minute < 14 * 60 + 4)
            if volatile:
                vol *= 3.1
            # Hidden order flow: AR(1), occasionally excited by news.
            pressure = 0.86 * pressure + 0.14 * rng.normal() * (2.2 if volatile else 1.0) * 0.55
            pressure = float(np.clip(pressure, -1.0, 1.0))

            # Fat-tailed innovation via a Student-t(5) standardised.
            t5 = rng.standard_t(5) / math.sqrt(5.0 / 3.0)
            ret = vol * t5 * 0.35 + pressure * vol * 0.55
            o = price
            c = o * math.exp(ret)
            wick = vol * o * (0.6 + 1.4 * rng.random()) * (2.4 if volatile else 1.0)
            fbuy = 0.5 + 0.45 * pressure
            rng_span = abs(c - o) + wick
            h = max(o, c) + rng_span * (1.0 - fbuy) * rng.random()
            l = min(o, c) - rng_span * fbuy * rng.random()
            h = max(h, o, c)
            l = min(l, o, c)
            price = c

            # Tick counts: integer, autocorrelated, volatility-driven.
            base_ticks = 260.0 * HOUR_VOL[hour] * (1.0 + 2.4 * abs(ret) / (vol + 1e-12))
            tick_level = tick_level * 0.72 + base_ticks * 0.28
            n = tick_level * (0.45 + 1.15 * rng.random())
            if volatile:
                n *= 2.2
            n = int(max(1, min(30000, math.floor(n) + 1)))

            times.append(base + minute * 60)
            opens.append(o); highs.append(h); lows.append(l); closes.append(c)
            ticks.append(n); reals.append(0)
        day += 1

    return (np.asarray(times, dtype=np.int64), np.asarray(opens), np.asarray(highs),
            np.asarray(lows), np.asarray(closes), np.asarray(ticks, dtype=np.int64),
            np.asarray(reals, dtype=np.int64))


def write_csv(path, arrays, symbol, note):
    t, o, h, l, c, tv, rv = arrays
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        f.write("# VWAP Pro test fixture\n")
        f.write("# source: %s\n" % note)
        f.write("# symbol: %s  bars: %d\n" % (symbol, len(t)))
        f.write("# columns: unix_seconds,open,high,low,close,tick_volume,real_volume\n")
        f.write("time,open,high,low,close,tick_volume,real_volume\n")
        for i in range(len(t)):
            f.write("%d,%.6f,%.6f,%.6f,%.6f,%d,%d\n" %
                    (t[i], o[i], h[i], l[i], c[i], tv[i], rv[i]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=15)
    ap.add_argument("--symbol", default="EURUSD")
    ap.add_argument("--start-price", type=float, default=1.08420)
    ap.add_argument("--annual-vol", type=float, default=0.075)
    ap.add_argument("--seed", type=int, default=20260918)
    ap.add_argument("--out", default="tests/fixtures/synth_m1_eurusd.csv")
    args = ap.parse_args()

    arrays = generate(args.days, args.start_price, args.annual_vol, args.seed)
    note = ("synthetic M1, deterministic generator tools/make_fixture.py "
            "(seed %d, %d days, %s)" % (args.seed, args.days, args.symbol))
    write_csv(args.out, arrays, args.symbol, note)
    t = arrays[0]
    print("wrote %s: %d bars, %s .. %s" % (
        args.out, len(t),
        __import__("datetime").datetime.utcfromtimestamp(int(t[0])).isoformat(),
        __import__("datetime").datetime.utcfromtimestamp(int(t[-1])).isoformat()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
