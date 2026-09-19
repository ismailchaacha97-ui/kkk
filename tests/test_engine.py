"""Engine correctness tests.

These check arithmetic against hand-computed answers, and check the two
things that silently ruin backtests: look-ahead and optimistic fills.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from kkk.config import BacktestConfig, Costs, Instrument, RiskConfig
from kkk.engine import Engine, Signal


def frame(rows, freq="1h"):
    idx = pd.date_range("2024-01-01", periods=len(rows), freq=freq, tz="UTC")
    return pd.DataFrame(rows, columns=["open", "high", "low", "close"], index=idx)


@pytest.fixture
def flat_cfg():
    """No costs, no compounding, no ambiguity — pure arithmetic."""
    cfg = BacktestConfig(
        instrument=Instrument("TEST", point_value_per_lot=1.0, digits=2),
        risk=RiskConfig(initial_equity=10_000, risk_pct=1.0, compound=False),
        costs=Costs(),
    )
    return cfg


def test_long_target_hit(flat_cfg):
    # bar 0 is the signal bar; entry at open of bar 1 = 100
    # stop 95 (risk 5), target 110 (2R)
    df = frame([
        [100, 101, 99, 100],
        [100, 102, 99, 101],      # entry at 100
        [101, 106, 100, 105],
        [105, 111, 104, 110],     # high 111 >= 110 -> target
        [110, 110, 110, 110],
    ])
    sig = Signal(direction="long", stop=95.0, target=110.0, entry=None, bar=0)
    res = Engine(flat_cfg).run(df, [sig])

    assert res.n_trades == 1
    t = res.trades[0]
    assert t.entry == pytest.approx(100.0)
    assert t.exit == pytest.approx(110.0)
    assert t.exit_reason == "target"
    # risk 1% of 10k = 100 currency; stop distance 5 -> 20 lots; 10 price -> 200
    assert t.lots == pytest.approx(20.0)
    assert t.pnl == pytest.approx(200.0)
    assert t.r_multiple == pytest.approx(2.0)


def test_long_stop_hit(flat_cfg):
    df = frame([
        [100, 101, 99, 100],
        [100, 100, 94, 95],       # low 94 <= 95 -> stop
        [100, 110, 100, 110],
    ])
    sig = Signal(direction="long", stop=95.0, target=110.0, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    t = res.trades[0]
    assert t.exit_reason == "stop"
    assert t.exit == pytest.approx(95.0)
    assert t.r_multiple == pytest.approx(-1.0)


def test_ambiguous_bar_is_pessimistic_by_default(flat_cfg):
    """One bar touches both stop and target -> assume the stop."""
    df = frame([
        [100, 101, 99, 100],
        [100, 115, 90, 105],      # touches 95 (stop) AND 110 (target)
    ])
    sig = Signal(direction="long", stop=95.0, target=110.0, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.trades[0].exit_reason == "stop"

    optimistic = BacktestConfig(
        instrument=flat_cfg.instrument,
        risk=flat_cfg.risk,
        costs=Costs(),
        stop_first_on_ambiguous_bar=False,
    )
    res2 = Engine(optimistic).run(df, [sig])
    assert res2.trades[0].exit_reason == "target"
    # the optimistic assumption must never lose money relative to the strict one
    assert res2.trades[0].pnl >= res.trades[0].pnl


def test_short_target_hit(flat_cfg):
    df = frame([
        [100, 101, 99, 100],
        [100, 100, 99, 100],
        [98, 99, 88, 89],         # low 88 <= 90 -> target
    ])
    sig = Signal(direction="short", stop=105.0, target=90.0, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    t = res.trades[0]
    assert t.direction == "short"
    assert t.exit_reason == "target"
    assert t.exit == pytest.approx(90.0)
    assert t.r_multiple == pytest.approx(2.0)


def test_limit_order_needs_price_to_reach_it(flat_cfg):
    """A long limit at 95 must not fill if price never trades down to it."""
    df = frame([
        [100, 102, 99, 100],
        [100, 103, 98, 102],      # low 98 > 95 -> no fill
        [102, 104, 99, 103],
        [103, 105, 101, 104],     # order expires here
        [104, 106, 102, 105],
    ])
    sig = Signal(direction="long", stop=90.0, target=110.0, entry=95.0,
                 valid_for=2, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.n_trades == 0
    assert res.skipped == 1


def test_limit_order_fills_when_touched(flat_cfg):
    df = frame([
        [100, 102, 99, 100],
        [100, 101, 94, 96],       # low 94 <= 95 -> fills at 95
        [96, 106, 95, 105],
    ])
    sig = Signal(direction="long", stop=90.0, target=105.0, entry=95.0,
                 valid_for=3, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.n_trades == 1
    assert res.trades[0].entry == pytest.approx(95.0)


def test_spread_is_charged_both_ways():
    cfg = BacktestConfig(
        instrument=Instrument("TEST", point_value_per_lot=1.0),
        risk=RiskConfig(initial_equity=10_000, risk_pct=1.0, compound=False),
        costs=Costs(spread=2.0),
    )
    df = frame([
        [100, 100, 100, 100],
        [100, 100, 100, 100],
        [100, 110, 100, 110],
    ])
    sig = Signal(direction="long", stop=95.0, target=110.0, bar=0)
    res = Engine(cfg).run(df, [sig])
    t = res.trades[0]
    assert t.entry == pytest.approx(101.0)      # 100 + half spread
    assert t.exit == pytest.approx(109.0)       # 110 - half spread
    assert t.r_multiple < 2.0


def test_no_lookahead_on_the_signal_bar(flat_cfg):
    """A signal on bar i must not be filled using bar i's own prices."""
    # bar 1 explodes upward; a signal at bar 1 must NOT get bar 1's open,
    # it can only be filled at bar 2's open.
    df = frame([
        [100, 100, 100, 100],
        [100, 200, 100, 200],
        [150, 210, 150, 200],     # open here is 150, not 100
    ])
    sig = Signal(direction="long", stop=140.0, target=250.0, bar=1)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.n_trades == 1
    assert res.trades[0].entry == pytest.approx(150.0)


