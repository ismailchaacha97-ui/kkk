"""
Fetch long-history daily price data for the EMA study.

The sandbox has almost no egress: only pypi.org and api.github.com/codeload.github.com
are reachable, so every dataset here is pulled out of public GitHub repositories through
the GitHub contents/blob API (which returns raw file bytes).

Sources (all public, all real historical data):
  * jiewwantan/StarTrader      -> ^GSPC ^IXIC ^DJI ^RUT ^TNX ^VIX, SPY QQQ GLD SHV SHY, 27 US stocks
                                  (Yahoo-style daily OHLCV, ~1980s/1990s -> 2016)
  * quantstart/qstrader        -> SPY (2000-2016) cross-check
  * pst-group/pysystemtrade    -> FX spot (1999-2024) and back-adjusted continuous futures
                                  (commodities / global equity index / rates) 1980s/1990s -> 2024
  * arch (PyPI package)        -> SP500 & NASDAQ daily OHLCV 1999-2018, bundled .csv.gz
  * crypto repo candidates     -> BTC / ETH daily (2015 -> 2025)

Output: data/clean/<asset_class>__<symbol>.csv with columns date,open,high,low,close,volume
        data/universe.csv describing every series (span, rows, source, adjustment style).
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import numpy as np
import pandas as pd

TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
API = "https://api.github.com"
RAW_DIR = os.environ.get("KKK_DATA", "/home/user/data")
RAW = os.path.join(RAW_DIR, "raw")
CLEAN = os.path.join(RAW_DIR, "clean")

UA = {"User-Agent": "ema-study/1.0", "Accept": "application/vnd.github+json"}
if TOKEN:
    UA["Authorization"] = f"Bearer {TOKEN}"


# ----------------------------------------------------------------------------- gh io
def _req(url: str, accept: str | None = None) -> bytes:
    h = dict(UA)
    if accept:
        h["Accept"] = accept
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=90) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code in (403, 429):  # rate limited -> back off to reset window
                wait = int(e.headers.get("Retry-After", 0) or 0) or 15 * (attempt + 1)
                print(f"    rate limited, sleeping {wait}s", flush=True)
                time.sleep(wait)
            else:
                raise
        except Exception as e:  # noqa: BLE001
            print(f"    retry {attempt} ({e})", flush=True)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"failed: {url}")


def gh_file(repo: str, path: str, dest: str) -> str | None:
    """Download one file from a GitHub repo into the raw cache. Returns local path."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 200:
        return dest
    try:
        meta = json.loads(_req(f"{API}/repos/{repo}/contents/{urllib.parse.quote(path)}").decode())
        if meta.get("size", 0) > 900_000:
            blob = _req(f"{API}/repos/{repo}/git/blobs/{meta['sha']}", accept="application/vnd.github.raw")
        else:
            blob = base64.b64decode(meta["content"])
    except Exception as e:  # noqa: BLE001
        print(f"  !! {repo}:{path} -> {type(e).__name__}: {str(e)[:90]}", flush=True)
        return None
    with open(dest, "wb") as fh:
        fh.write(blob)
    return dest


# ------------------------------------------------------------------------- readers
def read_csv_safe(buf, **kw) -> pd.DataFrame:
    kw = {k: v for k, v in kw.items() if v is not None}
    for opt in ({}, {"engine": "python"}):
        try:
            return pd.read_csv(buf, **kw)
        except Exception:  # noqa: BLE001
            continue
    raise RuntimeError("unreadable csv")


