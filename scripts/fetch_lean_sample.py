#!/usr/bin/env python3
"""Fetch real 1-minute US-equity bars from QuantConnect's open-source LEAN repo.

The LEAN repository ships a small set of minute bars (Apache-2.0 code; see the
repository for data terms). They are enough to sanity-check the pipeline on
real prices without any vendor account or API key.

The downloaded files are written in this project's CSV schema and are ignored
by git, so nothing large is committed.

Usage
-----
    python scripts/fetch_lean_sample.py --out data_real
    python scripts/fetch_lean_sample.py --symbols SPY IBM --out data_real --force

Then run a backtest on the real files (``--no-generate`` prevents any silent
synthetic fallback):

    python -m daytrader backtest --strategy orb --symbols SPY IBM BAC AIG \
        --data-dir data_real --no-generate --out reports/real_orb
"""

from __future__ import annotations

import argparse
import base64
import csv
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile
from datetime import UTC, date, datetime, timedelta
from datetime import time as dtime
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from daytrader import MARKET_TZ
from daytrader.data import save_bars

REPO = "QuantConnect/Lean"
BASE_PATH = "Data/equity/usa/minute"
DEFAULT_SYMBOLS = ("SPY", "IBM", "BAC", "AIG")
SESSION_OPEN = dtime(9, 30)
SESSION_CLOSE = dtime(16, 0)


def _headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "daytrader-lean-sample-fetcher",
    }
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _get_json(path: str) -> object:
    url = f"https://api.github.com/repos/{REPO}/contents/{path}"
    request = urllib.request.Request(url, headers=_headers())
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 403:
            raise RuntimeError(
                "GitHub API rate limit hit. Set GITHUB_TOKEN (or run `gh auth login`) and retry.",
            ) from exc
        raise


def list_trade_files(symbol: str) -> list[str]:
    listing = _get_json(f"{BASE_PATH}/{symbol.lower()}")
    if not isinstance(listing, list):
        raise TypeError(f"unexpected GitHub response for {symbol}: {listing}")
    return sorted(item["name"] for item in listing if item["name"].endswith("_trade.zip"))


def download_blob(symbol: str, name: str) -> bytes:
    payload = _get_json(f"{BASE_PATH}/{symbol.lower()}/{name}")
    if not isinstance(payload, dict) or "content" not in payload:
        raise RuntimeError(f"could not download {symbol}/{name}")
    return base64.b64decode(payload["content"])


def parse_lean_csv(content: bytes, session_date: date) -> pd.DataFrame:
    """Convert a LEAN minute trade CSV into an OHLCV frame for one session."""
    rows: list[tuple[int, float, float, float, float, float]] = []
    reader = csv.reader(io.StringIO(content.decode("utf-8", errors="replace")))
    for record in reader:
        if len(record) < 6:
            continue
        try:
            milliseconds = int(float(record[0]))
            open_, high, low, close, volume = (float(value) for value in record[1:6])
        except ValueError:
            continue
        rows.append((milliseconds, open_, high, low, close, volume))

    if not rows:
        raise ValueError("empty LEAN file")

    frame = pd.DataFrame(
        rows,
        columns=["milliseconds", "open", "high", "low", "close", "volume"],
    )
    # LEAN stores prices as integers scaled by 10,000.
    for column in ("open", "high", "low", "close"):
        frame[column] = frame[column] / 10_000.0

    # LEAN stores the timestamp as milliseconds since local midnight.
    midnight = datetime.combine(session_date, dtime(0, 0))
    frame.index = pd.DatetimeIndex(
        [midnight + timedelta(milliseconds=int(ms)) for ms in frame["milliseconds"]],
        name="timestamp",
    ).tz_localize(MARKET_TZ)

    frame = frame[[c for c in ("open", "high", "low", "close", "volume") if c in frame]]
    frame = frame[(frame.index.time >= SESSION_OPEN) & (frame.index.time < SESSION_CLOSE)]
    if frame.empty:
        return frame

    frame = frame.resample("1min").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last", "volume": "sum"},
    )
    # Fill rare empty minutes so bars form a continuous 09:30-15:59 grid.
    full_index = pd.date_range(
        datetime.combine(session_date, SESSION_OPEN),
        periods=390,
        freq="1min",
        tz=MARKET_TZ,
    )
    frame = frame.reindex(full_index)
    frame["close"] = frame["close"].ffill().bfill()
    for column in ("open", "high", "low"):
        frame[column] = frame[column].ffill().bfill()
    frame["volume"] = frame["volume"].fillna(0.0)
    frame["open"] = frame["open"].fillna(frame["close"])
    frame["high"] = frame[["open", "high", "close"]].max(axis=1)
    frame["low"] = frame[["open", "low", "close"]].min(axis=1)
    frame.index.name = "timestamp"
    return frame


