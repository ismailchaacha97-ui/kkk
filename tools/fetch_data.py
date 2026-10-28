#!/usr/bin/env python3
"""
Download the H1 OHLCV history used by the research notebooks and the backtests.

Source: the publicly mirrored OHLCV export of the simonnmarket/OMEGA_OS_Kernel
repository (Dukascopy-derived, UTC timestamps, columns time,open,high,low,close,volume).
Files are written to data/<SYMBOL>_<TF>.csv and are .gitignore'd.

    python tools/fetch_data.py                       # default symbols, H1
    python tools/fetch_data.py --symbols EURUSD,XAUUSD --timeframes H1,H4

NOTE ON DATA QUALITY
--------------------
EURUSD_H1.csv in that mirror has a documented hole between 2020 and 2023
(~260 bars/year instead of ~6200).  The research code does not interpolate:
backtests either use the whole series (fewer EURUSD trades in the gap years) or
explicitly exclude the affected window.  Verified coverage per symbol/year is
printed by tools/data_report.py.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

REPO = "simonnmarket/OMEGA_OS_Kernel"
BASE = "OHLCV_DATA"
DEFAULT_SYMBOLS = ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "XAUUSD"]
DEFAULT_TFS = ["H1", "H4", "D1"]
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")


def download(symbol: str, tf: str) -> str:
    dest = os.path.join(DATA_DIR, f"{symbol}_{tf}.csv")
    if os.path.exists(dest) and os.path.getsize(dest) > 1000:
        return f"{dest} (already present)"
    url = f"repos/{REPO}/contents/{BASE}/{symbol}/{symbol}_{tf}.csv"
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(dest, "wb") as fh:
        proc = subprocess.run(
            ["gh", "api", url, "-H", "Accept: application/vnd.github.raw"],
            stdout=fh, stderr=subprocess.PIPE,
        )
    if proc.returncode != 0 or os.path.getsize(dest) < 1000:
        os.remove(dest)
        raise RuntimeError(f"download failed for {symbol} {tf}: {proc.stderr.decode()[:200]}")
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbols", default=",".join(DEFAULT_SYMBOLS))
    ap.add_argument("--timeframes", default="H1")
    a = ap.parse_args()
    syms = [s.strip().upper() for s in a.symbols.split(",") if s.strip()]
    tfs = [t.strip().upper() for t in a.timeframes.split(",") if t.strip()]
    for s in syms:
        for t in tfs:
            try:
                print("ok  ", download(s, t))
            except Exception as exc:          # noqa: BLE001
                print("FAIL", s, t, exc)
                return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
