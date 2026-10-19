"""Opening-range breakout (ORB) strategy.

Logic
-----
1. Build the opening range from the first ``opening_range_minutes`` of the
   regular session (09:30-09:45 ET by default).
2. After the range is complete, wait for a *bar close* above the range high
   (long) or below the range low (short) by a small buffer, confirmed by
   above-median volume.
3. Size the trade so that a stop at the opposite side of the range risks a
   fixed percentage of equity, then bracket the position with a take-profit at
   ``reward_risk`` times the stop distance.
4. One trade per direction per day, hard end-of-day flatten at 15:55 ET.

This is a classic, fully-rule-based intraday momentum template. It is included
as a *reference implementation*, not as a promise of profitability.
"""

from __future__ import annotations

import statistics

from nautilus_trader.model.data import Bar, BarType
from nautilus_trader.model.enums import OrderSide
from nautilus_trader.model.instruments.base import Instrument

from daytrader.common import add_minutes
from daytrader.config import ORBParams
from daytrader.data import SESSION_START
from daytrader.strategies.base import IntradayStrategy

__all__ = ["OpeningRangeBreakout"]


class OpeningRangeBreakout(IntradayStrategy):
    """Long/short breakouts of the first N minutes of the session."""

    def __init__(
        self,
        instrument: Instrument,
        bar_type: BarType,
        params: ORBParams | None = None,
    ) -> None:
        self.params = params or ORBParams()
        super().__init__(
            instrument=instrument,
            bar_type=bar_type,
            risk=self.params.risk,
            flatten_time=self.params.flatten_time,
        )
        self._or_end = add_minutes(SESSION_START, self.params.opening_range_minutes)
        self._or_high: float | None = None
        self._or_low: float | None = None
        self._or_volumes: list[float] = []
        self._or_ready = False
        self._or_disabled = False
        self._entered_sides: set[OrderSide] = set()

    # ------------------------------------------------------------------
    def on_session_start(self, timestamp) -> None:
        self._or_high = None
        self._or_low = None
        self._or_volumes = []
        self._or_ready = False
        self._or_disabled = False
        self._entered_sides = set()

    def on_session_bar(self, bar: Bar, timestamp) -> None:
        clock = self.clock_time(timestamp)

        # -- Phase 1: build the opening range -------------------------
        if clock < self._or_end:
            high = bar.high.as_double()
            low = bar.low.as_double()
            self._or_high = high if self._or_high is None else max(self._or_high, high)
            self._or_low = low if self._or_low is None else min(self._or_low, low)
            self._or_volumes.append(bar.volume.as_double())
            return

        # -- Phase 2: finalise the range, do not trade this bar --------
        if not self._or_ready:
            self._finalise_opening_range()
            return

        if self._or_disabled or self._or_high is None or self._or_low is None:
            return
        if self._trades_today >= self.params.risk.max_trades_per_day:
            return
        if self.at_or_after(timestamp, self.params.entry_cutoff):
            return
        if not self.is_flat():
            return

        close = bar.close.as_double()
        buffer = self.params.breakout_buffer_bps / 10_000.0
        long_trigger = self._or_high * (1.0 + buffer)
        short_trigger = self._or_low * (1.0 - buffer)

        volume_ok = self._volume_confirmed(bar)
        if not volume_ok:
            return

        if close > long_trigger:
            self._try_breakout(OrderSide.BUY, close)
        elif self.params.risk.allow_short and close < short_trigger:
            self._try_breakout(OrderSide.SELL, close)

    # ------------------------------------------------------------------
    def _finalise_opening_range(self) -> None:
        self._or_ready = True
        if self._or_high is None or self._or_low is None:
            self._or_disabled = True
            return

        mid = (self._or_high + self._or_low) / 2.0
        width_pct = (self._or_high - self._or_low) / mid * 100.0 if mid > 0 else 0.0
        if width_pct <= 0:
            self._or_disabled = True
        elif width_pct > self.params.max_or_width_pct:
            self._or_disabled = True
            self.log.info(
                f"ORB skipped: opening range {width_pct:.2f}% wider than "
                f"{self.params.max_or_width_pct:.2f}%",
            )
        else:
            self.log.debug(
                f"Opening range ready: {self._or_low:.2f} - {self._or_high:.2f} ({width_pct:.2f}%)",
            )

    def _volume_confirmed(self, bar: Bar) -> bool:
        if self.params.volume_mult <= 0 or not self._or_volumes:
            return True
        reference = statistics.median(self._or_volumes)
        if reference <= 0:
            return True
        return bar.volume.as_double() >= self.params.volume_mult * reference

    def _try_breakout(self, side: OrderSide, entry: float) -> None:
        if side in self._entered_sides:
            return

        min_distance = entry * self.params.min_stop_bps / 10_000.0
        max_distance = entry * self.params.max_stop_bps / 10_000.0

        if side == OrderSide.BUY:
            structural_stop = self._or_low
            distance = max(entry - structural_stop, min_distance)
            stop = entry - distance
            target = entry + self.params.reward_risk * distance
        else:
            structural_stop = self._or_high
            distance = max(structural_stop - entry, min_distance)
            stop = entry + distance
            target = entry - self.params.reward_risk * distance

        if distance > max_distance:
            self.log.debug(
                f"Breakout skipped: stop distance {distance:.2f} > max {max_distance:.2f}",
            )
            return

        tag = "orb_long" if side == OrderSide.BUY else "orb_short"
        if self.enter_bracket(side, entry, stop, target, tag):
            self._entered_sides.add(side)
