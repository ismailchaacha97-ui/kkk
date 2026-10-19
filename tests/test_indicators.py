"""Unit tests for the pure pandas/numpy indicators."""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from daytrader.indicators import (
    atr,
    opening_range,
    session_vwap,
    session_vwap_bands,
    true_range,
)


def _frame(rows: list[tuple[float, float, float, float]], day: str = "2026-01-05") -> pd.DataFrame:
    index = pd.date_range(f"{day} 09:30", periods=len(rows), freq="1min", tz="America/New_York")
    return pd.DataFrame(
        [
            {"open": open_, "high": high, "low": low, "close": close, "volume": 1000.0}
            for open_, high, low, close in rows
        ],
        index=index,
    )


class IndicatorTests(unittest.TestCase):
    def test_true_range_uses_previous_close(self) -> None:
        frame = _frame(
            [
                (10.0, 11.0, 9.0, 10.5),
                (10.5, 12.0, 10.0, 11.5),
            ],
        )
        tr = true_range(frame["high"], frame["low"], frame["close"])
        self.assertAlmostEqual(tr.iloc[0], 2.0)
        # max(high-low=2.0, |12-10.5|=1.5, |10-10.5|=0.5)
        self.assertAlmostEqual(tr.iloc[1], 2.0)

    def test_atr_warmup_and_value(self) -> None:
        frame = _frame([(10.0, 11.0, 9.0, 10.0)] * 5)
        result = atr(frame["high"], frame["low"], frame["close"], period=3)
        self.assertTrue(math.isnan(result.iloc[1]))
        self.assertFalse(math.isnan(result.iloc[2]))
        self.assertAlmostEqual(result.iloc[2], 2.0)
        self.assertAlmostEqual(result.iloc[4], 2.0)

    def test_opening_range(self) -> None:
        frame = _frame(
            [
                (10.0, 10.5, 9.8, 10.2),
                (10.2, 10.9, 10.0, 10.7),
                (10.7, 11.0, 10.5, 10.8),
                (10.8, 12.0, 10.7, 11.9),
            ],
        )
        high, low = opening_range(frame["high"], frame["low"], 3)
        self.assertAlmostEqual(high, 11.0)
        self.assertAlmostEqual(low, 9.8)

    def test_opening_range_requires_enough_bars(self) -> None:
        frame = _frame([(10.0, 10.5, 9.8, 10.2)] * 2)
        with self.assertRaises(ValueError):
            opening_range(frame["high"], frame["low"], 3)

    def test_session_vwap_resets_each_day(self) -> None:
        day_one = _frame([(10.0, 10.0, 10.0, 10.0), (10.0, 12.0, 10.0, 12.0)])
        day_two = _frame([(20.0, 20.0, 20.0, 20.0)], day="2026-01-06")
        frame = pd.concat([day_one, day_two])
        vwap = session_vwap(frame)
        # First session: typical prices 10 and 10.667, equal volume.
        self.assertAlmostEqual(vwap.iloc[0], 10.0)
        self.assertAlmostEqual(vwap.iloc[1], (10.0 + (12.0 + 10.0 + 12.0) / 3.0) / 2.0)
        # Second session starts fresh at 20, not diluted by day one.
        self.assertAlmostEqual(vwap.iloc[2], 20.0)

    def test_vwap_bands_are_ordered(self) -> None:
        frame = _frame(
            [
                (10.0, 10.2, 9.8, 10.0),
                (10.0, 10.4, 9.9, 10.3),
                (10.3, 10.5, 10.1, 10.2),
            ],
        )
        bands = session_vwap_bands(frame, band_k=2.0)
        self.assertAlmostEqual(bands["vwap"].iloc[-1], session_vwap(frame).iloc[-1])
        self.assertGreater(bands["upper"].iloc[-1], bands["vwap"].iloc[-1])
        self.assertLess(bands["lower"].iloc[-1], bands["vwap"].iloc[-1])
        self.assertTrue(math.isnan(bands["upper"].iloc[0]) is False)


if __name__ == "__main__":
    unittest.main()
