"""
Unit tests for the backtest engine.

Run:  python -m pytest backtest/test_engine.py -q
      (or  python backtest/test_engine.py  for a plain run)
"""
from __future__ import annotations

import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backtest import data as D
from backtest.engine import (EngineCfg, Position, pnl_usd, notional_usd,
                             price_unit_value, run)
from backtest.features import Features, Params


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def make_series(sym, o, h, l, c, start="2020-01-01 08:00"):
    n = len(o)
    t = pd.date_range(start, periods=n, freq="h").values.astype("datetime64[ns]")
    return D.Series(symbol=sym, time=t, open=np.asarray(o, float), high=np.asarray(h, float),
                    low=np.asarray(l, float), close=np.asarray(c, float),
                    volume=np.asarray([100.0] * n))


def flat_features(n, atr=0.0010, ok_long=None, ok_short=None, level_l=1.1, level_h=1.2):
    z = np.zeros(n)
    ok_long = np.zeros(n, bool) if ok_long is None else np.asarray(ok_long, bool)
    ok_short = np.zeros(n, bool) if ok_short is None else np.asarray(ok_short, bool)
    return Features(
        time=np.arange(n), atr=np.full(n, atr), pdh=np.full(n, level_h), pdl=np.full(n, level_l),
        pwh=np.full(n, level_h), pwl=np.full(n, level_l),
        swing_hi_1=np.full(n, level_h), swing_hi_2=np.full(n, level_h),
        swing_lo_1=np.full(n, level_l), swing_lo_2=np.full(n, level_l),
        structure=np.zeros(n, np.int8), rng=np.full(n, atr), vol_med=np.full(n, 100.0),
        hour=np.full(n, 9), weekday=np.zeros(n, int), day=np.zeros(n, np.int64),
        ok_long=ok_long, ok_short=ok_short,
        extra=dict(lvl_h=np.full(n, level_h), lvl_l=np.full(n, level_l)),
    )


def base_cfg(**kw):
    cfg = dict(start_equity=10_000.0, risk_pct=0.5, max_positions=3, daily_loss_stop_pct=0.0,
               daily_hard_stop_pct=0.0, weekly_loss_stop_pct=0.0, close_before_weekend_hour=99,
               cost_multiplier=1.0)
    cfg.update(kw)
    return EngineCfg(**cfg)


def fake_params(**kw):
    p = Params(rr=2.0, sl_atr_buffer=0.5, min_sl_atr=0.1, max_sl_atr=10.0, be_at_r=0.0,
               trail_atr=0.0, max_hold_bars=0, max_signals_per_day=5, min_range_atr=0.0,
               close_frac=0.0, vol_confirm=0, require_htf_trend=0)
    for k, v in kw.items():
        setattr(p, k, v)
    return p


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------
def test_pnl_and_notional():
    fx = D.INSTRUMENTS["EURUSD"]
    assert abs(pnl_usd("EURUSD", +1, 1.1000, 1.1050, 1.0, fx) - 500.0) < 1e-9
    assert abs(pnl_usd("EURUSD", -1, 1.1000, 1.0950, 1.0, fx) - 500.0) < 1e-9
    jpy = D.INSTRUMENTS["USDJPY"]
    # 1 lot USDJPY, 1.00 price move = 100000 JPY / 150 = 666.67 USD
    assert abs(pnl_usd("USDJPY", +1, 150.00, 151.00, 1.0, jpy) - 100000.0 / 151.0) < 1e-6
    assert abs(notional_usd("USDJPY", 1.0, 150.0, jpy) - 100_000.0) < 1e-9
    assert abs(notional_usd("EURUSD", 1.0, 1.10, fx) - 110_000.0) < 1e-9
    assert abs(price_unit_value("USDJPY", 150.0, jpy) - 100_000.0 / 150.0) < 1e-6


def test_long_target_hit():
    """Signal on bar 1, entry at the open of bar 2, target reached intrabar later."""
    o = [1.1000, 1.1000, 1.1000, 1.1012, 1.1020, 1.1020]
    h = [1.1002, 1.1005, 1.1006, 1.1018, 1.1028, 1.1022]
    l = [1.0998, 1.0995, 1.0997, 1.1010, 1.1015, 1.1016]
    c = [1.1000, 1.1000, 1.1002, 1.1015, 1.1025, 1.1020]
    s = make_series("EURUSD", o, h, l, c)
    f = flat_features(6, atr=0.0010, ok_long=[0, 1, 0, 0, 0, 0])
    res = run({"EURUSD": s}, {"EURUSD": f}, {"EURUSD": fake_params()}, base_cfg(),
              verbose=False)
    tr = res.trades
    assert len(tr) == 1, tr
    t = tr.iloc[0]
    stop = l[1] - 0.5 * 0.0010
    tp = t.entry + 2.0 * (t.entry - stop)
    assert t.side == 1
    assert t.reason == "tp", t.reason
    assert abs(t.exit - tp) < 1e-9
    assert t.pnl > 0


