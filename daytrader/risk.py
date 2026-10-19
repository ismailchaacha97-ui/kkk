"""Risk-based position sizing.

Day-trading sizing is driven by the distance to the protective stop, not by a
fixed share count. If a setup's stop is too wide, the trade is skipped rather
than sized up; if the stop is very tight, the notional cap keeps leverage sane.
"""

from __future__ import annotations

import math

__all__ = ["size_position"]


def size_position(
    equity: float,
    entry_price: float,
    stop_price: float,
    risk_pct: float = 0.5,
    max_notional_pct: float = 25.0,
    lot_size: int = 1,
) -> int:
    """Return the share quantity for a trade.

    Parameters
    ----------
    equity : float
        Current account equity in the quote currency.
    entry_price : float
        Reference entry price (last close for market orders).
    stop_price : float
        Protective stop price; must differ from ``entry_price``.
    risk_pct : float
        Fraction of equity to risk between entry and stop, in percent.
    max_notional_pct : float
        Maximum position notional as a percentage of equity.
    lot_size : int
        Minimum tradable quantity increment (1 share for equities).

    Returns
    -------
    int
        Quantity in shares, floored to ``lot_size``. Returns ``0`` when the
        trade cannot be sized (invalid prices, no risk budget, or less than
        one lot).
    """
    if equity <= 0 or entry_price <= 0 or stop_price <= 0:
        return 0
    if risk_pct <= 0 or max_notional_pct <= 0 or lot_size < 1:
        return 0

    stop_distance = abs(entry_price - stop_price)
    if stop_distance <= 0:
        return 0

    risk_budget = equity * (risk_pct / 100.0)
    qty_by_risk = math.floor(risk_budget / stop_distance)
    qty_by_notional = math.floor((equity * (max_notional_pct / 100.0)) / entry_price)
    qty = min(qty_by_risk, qty_by_notional)

    if qty < lot_size:
        return 0
    return int(qty // lot_size * lot_size)
