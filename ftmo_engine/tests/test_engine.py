"""Tests for the risk model. Run: python3 -m unittest discover -s ftmo_engine/tests -t .
"""

from __future__ import annotations

import random
import unittest

from ftmo_engine.mc import EdgeProfile, monte_carlo_funded, simulate_phase
from ftmo_engine.rules import PHASE_1, PLANS, PhaseRules
from ftmo_engine.risk import (
    EURUSD,
    USDCHF,
    DailyGuard,
    lots_for_risk,
    net_usd_exposure,
)


class TestRules(unittest.TestCase):
    def test_target_and_floor(self):
        self.assertAlmostEqual(PHASE_1.target_equity(100_000), 110_000)
        self.assertAlmostEqual(PHASE_1.total_loss_floor(100_000), 90_000)

    def test_daily_basis_is_stricter_from_day_start(self):
        day_start = 103_000
        strict = PHASE_1.daily_loss_floor(100_000, day_start)
        # 5% of the *higher* day-start balance is a tighter floor than 5% of initial
        self.assertAlmostEqual(strict, 103_000 * 0.95)
        self.assertGreater(strict, 95_000)

    def test_floor_never_moves_up_with_profit(self):
        # static drawdown: the floor depends only on the initial balance
        self.assertEqual(PHASE_1.total_loss_floor(100_000), PHASE_1.total_loss_floor(100_000))

    def test_no_target_phase(self):
        funded = PhaseRules("f", 0.0, 5.0, 10.0, 0)
        self.assertEqual(funded.target_equity(100_000), 100_000)


class TestSizing(unittest.TestCase):
    def test_fixed_fractional(self):
        # 0.5% of 100k = $500; 25 pips * $10/pip = $250 per lot -> 2.00 lots
        self.assertAlmostEqual(lots_for_risk(100_000, 0.5, 25, EURUSD), 2.0)

    def test_rounds_down_never_up(self):
        # 0.3% of 100k = $300 -> 1.2 lots at 25 pips; with step 0.1 -> 1.2 exactly
        self.assertAlmostEqual(lots_for_risk(100_000, 0.3, 25, EURUSD), 1.2)
        # a size that lands between steps must floor, not round up
        tiny = lots_for_risk(10_000, 0.13, 25, EURUSD)  # $13 -> 0.052 -> 0.05
        self.assertAlmostEqual(tiny, 0.05)

    def test_below_min_lot_returns_zero(self):
        # $200 * 0.5% = $1 of risk -> 0.002 lots, below the 0.01 minimum
        self.assertEqual(lots_for_risk(200, 0.5, 50, EURUSD), 0.0)

    def test_min_lot_boundary_is_kept(self):
        # $1000 * 0.5% = $5 = exactly 0.01 lots on a 50-pip stop: tradeable
        self.assertAlmostEqual(lots_for_risk(1_000, 0.5, 50, EURUSD), 0.01)

    def test_zero_inputs(self):
        self.assertEqual(lots_for_risk(100_000, 0, 25, EURUSD), 0.0)
        self.assertEqual(lots_for_risk(100_000, 0.5, 0, EURUSD), 0.0)


class TestDailyGuard(unittest.TestCase):
    def setUp(self):
        self.guard = DailyGuard(100_000, PHASE_1, self_imposed_daily_pct=2.0,
                                max_trades_per_day=3, max_consecutive_losses=2)

    def test_blocks_trade_that_could_breach_firm_floor(self):
        # equity already down 8%; a 2% risk could reach the 10% floor in one hit
        ok, why = self.guard.can_open(2_000, 92_000)
        self.assertFalse(ok)
        self.assertIn("floor", why)

    def test_blocks_on_consecutive_losses(self):
        self.guard.register(-1.0, 500, 99_500)
        self.guard.register(-1.0, 500, 99_000)
        ok, why = self.guard.can_open(500, 99_000)
        self.assertFalse(ok)
        self.assertEqual(why, "max consecutive losses")

    def test_blocks_after_max_trades(self):
        for _ in range(3):
            self.guard.register(+1.0, 500, 101_500)
        ok, _ = self.guard.can_open(500, 101_500)
        self.assertFalse(ok)

    def test_new_day_resets(self):
        self.guard.register(-1.0, 500, 99_500)
        self.guard.new_day(99_500)
        ok, why = self.guard.can_open(500, 99_500)
        self.assertTrue(ok, why)

    def test_halt_when_self_floor_hit(self):
        self.guard.register(-2.0, 1_000, 98_000)
        self.assertTrue(self.guard.halted)