def test_short_stop_triggers_on_ask():
    """A short's stop must trigger when Ask (bid + spread) reaches it - i.e. one
    spread *before* the bid chart touches the level.  That is what makes shorts
    structurally more expensive than longs, and the engine must model it."""
    lvl_h = 1.2000
    o = [1.1995, 1.1995, 1.1995, 1.1998, 1.1996]
    h = [1.1998, 1.2005, 1.2000, 1.20095, 1.2000]   # bar 3 high is *just* below the stop
    l = [1.1992, 1.1990, 1.1990, 1.1995, 1.1990]
    c = [1.1995, 1.1995, 1.1996, 1.1996, 1.1992]
    s = make_series("EURUSD", o, h, l, c)
    f = flat_features(5, atr=0.0010, ok_short=[0, 1, 0, 0, 0], level_h=lvl_h)
    res = run({"EURUSD": s}, {"EURUSD": f}, {"EURUSD": fake_params(sl_atr_buffer=0.5)},
              base_cfg(), verbose=False)
    t = res.trades.iloc[0]
    sl_level = h[1] + 0.5 * 0.0010          # 1.20100
    assert t.side == -1
    assert t.reason == "sl", t.reason
    assert abs(t.exit - sl_level) < 1e-9
    assert t.entry < o[2]                   # entry was at the bid
    assert t.pnl < 0

    # control: with no spread at all the same bar must NOT stop the trade out
    res0 = run({"EURUSD": s}, {"EURUSD": f}, {"EURUSD": fake_params(sl_atr_buffer=0.5)},
               base_cfg(cost_multiplier=0.0), verbose=False)
    assert res0.trades.iloc[0].reason != "sl", "spread must be what triggers this stop"


def test_position_size_matches_risk():
    o = [1.1000] * 6
    h = np.array([1.1002] * 6)
    l = np.array([1.0998] * 6)
    c = [1.1000] * 6
    s = make_series("EURUSD", o, h, l, c)
    f = flat_features(6, atr=0.0010, ok_long=[0, 1, 0, 0, 0, 0])
    res = run({"EURUSD": s}, {"EURUSD": f}, {"EURUSD": fake_params()},
              base_cfg(risk_pct=1.0, close_before_weekend_hour=99), verbose=False)
    t = res.trades.iloc[0]
    # planned risk in USD must be ≈ 1% of the starting equity
    assert abs(t.risk_amount - 100.0) < 1e-6
    stop_dist = abs(t.entry - (t.entry - t.sl_dist))
    unit = price_unit_value("EURUSD", t.entry, D.INSTRUMENTS["EURUSD"])
    assert abs(t.lots * stop_dist * unit - 100.0) < 2.0     # lot rounding tolerance


def test_daily_loss_stop_blocks_new_trades():
    """Every trade is a loser; the daily guard must stop opening new ones."""
    n = 60
    lvl = 1.1000
    o = np.full(n, lvl)
    h = np.full(n, lvl + 0.0015)
    l = np.full(n, lvl - 0.0004)
    c = np.full(n, lvl)
    s = make_series("EURUSD", o, h, l, c)
    ok_short = np.zeros(n, bool)
    ok_short[1::2] = True
    f = flat_features(n, atr=0.0010, ok_short=ok_short, level_h=lvl + 0.0005)
    cfg = base_cfg(risk_pct=2.0, daily_loss_stop_pct=0.5, daily_hard_stop_pct=0.0)
    res = run({"EURUSD": s}, {"EURUSD": f}, {"EURUSD": fake_params(max_signals_per_day=99,
                                                                   sl_atr_buffer=0.5)}, cfg)
    assert len(res.trades) > 0, "test setup must produce trades"
    assert len(res.trades) < n / 4, f"guard did not stop entries ({len(res.trades)} trades)"
    assert res.trades.pnl.sum() < 0


def test_max_positions_respected():
    n = 30
    series, feats, prm = {}, {}, {}
    for sym in ("EURUSD", "GBPUSD", "AUDUSD", "USDJPY"):
        o = np.full(n, 1.1000)
        s = make_series(sym, o, o + 0.0005, o - 0.0005, o)
        series[sym] = s
        ok = np.zeros(n, bool)
        ok[1:] = True
        feats[sym] = flat_features(n, atr=0.0010, ok_long=ok)
        prm[sym] = fake_params(max_signals_per_day=99)
    res = run(series, feats, prm, base_cfg(max_positions=2), verbose=False)
    # with 2 slots and 48 bars held at most, never more than 2 trades can be open
    tr = res.trades.sort_values("open_time")
    open_times = list(tr.open_time)
    for i in range(len(tr)):
        concurrent = ((tr.open_time <= tr.open_time.iloc[i]) & (tr.close_time > tr.open_time.iloc[i])).sum()
        assert concurrent <= 2, f"{concurrent} concurrent positions at {tr.open_time.iloc[i]}"


def test_no_lookahead_in_engine():
    """Running on truncated data must reproduce the same trades up to the cut."""
    syms = ["GBPUSD"]
    s = D.load("GBPUSD", "H1")
    p = Params()
    from backtest.features import build
    cut = len(s) - 2000
    trunc = D.Series(symbol=s.symbol, time=s.time[:cut], open=s.open[:cut], high=s.high[:cut],
                     low=s.low[:cut], close=s.close[:cut], volume=s.volume[:cut])
    f_full = build(s, p)
    f_tr = build(trunc, p)
    cfg = base_cfg(risk_pct=0.25)
    r_full = run({"GBPUSD": s}, {"GBPUSD": f_full}, {"GBPUSD": p}, cfg,
                 start="2018-01-01", end="2018-06-01")
    r_tr = run({"GBPUSD": trunc}, {"GBPUSD": f_tr}, {"GBPUSD": p}, cfg,
               start="2018-01-01", end="2018-06-01")
    a = r_full.trades[["open_time", "entry", "exit", "pnl"]]
    b = r_tr.trades[["open_time", "entry", "exit", "pnl"]]
    assert len(a) == len(b) > 0
    assert np.allclose(a.pnl.values, b.pnl.values)


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for fn in fns:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except AssertionError as exc:
            failed += 1
            print(f"FAIL {fn.__name__}: {exc}")
        except Exception as exc:                       # noqa: BLE001
            failed += 1
            print(f"ERROR {fn.__name__}: {type(exc).__name__}: {exc}")
    print(f"\n{len(fns) - failed}/{len(fns)} tests passed")
    sys.exit(1 if failed else 0)
