#!/usr/bin/env python3
"""
fetch_data.py - download real M1 data and convert it to the fixture format.

This is the "run the exact same test battery on real ticks" path.  It
needs a network connection (the sandbox that developed VWAP Pro had none,
which is why the repository ships a deterministic synthetic fixture as
well).

Sources:
  binance   - public REST, no key, M1 klines, up to 1000 bars per request.
              Works for BTCUSDT, ETHUSDT, and any listed pair.
  csv       - convert any CSV that already has timestamp,open,high,low,close
              (column order configurable), including MetaTrader exports
              through tools/mt4_export_to_fixture.py.

Usage:
    python3 tools/fetch_data.py binance --symbol BTCUSDT --days 20 \
        --out tests/fixtures/btcusdt_m1.csv
"""

import argparse
import datetime as dt
import os
import sys
import time
import urllib.parse
import urllib.request


def fetch_binance(symbol, days, interval="1m", base="https://api.binance.com"):
    end = int(time.time() * 1000)
    start = end - days * 86400 * 1000
    out = []
    url = base + "/api/v3/klines"
    cur = start
    while cur < end:
        q = urllib.parse.urlencode({
            "symbol": symbol, "interval": interval,
            "startTime": cur, "endTime": min(cur + 1000 * 60000, end),
            "limit": 1000,
        })
        with urllib.request.urlopen(url + "?" + q, timeout=30) as r:
            import json
            rows = json.loads(r.read().decode())
        if not rows:
            break
        for k in rows:
            # [openTime, o, h, l, c, volume, closeTime, quoteVolume, trades, ...]
            out.append((int(k[0] / 1000), float(k[1]), float(k[2]), float(k[3]),
                        float(k[4]), int(float(k[5])), int(k[8])))
        cur = rows[-1][6] + 1
        sys.stderr.write("\r%d bars" % len(out))
        sys.stderr.flush()
        time.sleep(0.25)          # be polite to the public endpoint
    sys.stderr.write("\n")
    return out


def write(rows, path, symbol, note):
    rows.sort(key=lambda r: r[0])
    # dedupe consecutive identical timestamps
    clean = []
    for r in rows:
        if clean and clean[-1][0] == r[0]:
            clean[-1] = r
        else:
            clean.append(r)
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write("# VWAP Pro test fixture\n")
        f.write("# source: %s\n" % note)
        f.write("# symbol: %s  bars: %d\n" % (symbol, len(clean)))
        f.write("# columns: unix_seconds,open,high,low,close,tick_volume,real_volume\n")
        f.write("time,open,high,low,close,tick_volume,real_volume\n")
        for r in clean:
            f.write("%d,%.8f,%.8f,%.8f,%.8f,%d,%d\n" % r)
    print("wrote %s: %d bars (%s .. %s)" % (
        path, len(clean),
        dt.datetime.utcfromtimestamp(clean[0][0]).isoformat(),
        dt.datetime.utcfromtimestamp(clean[-1][0]).isoformat()))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("binance")
    b.add_argument("--symbol", default="BTCUSDT")
    b.add_argument("--days", type=int, default=20)
    b.add_argument("--interval", default="1m")
    b.add_argument("--base", default="https://api.binance.com")
    b.add_argument("--out", required=True)

    c = sub.add_parser("csv")
    c.add_argument("--in", dest="src", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--symbol", default="CUSTOM")
    c.add_argument("--time-format", default="unix",
                   choices=["unix", "unix-ms", "iso", "mt4"])

    args = ap.parse_args()

    if args.cmd == "binance":
        rows = fetch_binance(args.symbol, args.days, args.interval, args.base)
        write(rows, args.out, args.symbol, "binance klines %s %s" % (args.symbol, args.interval))
        return 0

    # generic CSV conversion
    import csv as _csv
    rows = []
    with open(args.src, newline="") as f:
        sample = f.read(4096)
        f.seek(0)
        delim = ";" if sample.count(";") > sample.count(",") else ","
        rd = _csv.reader(f, delimiter=delim)
        for row in rd:
            if not row or row[0].startswith("#"):
                continue
            try:
                if args.time_format == "mt4":
                    # 2025.01.06,00:00
                    t = dt.datetime.strptime(row[0] + "," + row[1], "%Y.%m.%d,%H:%M")
                    t = t.replace(tzinfo=dt.timezone.utc)
                    vals = row[2:]
                else:
                    if args.time_format == "iso":
                        t = dt.datetime.fromisoformat(row[0]).replace(tzinfo=dt.timezone.utc)
                    else:
                        raw = float(row[0])
                        if args.time_format == "unix-ms" or raw > 1e11:
                            raw /= 1000.0
                        t = dt.datetime.fromtimestamp(raw, tz=dt.timezone.utc)
                    vals = row[1:]
                o, h, l, c = (float(vals[0]), float(vals[1]), float(vals[2]), float(vals[3]))
                v = int(float(vals[4])) if len(vals) > 4 else 0
                rv = int(float(vals[5])) if len(vals) > 5 else 0
                rows.append((int(t.timestamp()), o, h, l, c, v, rv))
            except (ValueError, IndexError):
                continue
    write(rows, args.out, args.symbol, "converted from %s" % args.src)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
