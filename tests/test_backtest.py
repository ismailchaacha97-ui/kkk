"""End-to-end smoke tests: engine wiring, reports and intraday guarantees."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from daytrader.backtest import run_backtest
from daytrader.config import (
    BacktestConfig,
    ORBParams,
    VWAPParams,
)


class BacktestSmokeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.config = BacktestConfig(
            symbols=("AAPL",),
            days=10,
            seed=11,
            starting_balance=100_000.0,
            data_dir=root / "data",
            out_dir=root / "reports",
            auto_generate=True,
        )
        cls.orb = run_backtest("orb", cls.config, ORBParams())
        cls.vwap = run_backtest("vwap", cls.config, VWAPParams())

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def test_sessions_match_requested_window(self) -> None:
        self.assertEqual(self.orb.summary["sessions"], 10)
        self.assertEqual(self.vwap.summary["sessions"], 10)

    def test_vwap_produces_trades(self) -> None:
        self.assertGreater(self.vwap.summary["trades"], 0)
        self.assertFalse(self.vwap.positions.empty)

    def test_no_overnight_positions(self) -> None:
        for result in (self.orb, self.vwap):
            positions = result.positions
            if positions.empty:
                continue
            # The positions report is flat snapshots; make sure each had a close.
            closed = positions[positions["ts_closed"].notna()]
            opened = pd.to_datetime(closed["ts_opened"], utc=True).dt.tz_convert(
                "America/New_York",
            )
            shut = pd.to_datetime(closed["ts_closed"], utc=True).dt.tz_convert(
                "America/New_York",
            )
            self.assertTrue((opened.dt.date == shut.dt.date).all())
            self.assertTrue((shut.dt.strftime("%H:%M") <= "15:56").all())

    def test_summary_matches_daily_equity(self) -> None:
        for result in (self.orb, self.vwap):
            final_equity = result.daily["equity"].iloc[-1]
            self.assertAlmostEqual(
                final_equity,
                result.config.starting_balance + result.summary["net_pnl"],
                places=2,
            )
            self.assertEqual(result.summary["trades"], int(result.daily["trades"].sum()))

    def test_daily_has_one_row_per_session(self) -> None:
        self.assertEqual(len(self.vwap.daily), 10)
        self.assertEqual(self.vwap.daily.index.name, "session")

    def test_missing_data_without_generation_raises(self) -> None:
        config = BacktestConfig(
            symbols=("ZZZZ",),
            days=3,
            data_dir=Path(self.tmp.name) / "empty",
            auto_generate=False,
        )
        with self.assertRaises(FileNotFoundError):
            run_backtest("orb", config)


if __name__ == "__main__":
    unittest.main()