def canon(df: pd.DataFrame, datecol=None, ohlc=None, prefer_adj: bool = True) -> pd.DataFrame:
    """Normalise any daily price table -> tz-naive date index + open/high/low/close/volume."""
    cols = {c.lower().strip().lstrip("^"): c for c in df.columns}
    dcol = datecol or next((cols[k] for k in ("date", "datetime", "timestamp", "time") if k in cols), df.columns[0])
    idx = pd.DatetimeIndex(pd.to_datetime(df[dcol], format="mixed"))
    if idx.tz is not None:
        idx = idx.tz_localize(None)
    out = pd.DataFrame(index=idx.normalize())
    lookup = dict(ohlc or {})
    if "price" in cols and "close" not in cols:          # pysystemtrade style single price col
        lookup.setdefault("close", cols["price"])
    used_adj = False
    if "adj close" in cols and (not lookup.get("close") or prefer_adj):
        lookup["close"] = cols["adj close"]          # total-return series: splits + dividends
        used_adj = True
    for name in ("open", "high", "low", "close", "volume"):
        src = lookup.get(name) or cols.get(name)
        if src is not None and src in df.columns:
            out[name] = pd.to_numeric(df[src].values, errors="coerce")
    if "close" not in out or out["close"].isna().all():
        raise RuntimeError("no close column")
    for c in ("open", "high", "low", "volume"):
        if c not in out:
            out[c] = out["close"]
        out[c] = out[c].astype("float64")
    if used_adj and "close" in cols and cols["close"] != cols.get("adj close"):
        # put open/high/low on the same (dividend+split adjusted) basis as the close we use
        rawc = pd.to_numeric(df[cols["close"]].values, errors="coerce")
        adjc = pd.to_numeric(df[cols["adj close"]].values, errors="coerce")
        ratio = pd.Series(adjc / rawc, index=out.index).replace([np.inf, -np.inf], np.nan)
        ratio = ratio.where(ratio > 0).ffill().bfill().fillna(1.0)
        for c in ("open", "high", "low"):
            out[c] = out[c] * ratio.to_numpy()
    out = out[~out.index.duplicated(keep="last")].sort_index()
    out = out.dropna(subset=["close"])
    out = out[(out["volume"].fillna(0) >= 0)]
    out.index.name = "date"
    return out[["open", "high", "low", "close", "volume"]]


# ------------------------------------------------------------------------ manifest
STARTRADER = "jiewwantan/StarTrader"
PSYT = "pst-group/pysystemtrade"
ARCH = "arch"

INDICES = ["^GSPC", "^IXIC", "^DJI", "^RUT"]
INDICES_OFFICIAL = ["SPX", "NDX"]
ARCH_NAME = {"SPX": "sp500", "NDX": "nasdaq"}
ETF = ["SPY", "QQQ", "GLD", "SHV", "SHY"]
STOCKS = [
    "AAPL", "MSFT", "GE", "JNJ", "XOM", "JPM", "DIS", "CSCO", "IBM", "PFE",
    "KO", "WMT", "CAT", "BA", "INTC", "NKE", "MRK", "PG", "HD", "UNH",
    "VZ", "MMM", "CVX", "GS", "AXP", "MCD",
]
MACRO = ["^TNX", "^VIX"]
# FX *spot* feeds available offline are sampled at a fixed clock hour -> their daily
# returns carry +0.2..+0.4 lag-1 autocorrelation (see ema_study.data docstring), which
# manufactures fake trend alpha for fast pairs.  We therefore use CME FX futures marks
# (traded ~23h/day, proper daily settlement marks) for the FX panel, and keep the spot
# files on disk as a documented negative control.
FX = ["EURUSD", "GBPUSD", "JPYUSD", "AUDUSD", "CADUSD", "CHFUSD", "SEKUSD", "SGDUSD", "HKDUSD", "CNHUSD"]
FX_FUT = ["AUD", "CAD", "CHF", "EUR", "GBP", "JPY", "NZD", "SEK", "MXN", "ZAR",
          "INR", "KRW", "NOK", "PLN", "RUB", "CZK", "CLP", "CNH", "TRY", "SGD"]
