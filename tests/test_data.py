"""Tests for the synthetic generator and CSV loader."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from daytrader import MARKET_TZ
from daytrader.data import (
    generate_synthetic_bars,
    load_bars,
    resample_bars,
    save_bars,
    validate_bars,
)
from daytrader.instruments import (
    bar_type_for,
    make_equity,
)


class SyntheticDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.frames = generate_synthetic_bars(
            symbols=("AAPL", "NVDA"),
            start_date="2026-01-05",
            days=3,
            seed=1,
        )

    def test_bar_count_and_sessions(self) -> None:
        for frame in self.frames.values():
            self.assertEqual(len(frame), 3 * 390)
            self.assertEqual(frame.index.normalize().nunique(), 3)
            self.assertEqual(str(frame.index.tz), MARKET_TZ)

    def test_ohlcv_invariants(self) -> None:
        for symbol, frame in self.frames.items():
            validate_bars(frame, symbol)
            self.assertGreater(frame["volume"].min(), 0)
            self.assertTrue((frame["high"] >= frame["low"]).all())

    def test_sessions_start_at_0930(self) -> None:
        frame = self.frames["AAPL"]
        first_bar = frame.index[0]
        self.assertEqual((first_bar.hour, first_bar.minute), (9, 30))
        last_bar = frame.index[-1]
        self.assertEqual((last_bar.hour, last_bar.minute), (15, 59))

    def test_deterministic_for_same_seed(self) -> None:
        again = generate_synthetic_bars(
            symbols=("AAPL", "NVDA"),
            start_date="2026-01-05",
            days=3,
            seed=1,
        )
        for symbol in self.frames:
            pd.testing.assert_frame_equal(self.frames[symbol], again[symbol])

    def test_different_seed_changes_prices(self) -> None:
        other = generate_synthetic_bars(
            symbols=("AAPL",),
            start_date="2026-01-05",
            days=3,
            seed=2,
        )
        self.assertFalse(
            self.frames["AAPL"]["close"].equals(other["AAPL"]["close"]),
        )

    def test_symbol_order_does_not_change_a_symbol(self) -> None:
        reversed_order = generate_synthetic_bars(
            symbols=("NVDA", "AAPL"),
            start_date="2026-01-05",
            days=3,
            seed=1,
        )
        pd.testing.assert_frame_equal(self.frames["AAPL"], reversed_order["AAPL"])

    def test_resample_preserves_ohlc(self) -> None:
        frame = self.frames["AAPL"]
        five = resample_bars(frame, 5)
        self.assertEqual(len(five), 3 * 78)
        first = five.iloc[0]
        window = frame.iloc[:5]
        self.assertAlmostEqual(first["open"], window["open"].iloc[0])
        self.assertAlmostEqual(first["high"], window["high"].max())
        self.assertAlmostEqual(first["low"], window["low"].min())
        self.assertAlmostEqual(first["close"], window["close"].iloc[-1])
        self.assertAlmostEqual(first["volume"], window["volume"].sum())


class CsvLoaderTests(unittest.TestCase):
    def _write(self, directory: Path, frame: pd.DataFrame, naive: bool = False) -> Path:
        path = directory / "TEST_1min.csv"
        output = frame.reset_index()
        if naive:
            output["timestamp"] = output["timestamp"].dt.tz_localize(None)
        output.to_csv(path, index=False)
        return path

    def test_save_and_load_roundtrip(self) -> None:
        frame = generate_synthetic_bars(("AAPL",), days=1, seed=3)["AAPL"]
        instrument = make_equity("TEST")
        with tempfile.TemporaryDirectory() as tmp:
            path = save_bars(frame, Path(tmp) / "AAPL_1min.csv")
            bars = load_bars(path, instrument, bar_type_for(instrument))
        self.assertEqual(len(bars), 390)
        self.assertAlmostEqual(bars[0].open.as_double(), round(frame["open"].iloc[0], 2))
        self.assertAlmostEqual(bars[-1].close.as_double(), round(frame["close"].iloc[-1], 2))
        self.assertEqual(int(bars[0].volume), int(frame["volume"].iloc[0]))

    def test_naive_timestamps_are_treated_as_exchange_time(self) -> None:
        frame = generate_synthetic_bars(("AAPL",), days=1, seed=4)["AAPL"]
        instrument = make_equity("TEST")
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write(Path(tmp), frame, naive=True)
            bars = load_bars(path, instrument, bar_type_for(instrument))
        expected = pd.Timestamp("2026-01-05 14:30", tz="UTC").value
        self.assertEqual(bars[0].ts_event, expected)

    def test_date_and_time_columns_are_supported(self) -> None:
        frame = generate_synthetic_bars(("AAPL",), days=1, seed=5)["AAPL"]
        instrument = make_equity("TEST")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "TEST_1min.csv"
            output = frame.reset_index()
            output["date"] = output["timestamp"].dt.strftime("%Y-%m-%d")
            output["time"] = output["timestamp"].dt.strftime("%H:%M:%S")
            output.drop(columns=["timestamp"]).to_csv(path, index=False)
            bars = load_bars(path, instrument, bar_type_for(instrument))
        self.assertEqual(len(bars), 390)

    def test_invalid_ohlc_is_rejected(self) -> None:
        frame = generate_synthetic_bars(("AAPL",), days=1, seed=6)["AAPL"].copy()
        frame.iloc[0, frame.columns.get_loc("high")] = frame["low"].iloc[0] - 1.0
        instrument = make_equity("TEST")
        with tempfile.TemporaryDirectory() as tmp:
            path = save_bars(frame, Path(tmp) / "BAD_1min.csv")
            with self.assertRaises(ValueError):
                load_bars(path, instrument, bar_type_for(instrument))

    def test_missing_columns_raise(self) -> None:
        frame = generate_synthetic_bars(("AAPL",), days=1, seed=7)["AAPL"]
        instrument = make_equity("TEST")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "TEST_1min.csv"
            frame.drop(columns=["volume"]).reset_index().to_csv(path, index=False)
            # Volume is optional in the loader, so this should succeed.
            bars = load_bars(path, instrument, bar_type_for(instrument))
            self.assertEqual(len(bars), 390)

            broken = Path(tmp) / "BROKEN_1min.csv"
            frame.drop(columns=["close"]).reset_index().to_csv(broken, index=False)
            with self.assertRaises(ValueError):
                load_bars(broken, instrument, bar_type_for(instrument))


if __name__ == "__main__":
    unittest.main()
