"""Intraday (day-trading) research and backtesting toolkit built on NautilusTrader.

The package provides:

* a deterministic synthetic intraday data generator (no API keys required),
* a CSV loader for your own 1-minute bars,
* two reference day-trading strategies (opening-range breakout and VWAP reversion),
* risk-based position sizing and end-of-day flattening,
* a thin runner around the NautilusTrader backtest engine plus reporting helpers.

The package is intentionally small: strategies are ordinary
``nautilus_trader.trading.strategy.Strategy`` subclasses, so the same code can be
wired to a live adapter (Interactive Brokers, Databento, Binance, Bybit, ...)
without rewrite.
"""

from __future__ import annotations

__version__ = "0.1.0"

MARKET_TZ = "America/New_York"
DEFAULT_VENUE = "XNAS"

__all__ = ["DEFAULT_VENUE", "MARKET_TZ", "__version__"]
