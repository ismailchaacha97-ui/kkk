"""Bar-by-bar backtest engine.

Design notes
------------
* Strategies are evaluated **on bar close** and can only act from the next
  bar onward. No look-ahead.
* Exits are checked intrabar against high/low. When a single bar touches
  both the stop and the target, the pessimistic assumption is used by
  default (stop first). This is the single most common way backtests lie.
* Spread and slippage are charged against you on both entry and exit.
* One position at a time; a pending order is cancelled when it expires.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, Sequence

import numpy as np
import pandas as pd

from .config import BacktestConfig

Direction = Literal["long", "short"]


@dataclass
class Signal:
    """An intent generated at the close of bar `bar` (exclusive index)."""

    direction: Direction
    stop: float
    target: float | None = None
    entry: float | None = None      # None -> market order at next open
    valid_for: int = 3              # bars a resting limit order stays alive
    tag: str = ""
    bar: int | None = None          # filled in by the engine

    @property
    def sign(self) -> int:
        return 1 if self.direction == "long" else -1


@dataclass
class Trade:
    entry_time: pd.Timestamp
    exit_time: pd.Timestamp
    direction: Direction
    entry: float
    exit: float
    stop: float
    target: float | None
    lots: float
    pnl: float
    r_multiple: float
    risk_amount: float              # account currency put at risk on entry
    bars_held: int
    exit_reason: str
    tag: str = ""
    mae: float = 0.0                # max adverse excursion, in R (<= 0)
    mfe: float = 0.0                # max favourable excursion, in R (>= 0)

    @property
    def sign(self) -> int:
        return 1 if self.direction == "long" else -1


@dataclass
class BacktestResult:
    trades: list[Trade]
    equity: pd.Series
    config: BacktestConfig
    skipped: int = 0
    notes: list[str] = field(default_factory=list)

    @property
    def n_trades(self) -> int:
        return len(self.trades)

    def to_frame(self) -> pd.DataFrame:
        if not self.trades:
            return pd.DataFrame(
                columns=[f.name for f in Trade.__dataclass_fields__.values()]
            )
        return pd.DataFrame([t.__dict__ for t in self.trades])


class Engine:
    def __init__(self, config: BacktestConfig):
        self.cfg = config

    # -- helpers ----------------------------------------------------------
    def _fill_price(self, base: float, sign: int) -> float:
        """Apply half-spread plus slippage against the trader."""
        half = self.cfg.costs.spread / 2.0
        return base + sign * (half + self.cfg.costs.slippage)

    def _exit_price(self, base: float, sign: int) -> float:
        """Closing a long sells at bid; slippage hurts both ways."""
        half = self.cfg.costs.spread / 2.0
        return base - sign * half - sign * self.cfg.costs.slippage

    def _size(self, equity: float, stop_distance: float) -> float:
        risk = self.cfg.risk
        base = equity if risk.compound else risk.initial_equity
        amount = base * risk.risk_pct / 100.0
        lots = self.cfg.instrument.lots_for_risk(amount, stop_distance)
        lots = min(lots, risk.max_lots)
        step = risk.lot_step
        lots = np.floor(lots / step) * step if step > 0 else lots
        return round(max(lots, 0.0), 4)

    # -- main loop --------------------------------------------------------
    def run(
        self,
        df: pd.DataFrame,
        signals: Sequence[Signal],
        *,
        warmup: int = 0,
    ) -> BacktestResult:
        if self.cfg.instrument is None:
            raise ValueError("config.instrument is required")

        o = df["open"].to_numpy(float)
        h = df["high"].to_numpy(float)
        l = df["low"].to_numpy(float)
        c = df["close"].to_numpy(float)
        ts = df.index
        n = len(df)

        by_bar: dict[int, list[Signal]] = {}
        for s in signals:
            if s.bar is None:
                raise ValueError("Signal.bar must be set (index of the signal bar)")
            if s.bar < warmup:
                continue
            by_bar.setdefault(s.bar, []).append(s)

        equity = self.cfg.risk.initial_equity
        equity_curve = np.full(n, np.nan)
        trades: list[Trade] = []
        notes: list[str] = []
        skipped = 0

        pending: Signal | None = None
        pending_expiry = -1
        trade: dict | None = None

        def close_trade(i: int, price: float, reason: str) -> None:
            nonlocal trade, equity
            t = trade
            assert t is not None
            sign = 1 if t["direction"] == "long" else -1
            exit_px = self._exit_price(price, sign)
            pnl = self.cfg.instrument.pnl(sign, t["entry"], exit_px, t["lots"])
            pnl -= self.cfg.costs.commission_per_lot * t["lots"] * 2
            stop_dist = abs(t["entry"] - t["raw_stop"]) or 1e-12
            equity += pnl
            trades.append(
                Trade(
                    entry_time=t["entry_time"],
                    exit_time=ts[i],
                    direction=t["direction"],
                    entry=t["entry"],
                    exit=exit_px,
                    stop=t["raw_stop"],
                    target=t["target"],
                    lots=t["lots"],
                    pnl=pnl,
                    r_multiple=pnl / t["risk_amount"] if t["risk_amount"] else 0.0,
                    risk_amount=t["risk_amount"],
                    bars_held=i - t["entry_bar"],
                    exit_reason=reason,
                    tag=t["tag"],
                    mae=t["mae"] / stop_dist,
                    mfe=t["mfe"] / stop_dist,
                )
            )
            trade = None

        for i in range(n):
            # ---------- 1. act on orders resting from previous bars ------
            if pending is not None and pending_expiry < i:
                pending = None
                skipped += 1

            if trade is None and pending is not None:
                s = pending
                sign = s.sign
                if s.entry is None:
                    fill = self._fill_price(o[i], sign)
                    armed = True
                else:
                    # limit order: only fill if price traded through it
                    touched = (l[i] <= s.entry) if sign > 0 else (h[i] >= s.entry)
                    fill = self._fill_price(s.entry, sign)
                    armed = touched
                if armed:
                    raw_stop = s.stop
                    stop_dist = abs(fill - raw_stop)
                    if stop_dist <= 0:
                        notes.append(f"bar {i}: zero stop distance, order dropped")
                        pending = None
                    else:
                        lots = self._size(equity, stop_dist)
                        if lots <= 0:
                            notes.append(f"bar {i}: sizing produced 0 lots, skipped")
                            pending = None
                            skipped += 1
                        else:
                            trade = {
                                "entry": fill,
                                "raw_stop": raw_stop,
                                "target": s.target,
                                "direction": s.direction,
                                "lots": lots,
                                "entry_bar": i,
                                "entry_time": ts[i],
                                "risk_amount": stop_dist
                                * lots
                                * self.cfg.instrument.point_value_per_lot,
                                "tag": s.tag,
                                "mae": 0.0,
                                "mfe": 0.0,
                            }
                            pending = None

            # ---------- 2. manage the open trade -------------------------
            if trade is not None:
                sign = 1 if trade["direction"] == "long" else -1
                stop = trade["raw_stop"]
                target = trade["target"]

                # Excursions are signed in R-space: for a long, (low - entry)
                # is the worst case and (high - entry) the best; for a short
                # the signs invert, and min/max still give worst/best.
                exc_low = (l[i] - trade["entry"]) * sign
                exc_high = (h[i] - trade["entry"]) * sign
                trade["mae"] = min(trade["mae"], min(exc_low, exc_high))
                trade["mfe"] = max(trade["mfe"], max(exc_low, exc_high))

                hit_stop = (l[i] <= stop) if sign > 0 else (h[i] >= stop)
                hit_target = False
                if target is not None:
                    hit_target = (h[i] >= target) if sign > 0 else (l[i] <= target)

                if hit_stop and hit_target:
                    if self.cfg.stop_first_on_ambiguous_bar:
                        close_trade(i, stop, "stop")
                    else:
                        close_trade(i, target, "target")
                elif hit_stop:
                    close_trade(i, stop, "stop")
                elif hit_target:
                    close_trade(i, target, "target")

            # ---------- 3. read signals generated at this bar's close ----
            if i in by_bar:
                if trade is None and pending is None:
                    pending = by_bar[i][0]
                    pending_expiry = i + pending.valid_for
                elif len(by_bar[i]) > 1:
                    skipped += len(by_bar[i]) - 1

            equity_curve[i] = equity

        if trade is not None and self.cfg.close_at_end:
            close_trade(n - 1, c[n - 1], "eod")

        eq = pd.Series(equity_curve, index=ts, name="equity")
        return BacktestResult(trades, eq, self.cfg, skipped=skipped, notes=notes)


def run_backtest(df: pd.DataFrame, signals: Sequence[Signal], config: BacktestConfig):
    return Engine(config).run(df, signals)
