"""FTMO-style evaluation rules as an executable, versioned model.

Everything that a "prop firm model" can do to you is encoded here as a number or a
boolean, so the rest of the engine never has to guess. Rule values are the public
2-Step terms as of late 2025 / early 2026 -- verify against ftmo.com before you buy,
because firms change these without much notice.

Deliberate design choice: where the public wording is ambiguous (e.g. whether the 5%
daily limit is computed off the day's starting balance or the initial balance), the
default is the *stricter* interpretation. Modelling a rule more generously than the
firm does is how people fail challenges by one dollar.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class PhaseRules:
    """Objective + loss limits for one evaluation phase."""

    name: str
    profit_target_pct: float
    max_daily_loss_pct: float
    max_total_loss_pct: float
    min_trading_days: int
    daily_basis: str = "day_start"  # "day_start" (stricter) or "initial"

    def target_equity(self, initial_balance: float) -> float:
        return initial_balance * (1.0 + self.profit_target_pct / 100.0)

    def total_loss_floor(self, initial_balance: float) -> float:
        """Static floor: never moves as you profit."""
        return initial_balance * (1.0 - self.max_total_loss_pct / 100.0)

    def daily_loss_floor(self, initial_balance: float, day_start_balance: float) -> float:
        basis = day_start_balance if self.daily_basis == "day_start" else initial_balance
        return basis * (1.0 - self.max_daily_loss_pct / 100.0)


PHASE_1 = PhaseRules(
    name="Challenge",
    profit_target_pct=10.0,
    max_daily_loss_pct=5.0,
    max_total_loss_pct=10.0,
    min_trading_days=4,
)

PHASE_2 = PhaseRules(
    name="Verification",
    profit_target_pct=5.0,
    max_daily_loss_pct=5.0,
    max_total_loss_pct=10.0,
    min_trading_days=4,
)

FUNDED = PhaseRules(
    name="FTMO Account",
    profit_target_pct=0.0,  # no target; the objective becomes "survive and withdraw"
    max_daily_loss_pct=5.0,
    max_total_loss_pct=10.0,
    min_trading_days=0,
)


@dataclass(frozen=True)
class AccountPlan:
    """Commercial terms of one challenge purchase."""

    size_label: str
    initial_balance: float
    fee: float
    profit_split: float = 0.80          # 0.80 base, 0.90 after scaling
    fee_refunded_on_first_payout: bool = True
    payout_cycle_trading_days: int = 10  # 14 calendar days ~= 10 trading days
    max_accounts_per_strategy: int = 400_000  # combined allocation cap, USD

    def first_payout_net(self, profit: float) -> float:
        """Trader's cash from a payout cycle, before the one-off fee refund."""
        return max(profit, 0.0) * self.profit_split

    def break_even_funded_profit(self, p_reach_funded: float) -> float:
        """Profit the funded account must generate, on average, to repay the fees.

        If the fee is refunded on the first payout the trader recovers it as soon as
        the first payout happens, so we net it out here rather than pretending the
        challenge is free.
        """
        if p_reach_funded <= 0:
            return float("inf")
        gross_needed = self.fee / (p_reach_funded * self.profit_split)
        return max(gross_needed - self.fee, 0.0)


# Public price points. Sizes not listed are simply not modelled.
PLANS: dict[str, AccountPlan] = {
    "10K": AccountPlan("10K", 10_000, fee=155),
    "25K": AccountPlan("25K", 25_000, fee=250),
    "50K": AccountPlan("50K", 50_000, fee=345),
    "100K": AccountPlan("100K", 100_000, fee=540),
    "200K": AccountPlan("200K", 200_000, fee=1080),
}


@dataclass(frozen=True)
class ConductRules:
    """Non-numeric rules that void accounts even when the equity curve is clean."""

    max_server_requests_per_day: int = 2000
    news_blackout_minutes: int = 2          # Normal accounts only; Swing exempt
    allow_weekend_hold: bool = False        # Normal accounts: no
    allow_martingale: bool = False
    allow_multi_account_hedging: bool = False
    allow_copying_third_party_signals: bool = False
    max_single_trade_risk_pct: float = 2.0  # internal, not an FTMO rule


CONDUCT = ConductRules()
