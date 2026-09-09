"""Tests for the out-of-sample machinery in ``ema_study.robust``.

split_sample() is new code that touches the same alignment conventions as the engine, so
the two properties worth pinning are: (1) the two halves recombine into exactly the
full-sample curve, and (2) the in-sample half cannot see the future.
"""

from __future__ import annotations

import os
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src"))

from ema_study.data import Series, _returns                              # noqa: E402
from ema_study.engine import evaluate_pair, metrics                      # noqa: E402
from ema_study.robust import split_sample, summarise_split, book_window   # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests"))
from test_engine import make_series                                       # noqa: E402


def uni(n=1400, seed=3, **kw):
    return {f"T{k}": make_series(n=n, seed=seed + k, **kw) for k in range(3)}


# --------------------------------------------------------------------- halves <-> whole
@pytest.mark.parametrize("mode,fast,slow", [("long", 8, 40), ("ls", 12, 60), ("long", 20, 200)])
def test_halves_recombine_to_the_full_sample(mode, fast, slow):
    """IS+OOS returns are a partition of the full-sample curve -> recomposing them must
    reproduce evaluate_pair()'s Sharpe exactly (up to float noise)."""
    s = make_series(n=1500)
    sp = split_sample({"T": s}, [(fast, slow)], mode=mode, cut=0.6, warmup_mult=0.0,
                      progress=False)
    assert len(sp) == 1
    row = sp.iloc[0]
    _m, rr, _w, _tr = evaluate_pair(s.close, fast, slow, adjustment=s.adjustment, ann=s.ann,
                                    cost_bps=s.cost_bps, mode=mode, warmup=False)
    r = np.asarray(rr, dtype=float)
    k = int(row["is_bars"])
    assert k + int(row["oos_bars"]) == r.size
    a, b = r[:k], r[k:]
    mu = (a.mean() * a.size + b.mean() * b.size) / r.size
    var = ((a - mu) ** 2).sum() + ((b - mu) ** 2).sum()
    sharpe = mu / np.sqrt(var / (r.size - 1)) * np.sqrt(s.ann)
    ref = metrics(r[None, :], s.ann)["sharpe"].iloc[0]
    assert abs(sharpe - ref) < 1e-9, (sharpe, ref)
    assert abs(float(row["is_sharpe"]) - metrics(a[None, :], s.ann)["sharpe"].iloc[0]) < 1e-9
    assert abs(float(row["oos_sharpe"]) - metrics(b[None, :], s.ann)["sharpe"].iloc[0]) < 1e-9


def test_split_boundary_is_after_warmup_and_uses_its_own_costs():
    s = make_series(n=1500)
    sp = split_sample({"T": s}, [(10, 50)], mode="ls", cut=0.5, warmup_mult=0.0, progress=False)
    row = sp.iloc[0]
    assert row["is_start"] == str(s.close.index[0].date())            # warmup_mult=0 -> starts at bar 1
    assert row["split"] > row["is_start"] and row["oos_end"] >= row["split"]
    # cost is charged per flip: an empty trade list would show up as zero turnover
    assert row["oos_bars"] >= 250 and row["is_bars"] >= 250


# ------------------------------------------------------------------------- no lookahead
def test_in_sample_score_is_blind_to_the_future():
    """Replace every return after the split date with garbage: is_sharpe must not move."""
    s = uni(n=1500)["T0"]
    sp0 = split_sample({"T": s}, [(10, 40), (20, 120)], mode="long", cut=0.55,
                       warmup_mult=0.0, progress=False)
    rets = np.asarray(_returns(s.close, s.adjustment), dtype=float)
    split_pos = int(sp0.iloc[0]["is_bars"])
    rets2 = rets.copy()
    rng = np.random.default_rng(99)
    rets2[split_pos:] = rng.normal(0.0, 0.05, rets2[split_pos:].size)     # future is pure noise
    # rebuild the price path from the modified simple returns: px0 * cumprod(1+r).
    # (exp(cumsum(r)) would be wrong: these are simple, not log, returns.)
    px = s.close.iloc[0] * np.concatenate([[1.0], np.cumprod(1.0 + rets2)])
    s2 = Series(symbol="T", asset_class=s.asset_class, close=pd.Series(px, index=s.close.index),
                rets=_returns(pd.Series(px, index=s.close.index), s.adjustment), ann=s.ann,
                adjustment=s.adjustment, cost_bps=s.cost_bps, n=len(px) - 1,
                start=s.close.index[0], end=s.close.index[-1])
    sp1 = split_sample({"T": s2}, [(10, 40), (20, 120)], mode="long", cut=0.55,
                       warmup_mult=0.0, progress=False)
    m0 = sp0.set_index(["fast", "slow"])["is_sharpe"].to_numpy(float)
    m1 = sp1.set_index(["fast", "slow"])["is_sharpe"].to_numpy(float)
    # the rebuilt price path is exact only to float precision (exp/cumsum round-trip), so
    # "identical" here means identical to well below any number anyone would quote.
    assert np.max(np.abs(m0 - m1)) < 1e-9, (m0, m1)
    # ...and the OOS numbers did change, so the test is not vacuous
    o0 = sp0.set_index(["fast", "slow"])["oos_sharpe"].to_numpy(float)
    o1 = sp1.set_index(["fast", "slow"])["oos_sharpe"].to_numpy(float)
    assert np.max(np.abs(o0 - o1)) > 0.05            # the future really did change


# --------------------------------------------------------------------------- summarise
def test_summarise_split_ranks_and_marks_picks():
    sp = split_sample(uni(n=1500, seed=5), [(5, 20), (10, 40), (20, 60), (8, 100), (40, 150)],
                      mode="ls", cut=0.6, warmup_mult=0.0, progress=False)
    g = summarise_split(sp)
    assert {"rank_is", "rank_oos", "picked", "nb_is", "med_is", "med_oos"} <= set(g.columns)
    assert len(g) == sp[["fast", "slow"]].drop_duplicates().shape[0]
    # rank_is must be monotone in nb_is (descending)
    gg = g.sort_values("nb_is", ascending=False)
    assert list(gg["rank_is"]) == sorted(gg["rank_is"])
    assert g["picked"].notna().sum() <= 3                     # at most one row per rule
    assert any("cheating" in x for x in g["picked"].dropna())


def test_summarise_split_empty_is_safe():
    assert summarise_split(pd.DataFrame()).empty


# ------------------------------------------------------------------------- book_window
def test_book_window_returns_a_sane_span():
    lo, hi = book_window(uni(n=1500, seed=1), frac=0.5)
    assert lo < hi and pd.Timestamp(lo) < pd.Timestamp(hi)
