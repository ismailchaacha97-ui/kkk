#!/usr/bin/env python3
"""
prepare_data.py - build the research dataset.

Two independent sources, so a result has to survive more than one broker/era:

  A. FTMO-Server4 export (2025-01 .. 2026-05) - the actual execution
     environment, M15 broker bars WITH the broker's per-bar spread.
  B. HistData-style 1-minute EURUSD (2008 .. 2018) - four extra years of a
     different era and a different feed, resampled to M15. This file has no
     spread, so a fixed assumption is applied and the sensitivity is tested.

Everything lands in research/data/ as the same CSV shape the backtester reads:
    datetime,open,high,low,close,volume,spread

Raw downloads are deleted after resampling: the repository keeps only the
resampled files, and this script reproduces them on demand.
"""
import csv
import os
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "research", "data")

FTMO_REPO = "Gianniskas/mt5-m1-bars-us500-eurusd-xauusd"
FTMO_SYMBOLS = ["EURUSD", "XAUUSD", "US500.cash"]
KEEP_TF = ["m15", "h1", "h4"]

HIST_REPO = "vdtdg/EURUSD-market-data"
HIST_YEARS = [2008, 2010, 2012, 2014, 2016, 2018]
HIST_SPREAD_PTS = 7.0          # 0.7 pip assumption for the HistData era
# The 1-minute source is stamped in US Eastern time. Its documented convention
# is fixed EST (UTC-5, no DST); a DST-aware reading is also produced so the
# sensitivity of any conclusion to this ambiguity can be measured instead of
# assumed.
HIST_TZ_MODES = {"est": "fixed UTC-5", "edt": "UTC-5 winter / UTC-4 summer"}


def gh_raw(repo, path, dest):
    """Download one file through the GitHub API (raw media type)."""
    url = f"https://api.github.com/repos/{repo}/contents/{path}"
    out = subprocess.run(["curl", "-s", "-H", "Accept: application/vnd.github.raw",
                          "-o", dest, url], check=False)
    if out.returncode != 0 or not os.path.exists(dest) or os.path.getsize(dest) < 1000:
        raise SystemExit(f"download failed: {path}")
    return dest


def fetch_ftmo():
    os.makedirs(DATA, exist_ok=True)
    url = f"https://codeload.github.com/{FTMO_REPO}/tar.gz/refs/heads/main"
    with tempfile.TemporaryDirectory() as td:
        tgz = os.path.join(td, "repo.tgz")
        subprocess.run(["curl", "-sL", "-o", tgz, url], check=True)
        with tarfile.open(tgz) as tf:
            tf.extractall(td)
        base = None
        for entry in os.listdir(td):
            cand = os.path.join(td, entry)
            if os.path.isdir(cand) and entry != "__MACOSX":
                base = cand
        for f in os.listdir(base):
            sym, _, tf_part = f.partition("_")
            tfc = tf_part.replace(".csv", "")
            if sym in FTMO_SYMBOLS and tfc in KEEP_TF:
                with open(os.path.join(base, f), "rb") as src, \
                        open(os.path.join(DATA, f), "wb") as dst:
                    dst.write(src.read())
                print(f"  kept {f}")
        for meta in ("symbol_specs.csv", "spreads_summary.csv", "README.md"):
            p = os.path.join(base, meta)
            if os.path.exists(p):
                with open(p, "rb") as src, open(os.path.join(DATA, meta), "wb") as dst:
                    dst.write(src.read())


def _tz_shift(dt, mode):
    if mode == "est":
        return timedelta(hours=5)
    # US DST: second Sunday of March .. first Sunday of November
    year = dt.year
    march = datetime(year, 3, 8)
    while march.weekday() != 6:
        march += timedelta(days=1)
    nov = datetime(year, 11, 1)
    while nov.weekday() != 6:
        nov += timedelta(days=1)
    dst = march <= dt < nov
    return timedelta(hours=5 if dst else 4)


def resample_hist(mode="est", outdir=None, tfs=(("m15", 15),)):
    """1-minute -> 15-minute OHLC, converted to UTC."""
    outdir = outdir or DATA
    os.makedirs(outdir, exist_ok=True)
    gt = "UTC-5 winter, UTC-4 summer" if mode == "edt" else "fixed UTC-5"
    print(f"  time conversion: source Eastern ({gt}) -> UTC")
    for year in HIST_YEARS:
        raw = os.path.join(tempfile.gettempdir(), f"EURUSD_{year}.csv")
        print(f"  downloading EURUSD {year} ...")
        gh_raw(HIST_REPO, f"EURUSD_{year}.csv", raw)

        buckets_by_tf = {name: {} for name, _ in tfs}
        with open(raw, newline="") as fh:
            for line in fh:
                parts = line.strip().split(";")
                if len(parts) < 5:
                    continue
                stamp, o, h, l, c = parts[0], float(parts[1]), float(parts[2]), \
                    float(parts[3]), float(parts[4])
                dt = datetime.strptime(stamp, "%Y%m%d %H%M%S")
                for name, mins in tfs:
                    if mins < 60:
                        key = dt.replace(minute=(dt.minute // mins) * mins, second=0)
                    else:
                        step = mins // 60
                        key = (dt.replace(minute=0, second=0)
                               - timedelta(hours=dt.hour % step))
                    b = buckets_by_tf[name].get(key)
                    if b is None:
                        buckets_by_tf[name][key] = [o, h, l, c, 1]
                    else:
                        b[1] = max(b[1], h)
                        b[2] = min(b[2], l)
                        b[3] = c
                        b[4] += 1
        os.unlink(raw)

        for name, mins in tfs:
            buckets = buckets_by_tf[name]
            out = os.path.join(outdir, f"EURUSD_{year}_{name}.csv")
            rows = 0
            with open(out, "w", newline="") as fh:
                w = csv.writer(fh)
                w.writerow(["datetime", "open", "high", "low", "close", "volume", "spread"])
                for key in sorted(buckets):
                    o, h, l, c, n = buckets[key]
                    utc = key + _tz_shift(key, mode)
                    w.writerow([utc.strftime("%Y-%m-%d %H:%M:%S"),
                                f"{o:.5f}", f"{h:.5f}", f"{l:.5f}", f"{c:.5f}", n,
                                f"{HIST_SPREAD_PTS:.0f}"])
                    rows += 1
            print(f"  wrote {os.path.basename(out)} ({rows} bars)")


def main():
    os.makedirs(DATA, exist_ok=True)
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("all", "ftmo"):
        print("FTMO-Server4 data:")
        fetch_ftmo()
    if which in ("all", "hist"):
        print("HistData EURUSD (independent era):")
        resample_hist("est", tfs=(("m15", 15), ("h1", 60), ("h4", 240)))
    if which == "hist_dst":
        print("HistData EURUSD, DST-aware reading (sensitivity check only):")
        resample_hist("edt", os.path.join(ROOT, "research", "data_dst"))
    print(f"\ndataset in {DATA}")


if __name__ == "__main__":
    main()
