"""Sanity + correctness tests for the backtest engine.

The grid search is fast but unusual code (everything is batched), so these tests pin down
the things that would silently invalidate the whole study: EMA definition, lookahead,
cost accounting, warm-up handling, and agreement between the fast batched path and a
slow, dumb, explicitly-written loop.
"""

from __future__ import annotations

import os
import sys

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src"))

from ema_study.engine import (ema, ema_matrix, metrics, position_from_state, evaluate_pair,  # noqa: E402
                             trade_stats)
from ema_study.grid import grid_for_series, pair_grid                                       # noqa: E402
from ema_study.data import Series, _returns                                                   # noqa: E402


def make_series(n=900, seed=0, drift=0.0004, vol=0.01, asset_class="stock", adjustment="raw"):
    rng = np.random.default_rng(seed)
    px = 100.0 * np.exp(np.cumsum(rng.normal(drift, vol, n)))
    idx = pd.bdate_range("2000-01-03", periods=n)
    close = pd.Series(px, index=idx, name="close")
    return Series(symbol="T", asset_class=asset_class, close=close, rets=_returns(close, adjustment),
                  ann=252, adjustment=adjustment, cost_bps=10.0, n=n - 1, start=idx[0], end=idx[-1])


# ------------------------------------------------------------------------------- EMA
def test_ema_matches_pandas_recursive_definition():
    x = make_series(500).close.to_numpy()
    for p in (2, 5, 21, 200, 399):
        mine = ema(x, p)
        ref = pd.Series(x).ewm(span=p, adjust=False, ignore_na=False).mean().to_numpy()
        assert np.max(np.abs(mine - ref)) < 1e-12, p
    assert np.allclose(ema(x, 1), x)


def test_ema_matrix_row_order():
    x = make_series(300).close.to_numpy()
    E = ema_matrix(x, [5, 21, 50])
    assert E.shape == (3, 300)
    assert np.allclose(E[1], ema(x, 21))


def test_ema_is_recursive_and_causal():
    """Changing a future bar must not change the EMA at earlier bars."""
    x = make_series(400).close.to_numpy().copy()
    a = ema(x, 20)
    x2 = x.copy()
    x2[300:] = x2[300:] * 1.5
    assert np.allclose(a[:300], ema(x2, 20)[:300])


# -------------------------------------------------------------------------- alignment
def test_no_lookahead_in_position():
    """The position held over bar t+1 may only depend on closes up to t."""
    s = make_series(600)
    fast, slow = 10, 40
    m, r, w, tr = evaluate_pair(s.close, fast, slow, cost_bps=0.0)
    px = s.close.to_numpy()
    st = (ema(px, fast) > ema(px, slow))
    for t in (45, 100, 250, 500):
        # recompute on data truncated just after close t-1 : must reproduce w at the
        # matching return index
        m2, r2, w2, _ = evaluate_pair(s.close.iloc[: t + 1], fast, slow, cost_bps=0.0)
        assert w2[t - 1] == w[t - 1] == (1.0 if st[t - 1] else 0.0)
        assert r2.iloc[t - 1] == pytest.approx(r.iloc[t - 1])


def test_position_shift_is_one_bar():
    s = make_series(600)
    px = s.close.to_numpy()
    st = (ema(px, 10)[1:] > ema(px, 40)[1:])
    w, tr = position_from_state(st[None, :], "long")
    assert w[0, 1] == (1.0 if st[0] else 0.0)
    assert np.all(w[0, 1:] == st[:-1].astype(float))


def test_long_short_states_are_signed():
    st = np.array([[False, True, True, False]])
    w, tr = position_from_state(st, "ls")
    # bar 0 is always flat (nothing is known yet), then the state known at the previous close
    assert list(w[0]) == [0.0, -1.0, 1.0, 1.0]
    assert tr[0].sum() == 2          # flat->short and short->long


# ------------------------------------------------------------------- brute-force parity
def test_grid_matches_brute_force_loop():
    """The batched grid must reproduce an explicit loop over bars, pair by pair."""
    s = make_series(700, seed=3)
    pairs = [(5, 30), (12, 26), (20, 100), (60, 180)]
    f = np.array([p[0] for p in pairs])
    sl = np.array([p[1] for p in pairs])
    grid = grid_for_series(s, f, sl, mode="long", cost_mult=1.0).set_index(["fast", "slow"])
    px = s.close.to_numpy()
    rets = s.rets
    fee = s.cost_bps / 1e4
    N = rets.size
    for (ff, ss) in pairs:
        warm = int(min(ss, max(N - 260, 0)))          # same clamp as the grid
        ema_f, ema_s = ema(px, ff), ema(px, ss)
        daily = np.zeros(len(rets))
        wvec = np.zeros(len(rets))
        pos = 0.0                                      # flat before the first signal
        for t in range(len(rets)):
            # crossover known at the close of bar t -> held over bar t -> t+1, cost on that bar
            want = 1.0 if ema_f[t] > ema_s[t] else 0.0
            daily[t] = want * rets[t] - abs(want - pos) * fee
            wvec[t] = want
            pos = want
        d, ww = daily[warm:], wvec[warm:]
        mu, sd = d.mean(), d.std(ddof=1)
        lc = np.log1p(d).cumsum()
        dd = np.expm1((lc - np.maximum.accumulate(lc)).min())
        g = grid.loc[(ff, ss)]
        assert g["sharpe"] == pytest.approx(mu / sd * np.sqrt(252), rel=1e-6)
        assert g["max_dd"] == pytest.approx(dd, rel=1e-6)
        assert g["cagr"] == pytest.approx(np.expm1(lc[-1] / len(d) * 252), rel=1e-6)
        assert g["n_bars"] == len(d)
        assert g["exposure"] == pytest.approx(ww.mean(), rel=1e-6)