def fetch_symbol(symbol: str, out_dir: Path, force: bool, pause: float) -> pd.DataFrame:
    files = list_trade_files(symbol)
    if not files:
        raise RuntimeError(f"no minute trade files found for {symbol}")
    frames = []
    print(f"{symbol}: {len(files)} session(s) available")
    for index, name in enumerate(files):
        session_date = date.fromisoformat(name.split("_")[0])
        target = out_dir / f".{symbol}_{session_date.isoformat()}.cached.csv"
        if target.exists() and not force:
            frame = pd.read_csv(target, parse_dates=["timestamp"]).set_index("timestamp")
            frame.index = pd.DatetimeIndex(frame.index).tz_convert(MARKET_TZ)
        else:
            blob = download_blob(symbol, name)
            with zipfile.ZipFile(io.BytesIO(blob)) as archive:
                csv_names = [n for n in archive.namelist() if n.endswith(".csv")]
                if not csv_names:
                    raise RuntimeError(f"{symbol}/{name}: no CSV inside the archive")
                frame = parse_lean_csv(archive.read(csv_names[0]), session_date)
            frame.to_csv(target)
            if pause:
                time.sleep(pause)
        if not frame.empty:
            frames.append(frame)
        if (index + 1) % 3 == 0:
            print(f"  {index + 1}/{len(files)} sessions")

    if not frames:
        raise RuntimeError(f"{symbol}: no regular-session bars produced")
    combined = pd.concat(frames).sort_index()
    combined.index.name = "timestamp"
    path = save_bars(combined, out_dir / f"{symbol}_1min.csv")
    print(f"  wrote {len(combined):,} bars -> {path}")
    for cached in out_dir.glob(f".{symbol}_*.cached.csv"):
        cached.unlink(missing_ok=True)
    return combined


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--symbols", nargs="+", default=list(DEFAULT_SYMBOLS))
    parser.add_argument("--out", default="data_real", help="output directory")
    parser.add_argument("--force", action="store_true", help="re-download cached files")
    parser.add_argument(
        "--pause",
        type=float,
        default=0.15,
        help="seconds between GitHub API calls (be polite)",
    )
    args = parser.parse_args(argv)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    fetched = {}

    for symbol in args.symbols:
        fetch_symbol(symbol.upper(), out_dir, args.force, args.pause)
        fetched[symbol.upper()] = True

    metadata = {
        "source": f"https://github.com/{REPO}/{BASE_PATH}",
        "repo": REPO,
        "path": BASE_PATH,
        "symbols": sorted(fetched),
        "license_note": (
            "LEAN source code is Apache-2.0; the bundled market data is a small "
            "sample and remains subject to QuantConnect's terms. Do not redistribute "
            "the downloaded files; they are gitignored here."
        ),
        "fetched_at_utc": datetime.now(tz=UTC).isoformat(timespec="seconds"),
    }
    (out_dir / ".source.json").write_text(json.dumps(metadata, indent=2))
    print(f"\nDone. Real bars in {out_dir.resolve()}")
    print(
        "Run: python -m daytrader backtest --strategy orb "
        f"--symbols {' '.join(args.symbols)} --data-dir {out_dir} --no-generate "
        "--out reports/real_orb",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
