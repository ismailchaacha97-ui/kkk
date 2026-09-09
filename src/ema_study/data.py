"""Data loading / universe assembly for the EMA grid study.

Reads the normalised CSVs produced by ``scripts/fetch_data.py`` and turns each one into
a small :class:`Series` object holding the close, the return vector and metadata used by
the backtester.

Two return conventions are used, because the raw data differs:

``raw``            prices are genuine level series (stocks, ETFs, indices, FX spot, crypto).
                   ``r_t = close_t / close_{t-1} - 1``.
``back_adjusted``  pysystemtrade continuous futures are *additively* roll adjusted, so the
                   level in the 1970s can be near zero or negative.  Percentage returns are
                   therefore taken as ``r_t = (close_t - close_{t-1}) / scale_t`` where
                   ``scale_t`` is the trailing median absolute price (a standard "P&L in
                   points over a representative contract price" approximation).
"""

from __future__ import annotations

import dataclasses
import glob
import os

import numpy as np
import pandas as pd

DATA = os.environ.get("KKK_DATA", "/home/user/data")
CLEAN = os.path.join(DATA, "clean")

#: one-way transaction cost as a fraction of notional, by asset class
COST_BPS = {
    "stock": 10.0,
    "etf": 6.0,
    "index": 6.0,
    "index_pkg": 6.0,
    "macro": 6.0,
    "fx": 2.0,
    "fx_futures": 3.0,
    "fx_spot_ctrl": 2.0,
    "fut_commodity": 4.0,
    "fut_equity": 4.0,
    "fut_rates": 4.0,
    "crypto": 20.0,
}
COST_BPS_DEFAULT = 8.0

FAMILY = {
    "stock": "US single stocks",
    "etf": "US ETFs",
    "index": "US equity indices",
    "index_pkg": "US equity indices",
    "fx": "FX spot",
    "fx_futures": "FX (futures marks)",
    "fx_spot_ctrl": "FX spot (contaminated control)",
    "fut_equity": "Global equity-index futures",
    "fut_commodity": "Commodity futures",
    "fut_rates": "Rate futures",
    "crypto": "Crypto spot",
    "macro": "Macro (context only)",
}


@dataclasses.dataclass
class Series:
    symbol: str
    asset_class: str
    close: pd.Series
    rets: np.ndarray            # aligned with close[1:] -> r[t] is close[t-1] -> close[t]
    ann: int                    # annualisation factor (252 / 365)
    adjustment: str
    cost_bps: float
    n: int
    start: pd.Timestamp
    end: pd.Timestamp
    open_px: pd.Series | None = None      # only populated when it differs from close

    @property
    def key(self) -> str:
        return f"{self.asset_class}/{self.symbol}"

    def slice(self, lo=None, hi=None):
        s = self.close.slice_slice(lo, hi) if False else self.close.loc[lo:hi]
        return s


def apply_level_filter(px: pd.Series, adjustment: str, keep_frac: float = 0.25) -> pd.Series:
    """Drop bars of a *back-adjusted* continuous futures series where the level has been
    pushed close to zero by the additive roll adjustment.

    Those bars are unusable: a +0.1 point daily move on an adjusted level of 0.3 is a
    meaningless "33% return".  We keep bars whose absolute level is at least ``keep_frac``
    of the series' median absolute level, and only from the first such bar onwards (so the
    series stays a single contiguous history instead of getting holes).
    """
    if adjustment != "back_adjusted":
        return px
    a = px.abs()
    ok = a >= keep_frac * float(a.median())
    if not ok.any():
        return px
    return px.iloc[int(np.argmax(ok.to_numpy())):]


def _annualisation(index: pd.DatetimeIndex) -> int:
    """Bars per year, measured from the index itself.

    Snapping to {252, 365} from the *median gap* is wrong: business-day data alternates 1-day
    (Tue-Wed) and 3-day (Fri-Mon) gaps, so its median gap is 1.0 and every equity series would be
    annualised as though it traded on weekends -- inflating every Sharpe by 20% and every CAGR
    much more.  Counting bars per calendar year and taking the median is robust to the partial
    first/last years, to mid-sample holes, and to weekly resampling (52) alike.
    """
    idx = pd.DatetimeIndex(index)
    if len(idx) < 30:
        return 365 if idx.dayofweek.nunique() == 7 else 252
    counts = idx.to_series().groupby(idx.year).size()
    if len(counts) >= 2:
        # a *complete* year is the one with the most bars, so keep the years within 10% of the
        # maximum and take their median: immune to stub first/last years and to mid-sample holes
        keep = counts[counts >= 0.9 * float(counts.max())]
        if len(keep):
            return int(max(12, min(400, round(float(keep.median())))))
    yrs = (idx[-1] - idx[0]).days / 365.25
    if yrs > 0.5:
        return int(max(12, min(400, round(len(idx) / yrs))))
    return 365 if idx.dayofweek.nunique() == 7 else 252


def _returns(close: pd.Series, adjustment: str) -> np.ndarray:
    prev = close.shift(1)
    if adjustment == "back_adjusted":
        scale = close.abs().rolling(252, min_periods=60).median().shift(1)
        scale = scale.replace(0.0, np.nan).ffill()
        floor = max(np.nanmedian(close.abs()), 1e-9) * 1e-3
        scale = scale.clip(lower=floor)
        r = (close - prev) / scale
    else:
        r = close / prev - 1.0
    r = r.replace([np.inf, -np.inf], np.nan).fillna(0.0).to_numpy(np.float64)
    return r[1:]                                   # drop first (no return on day 0)