class TestExposure(unittest.TestCase):
    def test_signed_net_exposure(self):
        # long EURUSD and long USDCHF are not the same bet: +1 and -1 cancel
        self.assertEqual(net_usd_exposure([(EURUSD, 1.0), (USDCHF, 1.0)]), 0.0)

    def test_stacking_correlated_longs(self):
        self.assertEqual(net_usd_exposure([(EURUSD, 1.0), (USDCHF, -0.5)]), 1.5)


class TestSimulation(unittest.TestCase):
    def test_reproducible(self):
        e = EdgeProfile(win_prob=0.45)
        a = simulate_phase(PHASE_1, 100_000, e, 0.5, random.Random(7), max_days=60)
        b = simulate_phase(PHASE_1, 100_000, e, 0.5, random.Random(7), max_days=60)
        self.assertEqual(a, b)

    def test_better_edge_passes_more_often(self):
        good = EdgeProfile(win_prob=0.50)
        bad = EdgeProfile(win_prob=0.40)
        rng = random.Random(11)
        good_passes = sum(
            simulate_phase(PHASE_1, 100_000, good, 0.5, rng, max_days=200).outcome == "PASS"
            for _ in range(200)
        )
        bad_passes = sum(
            simulate_phase(PHASE_1, 100_000, bad, 0.5, rng, max_days=200).outcome == "PASS"
            for _ in range(200)
        )
        self.assertGreater(good_passes, bad_passes)

    def test_oversizing_reduces_survival(self):
        e = EdgeProfile(win_prob=0.45)
        rng = random.Random(3)
        small = sum(simulate_phase(PHASE_1, 100_000, e, 0.5, rng, max_days=200).outcome == "PASS"
                    for _ in range(300))
        large = sum(simulate_phase(PHASE_1, 100_000, e, 3.0, rng, max_days=200).outcome == "PASS"
                    for _ in range(300))
        self.assertGreater(small, large)

    def test_zero_edge_funded_account_eventually_dies(self):
        """The floor is static; withdraw-everything must not be immortal."""
        flat = EdgeProfile(win_prob=0.45).with_expectancy_scale(0.0)
        self.assertAlmostEqual(flat.expectancy_R, 0.0, places=6)
        res = monte_carlo_funded(PLANS["100K"], flat, 0.5, n_trials=400, cycles=52,
                                 withdraw_fraction=1.0)
        self.assertGreater(res["p_account_lost"], 0.85)

    def test_buffer_policy_beats_take_all(self):
        e = EdgeProfile(win_prob=0.45)
        take_all = monte_carlo_funded(PLANS["100K"], e, 0.5, n_trials=800, cycles=52,
                                      withdraw_fraction=1.0)
        buffered = monte_carlo_funded(PLANS["100K"], e, 0.5, n_trials=800, cycles=52,
                                      buffer_target_pct=15.0)
        self.assertGreater(buffered["mean_earnings"], take_all["mean_earnings"])
        self.assertLess(buffered["p_account_lost"], take_all["p_account_lost"])

    def test_min_trading_days_respected(self):
        e = EdgeProfile(win_prob=0.60)  # very strong: reaches target fast
        rng = random.Random(5)
        for _ in range(50):
            r = simulate_phase(PHASE_1, 100_000, e, 2.0, rng, max_days=100)
            if r.outcome == "PASS":
                self.assertGreaterEqual(r.trading_days, PHASE_1.min_trading_days)


if __name__ == "__main__":
    unittest.main()
