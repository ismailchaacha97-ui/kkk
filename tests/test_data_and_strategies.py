"""Data loading, primitives and strategy contract tests."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from kkk import data as kdata
from kkk.config import BacktestConfig
from kkk.engine import Engine
from kkk.primitives import SwingIndex, atr, is_engulfing, is_pin_bar, swing_points
from kkk.strategies import REGISTRY, get


# ------------------------------------------------------------------ data
MT5_CSV = (
    "<DATE>\t<TIME>\t<OPEN>\t<HIGH>\t<LOW>\t<CLOSE>\t<TICKVOL>\t<VOL>\t<SPREAD>\n"
    "2024.01.02\t01:00:00\t2063.5\t2066.1\t2062.8\t2065.4\t1120\t0\t25\n"
    "2024.01.02\t02:00:00\t2065.4\t2068.9\t2064.2\t2068.1\t1310\t0\t25\n"
    "2024.01.02\t03:00:00\t2068.1\t2069.5\t2061.0\t2062.4\t1502\t0\t25\n"
) + "".join(
    f"2024.01.0{2 + (i // 24) % 3}\t{i % 24:02d}:00:00\t"
    f"{2062.0 + i * 0.3:.1f}\t{2064.0 + i * 0.3:.1f}\t"
    f"{2060.0 + i * 0.3:.1f}\t{2063.0 + i * 0.3:.1f}\t900\t0\t25\n"
    for i in range(80)
)


def test_load_mt5_export(tmp_path):
    p = tmp_path / "XAUUSD_H1.csv"
    p.write_text(MT5_CSV)
    df = kdata.load_csv(p)
    assert list(df.columns)[:5] == ["open", "high", "low", "close", "volume"]
    assert df.index.tz is not None
    assert len(df) > 50
    assert (df["high"] >= df["low"]).all()


def _hourly_stamps(n: int, start="2024-01-02") -> list[str]:
    """n hourly, ISO-8601, weekday-only timestamps."""
    idx = pd.date_range(start, periods=n * 2, freq="1h", tz="UTC")
    return [t.strftime("%Y-%m-%dT%H:%M:%SZ") for t in idx[idx.dayofweek < 5][:n]]


def _tv_csv(n: int = 120) -> str:
    rows = []
    for i, ts in enumerate(_hourly_stamps(n)):
        px = 1.1040 + i * 0.0002
        rows.append(f"{ts},{px:.4f},{px + 0.0008:.4f},{px - 0.0005:.4f},{px + 0.0004:.4f},800")
    return "time,open,high,low,close,Volume\n" + "\n".join(rows) + "\n"


def test_load_tradingview_export(tmp_path):
    p = tmp_path / "EURUSD.csv"
    p.write_text(_tv_csv())
    df = kdata.load_csv(p)
    assert len(df) > 50
    assert df["close"].iloc[0] == pytest.approx(1.1044)
    assert df.index.is_monotonic_increasing


def test_load_rejects_broken_ohlc(tmp_path):
    p = tmp_path / "bad.csv"
    rows = "\n".join(
        f"{ts},10,5,20,10" for ts in _hourly_stamps(60)
    )
    p.write_text("time,open,high,low,close\n" + rows + "\n")
    with pytest.raises(ValueError, match="OHLC"):
        kdata.load_csv(p)


def test_load_rejects_missing_columns(tmp_path):
    p = tmp_path / "bad.csv"
    rows = "\n".join(f"{ts},10" for ts in _hourly_stamps(60))
    p.write_text("time,price\n" + rows + "\n")
    with pytest.raises(ValueError, match="missing"):
        kdata.load_csv(p)


def test_resample_roundtrip(tmp_path):
    h1 = kdata.make_synthetic(n=500, freq="1h")
    h4 = kdata.resample(h1, "4h")
    assert 100 < len(h4) < 200
    assert h4["high"].max() <= h1["high"].max() + 1e-9
    assert h4["low"].min() >= h1["low"].min() - 1e-9


def test_sessions_tagging():
    df = kdata.add_sessions(kdata.make_synthetic(n=48, freq="1h"))
    assert {"asia", "london", "overlap", "newyork"} <= set(df["session"].unique())


def test_train_test_split_is_ordered():
    df = kdata.make_synthetic(n=100)
    a, b = kdata.train_test_split(df, 0.7)
    assert len(a) == 70
    assert a.index[-1] < b.index[0]


# ------------------------------------------------------------ primitives
def test_swing_detection():
    df = pd.DataFrame(
        {"open": [1, 2, 3, 2, 1, 2, 3, 2, 1],
         "high": [1, 2, 5, 2, 1, 2, 6, 2, 1],
         "low": [1, 2, 3, 2, 1, 2, 3, 2, 1],
         "close": [1, 2, 4, 2, 1, 2, 5, 2, 1]},
        index=pd.date_range("2024-01-01", periods=9, freq="1h", tz="UTC"),
    )
    s = swing_points(df, left=1, right=1)
    assert s["swing_high"].sum() == 2
    assert s["swing_high"].iloc[2]


def test_swing_index_never_reveals_unconfirmed_swings():
    """A swing printed at bar j is invisible until bar j+right."""
    df = pd.DataFrame(
        {"open": [1, 2, 3, 2, 1], "high": [1, 2, 9, 2, 1],
         "low": [1, 2, 3, 2, 1], "close": [1, 2, 4, 2, 1]},
        index=pd.date_range("2024-01-01", periods=5, freq="1h", tz="UTC"),
    )
    si = SwingIndex(df, left=1, right=1)
    assert si.last_high(2) is None          # can't be known yet
    assert si.last_high(3) is not None      # confirmed at bar 3


def test_pin_bar_and_engulfing():
    # bar 0: tiny body at the top, long lower wick -> bullish pin
    # bar 1: bearish-then-bullish engulfing over bar 0's body
    df = pd.DataFrame(
        {
            "open": [10.6, 10.4],
            "high": [10.7, 11.6],
            "low": [8.0, 9.4],
            "close": [10.1, 11.5],
        },
        index=pd.date_range("2024-01-01", periods=2, freq="1h", tz="UTC"),
    )
    pin, direction = is_pin_bar(df, 0, 0.6)
    assert pin and direction == 1

    # bearish bar 0, then a bullish bar 1 that opens below and closes above
    # it -> bullish engulfing
    bear = pd.DataFrame(
        {"open": [11.0, 10.1], "high": [11.1, 11.8], "low": [9.8, 10.0],
         "close": [10.2, 11.5]},
        index=pd.date_range("2024-01-01", periods=2, freq="1h", tz="UTC"),
    )
    assert is_engulfing(bear, 1) == 1


def test_atr_is_positive_and_finite():
    df = kdata.make_synthetic(n=200)
    a = atr(df, 14).dropna()
    assert len(a) > 100
    assert (a > 0).all()
    assert np.isfinite(a).all()


# ------------------------------------------------------------ strategies
@pytest.mark.parametrize("name", sorted(REGISTRY))
def test_strategy_contract(name):
    """Every strategy: signals have sane geometry and never look ahead."""
    mod = get(name)
    df = kdata.add_sessions(kdata.make_synthetic(n=3000))
    sigs = mod.generate(df)

    assert isinstance(sigs, list)
    assert len(sigs) > 0, f"{name} produced no signals on 3000 bars"

    for s in sigs:
        assert s.bar is not None
        assert 0 <= s.bar < len(df)
        assert s.direction in ("long", "short")
        assert s.stop != (s.entry if s.entry is not None else df["close"].iloc[s.bar])
        if s.entry is not None:
            # a resting limit must sit on the correct side of the signal close
            close = float(df["close"].iloc[s.bar])
            if s.direction == "long":
                assert s.entry <= close + 1e-9
                assert s.stop < s.entry
                assert s.target is None or s.target > s.entry
            else:
                assert s.entry >= close - 1e-9
                assert s.stop > s.entry
                assert s.target is None or s.target < s.entry
        else:
            close = float(df["close"].iloc[s.bar])
            if s.direction == "long":
                assert s.stop < close
                assert s.target is None or s.target > close
            else:
                assert s.stop > close
                assert s.target is None or s.target < close


@pytest.mark.parametrize("name", sorted(REGISTRY))
def test_strategy_runs_through_engine(name):
    mod = get(name)
    df = kdata.add_sessions(kdata.make_synthetic(n=4000))
    cfg = BacktestConfig.for_symbol("XAUUSD")
    res = Engine(cfg).run(df, mod.generate(df), warmup=mod.WARMUP)
    assert res.n_trades > 0
    assert len(res.equity) == len(df)


@pytest.mark.parametrize("name", sorted(REGISTRY))
def test_strategy_is_deterministic(name):
    mod = get(name)
    df = kdata.make_synthetic(n=2000)
    a = [ (s.bar, s.direction, round(s.stop, 6)) for s in mod.generate(df) ]
    b = [ (s.bar, s.direction, round(s.stop, 6)) for s in mod.generate(df) ]
    assert a == b


def test_warmup_is_large_enough_for_every_strategy():
    """Signals must not be emitted before the strategy's declared warmup."""
    for name in REGISTRY:
        mod = get(name)
        df = kdata.make_synthetic(n=1200)
        for s in mod.generate(df):
            assert s.bar >= mod.WARMUP, f"{name} signalled at {s.bar} < warmup {mod.WARMUP}"