def weekly(close: pd.Series) -> pd.Series:
    return close.resample("W-FRI").last().dropna()


def load_universe(clean_dir: str = CLEAN, min_rows: int = 700, exclude: tuple = ("macro",),
                  bar: str = "D", hygiene: bool = True, verbose: bool = True) -> dict[str, Series]:
    """Return {asset_class/symbol: Series} for every cleaned CSV on disk.

    ``hygiene`` screens out series whose daily returns are dominated by stale / fixed-clock
    sampling artefacts (|lag-1 autocorrelation| > 0.15).  This matters a lot here: the FX
    feeds we could download are sampled at a fixed clock hour, which creates ~2-day
    overlapping windows and up to +0.39 lag-1 autocorrelation -- pure manufactured
    trend-following alpha for short EMA pairs.  Those series are dropped, not smoothed.
    """
    uni_path = os.path.join(os.path.dirname(clean_dir), "universe.csv")
    meta = pd.read_csv(uni_path) if os.path.exists(uni_path) else pd.DataFrame()
    adj_of = {f"{r.asset_class}/{r.symbol}": r.adjustment for r in meta.itertuples()} if len(meta) else {}

    out: dict[str, Series] = {}
    rejected: list[tuple[str, str]] = []
    for path in sorted(glob.glob(os.path.join(clean_dir, "*.csv"))):
        name = os.path.basename(path)[:-4]
        asset_class, symbol = name.split("__", 1)
        key = f"{asset_class}/{symbol}"
        if asset_class in exclude:
            continue
        tbl = pd.read_csv(path, parse_dates=["date"], index_col="date")
        px = tbl["close"].astype("float64")
        op = tbl["open"].astype("float64") if "open" in tbl.columns else None
        px = px[px.notna()]
        pidx = pd.DatetimeIndex(px.index)
        if pidx.tz is not None:
            px.index = pidx.tz_localize(None)
        px = px[~px.index.duplicated(keep="last")].sort_index()
        px = px[px.abs() > 1e-12]                     # zero level = unusable
        adjustment = adj_of.get(key, "raw")
        px = apply_level_filter(px, adjustment)       # n/a for raw series
        if len(px) < min_rows:
            rejected.append((key, f"short ({len(px)} rows)"))
            continue
        r = px.pct_change().dropna()
        if hygiene:
            ac1 = float(r.autocorr(1)) if r.size > 100 else 0.0
            if abs(ac1) > 0.15:
                rejected.append((key, f"stale/timestamp artefact, lag1 autocorr {ac1:+.2f}"))
                continue
            flat = float((r == 0).mean())
            if flat > 0.25:
                rejected.append((key, f"{flat:.0%} zero daily returns -> carried-forward prices"))
                continue
        if bar == "W":
            px = weekly(px)
        if op is not None:
            op = op.reindex(px.index)
            if op.isna().any() or np.allclose(op.to_numpy(), px.to_numpy()):
                op = None                      # futures/FX feeds have no separate open
        out[key] = Series(
            symbol=symbol, asset_class=asset_class, close=px, open_px=op,
            rets=_returns(px, adjustment), ann=_annualisation(px.index),
            adjustment=adjustment, cost_bps=COST_BPS.get(asset_class, COST_BPS_DEFAULT),
            n=len(px) - 1, start=px.index[0], end=px.index[-1],
        )
    if verbose and rejected:
        print(f"  data-hygiene screen dropped {len(rejected)} series:")
        for k, why in rejected:
            print(f"      - {k:<28} {why}")
    return out


def hygiene_report(clean_dir: str = CLEAN) -> pd.DataFrame:
    """Diagnostics for every series on disk (used in the report appendix)."""
    rows = []
    for path in sorted(glob.glob(os.path.join(clean_dir, "*.csv"))):
        asset_class, symbol = os.path.basename(path)[:-4].split("__", 1)
        tbl = pd.read_csv(path, parse_dates=["date"], index_col="date")
        px = tbl["close"].astype("float64")
        op = tbl["open"].astype("float64") if "open" in tbl.columns else None
        px = px[px.notna()].sort_index()
        r = px.pct_change().dropna()
        rows.append(dict(asset_class=asset_class, symbol=symbol, rows=len(px),
                         start=px.index.min().date(), end=px.index.max().date(),
                         lag1_autocorr=round(float(r.autocorr(1)), 3) if r.size > 100 else np.nan,
                         zero_return_share=round(float((r == 0).mean()), 3),
                         ann_vol=round(float(r.std() * np.sqrt(252)), 3),
                         min_price=round(float(px.min()), 4)))
    return pd.DataFrame(rows).sort_values(["asset_class", "symbol"], ignore_index=True)



def families(uni: dict[str, Series]) -> dict[str, list[str]]:
    d: dict[str, list[str]] = {}
    for k, s in uni.items():
        d.setdefault(FAMILY.get(s.asset_class, s.asset_class), []).append(k)
    return {k: sorted(v) for k, v in sorted(d.items())}