def test_evaluate_pair_matches_grid_row():
    s = make_series(700, seed=7)
    m, r, w, tr = evaluate_pair(s.close, 12, 26, adjustment="raw", ann=252, cost_bps=s.cost_bps)
    g = grid_for_series(s, np.array([12]), np.array([26]), mode="long").iloc[0]
    assert m["sharpe"] == pytest.approx(g["sharpe"], rel=1e-9)
    assert m["max_dd"] == pytest.approx(g["max_dd"], rel=1e-9)
    assert m["cagr"] == pytest.approx(g["cagr"], rel=1e-9)


# ------------------------------------------------------------------------- cost engine
def test_cost_is_charged_once_per_position_change():
    s = make_series(700, seed=5)
    for mode, unit in (("long", 1.0), ("ls", 2.0)):
        m0, r0, w0, t0 = evaluate_pair(s.close, 12, 26, cost_bps=0.0, mode=mode)
        m1, r1, w1, t1 = evaluate_pair(s.close, 12, 26, cost_bps=25.0, mode=mode)
        drag = r0.sum() - r1.sum()
        assert drag == pytest.approx(t1.sum() * 25e-4 * unit, rel=1e-9)


def test_zero_cost_long_only_never_trades_when_price_falls_monotonically():
    idx = pd.bdate_range("2001-01-01", periods=500)
    close = pd.Series(200.0 - np.arange(500) * 0.2, index=idx)
    s = Series("DOWN", "stock", close, _returns(close, "raw"), 252, "raw", 0.0, 499, idx[0], idx[-1])
    m, r, w, tr = evaluate_pair(s.close, 5, 20, cost_bps=0.0, mode="long")
    assert np.all(w == 0.0)
    assert m["total_return"] == pytest.approx(0.0)
    assert np.isnan(m["sharpe"])                       # never traded -> Sharpe undefined
    mls, rls, wls, trls = evaluate_pair(s.close, 5, 20, cost_bps=0.0, mode="ls")
    assert np.all(wls[30:] == -1.0)
    assert mls["cagr"] > 0                                  # shorting a falling series makes money


def test_buy_and_hold_equals_always_long():
    s = make_series(700, seed=11)
    warm = 40
    bh = metrics(s.rets[warm:][None, :], 252, pos=np.ones((1, s.n - warm)),
                 changes=np.zeros((1, s.n - warm), bool)).iloc[0]
    st = np.ones((1, s.n - warm), bool)
    w, tr = position_from_state(st, "long")
    on = metrics((1.0 * s.rets[warm:])[None, :], 252, pos=w, changes=tr).iloc[0]
    assert bh["sharpe"] == pytest.approx(on["sharpe"], rel=1e-12)
    assert bh["max_dd"] == pytest.approx(on["max_dd"], rel=1e-9)


# ----------------------------------------------------------------------------- metrics
def test_warmup_exactly_slow_bars():
    s = make_series(700, seed=13)
    for slow in (30, 120, 400):
        g = grid_for_series(s, np.array([5]), np.array([slow]), mode="long").iloc[0]
        N = s.n                                      # len(close) - 1
        assert g["n_bars"] == N - min(slow, N - 260)


def test_metrics_need_enough_bars():
    rng = np.random.default_rng(0)
    r = rng.normal(0.0004, 0.01, (1, 100))
    z = np.zeros(r.shape, bool)
    assert np.isnan(metrics(r, 252, pos=np.ones(r.shape), changes=z)["sharpe"].iloc[0])
    assert np.isfinite(metrics(r, 252, min_bars=10, pos=np.ones(r.shape), changes=z)["sharpe"].iloc[0])
    flat = np.zeros((1, 400))
    mf = metrics(flat, 252, pos=np.ones_like(flat), changes=np.zeros(flat.shape, bool))
    assert np.isnan(mf["sharpe"].iloc[0]) and mf["total_return"].iloc[0] == 0.0


def test_max_drawdown_definition():
    r = np.array([0.10, -0.05, -0.05, 0.20, -0.30, 0.10])
    m = metrics(r[None, :], 252, pos=np.ones((1, 6)), changes=np.zeros((1, 6), bool),
                min_bars=6).iloc[0]
    eq = np.cumprod(1 + r)
    expected = (eq / np.maximum.accumulate(eq) - 1).min()
    assert m["max_dd"] == pytest.approx(expected, rel=1e-12)
    assert m["max_dd"] < 0