def test_is_deterministic(flat_cfg):
    df = frame([[100 + i, 101 + i, 99 + i, 100 + i] for i in range(50)])
    sig = Signal(direction="long", stop=90.0, target=120.0, bar=5)
    a = Engine(flat_cfg).run(df, [sig]).to_frame()
    b = Engine(flat_cfg).run(df, [sig]).to_frame()
    pd.testing.assert_frame_equal(a, b)


def test_sizing_respects_risk_percent(flat_cfg):
    df = frame([
        [100, 100, 100, 100],
        [100, 100, 100, 100],
        [100, 100, 90, 95],
    ])
    # risk 1% of 10,000 = 100; stop distance 10 -> 10 lots
    sig = Signal(direction="long", stop=90.0, target=130.0, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.trades[0].lots == pytest.approx(10.0)
    assert res.trades[0].risk_amount == pytest.approx(100.0)


def test_equity_curve_tracks_realised_pnl(flat_cfg):
    df = frame([
        [100, 100, 100, 100],
        [100, 100, 100, 100],
        [100, 110, 100, 110],
    ])
    sig = Signal(direction="long", stop=95.0, target=110.0, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.equity.iloc[-1] == pytest.approx(10_000 + res.trades[0].pnl)


def test_expired_order_is_skipped(flat_cfg):
    df = frame([[100, 100, 100, 100] for _ in range(10)])
    sig = Signal(direction="long", stop=90.0, target=130.0, entry=50.0,
                 valid_for=2, bar=0)
    res = Engine(flat_cfg).run(df, [sig])
    assert res.n_trades == 0
    assert res.skipped == 1
