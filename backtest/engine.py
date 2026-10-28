"""
Bar-by-bar reference backtest engine.

Design rules (so that the MQL4 EA can be a literal translation):

* a signal is evaluated on the **close** of bar *i* and filled at the **open** of
  bar *i+1* - no intrabar decisions, no repainting;
* orders, stops and targets are checked in the same order the EA will use:
  gap -> stop -> target -> break-even/trail bookkeeping;
* when the protective stop and the target are both inside one bar's range the
  stop is assumed to be hit first (pessimistic, the standard MT4 assumption on
  H1 data);
* spread is paid on every trade: longs enter at Ask and exit at Bid, shorts the
  other way round;
* equity is marked to market on every bar so drawdown reflects floating risk,
  exactly like the MT4 strategy tester.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
import pandas as pd

from . import data as D
from .features import Features, Params


@dataclass
class EngineCfg:
    start_equity: float = 10_000.0
    risk_pct: float = 0.25          # risk per trade, % of equity
    max_positions: int = 3          # concurrent positions over the whole portfolio
    max_per_symbol: int = 1
    daily_loss_stop_pct: float = 1.5   # stop opening new trades for the day
    daily_hard_stop_pct: float = 2.5   # flatten everything
    daily_profit_lock_pct: float = 0.0  # 0 = disabled, else stop after +x% day
    weekly_loss_stop_pct: float = 0.0    # 0 = disabled
    max_leverage: float = 20.0      # notional / equity guard
    close_before_weekend_hour: int = 20  # UTC; 99 = never
    compound: bool = True
    cost_multiplier: float = 1.0    # scales the modelled spread (for cost-sensitivity tests)


@dataclass
class Position:
    sym: str
    side: int                 # +1 long, -1 short
    lots: float
    entry: float
    sl: float
    tp: float
    risk_price: float         # |entry - initial stop|
    open_i: int               # bar index of the symbol
    be_done: bool = False
    mfe: float = 0.0
    mae: float = 0.0
    risk_amount: float = 0.0
    diag: dict = field(default_factory=dict)

    def unrealised(self, price: float, spec: dict) -> float:
        return pnl_usd(self.sym, self.side, self.entry, price, self.lots, spec)


def pnl_usd(sym: str, side: int, entry: float, exit_: float, lots: float, spec: dict) -> float:
    contract = spec["contract"]
    raw = (exit_ - entry) * side * lots * contract
    if sym.endswith("JPY"):          # quote currency is JPY -> convert to account USD
        raw = raw / max(exit_, 1e-9)
    return raw


def notional_usd(sym: str, lots: float, price: float, spec: dict) -> float:
    """USD notional of a position (used only for the leverage guard)."""
    contract = spec["contract"]
    if sym.startswith("USD"):            # USD is the base currency (USDJPY ...)
        return lots * contract
    return lots * contract * price


def price_unit_value(sym: str, price: float, spec: dict) -> float:
    """USD value of one full price unit (1.0000 on EURUSD) for 1 lot."""
    v = spec["contract"]
    if sym.endswith("JPY"):
        v = v / max(price, 1e-9)
    return v


@dataclass
class BacktestResult:
    trades: pd.DataFrame
    equity: pd.Series
    daily: pd.Series
    stats: dict = field(default_factory=dict)


def run(
    series: dict[str, D.Series],
    feats: dict[str, Features],
    params: dict[str, Params],
    cfg: EngineCfg,
    start: str | None = None,
    end: str | None = None,
    verbose: bool = False,
) -> BacktestResult:
    syms = list(series.keys())
    # ---- align all symbols on one timeline ------------------------------
    times = np.unique(np.concatenate([series[s].time for s in syms]))
    if start is not None:
        times = times[times >= np.datetime64(start)]
    if end is not None:
        times = times[times < np.datetime64(end)]
    t0, t1 = times[0], times[-1]
    bar_end = {s: int(np.searchsorted(series[s].time, t1)) for s in syms}
    # timeline index -> bar index of that symbol (-1 = no bar at this timestamp)
    baridx = {}
    for s in syms:
        j = np.searchsorted(series[s].time, times)
        j = np.clip(j, 0, len(series[s].time) - 1)
        hit = series[s].time[j] == times
        baridx[s] = np.where(hit, j, -1)
    wday = pd.DatetimeIndex(times).weekday.to_numpy()
    hh = pd.DatetimeIndex(times).hour.to_numpy()

    equity = cfg.start_equity
    balance = equity
    specs = {}
    for s in syms:
        spec = dict(D.INSTRUMENTS[s])
        spec["spread_pips"] = spec["spread_pips"] * cfg.cost_multiplier
        specs[s] = spec

    open_pos: list[Position] = []
    pending: dict[str, dict] = {}      # symbol -> order to fill on next bar open
    trades: list[dict] = []
    eq_curve = np.zeros(len(times))
    day_key = None
    day_start_balance = balance
    day_key_arr = times.astype("datetime64[D]")
    year_week = pd.DatetimeIndex(times).strftime("%G-%V").to_numpy()
    week_key = None
    week_start_balance = balance
    halted_today = False
    halted_this_week = False
    signals_per_day: dict[tuple, int] = {}

    for ti, t in enumerate(times):
        # ---------- new day / week bookkeeping --------------------------
        dk = day_key_arr[ti]
        if dk != day_key:
            day_key = dk
            day_start_balance = balance
            halted_today = False
        wk = year_week[ti]
        if wk != week_key:
            week_key = wk
            week_start_balance = balance
            halted_this_week = False

        realised_day = balance - day_start_balance
        day_pnl_pct = 100.0 * realised_day / max(day_start_balance, 1e-9)
        week_pnl_pct = 100.0 * (balance - week_start_balance) / max(week_start_balance, 1e-9)

        if cfg.daily_hard_stop_pct > 0 and day_pnl_pct <= -cfg.daily_hard_stop_pct:
            halted_today = True
        if cfg.weekly_loss_stop_pct > 0 and week_pnl_pct <= -cfg.weekly_loss_stop_pct:
            halted_this_week = True

        # ---------- manage open positions on this bar -------------------
        still_open = []
        for pos in open_pos:
            s = series[pos.sym]
            bi = baridx[pos.sym][ti]
            if bi < 0:                           # symbol has no bar here
                still_open.append(pos)
                continue
            f = feats[pos.sym]
            p = params[pos.sym]
            spec = specs[pos.sym]
            o, h, l, c = s.open[bi], s.high[bi], s.low[bi], s.close[bi]
            spread = spec["spread_pips"] * spec["pip"]

            # Bars are BID prices.  A long enters at Ask and exits at Bid, so stop
            # and target levels compare directly with the bar.  A short enters at
            # Bid and exits at Ask, so every bid price has to be shifted by the
            # spread before it can trigger a stop or a target.
            if pos.side > 0:
                fav = h - pos.entry
                adv = l - pos.entry
            else:
                fav = pos.entry - l
                adv = pos.entry - h
            pos.mfe = max(pos.mfe, fav / pos.risk_price if pos.risk_price else 0.0)
            pos.mae = min(pos.mae, adv / pos.risk_price if pos.risk_price else 0.0)

            def exit_of(side: int, bidpx: float) -> float:
                """Price actually received when liquidating at this bid quote."""
                return bidpx if side > 0 else bidpx + spread

            exit_price = None
            reason = None
            if pos.side > 0:
                # 1) gap through the stop / target at the open
                if o <= pos.sl:
                    exit_price, reason = o, "gap_sl"
                elif o >= pos.tp:
                    exit_price, reason = o, "gap_tp"
                # 2) intrabar: the stop is assumed to be hit before the target
                elif l <= pos.sl:
                    exit_price, reason = pos.sl, "sl"
                elif h >= pos.tp:
                    exit_price, reason = pos.tp, "tp"
            else:
                if o + spread >= pos.sl:
                    exit_price, reason = o + spread, "gap_sl"
                elif o + spread <= pos.tp:
                    exit_price, reason = o + spread, "gap_tp"
                elif h + spread >= pos.sl:
                    exit_price, reason = pos.sl, "sl"
                elif l + spread <= pos.tp:
                    exit_price, reason = pos.tp, "tp"

            # 3) bar-close management: time stop, weekend flat, break-even, trail
            if exit_price is None:
                held = bi - pos.open_i
                if p.max_hold_bars and held >= p.max_hold_bars:
                    exit_price, reason = exit_of(pos.side, c), "time"
                elif cfg.close_before_weekend_hour < 90 and wday[ti] == 4 and \
                        hh[ti] >= cfg.close_before_weekend_hour:
                    exit_price, reason = exit_of(pos.side, c), "weekend"
                else:
                    r_now = ((c - pos.entry) if pos.side > 0 else (pos.entry - c)) / max(pos.risk_price, 1e-12)
                    if p.be_at_r > 0 and not pos.be_done and r_now >= p.be_at_r:
                        pos.sl = pos.entry
                        pos.be_done = True
                    if p.trail_atr > 0 and np.isfinite(f.atr[bi]):
                        tr = p.trail_atr * f.atr[bi]
                        if pos.side > 0:
                            pos.sl = max(pos.sl, c - tr)
                        else:
                            pos.sl = min(pos.sl, c + tr)

            if exit_price is not None:
                px = exit_price
                pnl = pnl_usd(pos.sym, pos.side, pos.entry, px, pos.lots, spec)
                balance += pnl
                trades.append(dict(
                    symbol=pos.sym, side=pos.side, lots=pos.lots,
                    open_time=series[pos.sym].time[pos.open_i],
                    close_time=t, entry=pos.entry, exit=px,
                    sl_dist=pos.risk_price, pnl=pnl,
                    r_multiple=pnl / max(pos.risk_amount, 1e-9),
                    risk_amount=pos.risk_amount,
                    bars=bi - pos.open_i, reason=reason,
                    mfe=pos.mfe, mae=pos.mae,
                    balance=balance, **pos.diag,
                ))
            else:
                still_open.append(pos)
        open_pos = still_open

        # ---------- fill pending orders at this bar's open ---------------
        new_open = []
        for sym, order in list(pending.items()):
            bi = baridx[sym][ti]
            if bi < 0:
                continue
            del pending[sym]
            s = series[sym]
            spec = specs[sym]
            p = params[sym]
            spread = spec["spread_pips"] * spec["pip"]
            slip = p.entry_slippage_pips * spec["pip"]
            if order["side"] > 0:
                px = s.open[bi] + spread + slip
            else:
                px = s.open[bi] - slip
            sl_dist = abs(px - order["sl"])
            if sl_dist <= 0:
                continue
            unit_val = price_unit_value(sym, px, spec)
            risk_amt = balance * cfg.risk_pct / 100.0
            lots = risk_amt / (sl_dist * unit_val)
            lots = _round_lots(lots)
            notional = notional_usd(sym, lots, px, spec)
            if lots <= 0 or notional > cfg.max_leverage * balance:
                continue
            tp = px + order["side"] * p.rr * sl_dist
            pos = Position(sym=sym, side=order["side"], lots=lots, entry=px,
                           sl=order["sl"], tp=tp, risk_price=sl_dist,
                           open_i=bi)
            pos.risk_amount = risk_amt
            pos.diag = {k: order.get(k) for k in
                        ("score", "penetration", "vol_ratio", "close_frac", "atr", "structure", "hour", "level")}
            new_open.append(pos)
        open_pos.extend(new_open)

        # ---------- mark to market --------------------------------------
        floating = 0.0
        for pos in open_pos:
            bi = baridx[pos.sym][ti]
            if bi < 0:
                continue
            spread = specs[pos.sym]["spread_pips"] * specs[pos.sym]["pip"]
            px = series[pos.sym].close[bi]
            px = px + spread if pos.side < 0 else px   # shorts would be bought back at Ask
            floating += pnl_usd(pos.sym, pos.side, pos.entry, px, pos.lots, specs[pos.sym])
        equity = balance + floating
        eq_curve[ti] = equity

        # ---------- gather signals (evaluated at this bar's close) ------
        if halted_today or halted_this_week:
            continue
        if cfg.daily_loss_stop_pct > 0 and day_pnl_pct <= -cfg.daily_loss_stop_pct:
            halted_today = True
            continue
        if cfg.daily_profit_lock_pct > 0 and day_pnl_pct >= cfg.daily_profit_lock_pct:
            halted_today = True
            continue

        # rank the bar's signals across symbols by setup quality, then fill slots
        cands = []
        for sym in syms:
            bi = baridx[sym][ti]
            if bi < 0:
                continue
            if bi + 1 >= len(series[sym].time):
                continue
            if any(q.sym == sym for q in open_pos) or sym in pending:
                continue
            if any(c["sym"] == sym for c in cands):
                continue
            f = feats[sym]
            p = params[sym]
            key = (sym, dk)
            if signals_per_day.get(key, 0) >= p.max_signals_per_day:
                continue
            atr = f.atr[bi]
            if not np.isfinite(atr) or atr <= 0:
                continue
            side = 0
            level = np.nan
            if f.ok_long[bi]:
                side, level = 1, f.extra["lvl_l"][bi]
            elif f.ok_short[bi]:
                side, level = -1, f.extra["lvl_h"][bi]
            if side == 0 or not np.isfinite(level):
                continue
            ser = series[sym]
            o, h, l, c = ser.open[bi], ser.high[bi], ser.low[bi], ser.close[bi]
            if side > 0:
                sweep_extreme = l
                sl = sweep_extreme - p.sl_atr_buffer * atr
            else:
                sweep_extreme = h
                sl = sweep_extreme + p.sl_atr_buffer * atr
            dist = abs(c - sl) / atr
            if dist < p.min_sl_atr or dist > p.max_sl_atr:
                continue
            penetration = abs((sweep_extreme - level)) / atr
            vol_ratio = ser.volume[bi] / max(f.vol_med[bi], 1e-9) if np.isfinite(f.vol_med[bi]) else 1.0
            rngv = max(h - l, 1e-12)
            close_frac = (c - l) / rngv if side > 0 else (h - c) / rngv
            score = 1.0 * min(penetration, 3.0) + 0.35 * min(vol_ratio, 4.0) + 0.5 * close_frac
            cands.append(dict(sym=sym, side=side, sl=sl, signal_i=bi, score=score,
                              penetration=penetration, vol_ratio=vol_ratio,
                              close_frac=close_frac, atr=atr, level=level))
        cands.sort(key=lambda c: -c["score"])
        for cnd in cands:
            if len(open_pos) + len(pending) >= cfg.max_positions:
                break
            sym = cnd["sym"]
            pending[sym] = dict(side=cnd["side"], sl=cnd["sl"], signal_i=cnd["signal_i"],
                                score=cnd["score"], penetration=cnd["penetration"],
                                vol_ratio=cnd["vol_ratio"], close_frac=cnd["close_frac"],
                                atr=cnd["atr"], structure=int(feats[sym].structure[cnd["signal_i"]]),
                                hour=int(feats[sym].hour[cnd["signal_i"]]),
                                level=cnd["level"])
            key = (sym, dk)
            signals_per_day[key] = signals_per_day.get(key, 0) + 1

    # ---------- force-close anything left -------------------------------
    last_t = times[-1]
    for pos in open_pos:
        bi = max(baridx[pos.sym][-1], len(series[pos.sym]) - 1)
        px = series[pos.sym].close[bi]
        spec = specs[pos.sym]
        spread = spec["spread_pips"] * spec["pip"]
        px = px + spread if pos.side < 0 else px
        pnl = pnl_usd(pos.sym, pos.side, pos.entry, px, pos.lots, spec)
        balance += pnl
        trades.append(dict(
            symbol=pos.sym, side=pos.side, lots=pos.lots,
            open_time=series[pos.sym].time[pos.open_i], close_time=last_t,
            entry=pos.entry, exit=px, sl_dist=pos.risk_price, pnl=pnl,
            r_multiple=pnl / max(pos.risk_amount, 1e-9), risk_amount=pos.risk_amount,
            bars=bi - pos.open_i, reason="eod", mfe=pos.mfe, mae=pos.mae, balance=balance,
            **pos.diag,
        ))
    eq_curve[-1] = balance

    tr = pd.DataFrame(trades)
    if len(tr):
        tr["open_time"] = pd.to_datetime(tr["open_time"])
        tr["close_time"] = pd.to_datetime(tr["close_time"])
    eq = pd.Series(eq_curve, index=pd.DatetimeIndex(times), name="equity")
    daily = eq.resample("D").last().dropna()
    res = BacktestResult(trades=tr, equity=eq, daily=daily)
    res.stats = metrics(res, cfg)
    if verbose:
        print(summary(res.stats))
    return res


def _round_lots(lots: float) -> float:
    """MT4 lot step = 0.01."""
    return np.floor(lots * 100.0) / 100.0


# ----------------------------------------------------------------------------
# metrics
# ----------------------------------------------------------------------------
def metrics(res: BacktestResult, cfg: EngineCfg) -> dict:
    tr = res.trades
    eq = res.equity
    daily = res.daily
    out: dict = {}
    if len(eq) < 2:
        return out
    span_days = max((eq.index[-1] - eq.index[0]).days, 1)
    total_ret = eq.iloc[-1] / cfg.start_equity - 1.0
    out["start"] = str(eq.index[0].date())
    out["end"] = str(eq.index[-1].date())
    out["days"] = span_days
    out["trades"] = int(len(tr))
    out["total_return_pct"] = 100 * total_ret
    out["cagr_pct"] = 100 * ((eq.iloc[-1] / cfg.start_equity) ** (365.25 / span_days) - 1) if eq.iloc[-1] > 0 else -100
    peak = eq.cummax()
    dd = eq / peak - 1.0
    out["max_dd_pct"] = 100 * float(-dd.min())
    out["calmar"] = (out["cagr_pct"] / out["max_dd_pct"]) if out["max_dd_pct"] > 0 else np.nan
    dret = daily.pct_change().dropna()
    out["avg_daily_pct"] = 100 * float(dret.mean()) if len(dret) else 0.0
    out["median_daily_pct"] = 100 * float(dret.median()) if len(dret) else 0.0
    out["worst_day_pct"] = 100 * float(dret.min()) if len(dret) else 0.0
    out["std_daily_pct"] = 100 * float(dret.std()) if len(dret) else 0.0
    out["sharpe"] = float(dret.mean() / dret.std() * np.sqrt(252)) if len(dret) > 2 and dret.std() > 0 else 0.0
    out["days_traded"] = int(len(daily))
    if len(tr):
        wins = tr[tr.pnl > 0]
        losses = tr[tr.pnl <= 0]
        gp = wins.pnl.sum()
        gl = -losses.pnl.sum()
        out["win_rate_pct"] = 100 * len(wins) / len(tr)
        out["profit_factor"] = float(gp / gl) if gl > 0 else (np.inf if gp > 0 else 0.0)
        out["avg_win"] = float(wins.pnl.mean()) if len(wins) else 0.0
        out["avg_loss"] = float(losses.pnl.mean()) if len(losses) else 0.0
        out["expectancy_r"] = float(tr.r_multiple.mean())
        out["avg_bars"] = float(tr.bars.mean())
        out["trades_per_day"] = len(tr) / max(out["days_traded"], 1)
        # longest losing streak
        streak = max_streak = 0
        for p in tr.pnl:
            streak = streak + 1 if p <= 0 else 0
            max_streak = max(max_streak, streak)
        out["max_losing_streak"] = max_streak
        by_sym = tr.groupby("symbol").pnl.agg(["sum", "count"])
        out["by_symbol"] = {k: dict(pnl=float(v["sum"]), n=int(v["count"])) for k, v in by_sym.iterrows()}
    else:
        out.update(win_rate_pct=0.0, profit_factor=0.0, expectancy_r=0.0, trades_per_day=0.0)
    return out


def summary(st: dict) -> str:
    keys = ["start", "end", "days", "trades", "trades_per_day", "total_return_pct", "cagr_pct",
            "avg_daily_pct", "median_daily_pct", "std_daily_pct", "worst_day_pct",
            "max_dd_pct", "calmar", "sharpe", "win_rate_pct", "profit_factor",
            "expectancy_r", "max_losing_streak"]
    lines = []
    for k in keys:
        v = st.get(k)
        if isinstance(v, float):
            lines.append(f"  {k:22s} {v:12.3f}")
        else:
            lines.append(f"  {k:22s} {v!s:>12s}")
    if "by_symbol" in st:
        lines.append("  by symbol: " + ", ".join(f"{k}:{v['n']}tr/{v['pnl']:.0f}$" for k, v in st["by_symbol"].items()))
    return "\n".join(lines)