# back-adjusted continuous futures (level includes additive roll adjustment)
FUT_EQ = ["DAX", "FTSE100", "CAC", "NIKKEI", "HANG", "KOSPI", "SPI200", "EUROSTX200-LARGE", "IBEX", "TOPIX", "BOVESPA"]
FUT_COMM = ["GOLD", "SILVER", "COPPER", "CORN", "WHEAT", "SOYBEAN", "CRUDE_W", "BRENT_W", "GAS_US", "COTTON"]
FUT_RATE = ["US20", "US10", "BUND", "GILT", "JGB", "OAT", "BOBL"]
CRYPTO = [
    # (repo, path, symbol) -- kept as separate series so we never splice two feeds together
    ("notadamking/RLTrader", "data/input/coinbase-1d-btc-usd.csv", "BTC_14_19"),
    ("whchien/ai-trader", "data/crypto/BTC-USD_2020-01-01_to_2026-03-28.csv", "BTC_20_26"),
    ("upstarter/crypto_data", "data/gemini_BTCUSD_1d.csv", "BTC_gemini"),
    ("whchien/ai-trader", "data/crypto/ETH-USD.csv", "ETH_24_25"),
]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    os.makedirs(CLEAN, exist_ok=True)
    os.makedirs(RAW, exist_ok=True)
    manifest = []

    def add(kind, symbol, repo, path, reader="yahoo", note=""):
        manifest.append(dict(kind=kind, symbol=symbol, repo=repo, path=path, reader=reader, note=note))

    for s in INDICES + ETF + STOCKS + MACRO:
        kind = "index" if s in INDICES else "etf" if s in ETF else "macro" if s in MACRO else "stock"
        add(kind, s, STARTRADER, f"data/{s}.csv", "yahoo")

    for s in FX:
        add("fx_spot_ctrl", s, PSYT, f"data/futures/fx_prices_csv/{s}.csv", "psyt")
    for s in FX_FUT:
        add("fx_futures", s, PSYT, f"data/futures/adjusted_prices_csv/{s}.csv", "psyt_adj")
    for s in FUT_EQ:
        add("fut_equity", s, PSYT, f"data/futures/adjusted_prices_csv/{s}.csv", "psyt_adj")
    for s in FUT_COMM:
        add("fut_commodity", s, PSYT, f"data/futures/adjusted_prices_csv/{s}.csv", "psyt_adj")
    for s in FUT_RATE:
        add("fut_rates", s, PSYT, f"data/futures/adjusted_prices_csv/{s}.csv", "psyt_adj")

    # indices bundled in the `arch` pypi package (csv.gz inside site-packages)
    for repo, path, sym in CRYPTO:
        add("crypto", sym, repo, path, "yahoo")

    for s in INDICES_OFFICIAL:
        n = ARCH_NAME[s]
        add("index_pkg", s, ARCH, f"arch/data/{n}/{n}.csv.gz", "arch_gz")

    rows, skipped = [], []
    for m in manifest:
        if args.dry_run:
            print(m["kind"], m["symbol"], m["repo"], m["path"])
            continue
        try:
            if m["reader"] == "arch_gz":
                n = ARCH_NAME[m["symbol"]]
                p = os.path.join(os.path.dirname(__import__("arch").__file__), "data", n, n + ".csv.gz")
                if not os.path.exists(p):
                    raise FileNotFoundError(p)
                raw = open(p, "rb").read()
            else:
                dest = os.path.join(RAW, f"{m['symbol'].replace('^','')}__{m['repo'].split('/')[-1]}.csv")
                p = gh_file(m["repo"], m["path"], dest)
                if not p:
                    raise RuntimeError("download failed")
                raw = open(p, "rb").read()
            df = read_csv_safe(io.BytesIO(raw), compression="gzip") if m["reader"] == "arch_gz" else read_csv_safe(io.BytesIO(raw))
            if len(df.columns) < 2:
                df = read_csv_safe(io.BytesIO(raw), sep=r"[;,\t]", comment="#")
            px = canon(df, prefer_adj=m["reader"] == "yahoo")
            if len(px) < 700:  # need ~3+ years minimum to be worth a 400-bar EMA study
                raise RuntimeError(f"too short: {len(px)} rows")
            out = os.path.join(CLEAN, f"{m['kind']}__{m['symbol']}.csv")
            px.to_csv(out)
            rows.append(dict(symbol=m["symbol"], asset_class=m["kind"], source=m["repo"],
                             rows=len(px), start=px.index[0].date(), end=px.index[-1].date(),
                             years=round(len(px) / 252, 1), adjustment="raw" if m["reader"] != "psyt_adj" else "back_adjusted",
                             min_price=round(float(px["close"].min()), 4)))
            print(f"  ok {m['kind']:<14} {m['symbol']:<18} {len(px):>6}d  {px.index[0].date()} -> {px.index[-1].date()}", flush=True)
        except Exception as e:  # noqa: BLE001
            skipped.append(f"{m['kind']}/{m['symbol']}: {str(e)[:70]}")
            print(f"  -- skip {m['kind']}/{m['symbol']}: {str(e)[:70]}", flush=True)

    pd.DataFrame(rows).to_csv(os.path.join(CLEAN, "..", "universe.csv"), index=False)
    print(f"\n{len(rows)} series written to {CLEAN}; {len(skipped)} skipped")
    for s in skipped:
        print("   ", s)


if __name__ == "__main__":
    sys.exit(main())
