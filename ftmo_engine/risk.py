"""Position sizing and the daily circuit breaker.

This is the half of the system that decides whether the account survives. Entry
signals are cheap; what kills prop accounts is a size decision made under stress.
So sizing is deterministic, computed from the *initial* balance, and never
re-derived from current equity mid-challenge.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from .rules import PhaseRules


@dataclass(frozen=True)
class SymbolSpec:
    """Broker-side contract details you must read, not assume."""

    name: str
    pip_size: float = 0.0001
    pip_value_per_lot: float = 10.0   # account-currency value of 1 pip on 1.00 lot
    lot_step: float = 0.01
    min_lot: float = 0.01
    max_lot: float = 100.0
    stop_level_points: float = 0.0    # broker MODE_STOPLEVEL, in points
    usd_sign: int = 0                 # +1 long USD, -1 short USD, 0 not a USD pair

    def round_lots(self, lots: float) -> float:
        """Floor to the broker's lot step -- never round up into more risk."""
        if lots <= 0:
            return 0.0
        steps = math.floor(lots / self.lot_step + 1e-9)
        lots = steps * self.lot_step
        lots = min(lots, self.max_lot)
        return round(lots, 8) if lots >= self.min_lot else 0.0


EURUSD = SymbolSpec("EURUSD", 0.0001, 10.0, 0.01, 0.01, 100.0, 0.0, +1)
GBPUSD = SymbolSpec("GBPUSD", 0.0001, 10.0, 0.01, 0.01, 100.0, 0.0, +1)
AUDUSD = SymbolSpec("AUDUSD", 0.0001, 10.0, 0.01, 0.01, 100.0, 0.0, +1)
USDCHF = SymbolSpec("USDCHF", 0.0001, 10.0, 0.01, 0.01, 100.0, 0.0, -1)
USDJPY = SymbolSpec("USDJPY", 0.01, 6.7, 0.01, 0.01, 100.0, 0.0, -1)
XAUUSD = SymbolSpec("XAUUSD", 0.1, 10.0, 0.01, 0.01, 100.0, 0.0, -1)


def lots_for_risk(
    balance: float,
    risk_pct: float,
    stop_pips: float,
    spec: SymbolSpec,
) -> float:
    """Fixed-fractional sizing off the *stop distance*, not a balance/10000 guess.

    risk_$ = balance * risk_pct/100
    lots   = risk_$ / (stop_pips * pip_value_per_lot)
    """
    if stop_pips <= 0 or risk_pct <= 0 or balance <= 0:
        return 0.0
    risk_money = balance * risk_pct / 100.0
    raw = risk_money / (stop_pips * spec.pip_value_per_lot)
    return spec.round_lots(raw)


def stop_pips_ok(stop_pips: float, spec: SymbolSpec, spread_pips: float) -> bool:
    """Reject stops the broker will refuse (and that are eaten by spread anyway)."""
    # broker stop level is quoted in points; a pip is 10 points on both 5-digit
    # (0.0001) and 3-digit-style JPY (0.01) quotes
    min_pips = spec.stop_level_points / 10.0
    return stop_pips >= max(min_pips, spread_pips * 2.0)


@dataclass
class DailyGuard:
    """Self-imposed circuit breaker, always tighter than the firm's limit.

    The firm gives 5% daily. We stop at `self_imposed_daily_pct` (default 2%).
    The 3-point gap is not caution, it is arithmetic: it keeps a single bad day
    from ending the whole evaluation and lets the account recover.
    """

    plan_initial_balance: float
    rules: PhaseRules
    self_imposed_daily_pct: float = 2.0
    max_trades_per_day: int = 3
    max_consecutive_losses: int = 2

    day_start_balance: float = field(init=False)
    realized_pnl: float = 0.0
    losses_today: int = 0
    trades_today: int = 0
    halted: bool = False

    def __post_init__(self) -> None:
        self.day_start_balance = self.plan_initial_balance

    # -- lifecycle ---------------------------------------------------------
    def new_day(self, closing_balance: float) -> None:
        self.day_start_balance = closing_balance
        self.realized_pnl = 0.0
        self.losses_today = 0
        self.trades_today = 0
        self.halted = False

    def firm_daily_floor(self) -> float:
        return self.rules.daily_loss_floor(self.plan_initial_balance, self.day_start_balance)

    def self_daily_floor(self) -> float:
        return self.day_start_balance * (1.0 - self.self_imposed_daily_pct / 100.0)

    def effective_floor(self) -> float:
        """Whichever bites first: our stop, or theirs."""
        return max(self.firm_daily_floor(), self.self_daily_floor())

    # -- gates -------------------------------------------------------------
    def can_open(self, risk_money: float, equity: float) -> tuple[bool, str]:
        if self.halted:
            return False, "daily guard halted"
        if self.trades_today >= self.max_trades_per_day:
            return False, "max trades per day"
        if self.losses_today >= self.max_consecutive_losses:
            return False, "max consecutive losses"
        # Never let one trade be able to breach the firm's daily limit by itself.
        if equity - risk_money < self.firm_daily_floor():
            return False, "one loss would breach the firm daily floor"
        if equity - risk_money < self.effective_floor():
            return False, "would breach self-imposed daily stop"
        return True, "ok"

    def register(self, r_multiple: float, risk_money: float, equity_after: float) -> None:
        self.realized_pnl += r_multiple * risk_money
        self.trades_today += 1
        if r_multiple < 0:
            self.losses_today += 1
        if equity_after <= self.effective_floor():
            self.halted = True


def net_usd_exposure(open_positions: list[tuple[SymbolSpec, float]]) -> float:
    """Sum of lot-weighted USD direction exposure (long USD positive).

    Correlated pairs are one bet, not three. FTMO's ban is on hedging *across*
    accounts; stacking EURUSD-long + GBPUSD-long + USDCHF-short is the same trade
    three times and will hit the 10% floor in one correlated move.
    """
    total = 0.0
    for spec, lots in open_positions:
        total += spec.usd_sign * lots
    return total


def exposure_within_cap(
    open_positions: list[tuple[SymbolSpec, float]],
    candidate: tuple[SymbolSpec, float],
    cap_in_ref_lots: float = 1.5,
) -> bool:
    current = abs(net_usd_exposure(open_positions))
    projected = abs(net_usd_exposure(open_positions + [candidate]))
    return projected <= max(cap_in_ref_lots, current)
