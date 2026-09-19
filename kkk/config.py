"""Instruments and backtest configuration.

Everything is expressed in *price units* of the instrument so the same
engine works for FX, metals, indices and crypto without special cases.

`point_value_per_lot` is the account-currency value of a 1.0 price move
for a 1.00 lot position:

    EURUSD  1 lot = 100_000 units  ->  1.0 move = 100_000 USD
    XAUUSD  1 lot =     100 oz     ->  1.0 move =     100 USD
    US30    1 lot =       1 index  ->  1.0 move =       1 USD
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Instrument:
    name: str
    point_value_per_lot: float
    digits: int = 5
    spread: float = 0.0
    slippage: float = 0.0

    def pnl(self, direction: int, entry: float, exit_: float, lots: float) -> float:
        """Profit/loss in account currency, before spread/slippage."""
        return (exit_ - entry) * direction * lots * self.point_value_per_lot

    def lots_for_risk(self, risk_amount: float, stop_distance: float) -> float:
        """Position size so that `stop_distance` costs exactly `risk_amount`."""
        if stop_distance <= 0:
            raise ValueError("stop_distance must be > 0")
        value_per_lot = stop_distance * self.point_value_per_lot
        return risk_amount / value_per_lot


# --- presets -------------------------------------------------------------
# Spread figures are typical retail averages; override with your own broker's.
XAUUSD = Instrument("XAUUSD", point_value_per_lot=100.0, digits=2, spread=0.25)
EURUSD = Instrument("EURUSD", point_value_per_lot=100_000.0, digits=5, spread=0.00008)
GBPUSD = Instrument("GBPUSD", point_value_per_lot=100_000.0, digits=5, spread=0.00010)
USDJPY = Instrument("USDJPY", point_value_per_lot=1_000.0, digits=3, spread=0.010)
US30 = Instrument("US30", point_value_per_lot=1.0, digits=1, spread=2.0)
NAS100 = Instrument("NAS100", point_value_per_lot=1.0, digits=1, spread=1.5)

PRESETS: dict[str, Instrument] = {
    i.name: i for i in (XAUUSD, EURUSD, GBPUSD, USDJPY, US30, NAS100)
}


@dataclass
class Costs:
    """Execution frictions, all in price units."""

    spread: float = 0.0
    slippage: float = 0.0
    commission_per_lot: float = 0.0

    @classmethod
    def from_instrument(cls, inst: Instrument) -> "Costs":
        return cls(spread=inst.spread, slippage=inst.slippage)


@dataclass
class RiskConfig:
    """Money-management rules."""

    initial_equity: float = 10_000.0
    risk_pct: float = 1.0           # % of *current* equity risked per trade
    max_lots: float = 100.0
    min_lots: float = 0.01
    lot_step: float = 0.01
    compound: bool = True           # risk % of growing equity, else of initial


@dataclass
class BacktestConfig:
    instrument: Instrument
    risk: RiskConfig = field(default_factory=RiskConfig)
    costs: Costs = field(default_factory=Costs)
    # Conservative default: when a bar touches both stop and target we assume
    # the stop was hit first. Set False to assume the target was hit first.
    stop_first_on_ambiguous_bar: bool = True
    # Force-close any open trade at the end of the data.
    close_at_end: bool = True
    # Allow one position at a time (no pyramiding / hedging).
    one_position_at_a_time: bool = True

    @classmethod
    def for_symbol(cls, symbol: str, **kwargs) -> "BacktestConfig":
        inst = PRESETS.get(symbol.upper())
        if inst is None:
            raise KeyError(f"unknown symbol {symbol!r}; known: {sorted(PRESETS)}")
        cfg = cls(instrument=inst)
        cfg.costs = Costs.from_instrument(inst)
        for k, v in kwargs.items():
            if k == "risk":
                cfg.risk = v
            elif k == "costs":
                cfg.costs = v
            else:
                setattr(cfg, k, v)
        return cfg
