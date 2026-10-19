"""Shared plumbing for intraday strategies.

The base class owns the parts that must be identical across strategies to make
comparisons fair:

* session bookkeeping and daily trade limits,
* ATR tracking used for stop placement,
* risk-based position sizing,
* market-entry bracket orders (take-profit + protective stop, OCO),
* mandatory end-of-day flattening, so nothing is ever held overnight.
"""

from __future__ import annotations

import datetime as dt
from collections import deque

import pandas as pd
from nautilus_trader.common.enums import LogColor
from nautilus_trader.model.data import Bar, BarType
from nautilus_trader.model.enums import OrderSide, OrderType, TimeInForce
from nautilus_trader.model.events import OrderDenied, OrderRejected, PositionClosed, PositionOpened
from nautilus_trader.model.instruments.base import Instrument
from nautilus_trader.trading.strategy import Strategy

from daytrader import MARKET_TZ
from daytrader.config import RiskConfig
from daytrader.risk import size_position


class IntradayStrategy(Strategy):
    """Base class for strategies that trade one instrument intraday."""

    def __init__(
        self,
        instrument: Instrument,
        bar_type: BarType,
        risk: RiskConfig,
        flatten_time: str,
        atr_period: int = 14,
    ) -> None:
        super().__init__()
        self.instrument = instrument
        self.bar_type = bar_type
        self.risk = risk
        self.flatten_time = flatten_time

        self._session: dt.date | None = None
        self._bars_today = 0
        self._trades_today = 0
        self._flattened_today = False

        # ATR state (true ranges, reset at each session open to avoid gaps).
        self._tr_window: deque[float] = deque(maxlen=atr_period)
        self._prev_close: float | None = None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------
    def on_start(self) -> None:
        self.subscribe_bars(self.bar_type)
        self.log.info(
            f"Starting {type(self).__name__} on {self.instrument.id} "
            f"(risk {self.risk.risk_per_trade_pct}%/trade, flatten {self.flatten_time})",
            color=LogColor.GREEN,
        )

    def on_bar(self, bar: Bar) -> None:
        timestamp = self.ny_timestamp(bar)
        session = timestamp.date()

        if session != self._session:
            self._start_session(session, timestamp)

        self._bars_today += 1
        self._update_atr(bar)

        if self._flattened_today:
            return

        if self.at_or_after(timestamp, self.flatten_time):
            self._flatten_all()
            return

        self.on_session_bar(bar, timestamp)

    def on_stop(self) -> None:
        self.cancel_all_orders(self.instrument.id)

    def on_reset(self) -> None:
        self._session = None
        self._bars_today = 0
        self._trades_today = 0
        self._flattened_today = False
        self._tr_window.clear()
        self._prev_close = None

    # ------------------------------------------------------------------
    # Strategy hook
    # ------------------------------------------------------------------
    def on_session_bar(self, bar: Bar, timestamp: pd.Timestamp) -> None:
        """Handle a bar inside an active session (implemented by strategies)."""
        raise NotImplementedError

    def on_session_start(self, timestamp: pd.Timestamp) -> None:
        """Reset per-session strategy state (optional override)."""

    # ------------------------------------------------------------------
    # Execution helpers
    # ------------------------------------------------------------------
    def enter_bracket(
        self,
        side: OrderSide,
        entry_price: float,
        stop_price: float,
        target_price: float,
        tag: str,
    ) -> bool:
        """Submit a market-entry bracket order sized from the stop distance.

        Returns ``True`` when an order was submitted.
        """
        if self._trades_today >= self.risk.max_trades_per_day:
            return False

        equity = self.equity()
        lot = int(self.instrument.lot_size)
        qty = size_position(
            equity=equity,
            entry_price=entry_price,
            stop_price=stop_price,
            risk_pct=self.risk.risk_per_trade_pct,
            max_notional_pct=self.risk.max_notional_pct,
            lot_size=lot,
        )
        if qty <= 0:
            self.log.debug(
                f"{tag}: skipped, size=0 (equity={equity:.2f}, "
                f"entry={entry_price:.2f}, stop={stop_price:.2f})",
            )
            return False
        if side == OrderSide.SELL and not self.risk.allow_short:
            return False

        order_list = self.order_factory.bracket(
            instrument_id=self.instrument.id,
            order_side=side,
            quantity=self.instrument.make_qty(qty),
            entry_order_type=OrderType.MARKET,
            entry_tags=[tag],
            tp_price=self.instrument.make_price(round(target_price, 2)),
            tp_tags=[tag, "tp"],
            sl_trigger_price=self.instrument.make_price(round(stop_price, 2)),
            sl_tags=[tag, "sl"],
            time_in_force=TimeInForce.DAY,
            tp_time_in_force=TimeInForce.DAY,
            sl_time_in_force=TimeInForce.DAY,
        )
        self.submit_order_list(order_list)
        self._trades_today += 1
        risk_distance = abs(entry_price - stop_price)
        reward_distance = abs(target_price - entry_price)
        reward_risk = reward_distance / risk_distance if risk_distance > 0 else 0.0
        self.log.info(
            f"{tag} {side.name} {qty} @ ~{entry_price:.2f} | stop {stop_price:.2f} "
            f"target {target_price:.2f} (R:R {reward_risk:.2f})",
            color=LogColor.GREEN,
        )
        return True

    def _flatten_all(self) -> None:
        """Cancel resting orders and close any open position at the close."""
        self._flattened_today = True
        self.cancel_all_orders(self.instrument.id)
        if not self.portfolio.is_flat(self.instrument.id):
            self.close_all_positions(self.instrument.id)
            self.log.info("End-of-day flatten: closing open position", color=LogColor.YELLOW)

    # ------------------------------------------------------------------
    # Portfolio / risk helpers
    # ------------------------------------------------------------------
    def equity(self) -> float:
        """Current realized account equity in the instrument's quote currency."""
        account = self.portfolio.account(self.instrument.venue)
        if account is None:  # pragma: no cover - defensive
            return 0.0
        return float(account.balance_total(self.instrument.quote_currency))

    def is_flat(self) -> bool:
        return self.portfolio.is_flat(self.instrument.id)

    def atr(self) -> float | None:
        """Simple average of the tracked true ranges (``None`` during warmup)."""
        if len(self._tr_window) < self._tr_window.maxlen:
            return None
        return sum(self._tr_window) / len(self._tr_window)

    # ------------------------------------------------------------------
    # Event handlers
    # ------------------------------------------------------------------
    def on_position_opened(self, event: PositionOpened) -> None:
        self.log.info(
            f"Position opened {event.instrument_id} {event.side.name} "
            f"{event.quantity} @ {event.avg_px_open}",
            color=LogColor.GREEN,
        )

    def on_position_closed(self, event: PositionClosed) -> None:
        pnl = getattr(event, "realized_pnl", None)
        self.log.info(
            f"Position closed {event.instrument_id} {event.side.name} "
            f"{event.quantity} @ {event.avg_px_close} | PnL {pnl}",
            color=LogColor.YELLOW,
        )

    def on_order_rejected(self, event: OrderRejected) -> None:
        self.log.warning(f"Order rejected: {event.reason}")

    def on_order_denied(self, event: OrderDenied) -> None:
        self.log.warning(f"Order denied: {event.reason}")

    # ------------------------------------------------------------------
    # Time helpers
    # ------------------------------------------------------------------
    @staticmethod
    def ny_timestamp(bar: Bar) -> pd.Timestamp:
        return pd.Timestamp(bar.ts_event, unit="ns", tz="UTC").tz_convert(MARKET_TZ)

    @staticmethod
    def at_or_after(timestamp: pd.Timestamp, hhmm: str) -> bool:
        hours, minutes = (int(part) for part in hhmm.split(":"))
        cutoff = timestamp.replace(hour=hours, minute=minutes, second=0, microsecond=0)
        return timestamp >= cutoff

    @staticmethod
    def clock_time(timestamp: pd.Timestamp) -> dt.time:
        return timestamp.time().replace(tzinfo=None)

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------
    def _start_session(self, session: dt.date, timestamp: pd.Timestamp) -> None:
        self._session = session
        self._bars_today = 0
        self._trades_today = 0
        self._flattened_today = False
        self._tr_window.clear()
        self._prev_close = None
        self.log.debug(f"New session {session}")
        self.on_session_start(timestamp)

    def _update_atr(self, bar: Bar) -> None:
        high = bar.high.as_double()
        low = bar.low.as_double()
        close = bar.close.as_double()
        if self._prev_close is None:
            true_range = high - low
        else:
            true_range = max(
                high - low,
                abs(high - self._prev_close),
                abs(low - self._prev_close),
            )
        self._tr_window.append(true_range)
        self._prev_close = close
