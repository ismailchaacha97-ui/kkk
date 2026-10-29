"""Monte Carlo of the evaluation, and of the funded account after you pass.

The point of this module is to replace the two things prop-firm marketing relies on:

  1. "You can pass with 1% risk" -- without saying what that costs in months.
  2. "The payout is 80%" -- without saying what the probability of *reaching* a
     payout is, and how many re-buys the fee implies.

Everything here is pure standard library and seeded, so results are reproducible.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

from .rules import FUNDED, PHASE_1, PHASE_2, AccountPlan, PhaseRules

PASS = "PASS"
FAIL_DAILY = "FAIL_DAILY"
FAIL_TOTAL = "FAIL_TOTAL"
INCOMPLETE = "INCOMPLETE"


@dataclass(frozen=True)
class EdgeProfile:
    """Your strategy, reduced to the only four numbers that matter.

    win_prob / win_R come from a backtest *including* spread and commission in
    `cost_R`. `tail_prob` is the honest part most backtests omit: the occasional
    loss that is not 1R because a stop was gapped through. If you set tail_prob
    to 0 you are modelling a market that does not exist.
    """

    win_prob: float
    win_R: float = 1.8
    cost_R: float = 0.05
    tail_prob: float = 0.02
    tail_loss_R: float = 2.5
    trades_per_day: float = 3.0

    @property
    def expectancy_R(self) -> float:
        loss = (1 - self.tail_prob) * 1.0 + self.tail_prob * self.tail_loss_R
        return self.win_prob * self.win_R - (1 - self.win_prob) * loss - self.cost_R

    @property
    def profit_factor(self) -> float:
        gross_win = self.win_prob * self.win_R
        loss = (1 - self.tail_prob) * 1.0 + self.tail_prob * self.tail_loss_R
        gross_loss = (1 - self.win_prob) * loss + self.cost_R
        return gross_win / gross_loss if gross_loss > 0 else float("inf")

    def win_prob_for_expectancy(self, target_R: float) -> float:
        """Invert the expectancy formula: what hit-rate gives `target_R` per trade?"""
        loss = (1 - self.tail_prob) * 1.0 + self.tail_prob * self.tail_loss_R
        return (target_R + self.cost_R + loss) / (self.win_R + loss)

    def with_expectancy_scale(self, k: float) -> "EdgeProfile":
        """Same trade generator, degraded edge.

        Live performance is never the backtest. Scaling the *expectancy* (rather than
        the win rate) models the realistic case: the same setups, executed worse --
        more slippage, more missed entries, a regime that no longer pays.
        """
        return EdgeProfile(
            win_prob=self.win_prob_for_expectancy(self.expectancy_R * k),
            win_R=self.win_R,
            cost_R=self.cost_R,
            tail_prob=self.tail_prob,
            tail_loss_R=self.tail_loss_R,
            trades_per_day=self.trades_per_day,
        )


def _poisson(rng: random.Random, lam: float) -> int:
    if lam <= 0:
        return 0
    limit, k, p = pow(2.718281828459045, -lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def _sample_r(edge: EdgeProfile, rng: random.Random) -> float:
    if rng.random() < edge.win_prob:
        r = edge.win_R
    else:
        r = -1.0
        if rng.random() < edge.tail_prob:
            r = -edge.tail_loss_R
    return r - edge.cost_R


@dataclass
class PhaseResult:
    outcome: str
    days: int
    trading_days: int
    trades: int
    max_drawdown_pct: float
    return_pct: float


def simulate_phase(
    rules: PhaseRules,
    initial_balance: float,
    edge: EdgeProfile,
    risk_pct: float,
    rng: random.Random,
    daily_stop_R: float | None = 2.0,
    max_days: int = 260,
    lock_profits_at_target: bool = True,
    total_floor_reference: float | None = None,
) -> PhaseResult:
    """One attempt at one phase.

    `risk_pct` is a percentage of the *initial* balance, held constant. Raising risk
    after a loss is the martingale path: banned, and it is what makes the failure
    distribution have a fat left tail instead of a thin one.
    """
    risk_money = initial_balance * risk_pct / 100.0
    has_target = rules.profit_target_pct > 0
    target = rules.target_equity(initial_balance) if has_target else None
    # The maximum-loss floor is STATIC from the account's opening balance. On a funded
    # account it must not be re-based to the current balance each payout cycle --
    # doing that makes the account immortal and silently turns a losing system into a
    # "payout machine" that never dies.
    floor_ref = initial_balance if total_floor_reference is None else total_floor_reference
    total_floor = rules.total_loss_floor(floor_ref)
    equity = initial_balance
    peak = equity
    max_dd = 0.0
    trading_days = 0
    trades = 0
    locked = False

    for day in range(max_days):
        day_start = equity
        daily_floor = max(rules.daily_loss_floor(initial_balance, day_start), total_floor)
        day_r = 0.0
        n = _poisson(rng, edge.trades_per_day)
        reached_target = has_target and equity >= target

        if reached_target and lock_profits_at_target:
            # Target hit: stop taking risk, just satisfy the minimum-days rule.
            trading_days += 1
            locked = True
            if trading_days >= rules.min_trading_days:
                return PhaseResult(PASS, day + 1, trading_days, trades, max_dd, (equity / initial_balance - 1) * 100)
            continue

        if n > 0 and not reached_target:
            trading_days += 1

        for _ in range(n):
            r = _sample_r(edge, rng)
            equity += r * risk_money
            day_r += r
            trades += 1
            peak = max(peak, equity)
            max_dd = max(max_dd, (peak - equity) / peak * 100.0)

            if equity <= total_floor:
                return PhaseResult(FAIL_TOTAL, day + 1, trading_days, trades, max_dd, (equity / initial_balance - 1) * 100)
            if equity < daily_floor:
                return PhaseResult(FAIL_DAILY, day + 1, trading_days, trades, max_dd, (equity / initial_balance - 1) * 100)
            if has_target and equity >= target:
                break  # stop for the day once the target is reached
            if daily_stop_R is not None and day_r <= -daily_stop_R:
                break  # our own breaker, well before the firm's 5%

        if has_target and equity >= target and trading_days >= rules.min_trading_days:
            return PhaseResult(PASS, day + 1, trading_days, trades, max_dd, (equity / initial_balance - 1) * 100)

    return PhaseResult(INCOMPLETE, max_days, trading_days, trades, max_dd, (equity / initial_balance - 1) * 100)


@dataclass
class FundedResult:
    earnings: float        # trader's cash, after the profit split, before fee refund
    cycles_survived: int
    account_lost: bool
    max_drawdown_pct: float
    first_payout_received: bool = False   # the fee is only refunded once this is True


def simulate_funded(
    plan: AccountPlan,
    edge: EdgeProfile,
    risk_pct: float,
    rng: random.Random,
    cycles: int = 12,
    daily_stop_R: float | None = 2.0,
    withdraw_fraction: float = 1.0,
    buffer_target_pct: float | None = None,
) -> FundedResult:
    """Funded stage: no target, 10% static floor, payouts every ~14 days.

    `withdraw_fraction` is the payout policy and it is not a minor detail:

      1.00  take everything each cycle -> profits leave, losses stay, so the balance
            has a downward drift relative to a FIXED floor and the account dies with
            probability -> 1 as the horizon grows.
      0.50  leave half the cycle's profit in -> the buffer above the floor grows, and
            the account starts compounding instead of renting itself out.
    """
    balance = plan.initial_balance
    earnings = 0.0
    survived = 0
    max_dd = 0.0
    first_payout = False

    for _ in range(cycles):
        result = simulate_phase(
            rules=FUNDED,
            initial_balance=balance,
            edge=edge,
            risk_pct=risk_pct,
            rng=rng,
            daily_stop_R=daily_stop_R,
            max_days=plan.payout_cycle_trading_days,
            lock_profits_at_target=False,
            total_floor_reference=plan.initial_balance,  # static forever
        )
        max_dd = max(max_dd, result.max_drawdown_pct)
        profit = balance * result.return_pct / 100.0
        if buffer_target_pct is None:
            withdrawn = max(profit, 0.0) * withdraw_fraction
        else:
            # "Buffer, then withdraw": keep profits in the account until it sits
            # buffer_target_pct above its opening balance, then take everything above
            # that line. Simple enough to follow on a bad day.
            target = plan.initial_balance * (1.0 + buffer_target_pct / 100.0)
            excess = max(0.0, (balance + profit) - target)
            withdrawn = min(max(profit, 0.0), excess)
        payout = withdrawn * plan.profit_split
        earnings += payout
        if payout > 0:
            first_payout = True
        if result.outcome in (FAIL_DAILY, FAIL_TOTAL):
            return FundedResult(earnings, survived, True, max_dd, first_payout)
        survived += 1
        # Losses always stay in the account; only the withdrawn part leaves.
        balance += profit - withdrawn

    return FundedResult(earnings, survived, False, max_dd, first_payout)


def monte_carlo_phase(
    rules: PhaseRules,
    plan: AccountPlan,
    edge: EdgeProfile,
    risk_pct: float,
    n_trials: int = 20_000,
    daily_stop_R: float | None = 2.0,
    max_days: int = 260,
    seed: int = 20260101,
) -> dict:
    rng = random.Random(seed)
    outcomes = {PASS: 0, FAIL_DAILY: 0, FAIL_TOTAL: 0, INCOMPLETE: 0}
    days, dds, returns, trades = [], [], [], []
    for _ in range(n_trials):
        r = simulate_phase(rules, plan.initial_balance, edge, risk_pct, rng, daily_stop_R, max_days)
        outcomes[r.outcome] += 1
        if r.outcome == PASS:
            days.append(r.days)
        dds.append(r.max_drawdown_pct)
        returns.append(r.return_pct)
        trades.append(r.trades)

    days.sort()

    def pct(xs: list[float], q: float) -> float:
        if not xs:
            return float("nan")
        return xs[min(len(xs) - 1, int(q * len(xs)))]

    return {
        "p_pass": outcomes[PASS] / n_trials,
        "p_fail_daily": outcomes[FAIL_DAILY] / n_trials,
        "p_fail_total": outcomes[FAIL_TOTAL] / n_trials,
        "p_incomplete": outcomes[INCOMPLETE] / n_trials,
        "median_days_to_pass": pct(days, 0.5),
        "p90_days_to_pass": pct(days, 0.9),
        "median_max_dd_pct": pct(sorted(dds), 0.5),
        "p95_max_dd_pct": pct(sorted(dds), 0.95),
        "median_trades": pct(sorted(trades), 0.5),
        "outcomes": outcomes,
    }


def monte_carlo_funded(
    plan: AccountPlan,
    edge: EdgeProfile,
    risk_pct: float,
    n_trials: int = 10_000,
    cycles: int = 12,
    daily_stop_R: float | None = 2.0,
    seed: int = 20260202,
    withdraw_fraction: float = 1.0,
    buffer_target_pct: float | None = None,
) -> dict:
    rng = random.Random(seed)
    earnings, survived, lost, paid = [], [], 0, 0
    for _ in range(n_trials):
        r = simulate_funded(plan, edge, risk_pct, rng, cycles, daily_stop_R,
                            withdraw_fraction, buffer_target_pct)
        earnings.append(r.earnings)
        survived.append(r.cycles_survived)
        lost += int(r.account_lost)
        paid += int(r.first_payout_received)
    earnings.sort()
    return {
        "mean_earnings": sum(earnings) / n_trials,
        "median_earnings": earnings[n_trials // 2],
        "p10_earnings": earnings[int(0.10 * n_trials)],
        "p_account_lost": lost / n_trials,
        "p_first_payout": paid / n_trials,
        "withdraw_fraction": withdraw_fraction,
        "mean_cycles_survived": sum(survived) / n_trials,
    }


def evaluate_plan(
    plan: AccountPlan,
    edge: EdgeProfile,
    risk_pct: float,
    daily_stop_R: float | None = 2.0,
    n_trials: int = 20_000,
    funded_cycles: int = 12,
    payout_buffer_pct: float | None = None,
) -> dict:
    """Full path: pay fee -> phase 1 -> phase 2 -> funded cycles -> payouts."""
    p1 = monte_carlo_phase(
        rules=PHASE_1, plan=plan, edge=edge, risk_pct=risk_pct,
        n_trials=n_trials, daily_stop_R=daily_stop_R, max_days=260,
    )
    p2 = monte_carlo_phase(
        rules=PHASE_2, plan=plan, edge=edge, risk_pct=risk_pct,
        n_trials=max(n_trials // 2, 2000), daily_stop_R=daily_stop_R, max_days=260,
    )
    p_funded = p1["p_pass"] * p2["p_pass"]
    funded = monte_carlo_funded(
        plan=plan, edge=edge, risk_pct=risk_pct,
        n_trials=max(n_trials // 4, 1000), cycles=funded_cycles, daily_stop_R=daily_stop_R,
        buffer_target_pct=payout_buffer_pct,
    )

    # The fee is refunded only when a *first payout actually happens* -- passing and
    # then dying before payout gets you nothing back. Crediting the refund on every
    # pass is the error that makes break-even strategies look profitable.
    p_refund = p_funded * funded["p_first_payout"] * (1.0 if plan.fee_refunded_on_first_payout else 0.0)
    ev_per_attempt = -plan.fee + p_funded * funded["mean_earnings"] + p_refund * plan.fee
    expected_attempts = 1.0 / p_funded if p_funded > 0 else float("inf")
    break_even_profit = plan.break_even_funded_profit(p_funded)

    return {
        "plan": plan.size_label,
        "risk_pct": risk_pct,
        "daily_stop_R": daily_stop_R,
        "expectancy_R": edge.expectancy_R,
        "phase1": p1,
        "phase2": p2,
        "p_reach_funded": p_funded,
        "expected_challenge_purchases": expected_attempts,
        "total_expected_fee": expected_attempts * plan.fee,
        "funded": funded,
        "ev_per_attempt": ev_per_attempt,
        "p_first_payout_abs": p_funded * funded["p_first_payout"],
        "break_even_funded_profit": break_even_profit,
    }
