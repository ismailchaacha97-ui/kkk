"""Session-VWAP mean-reversion strategy.

Logic
-----
1. Track the session VWAP and its cumulative volume-weighted standard
   deviation bands (the classic "standard deviation channel").
2. Wait for price to extend beyond the upper/lower band and then close back
   inside it - a failed breakout / exhaustion signal.
3. Fade the extension: target the session VWAP, stop ``atr_stop_mult`` ATR away.
   Only take the trade when the reward-to-risk to VWAP is at least
   ``min_reward_risk``.
4. Cap the number of trades per day and flatten at 15:55 ET.

Mean reversion is the natural counterpart to ORB: it profits on the intraday
dislocations that breakouts lose to, which makes the two a useful comparison
and a starting point for a combined book.
"""

from __future__ import annotations

import math

from nautilus_trader.model.data import Bar, BarType
from nautilus_trader.model.enums import OrderSide
from nautilus_trader.model.instruments.base import Instrument

from daytrader.config import VWAPParams
from daytrader.strategies.base import IntradayStrategy

__all__ = ["VWAPReversion"]


class VWAPReversion(IntradayStrategy):
    """Fade over-extensions away from the session VWAP."""

    def __init__(
        self,
        instrument: Instrument,
        bar_type: BarType,
        params: VWAPParams | None = None,
    ) -> None:
        self.params = params or VWAPParams()
        super().__init__(
            instrument=instrument,
            bar_type=bar_type,
            risk=self.params.risk,
            flatten_time=self.params.flatten_time,
            atr_period=self.params.atr_period,
        )

        self._cum_pv = 0.0
        self._cum_volume = 0.0
        self._cum_pv2 = 0.0
        self._vwap: float | None = None
        self._upper: float | None = None
        self._lower: float | None = None
        self._band_prev_close: float | None = None
        self._prev_upper: float | None = None
        self._prev_lower: float | None = None

    # ------------------------------------------------------------------
    def on_session_start(self, timestamp) -> None:
        self._cum_pv = 0.0
        self._cum_volume = 0.0
        self._cum_pv2 = 0.0
        self._vwap = None
        self._upper = None
        self._lower = None
        self._band_prev_close = None
        self._prev_upper = None
        self._prev_lower = None

    def on_session_bar(self, bar: Bar, timestamp) -> None:
        high = bar.high.as_double()
        low = bar.low.as_double()
        close = bar.close.as_double()
        volume = bar.volume.as_double()
        typical = (high + low + close) / 3.0

        if volume > 0:
            self._cum_pv += typical * volume
            self._cum_volume += volume
            self._cum_pv2 += typical * typical * volume

        if self._cum_volume <= 0:
            return

        vwap = self._cum_pv / self._cum_volume
        variance = max(self._cum_pv2 / self._cum_volume - vwap * vwap, 0.0)
        std = math.sqrt(variance)
        upper = vwap + self.params.band_k * std
        lower = vwap - self.params.band_k * std

        self._vwap, self._upper, self._lower = vwap, upper, lower

        can_trade = (
            self.is_flat()
            and self._trades_today < self.params.risk.max_trades_per_day
            and not self.at_or_after(timestamp, self.params.entry_cutoff)
            and self.at_or_after(timestamp, self.params.entry_start)
        )

        if can_trade and self._band_prev_close is not None:
            long_cross = (
                self._prev_lower is not None
                and self._band_prev_close < self._prev_lower
                and close > lower
            )
            short_cross = (
                self._prev_upper is not None
                and self._band_prev_close > self._prev_upper
                and close < upper
            )
            if long_cross:
                self._try_reversion(OrderSide.BUY, close, stop_reference=low)
            elif short_cross and self.params.risk.allow_short:
                self._try_reversion(OrderSide.SELL, close, stop_reference=high)

        self._band_prev_close = close
        self._prev_upper = upper
        self._prev_lower = lower

    # ------------------------------------------------------------------
    def _try_reversion(self, side: OrderSide, entry: float, stop_reference: float) -> None:
        if self._vwap is None:
            return
        atr = self.atr()
        if atr is None or atr <= 0:
            return

        atr_distance = self.params.atr_stop_mult * atr
        target = self._vwap

        if side == OrderSide.BUY:
            # Stop below the signal bar low and at least one ATR away.
            stop = min(stop_reference, entry - atr_distance)
            risk = entry - stop
            reward = target - entry
            valid = risk > 0 and reward > 0
        else:
            stop = max(stop_reference, entry + atr_distance)
            risk = stop - entry
            reward = entry - target
            valid = risk > 0 and reward > 0

        if not valid:
            return
        if reward / risk < self.params.min_reward_risk:
            self.log.debug(
                f"VWAP fade skipped: R:R {reward / risk:.2f} < {self.params.min_reward_risk:.2f}",
            )
            return

        tag = "vwap_long" if side == OrderSide.BUY else "vwap_short"
        self.enter_bracket(side, entry, stop, target, tag)
