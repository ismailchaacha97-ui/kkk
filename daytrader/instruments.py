"""Instrument definitions for cash equities."""

from __future__ import annotations

from decimal import Decimal

from nautilus_trader.model.currencies import USD
from nautilus_trader.model.data import BarType
from nautilus_trader.model.identifiers import InstrumentId, Symbol, Venue
from nautilus_trader.model.instruments import Equity
from nautilus_trader.model.objects import Price, Quantity

from daytrader import DEFAULT_VENUE

__all__ = ["bar_type_for", "make_equity"]


def make_equity(
    symbol: str,
    venue: str = DEFAULT_VENUE,
    tick_size: str = "0.01",
    fee_bps: float = 1.0,
    lot_size: int = 1,
) -> Equity:
    """Build a cash-equity instrument with exchange-like fees.

    ``fee_bps`` is charged on both sides (entry and exit). Charging the maker
    side as well is deliberately conservative: many retail brokers bill the
    same commission on resting limit orders, and taking-profit fills should not
    look free in the results.
    """
    if fee_bps < 0:
        raise ValueError("fee_bps must be >= 0")
    precision = len(tick_size.split(".")[1]) if "." in tick_size else 0
    return Equity(
        instrument_id=InstrumentId(symbol=Symbol(symbol), venue=Venue(venue)),
        raw_symbol=Symbol(symbol),
        currency=USD,
        price_precision=precision,
        price_increment=Price.from_str(tick_size),
        lot_size=Quantity.from_int(lot_size),
        margin_init=Decimal("0.25"),
        margin_maint=Decimal("0.25"),
        maker_fee=Decimal(str(fee_bps / 10_000.0)),
        taker_fee=Decimal(str(fee_bps / 10_000.0)),
        ts_event=0,
        ts_init=0,
    )


def bar_type_for(instrument: Equity, minutes: int = 1) -> BarType:
    """External (pre-aggregated) bar type for the given instrument."""
    if minutes < 1:
        raise ValueError("minutes must be >= 1")
    return BarType.from_str(f"{instrument.id}-{minutes}-MINUTE-LAST-EXTERNAL")
