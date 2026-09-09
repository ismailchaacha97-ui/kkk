"""Full-grid evaluation of (fast, slow) EMA pairs, vectorised and grouped by slow period.

Why it is fast: for a fixed ``slow`` we compare one EMA curve against every ``fast`` EMA
curve at once as a single boolean matrix, then slice off the warm-up bars in one go.  A
pair ends up costing ~30-60 us, so ~10k pairs x ~76 markets is a couple of minutes rather
than a couple of hours.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from .data import Series, _returns
from .engine import ema_matrix, sma_matrix, position_from_state

COLS = ["fast", "slow", "n_bars", "sharpe", "sortino", "cagr", "ann_vol", "max_dd",
        "calmar", "total_return", "exposure", "round_trips", "trades_per_year"]


def pair_grid(fast_max: int = 120, slow_max: int = 400, fast_step: int = 1, slow_step: int = 1,
              min_ratio: float = 1.5, fast_min: int = 2, slow_min: int = 6):
    """All (fast, slow) pairs on the ladder honouring ``slow >= min_ratio * fast``.

    Returns 1-D arrays of matching fast/slow periods sorted by slow.
    """
    fasts = np.arange(fast_min, fast_max + 1, fast_step)
    slows = np.arange(slow_min, slow_max + 1, slow_step)
    f, s = np.meshgrid(fasts, slows, indexing="ij")
    ok = (s >= np.ceil(min_ratio * f)) & (s > f)
    f, s = f[ok].astype(int), s[ok].astype(int)
    order = np.argsort(s, kind="stable")
    return f[order], s[order]


def _metrics_block(r, w, trans, ann: int, unit: float, min_bars: int = 250):
    n = r.shape[1]
    mu = r.mean(1)
    var = np.maximum((r * r).mean(1) - mu ** 2, 0.0)
    sd = np.sqrt((n / max(n - 1, 1)) * var)
    logret = np.log1p(np.clip(r, -0.999999, None))
    logcum = logret.cumsum(1)
    dd = np.expm1((logcum - np.maximum.accumulate(logcum, axis=1)).min(axis=1))
    base = logcum[:, -1]
    cagr = np.expm1(base / n * ann)
    neg = np.where(r < 0, r, 0.0)
    dvar = (neg * neg).mean(1)
    sharpe = mu * np.sqrt(ann) / np.maximum(sd, 1e-18)
    sortino = mu * np.sqrt(ann) / np.maximum(np.sqrt(dvar), 1e-18)
    exposure = np.abs(w).mean(1)
    rt = trans.sum(1) / unit
    ok = (sd > 0) & np.isfinite(sharpe) & (n >= min_bars)
    return dict(sharpe=sharpe, sortino=sortino, cagr=cagr, ann_vol=sd * np.sqrt(ann),
                max_dd=dd, calmar=np.where(dd < -1e-9, cagr / np.abs(dd), np.nan),
                total_return=np.expm1(base), exposure=exposure, round_trips=rt,
                trades_per_year=rt / max(n, 1) * ann, ok=ok)


def grid_for_series(s: Series, f_idx: np.ndarray, s_idx: np.ndarray, mode: str = "long",
                    cost_mult: float = 1.0, span: tuple | None = None,
                    ma: str = "ema", warmup_mult: float = 1.0) -> pd.DataFrame:
    """Backtest every (f, s) pair on one asset.  ``span`` restricts the sample window."""
    px = s.close if span is None else s.close.loc[span[0]: span[1]]
    if len(px) < 320:
        return pd.DataFrame(columns=COLS + ["asset", "asset_class"])
    rets = _returns(px, s.adjustment).astype(np.float64)
    N = rets.size
    periods = np.union1d(f_idx, s_idx).astype(int)
    E = ema_matrix(px.to_numpy(np.float64), periods) if ma == "ema" else sma_matrix(px.to_numpy(np.float64), periods)
    pos_of = {int(p): i for i, p in enumerate(periods)}
    fee = s.cost_bps * cost_mult / 1e4
    unit = 1.0 if mode == "long" else 2.0
    rows = []

    np.seterr(divide="ignore", invalid="ignore")
    for slow in np.unique(s_idx):
        sel = s_idx == slow
        fasts = f_idx[sel]
        fi = np.fromiter((pos_of[int(p)] for p in fasts), int, fasts.size)
        state = E[fi, 1:] > E[pos_of[int(slow)], 1:]                    # (Pf, N)
        w, trans = position_from_state(state, mode)
        warm = int(min(slow * warmup_mult, max(N - 260, 0)))
        if N - warm < 250:
            continue
        rw, tw, ww = w[:, warm:], trans[:, warm:], w[:, warm:]
        r = ww * rets[warm:][None, :] - tw * fee * unit
        m = _metrics_block(r, ww, tw, s.ann, unit)
        keep = m.pop("ok")
        for j in np.flatnonzero(keep):
            row = {"asset": s.key, "asset_class": s.asset_class, "fast": int(fasts[j]), "slow": int(slow),
                   "n_bars": N - warm}
            row.update({k: float(v[j]) for k, v in m.items()})
            rows.append(row)

    df = pd.DataFrame(rows, columns=COLS + ["asset", "asset_class"])
    df = df[["asset", "asset_class"] + COLS] if len(df) else pd.DataFrame(columns=["asset", "asset_class"] + COLS)
    return df


def run_grid(universe: dict[str, Series], f_idx, s_idx, mode="long", cost_mult=1.0,
             span=None, ma="ema", progress=True, log_every=15) -> pd.DataFrame:
    frames, keys = [], list(universe)
    for i, k in enumerate(keys, 1):
        df = grid_for_series(universe[k], f_idx, s_idx, mode=mode, cost_mult=cost_mult,
                             span=span, ma=ma)
        if len(df):
            frames.append(df)
        if progress and (i % log_every == 0 or i == len(keys)):
            print(f"    grid {i:>3}/{len(keys)} assets   (last: {k}, {len(df):>6} pairs)", flush=True)
    if not frames:
        return pd.DataFrame(columns=["asset", "asset_class"] + COLS)
    return pd.concat(frames, ignore_index=True)
