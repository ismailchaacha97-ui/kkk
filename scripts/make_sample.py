#!/usr/bin/env python3
"""Write a realistic MT5-format CSV so you can exercise the whole pipeline
before your broker's export is ready.

    python scripts/make_sample.py

The data is a seeded random walk in *broker server time* (UTC+2), tab
separated, with a <SPREAD> column — i.e. exactly the awkward shape a real MT5
export has, so it tests the loader properly.

It has **no real edge**. Any strategy that looks profitable on it is fitting
noise, which is the point: use it to check the plumbing, not to pick a method.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pandas as pd  # noqa: E402

from kkk import data as kdata  # noqa: E402

OUT = Path(__file__).resolve().parents[1] / "data" / "XAUUSD_H1_sample.csv"

SYMBOL_PARAMS = {
    "XAUUSD": dict(start_price=1800.0, volatility=0.0018),
    "EURUSD": dict(start_price=1.0850, volatility=0.0008),
    "US30": dict(start_price=34000.0, volatility=0.0012),
}


def main(symbol: str = "XAUUSD", bars: int = 12_000, seed: int = 11) -> Path:
    symbol = symbol.upper()
    params = SYMBOL_PARAMS.get(symbol, SYMBOL_PARAMS["XAUUSD"])
    digits = 5 if params["start_price"] < 10 else 2

    df = kdata.make_synthetic(
        n=bars, freq="1h", start="2022-01-03", seed=seed, **params
    )
    # Broker server time, like a real MT5 export (typically UTC+2 / UTC+3).
    df.index = (df.index + pd.Timedelta(hours=2)).tz_localize(None)

    fmt = f"{{:.{digits}f}}"
    rows = ["<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\t<TICKVOL>\t<VOL>\t<SPREAD>"]
    for t, r in df.iterrows():
        rows.append(
            "\t".join(
                (
                    t.strftime("%Y.%m.%d"),
                    t.strftime("%H:%M:%S"),
                    fmt.format(r["open"]),
                    fmt.format(r["high"]),
                    fmt.format(r["low"]),
                    fmt.format(r["close"]),
                    str(int(r["volume"])),
                    "0",
                    "25",
                )
            )
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(rows) + "\n")
    print(f"wrote {len(df):,} bars -> {OUT.relative_to(OUT.parents[1])}")
    print(f"try: python -m kkk.cli compare {OUT.relative_to(OUT.parents[1])} --symbol {symbol}")
    return OUT


if __name__ == "__main__":
    main(*sys.argv[1:])