def test_trades_are_non_flat_runs():
    r = np.array([0.01, 0.02, -0.01, -0.02, 0.03, 0.01])
    w = np.array([1.0, 1.0, 0.0, 0.0, 1.0, 1.0])
    ts = trade_stats(r, w, warm=0)
    t1, t2 = 1.01 * 1.02 - 1, 1.03 * 1.01 - 1        # the two long runs
    assert ts["n_trades"] == 2                      # flat stretches are not trades
    assert ts["hit_rate"] == pytest.approx(1.0)
    assert ts["avg_trade"] == pytest.approx((t1 + t2) / 2)
    assert ts["profit_factor"] == np.inf            # no losing trade


def test_short_and_long_runs_are_both_counted_as_trades():
    r = np.array([-0.02, 0.03, 0.01, -0.01])
    w = np.array([-1.0, -1.0, 1.0, 1.0])
    ts = trade_stats(r, w, warm=0)
    win, loss = 0.98 * 1.03 - 1, 1.01 * 0.99 - 1
    assert ts["n_trades"] == 2 and ts["hit_rate"] == pytest.approx(0.5)
    assert ts["profit_factor"] == pytest.approx(win / -loss)


# --------------------------------------------------------------------------- data layer
def test_back_adjusted_returns_use_level_normalisation():
    """Additive roll adjustment must not be turned into absurd % returns near zero level."""
    from ema_study.data import apply_level_filter
    idx = pd.bdate_range("1980-01-01", periods=600)
    px = pd.Series(np.linspace(0.05, 60.0, 600), index=idx)         # adjusted level near zero early
    r_raw = _returns(px, "raw")
    r_adj = _returns(px, "back_adjusted")
    assert np.nanmax(np.abs(r_raw)) > 1.0                # 0.05 -> 0.15 reads as +200%
    assert np.nanmax(np.abs(r_adj[:60])) < np.nanmax(np.abs(r_raw[:60]))
    kept = apply_level_filter(px, "back_adjusted")
    assert len(kept) < len(px)                           # the near-zero head is dropped
    assert kept.abs().min() >= 0.25 * px.abs().median()
    assert apply_level_filter(px, "raw").equals(px)      # raw series untouched


def test_returns_drop_first_bar():
    px = make_series(100).close
    r = _returns(px, "raw")
    assert r.size == len(px) - 1
    assert r[0] == pytest.approx(px.iloc[1] / px.iloc[0] - 1)


def test_pair_grid_respects_ratio_and_ordering():
    f, sl = pair_grid(fast_max=10, slow_max=30, fast_step=1, slow_step=1, min_ratio=2.0)
    exp = {(a, b) for a in range(2, 11) for b in range(6, 31) if b >= 2 * a}
    assert set(zip(f.tolist(), sl.tolist())) == exp
    assert np.all(sl > f)
    assert np.all(np.diff(sl) >= 0)          # sorted by slow -> exact warm-up slicing


# ------------------------------------------------------------------- annualisation factor
def test_annualisation_counts_bars_per_year_not_gaps():
    """A business-day index alternates 1- and 3-day gaps, so its *median* gap is 1.0: the old
    gap rule called it a 365-day market and inflated every equity Sharpe by sqrt(365/252)."""
    from ema_study.data import _annualisation

    bd = pd.bdate_range("2005-01-03", "2019-12-31")            # ~252 bars/yr, median gap 1 day
    assert 240 <= _annualisation(bd) <= 265, _annualisation(bd)      # bdate_range keeps holidays
    cal = pd.date_range("2014-01-01", "2019-07-04", freq="D")  # crypto: every day
    assert abs(_annualisation(cal) - 365) <= 3, _annualisation(cal)
    wk = pd.date_range("2005-01-07", "2019-12-27", freq="W-FRI")
    assert abs(_annualisation(wk) - 52) <= 2, _annualisation(wk)
    # a mid-sample hole must not be read as "fewer bars per year" by the full-period average
    holed = bd.drop(pd.date_range("2010-01-04", "2012-12-28", freq="B"))
    assert abs(_annualisation(holed) - _annualisation(bd)) <= 2, _annualisation(holed)
    # and a stub year at each end (partial data) must not drag the median down either
    stub = bd[:30].append(bd[400:1200]).append(bd[-25:])
    assert abs(_annualisation(stub) - _annualisation(bd)) <= 2, _annualisation(stub)


def test_annualisation_matches_metrics_scaling():
    """Sharpe must scale with sqrt(ann): the same curve annualised two ways."""
    from ema_study.data import _annualisation
    rng = np.random.default_rng(4)
    r = rng.normal(0.0005, 0.01, 2500)
    a = _annualisation(pd.bdate_range("2000-01-03", periods=2500))
    m1 = metrics(r[None, :], a)["sharpe"].iloc[0]
    m2 = metrics(r[None, :], 365)["sharpe"].iloc[0]
    assert abs(m1 * np.sqrt(365 / a) - m2) < 1e-12
