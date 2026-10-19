"""Unit tests for risk-based position sizing."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from daytrader.risk import size_position


class SizePositionTests(unittest.TestCase):
    def test_notional_cap_binds(self) -> None:
        # $500 risk budget / $1 stop distance = 500 shares, but 25 % of
        # $100k at $100 = 250 shares.
        qty = size_position(100_000, 100.0, 99.0, risk_pct=0.5, max_notional_pct=25)
        self.assertEqual(qty, 250)

    def test_risk_budget_binds(self) -> None:
        # $500 / $10 = 50 shares, well below the notional cap.
        qty = size_position(100_000, 100.0, 90.0, risk_pct=0.5, max_notional_pct=25)
        self.assertEqual(qty, 50)

    def test_stop_above_entry_is_symmetric(self) -> None:
        long_qty = size_position(50_000, 200.0, 196.0, risk_pct=1.0, max_notional_pct=100)
        short_qty = size_position(50_000, 200.0, 204.0, risk_pct=1.0, max_notional_pct=100)
        self.assertEqual(long_qty, short_qty)
        self.assertEqual(long_qty, 125)

    def test_lot_size_rounding(self) -> None:
        qty = size_position(100_000, 100.0, 99.0, risk_pct=0.5, max_notional_pct=25, lot_size=10)
        self.assertEqual(qty % 10, 0)
        self.assertEqual(qty, 250)

    def test_invalid_inputs_return_zero(self) -> None:
        self.assertEqual(size_position(0, 100, 99), 0)
        self.assertEqual(size_position(100_000, 100, 100), 0)
        self.assertEqual(size_position(100_000, 100, 99, risk_pct=0), 0)
        self.assertEqual(size_position(100_000, 100, 99, max_notional_pct=0), 0)
        self.assertEqual(size_position(100_000, 0, 99), 0)
        # Risk too small to buy even one share.
        self.assertEqual(size_position(1_000, 100, 99, risk_pct=0.01), 0)


if __name__ == "__main__":
    unittest.main()
