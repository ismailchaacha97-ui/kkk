"""Load the local OHLCV dataset and build a clean price panel."""
import os
import numpy as np
import pandas as pd

RAW_DIR = os.environ.get("RAW_DIR", "/tmp/hsm")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")

# Liquid, long-history universe: broad indices, sectors, factors, bonds, commodities,
# plus a few mega-cap single names. Kept deliberately small & liquid so that results
# are not driven by illiquid micro-caps.
UNIVERSE = [
    ("ETFs", "spy"), ("ETFs", "qqq"), ("ETFs", "dia"), ("ETFs", "iwm"), ("ETFs", "mdy"),
    ("ETFs", "efa"), ("ETFs", "eem"), ("ETFs", "ewj"), ("ETFs", "ewz"), ("ETFs", "fxi"),
    ("ETFs", "xlf"), ("ETFs", "xle"), ("ETFs", "xlk"), ("ETFs", "xlv"), ("ETFs", "xlp"),
    ("ETFs", "xlu"), ("ETFs", "xli"), ("ETFs", "xly"), ("ETFs", "xlb"),
    ("ETFs", "tlt"), ("ETFs", "ief"), ("ETFs", "lqd"), ("ETFs", "hyg"), ("ETFs", "shy"),
    ("ETFs", "gld"), ("ETFs", "slv"), ("ETFs", "uso"), ("ETFs", "vnq"), ("ETFs", "iyr"),
    ("Stocks", "aapl"), ("Stocks", "msft"), ("Stocks", "xom"), ("Stocks", "jnj"),
    ("Stocks", "jpm"), ("Stocks", "pg"), ("Stocks", "ge"), ("Stocks", "ko"),
    ("Stocks", "wmt"), ("Stocks", "csco"), ("Stocks", "intc"),
]

START = "2005-01-01"


def _read(folder, sym):
    path = os.path.join(RAW_DIR, folder, f"{sym}.us.txt")
    if not os.path.exists(path):
        return None
    df = pd.read_csv(path, parse_dates=["Date"]).set_index("Date")
    return df[["Open", "High", "Low", "Close", "Volume"]]


def build_panel():
    frames = {}
    for folder, sym in UNIVERSE:
        df = _read(folder, sym)
        if df is None:
            print("missing", sym)
            continue
        df = df[df.index >= START]
        if len(df) < 2000:
            print("short", sym, len(df))
            continue
        frames[sym.upper()] = df

    panels = {}
    for field in ["Open", "High", "Low", "Close", "Volume"]:
        panels[field] = pd.DataFrame({s: d[field] for s, d in frames.items()})

    close = panels["Close"]
    # keep dates where at least 90% of names trade, then forward fill small gaps
    good = close.notna().mean(axis=1) >= 0.9
    for f in panels:
        panels[f] = panels[f][good].ffill().dropna(how="any", axis=0)
    idx = panels["Close"].index
    for f in panels:
        panels[f] = panels[f].reindex(idx)
    return panels


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    p = build_panel()
    for f, df in p.items():
        df.to_parquet(os.path.join(OUT, f"{f.lower()}.parquet"))
    c = p["Close"]
    print("panel:", c.shape, c.index.min().date(), "->", c.index.max().date())
    print("symbols:", ", ".join(c.columns))
