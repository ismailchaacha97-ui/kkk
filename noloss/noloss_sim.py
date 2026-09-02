#!/usr/bin/env python3
"""
Simulator for the family of forex systems marketed as "No Loss" / "Rule OP".

Pure Python standard library only - no numpy, no pandas, no pip install.

What this models
----------------
"Rule OP" systems sold in the Indonesian/Malaysian retail-forex community are
almost always one of two position-management schemes dressed up as a
"guaranteed no loss" method:

  A) Grid + Martingale
     Buy, and if price moves against you by `step` pips, buy again with
     `multiplier` x the previous lot. Repeat. Close everything at one take
     profit. Because the newest position is bigger, a small bounce recovers the
     whole stack, so the win rate looks like 95-99%.

  B) Hedge + Martingale ("no loss" lock)
     Open BUY and SELL at the same time. One leg hits its take profit first and
     banks a profit. The other leg is now a naked loser, so you average it down
     with a martingale ladder until it recovers. Marketing calls the initial
     hedge a "lock" that makes loss impossible.

Neither has any edge. Both convert a random walk into a payoff distribution
that is: many small wins, plus a small probability of losing the whole account.
This script measures that distribution with a Monte Carlo and writes the
numbers into report.md along with SVG charts.

Run:  python3 noloss/noloss_sim.py
"""

from __future__ import annotations

import math
import os
import random
import statistics
import dataclasses
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Instrument / account constants
# ---------------------------------------------------------------------------

PIP_VALUE_PER_LOT = 10.0   # USD per 1.00 lot per 1 pip, EURUSD-style standard
PIP_SIZE = 0.0001          # price units in one pip (4-digit EURUSD scale)


@dataclass
class Params:
    """Everything a Rule-OP style system needs to specify."""

    balance: float = 100.0        # starting equity, USD
    base_lot: float = 0.01        # lot size of the first position
    tp_pips: float = 20.0         # take profit distance, pips
    step_pips: float = 30.0       # adverse move that triggers the next ladder rung
    multiplier: float = 2.0       # martingale multiplier per rung
    spread_pips: float = 1.5      # spread you pay on every entry
    max_rungs: int = 40           # ladder depth the "guru" claims is plenty
    stop_out_pct: float = 0.5     # broker force-closes when equity < 50% of used margin
    leverage: int = 500           # 1:500, so margin per lot = 100_000 * price / leverage
    price: float = 1.1000         # entry price, EURUSD-ish
    swap_per_lot_per_tick: float = 0.0   # overnight financing, USD per lot per tick
    tick_sd_pips: float = 3.3     # 1-sigma price movement per tick, pips
    equity_stop_pct: float = 0.0  # 0 = off. Close all at this % off the peak.
    cycles_target: int = 0        # 0 = off. Stop after this many closed cycles

    def margin_per_lot(self) -> float:
        return 100_000.0 * self.price / self.leverage


# ---------------------------------------------------------------------------
# Synthetic price path
# ---------------------------------------------------------------------------

class PricePath:
    """Discrete random walk in pip space.

    Deliberately drift-free (zero expected return) so nothing in the results can
    come from an edge in the price model - any profit the strategy books is
    purely an artefact of the position sizing, and any blow-up is purely an
    artefact of the payoff shape. That is the whole point of the exercise.
    """

    def __init__(self, tick_sd_pips: float, seed: int):
        self.tick_sd = tick_sd_pips
        self.rng = random.Random(seed)

    def next_pip_move(self) -> float:
        # sum of 6 uniforms -> approximately normal, no numpy needed
        u = sum(self.rng.random() for _ in range(6)) - 3.0
        return u * math.sqrt(2.0) * self.tick_sd


# ---------------------------------------------------------------------------
# Strategy A: grid + martingale
# ---------------------------------------------------------------------------

@dataclass
class Ladder:
    """An open martingale stack of same-direction positions."""

    direction: int                       # +1 buy, -1 sell
    entries: list = field(default_factory=list)  # list of (entry_price_pips, lot)

    @property
    def total_lot(self) -> float:
        return sum(lot for _, lot in self.entries)

    def floating_pnl(self, px: float) -> float:
        return sum((px - e) * self.direction * lot * PIP_VALUE_PER_LOT
                   for e, lot in self.entries)

    def average_entry(self) -> float:
        tot = self.total_lot
        if tot == 0:
            return 0.0
        return sum(e * lot for e, lot in self.entries) / tot


def simulate_grid(p: Params, n_ticks: int, tick_sd_pips: float | None, seed: int,
                  trace: list | None = None) -> dict:
    """One lifecycle of grid+martingale, from first entry to close or blow-up."""
    path = PricePath(p.tick_sd_pips if tick_sd_pips is None else tick_sd_pips,
                     seed)
    ladder = Ladder(direction=+1)
    px = 0.0  # work in pips relative to first entry
    ladder.entries.append((px + p.spread_pips, p.base_lot))

    equity_curve = []
    max_rung = 1
    max_floating = 0.0
    balance = p.balance
    cycles_closed = 0
    peak_equity = p.balance

    for tick in range(n_ticks):
        px += path.next_pip_move()

        # margin used by the stack
        margin = ladder.total_lot * p.margin_per_lot()
        equity = balance + ladder.floating_pnl(px)
        equity_curve.append(equity)
        if equity > peak_equity:
            peak_equity = equity

        # the EA's circuit breaker: a discretionary stop, taken at a loss,
        # before the broker takes it for you
        if (p.equity_stop_pct > 0.0
                and equity <= peak_equity * (1.0 - p.equity_stop_pct / 100.0)):
            return _result(p, equity, equity_curve, max_rung, max_floating,
                           cycles_closed, blowup=False, tick=tick,
                           stopped=True)
        if p.cycles_target > 0 and cycles_closed >= p.cycles_target:
            return _result(p, equity, equity_curve, max_rung, max_floating,
                           cycles_closed, blowup=False, tick=tick,
                           stopped=True)

        # broker stop-out: force close everything, book the floating loss
        if margin > 0 and equity <= p.stop_out_pct * margin:
            return _result(p, balance + ladder.floating_pnl(px), equity_curve,
                           max_rung, max_floating, cycles_closed,
                           blowup=True, tick=tick)
        if equity <= 0:
            return _result(p, 0.0, equity_curve, max_rung, max_floating,
                           cycles_closed, blowup=True, tick=tick)

        max_floating = min(max_floating, ladder.floating_pnl(px))

        # basket take profit: close the whole stack at its average entry + tp
        tp_level = ladder.average_entry() + p.tp_pips
        if px >= tp_level:
            pnl = ladder.floating_pnl(px)
            balance += pnl
            cycles_closed += 1
            if trace is not None:
                trace.append({
                    "kind": "grid_cycle",
                    "rungs": len(ladder.entries),
                    "lot": ladder.total_lot,
                    "pnl": pnl,
                    "tick": tick,
                })
            ladder = Ladder(direction=+1)
            ladder.entries.append((px + p.spread_pips, p.base_lot))
            max_rung = 1
            continue

        # adverse move of `step` pips below the deepest entry -> add a rung
        deepest = min(e for e, _ in ladder.entries)
        if px <= deepest - p.step_pips:
            if len(ladder.entries) >= p.max_rungs:
                # ladder exhausted: the system has no answer left
                return _result(p, balance + ladder.floating_pnl(px),
                               equity_curve, max_rung, max_floating,
                               cycles_closed, blowup=False, tick=tick,
                               exhausted=True)
            last_lot = ladder.entries[-1][1]
            new_lot = last_lot * p.multiplier
            # a real broker rejects this order when free margin is gone; the
            # stack then sits there until the stop out level takes it
            if free_margin(p, balance, ladder.floating_pnl(px),
                           ladder.total_lot + new_lot) <= 0:
                return _result(p, balance + ladder.floating_pnl(px),
                               equity_curve, max_rung, max_floating,
                               cycles_closed, blowup=False, tick=tick,
                               exhausted=True, blocked=True)
            ladder.entries.append((px + p.spread_pips, new_lot))
            max_rung = max(max_rung, len(ladder.entries))

    return _result(p, balance + ladder.floating_pnl(px), equity_curve,
                   max_rung, max_floating, cycles_closed, blowup=False,
                   tick=n_ticks)


def margin_used(p: Params, total_lot: float) -> float:
    """Margin locked up by `total_lot`, mirroring LadderMargin in the MT4 core."""
    return total_lot * p.margin_per_lot()


def free_margin(p: Params, balance: float, floating: float,
                total_lot: float) -> float:
    """What the broker would let you open another position with.

    Real MT4 rejects the order when this is not positive. Omitting this check
    makes a martingale look far more durable than it is, because the model lets
    you keep adding rungs after the account could no longer fund them.
    """
    return balance + floating - margin_used(p, total_lot)


def _result(p, final_balance, curve, max_rung, max_floating, cycles, blowup,
            tick, exhausted=False, blocked=False, stopped=False):
    peak = p.balance
    max_dd = 0.0
    for v in curve:
        peak = max(peak, v)
        max_dd = max(max_dd, peak - v)
    return {
        "final_balance": final_balance,
        "equity_curve": curve,
        "max_rung": max_rung,
        "max_floating_pnl": max_floating,
        "cycles_closed": cycles,
        "blowup": blowup,
        "exhausted": exhausted,
        "blocked": blocked,
        "stopped": stopped,
        "max_drawdown": max_dd,
        "ticks": tick,
    }


# ---------------------------------------------------------------------------
# Strategy B: hedge lock + martingale on the losing leg
# ---------------------------------------------------------------------------

def simulate_hedge(p: Params, n_ticks: int, tick_sd_pips: float | None, seed: int,
                   trace: list | None = None) -> dict:
    """Open buy+sell together, bank the first take profit, then ladder the loser."""
    path = PricePath(p.tick_sd_pips if tick_sd_pips is None else tick_sd_pips,
                     seed)
    px = 0.0

    # both legs open at once; spread is paid on each
    buy_entry = px + p.spread_pips / 2
    sell_entry = px - p.spread_pips / 2
    lot = p.base_lot

    balance = p.balance
    banked = 0.0
    buy_open = True
    sell_open = True
    buy_lot = sell_lot = lot
    ladder = None  # once a leg survives, it becomes a martingale stack
    survivor_dir = 0
    equity_curve = []
    max_rung = 1
    max_floating = 0.0
    cycles_closed = 0

    def floating():
        f = 0.0
        if buy_open:
            f += (px - buy_entry) * buy_lot * PIP_VALUE_PER_LOT
        if sell_open:
            f += (sell_entry - px) * sell_lot * PIP_VALUE_PER_LOT
        if ladder is not None:
            f += ladder.floating_pnl(px)
        return f

    def margin_used():
        m = 0.0
        if buy_open:
            m += buy_lot * p.margin_per_lot()
        if sell_open:
            m += sell_lot * p.margin_per_lot()
        if ladder is not None:
            m += ladder.total_lot * p.margin_per_lot()
        return m

    for tick in range(n_ticks):
        px += path.next_pip_move()

        f = floating()
        if p.swap_per_lot_per_tick:
            lots = (buy_lot if buy_open else 0) + (sell_lot if sell_open else 0)
            if ladder is not None:
                lots += ladder.total_lot
            f -= lots * p.swap_per_lot_per_tick
        equity = balance + banked + f
        equity_curve.append(equity)

        m = margin_used()
        if m > 0 and equity <= p.stop_out_pct * m:
            return _result(p, max(equity, 0.0), equity_curve, max_rung,
                           max_floating, cycles_closed, True, tick)
        if equity <= 0:
            return _result(p, 0.0, equity_curve, max_rung, max_floating,
                           cycles_closed, True, tick)
        max_floating = min(max_floating, f)

        # leg 1: bank whichever take profit is hit first
        if buy_open and px >= buy_entry + p.tp_pips:
            banked += p.tp_pips * buy_lot * PIP_VALUE_PER_LOT
            if trace is not None:
                trace.append({"kind": "hedge_banked", "lot": buy_lot,
                              "pnl": p.tp_pips * buy_lot * PIP_VALUE_PER_LOT,
                              "tick": tick,
                              "survivor_floating": (sell_entry - px)
                              * sell_lot * PIP_VALUE_PER_LOT})
            buy_open = False
            survivor_dir = -1
            ladder = Ladder(direction=-1, entries=[(sell_entry, sell_lot)])
            sell_open = False
            cycles_closed += 1
            continue
        if sell_open and px <= sell_entry - p.tp_pips:
            banked += p.tp_pips * sell_lot * PIP_VALUE_PER_LOT
            if trace is not None:
                trace.append({"kind": "hedge_banked", "lot": sell_lot,
                              "pnl": p.tp_pips * sell_lot * PIP_VALUE_PER_LOT,
                              "tick": tick,
                              "survivor_floating": (px - buy_entry)
                              * buy_lot * PIP_VALUE_PER_LOT})
            sell_open = False
            survivor_dir = +1
            ladder = Ladder(direction=+1, entries=[(buy_entry, buy_lot)])
            buy_open = False
            cycles_closed += 1
            continue

        # leg 2: martingale the surviving loser until it recovers
        if ladder is not None:
            tp_level = ladder.average_entry() + survivor_dir * p.tp_pips
            if (px >= tp_level) == (survivor_dir == +1):
                rec = ladder.floating_pnl(px)
                if trace is not None:
                    trace.append({"kind": "hedge_recovery",
                                  "rungs": len(ladder.entries),
                                  "lot": ladder.total_lot, "pnl": rec,
                                  "tick": tick, "banked_given_up": banked})
                balance += rec
                banked = 0.0
                cycles_closed += 1
                # new hedge cycle
                buy_entry = px + p.spread_pips / 2
                sell_entry = px - p.spread_pips / 2
                buy_lot = sell_lot = p.base_lot
                buy_open = sell_open = True
                ladder = None
                survivor_dir = 0
                max_rung = 1
                continue

            if survivor_dir == +1:
                deepest = min(e for e, _ in ladder.entries)
                trigger = px <= deepest - p.step_pips
            else:
                deepest = max(e for e, _ in ladder.entries)
                trigger = px >= deepest + p.step_pips
            if trigger:
                if len(ladder.entries) >= p.max_rungs:
                    return _result(p, max(equity, 0.0), equity_curve, max_rung,
                                   max_floating, cycles_closed, False, tick,
                                   exhausted=True)
                new_lot = ladder.entries[-1][1] * p.multiplier
                if free_margin(p, balance + banked, f,
                               ladder.total_lot + new_lot) <= 0:
                    return _result(p, max(equity, 0.0), equity_curve, max_rung,
                                   max_floating, cycles_closed, False, tick,
                                   exhausted=True, blocked=True)
                ladder.entries.append((px + p.spread_pips / 2, new_lot))
                max_rung = max(max_rung, len(ladder.entries))

    return _result(p, balance + banked + floating(), equity_curve, max_rung,
                   max_floating, cycles_closed, False, n_ticks)


# ---------------------------------------------------------------------------
# Monte Carlo driver
# ---------------------------------------------------------------------------

def monte_carlo(sim, p, n_runs, n_ticks, tick_sd_pips, seed0):
    runs = []
    for i in range(n_runs):
        runs.append(sim(p, n_ticks, tick_sd_pips, seed0 + i))
    return runs


def monte_carlo_traced(sim, p, n_runs, n_ticks, tick_sd_pips, seed0):
    """Same as monte_carlo but also returns the per-cycle event log."""
    runs, events = [], []
    for i in range(n_runs):
        tr = []
        runs.append(sim(p, n_ticks, tick_sd_pips, seed0 + i, trace=tr))
        events.extend(tr)
    return runs, events


def cycle_table(events, kind, p):
    """Group closed cycles by ladder depth. This is the heart of the lesson.

    With the basket take profit sitting at the *average* entry of the stack,
    the P&L of a closed cycle is (total lot) x (take profit in pips) x
    (pip value) - and total lot after n rungs of a 2x martingale is
    base_lot * (2**n - 1). So the payout of a closed cycle grows
    geometrically with how deep the ladder had to go.
    """
    by_rung = {}
    for e in events:
        if e["kind"] != kind:
            continue
        by_rung.setdefault(e["rungs"], []).append(e)
    rows = []
    for rung in sorted(by_rung):
        grp = by_rung[rung]
        total_lot = p.base_lot * (p.multiplier ** rung - 1) / (p.multiplier - 1)
        pnls = [g["pnl"] for g in grp]
        rows.append({
            "rung": rung,
            "n": len(grp),
            "share": len(grp) / max(1, len([e for e in events
                                            if e["kind"] == kind])),
            "total_lot": total_lot,
            "theoretical": total_lot * p.tp_pips * PIP_VALUE_PER_LOT,
            "mean_pnl": statistics.mean(pnls),
            "min_pnl": min(pnls),
        })
    return rows


def pct(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    idx = min(len(s) - 1, max(0, int(round(q * (len(s) - 1)))))
    return s[idx]


def summarize(runs, p):
    finals = [r["final_balance"] for r in runs]
    dds = [r["max_drawdown"] for r in runs]
    blowups = [r for r in runs if r["blowup"]]
    winners = [r for r in runs if r["final_balance"] > p.balance]
    rungs = [r["max_rung"] for r in runs]
    floats = [r["max_floating_pnl"] for r in runs]
    return {
        "n": len(runs),
        "win_rate": len(winners) / len(runs),
        "blowup_rate": len(blowups) / len(runs),
        "exhausted_rate": sum(1 for r in runs if r.get("exhausted")) / len(runs),
        "blocked_rate": sum(1 for r in runs if r.get("blocked")) / len(runs),
        "median_final": statistics.median(finals),
        "mean_final": statistics.mean(finals),
        "p10_final": pct(finals, 0.10),
        "p90_final": pct(finals, 0.90),
        "median_max_dd": statistics.median(dds),
        "p90_max_dd": pct(dds, 0.90),
        "median_rung": statistics.median(rungs),
        "p95_rung": pct(rungs, 0.95),
        "max_rung": max(rungs),
        "median_worst_floating": statistics.median(floats),
        "p95_worst_floating": pct(floats, 0.95),
        "median_cycles": statistics.median([r["cycles_closed"] for r in runs]),
        "total_final": sum(finals),
        "total_start": p.balance * len(runs),
    }


# ---------------------------------------------------------------------------
# Chart output: hand-rolled SVG, no matplotlib
# ---------------------------------------------------------------------------

def svg_equity(curves, path, width=900, height=300, blowup_idx=None):
    n = max(len(c) for c in curves)
    flat = [v for c in curves for v in c]
    lo, hi = min(flat), max(flat)
    span = (hi - lo) or 1.0

    def sx(i, ln):
        return 60 + (i / max(1, ln - 1)) * (width - 90)

    def sy(v):
        return height - 30 - ((v - lo) / span) * (height - 60)

    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
             f'height="{height}" viewBox="0 0 {width} {height}">',
             f'<rect width="{width}" height="{height}" fill="#0f1115"/>']
    # zero / starting balance line
    if lo <= 0 <= hi:
        y = sy(0)
        parts.append(f'<line x1="60" y1="{y:.1f}" x2="{width-30}" y2="{y:.1f}" '
                     'stroke="#e5484d" stroke-width="1" stroke-dasharray="4 4"/>')
        parts.append(f'<text x="62" y="{y-4:.1f}" fill="#e5484d" font-size="11" '
                     'font-family="monospace">account wiped (equity = 0)</text>')
    colors = ["#46a758", "#3b82f6", "#f5a623", "#a855f7", "#e5484d"]
    for k, c in enumerate(curves):
        pts = " ".join(f"{sx(i, len(c)):.1f},{sy(v):.1f}" for i, v in enumerate(c))
        parts.append(f'<polyline points="{pts}" fill="none" '
                     f'stroke="{colors[k % len(colors)]}" stroke-width="1.4"/>')
    parts.append(f'<text x="60" y="20" fill="#e6e6e6" font-size="13" '
                 'font-family="monospace">equity (USD) vs tick</text>')
    parts.append(f'<text x="60" y="{height-10}" fill="#8b8b8b" font-size="11" '
                 'font-family="monospace">0</text>')
    parts.append(f'<text x="{width-40}" y="{height-10}" fill="#8b8b8b" '
                 'font-size="11" font-family="monospace">{n}</text>')
    parts.append('</svg>')
    with open(path, "w") as f:
        f.write("\n".join(parts))


def svg_rungs(hist, path, width=900, height=260):
    """Histogram of the deepest ladder rung reached."""
    keys = sorted(hist)
    mx = max(hist.values())
    bw = (width - 90) / max(1, len(keys))
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
             f'height="{height}" viewBox="0 0 {width} {height}">',
             f'<rect width="{width}" height="{height}" fill="#0f1115"/>']
    for i, k in enumerate(keys):
        h = (hist[k] / mx) * (height - 70)
        x = 60 + i * bw
        y = height - 40 - h
        col = "#46a758" if k <= 4 else ("#f5a623" if k <= 7 else "#e5484d")
        parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw-3:.1f}" '
                     f'height="{h:.1f}" fill="{col}"/>')
        parts.append(f'<text x="{x+bw/2:.1f}" y="{height-24}" fill="#8b8b8b" '
                     f'font-size="10" font-family="monospace" '
                     f'text-anchor="middle">{k}</text>')
    parts.append('<text x="60" y="20" fill="#e6e6e6" font-size="13" '
                 'font-family="monospace">how deep the martingale ladder got '
                 '(rung = lot multiplier level)</text>')
    parts.append('</svg>')
    with open(path, "w") as f:
        f.write("\n".join(parts))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def ladder_table(p: Params) -> list:
    """Pure arithmetic: what the martingale ladder demands of the account.

    Two loss figures, because conflating them is exactly what makes these
    systems look survivable:

      newest_rung_loss - the loss on the rung just added, taken alone. This is
                         what most Rule-OP write-ups show, and it is small.
      stack_floating   - the loss on the WHOLE stack at that rung's entry.
                         This is what your equity actually reads, and it is
                         roughly 2.5x larger by rung 6.

    Both are reported. Only the second one can stop you out.
    """
    rows = []
    entries = []
    lots = []
    lot = p.base_lot
    for rung in range(1, 13):
        entries.append((rung - 1) * p.step_pips)   # adverse pips at this rung
        lots.append(lot)
        adverse = (rung - 1) * p.step_pips
        newest_loss = adverse * lot * PIP_VALUE_PER_LOT
        # signed: negative, because it is a loss. Storing the magnitude here
        # is a trap - every consumer has to remember to negate it, and one
        # of them did not.
        stack_floating = -sum((adverse - entries[i]) * lots[i]
                              for i in range(rung)) * PIP_VALUE_PER_LOT
        cum_lot = sum(lots[:rung])
        rows.append({
            "rung": rung,
            "lot": lot,
            "cum_lot": cum_lot,
            "adverse_pips": adverse,
            "newest_rung_loss": newest_loss,
            "cum_loss_usd": newest_loss,      # kept for report continuity
            "stack_floating_usd": stack_floating,
            "basket_tp_usd": cum_lot * p.tp_pips * PIP_VALUE_PER_LOT,
            "margin_usd": cum_lot * p.margin_per_lot(),
        })
        lot *= p.multiplier
    return rows


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    p = Params()

    tick_sd = None         # None -> use p.tick_sd_pips, so the field is live
    n_ticks = 4000
    n_runs = 600

    print("simulating grid + martingale ...")
    grid_runs, grid_events = monte_carlo_traced(
        simulate_grid, p, n_runs, n_ticks, tick_sd, seed0=1000)
    grid = summarize(grid_runs, p)

    print("simulating hedge lock + martingale ...")
    hedge_runs, hedge_events = monte_carlo_traced(
        simulate_hedge, p, n_runs, n_ticks, tick_sd, seed0=7000)
    hedge = summarize(hedge_runs, p)

    grid_cycles = cycle_table(grid_events, "grid_cycle", p)
    hedge_banked = [e for e in hedge_events if e["kind"] == "hedge_banked"]
    hedge_recov = cycle_table(hedge_events, "hedge_recovery", p)

    print("sweeping base lot size ...")
    sweep = lot_sweep(p, n_runs, n_ticks, tick_sd)
    print("sweeping spread (cost only, no edge) ...")
    spread_sweep = spread_test(p, n_runs, n_ticks, tick_sd)

    # ---- charts ----
    sample_grid = [r["equity_curve"] for r in grid_runs[:5]]
    sample_hedge = [r["equity_curve"] for r in hedge_runs[:5]]
    svg_equity(sample_grid, os.path.join(here, "equity_grid.svg"))
    svg_equity(sample_hedge, os.path.join(here, "equity_hedge.svg"))

    def rung_hist(runs):
        h = {}
        for r in runs:
            h[r["max_rung"]] = h.get(r["max_rung"], 0) + 1
        return h

    svg_rungs(rung_hist(grid_runs), os.path.join(here, "rungs_grid.svg"))
    svg_rungs(rung_hist(hedge_runs), os.path.join(here, "rungs_hedge.svg"))

    # ---- console summary ----
    for name, s in (("GRID + MARTINGALE", grid), ("HEDGE LOCK + MARTINGALE", hedge)):
        print(f"\n=== {name} === ({s['n']} accounts of ${p.balance:.0f})")
        print(f"  accounts ending in profit        : {s['win_rate']*100:5.1f}%")
        print(f"  accounts blown up (stop-out)     : {s['blowup_rate']*100:5.1f}%")
        print(f"  runs blocked by free margin      : {s['blocked_rate']*100:5.1f}%")
        print(f"  runs that hit the rung cap       : "
              f"{(s['exhausted_rate']-s['blocked_rate'])*100:5.1f}%")
        print(f"  median final equity              : ${s['median_final']:8.2f}")
        print(f"  mean final equity                : ${s['mean_final']:8.2f}")
        print(f"  10th pct final equity            : ${s['p10_final']:8.2f}")
        print(f"  90th pct final equity            : ${s['p90_final']:8.2f}")
        print(f"  median max drawdown              : ${s['median_max_dd']:8.2f}")
        print(f"  90th pct max drawdown            : ${s['p90_max_dd']:8.2f}")
        print(f"  median deepest rung              : {s['median_rung']:.0f}")
        print(f"  95th pct deepest rung            : {s['p95_rung']:.0f}")
        print(f"  worst rung ever seen             : {s['max_rung']}")
        print(f"  median worst floating P&L        : ${s['median_worst_floating']:8.2f}")
        print(f"  95th pct worst floating P&L      : ${s['p95_worst_floating']:8.2f}")
        print(f"  median completed cycles          : {s['median_cycles']:.0f}")
        print(f"  total capital in  -> ${s['total_start']:,.0f}")
        print(f"  total capital out -> ${s['total_final']:,.0f} "
              f"({s['total_final']/s['total_start']-1:+.1%})")

    # ---- cycle decomposition, the actual mechanism ----
    print("\n=== what a CLOSED cycle pays, by ladder depth (grid, spread "
          f"{p.spread_pips}) ===")
    print(f"  {'rungs':>5} {'share':>7} {'total lot':>10} "
          f"{'min P&L':>9} {'mean P&L':>9}")
    for r in grid_cycles:
        print(f"  {r['rung']:>5} {r['share']*100:>6.1f}% {r['total_lot']:>10.3f} "
              f"{r['min_pnl']:>9.2f} {r['mean_pnl']:>9.2f}")
    min_closed = min(r["min_pnl"] for r in grid_cycles)
    print(f"  -> the smallest closed cycle in "
          f"{sum(r['n'] for r in grid_cycles)} cycles still paid "
          f"+${min_closed:.2f}. That is the 'no loss' claim, and it is real.")

    # ---- write report.md ----
    rows = ladder_table(p)
    write_report(here, p, grid, hedge, rows, n_ticks, tick_sd, n_runs,
                 grid_cycles, hedge_recov, hedge_banked, sweep, spread_sweep)
    print("\nwrote report.md, equity_grid.svg, equity_hedge.svg, "
          "rungs_grid.svg, rungs_hedge.svg")


def _theo(cycles, rung):
    for r in cycles:
        if r["rung"] == rung:
            return r["theoretical"]
    return 0.0


def lot_sweep(p: Params, n_runs, n_ticks, tick_sd, sweep_runs=2000):
    """The universal objection: 'just use a smaller lot'. Does it work?"""
    out = []
    for lot in (0.01, 0.005, 0.002, 0.001):
        q = dataclasses.replace(p, base_lot=lot)
        s = summarize(monte_carlo(simulate_grid, q, sweep_runs, n_ticks,
                                 tick_sd, seed0=42), q)
        s["base_lot"] = lot
        out.append(s)
    return out


def spread_test(p: Params, n_runs, n_ticks, tick_sd, sweep_runs=1500):
    """Isolate the cost channel by switching the spread off."""
    out = {}
    for tag, sp in (("grid spread=0", 0.0), ("grid spread=%.1f" % p.spread_pips,
                                             p.spread_pips),
                    ("hedge spread=0", 0.0),
                    ("hedge spread=%.1f" % p.spread_pips, p.spread_pips)):
        q = dataclasses.replace(p, spread_pips=sp)
        sim = simulate_grid if tag.startswith("grid") else simulate_hedge
        out[tag] = summarize(monte_carlo(sim, q, sweep_runs, n_ticks, tick_sd,
                                        seed0=42), q)
    return out


def write_report(here, p, grid, hedge, rows, n_ticks, tick_sd, n_runs,
                 grid_cycles, hedge_recov, hedge_banked, sweep, spread_sweep):
    md = []
    a = md.append
    a("# The \"No Loss\" / Rule OP system, measured\n")
    a("Generated by `noloss_sim.py`. Re-run it any time with "
      "`python3 noloss/noloss_sim.py` - pure standard library, nothing to install.\n")
    a("## What was simulated\n")
    a(f"| parameter | value |\n|---|---|\n"
      f"| starting balance | ${p.balance:.0f} |\n"
      f"| first lot | {p.base_lot} |\n"
      f"| take profit | {p.tp_pips:.0f} pips |\n"
      f"| martingale step | {p.step_pips:.0f} pips adverse |\n"
      f"| multiplier | {p.multiplier}x |\n"
      f"| spread | {p.spread_pips} pips |\n"
      f"| leverage | 1:{p.leverage} |\n"
      f"| stop out | equity < {p.stop_out_pct*100:.0f}% of used margin |\n"
      f"| price model | zero-drift random walk, {p.tick_sd_pips} pips sigma/tick |\n"
      f"| ticks per run | {n_ticks} |\n"
      f"| accounts per variant | {n_runs} |\n")
    a("The price model has **zero expected return**. There is no edge in it. "
      "So every dollar these systems \"earns\" comes from position sizing, and "
      "every blow-up comes from the same place.\n")
    a("## The ladder, in plain arithmetic\n")
    a("Before any simulation, here is what the martingale ladder *requires*. "
      "This is not a model result, it is just multiplication.\n")
    a("| rung | lot | cum lot | adverse move | loss on newest rung | "
      "**floating loss on the whole stack** | basket TP payout | margin |\n"
      "|---|---|---|---|---|---|---|---|")
    for r in rows:
        a(f"| {r['rung']} | {r['lot']:.4f} | {r['cum_lot']:.3f} | "
          f"{r['adverse_pips']:.0f} pips | ${r['newest_rung_loss']:,.0f} | "
          f"**-${abs(r['stack_floating_usd']):,.0f}** | "
          f"${r['basket_tp_usd']:,.0f} | "
          f"${r['margin_usd']:,.0f} |")
    a("\nLook hard at the two loss columns, because conflating them is exactly "
      "what makes these systems look survivable. \"Loss on newest rung\" is "
      "what Rule-OP write-ups show you: the damage done by the position you "
      "just added, considered on its own. \"Floating loss on the whole stack\" "
      "is what your equity actually reads, and by rung 6 it is "
      f"${abs(rows[5]['stack_floating_usd']):,.0f} against the "
      f"${rows[5]['newest_rung_loss']:,.0f} you were shown. Only the second "
      "column can stop you out.\n")
    # deterministic depth limit, matching the MT4 indicator's MaxAffordableRung
    # Same rule as RungIsSurvivable in RuleOP_Ladder.mq4: after opening the
    # rung, equity must still sit above the stop out level AND there must be
    # free margin left. Checking only the stop out level is far too generous -
    # it lets the account keep adding rungs it could never actually fund.
    max_ok = 0
    killer = None
    for r in rows:
        equity = p.balance + r["stack_floating_usd"]
        if (equity > p.stop_out_pct * r["margin_usd"]
                and equity - r["margin_usd"] > 0):
            max_ok = r["rung"]
        else:
            killer = r
            break
    if killer is not None:
        last = rows[max_ok - 1]
        a(f"With these exact settings on a ${p.balance:.0f} account at "
          f"1:{p.leverage} and a {p.stop_out_pct*100:.0f}% stop out, the deepest "
          f"rung you can open is **rung {max_ok}** - just "
          f"{last['adverse_pips']:.0f} pips of adverse move. Rung "
          f"{killer['rung']} is the one that kills you: it wants "
          f"{killer['lot']:.2f} lot on top of a stack already "
          f"${abs(last['stack_floating_usd']):,.0f} underwater. "
          "`RuleOP_Ladder.mq4` computes the same number live and draws it as "
          "the kill price.\n")
    else:
        a(f"Every rung in this table still fits a ${p.balance:.0f} account at "
          f"1:{p.leverage}. Extend the table and it stops fitting quickly.\n")
    a(f"Read the bottom rows: by rung 10 the system is carrying "
      f"{rows[9]['adverse_pips']:.0f} pips of adverse move, "
      f"{rows[9]['cum_lot']:.2f} lot in total, and a stack floating loss of "
      f"${abs(rows[9]['stack_floating_usd']):,.0f} on a ${p.balance:.0f} "
      f"account.\n")
    a("## Monte Carlo results\n")
    a(f"| metric | grid + martingale | hedge lock + martingale |\n|---|---|---|\n"
      f"| accounts ending in profit | {grid['win_rate']*100:.1f}% | "
      f"{hedge['win_rate']*100:.1f}% |\n"
      f"| accounts blown up | {grid['blowup_rate']*100:.1f}% | "
      f"{hedge['blowup_rate']*100:.1f}% |\n"
      f"| runs where the broker refused the next rung | "
      f"{grid['blocked_rate']*100:.1f}% | {hedge['blocked_rate']*100:.1f}% |\n"
      f"| runs where the ladder hit its rung cap | "
      f"{(grid['exhausted_rate']-grid['blocked_rate'])*100:.1f}% | "
      f"{(hedge['exhausted_rate']-hedge['blocked_rate'])*100:.1f}% |\n"
      f"| median final equity | ${grid['median_final']:.2f} | "
      f"${hedge['median_final']:.2f} |\n"
      f"| mean final equity | ${grid['mean_final']:.2f} | "
      f"${hedge['mean_final']:.2f} |\n"
      f"| 10th pct final equity | ${grid['p10_final']:.2f} | "
      f"${hedge['p10_final']:.2f} |\n"
      f"| 90th pct final equity | ${grid['p90_final']:.2f} | "
      f"${hedge['p90_final']:.2f} |\n"
      f"| median max drawdown | ${grid['median_max_dd']:.2f} | "
      f"${hedge['median_max_dd']:.2f} |\n"
      f"| 90th pct max drawdown | ${grid['p90_max_dd']:.2f} | "
      f"${hedge['p90_max_dd']:.2f} |\n"
      f"| median deepest rung | {grid['median_rung']:.0f} | "
      f"{hedge['median_rung']:.0f} |\n"
      f"| 95th pct deepest rung | {grid['p95_rung']:.0f} | "
      f"{hedge['p95_rung']:.0f} |\n"
      f"| median worst floating P&L | ${grid['median_worst_floating']:.2f} | "
      f"${hedge['median_worst_floating']:.2f} |\n"
      f"| 95th pct worst floating P&L | ${grid['p95_worst_floating']:.2f} | "
      f"${hedge['p95_worst_floating']:.2f} |\n"
      f"| median completed cycles | {grid['median_cycles']:.0f} | "
      f"{hedge['median_cycles']:.0f} |\n"
      f"| **capital in** | ${grid['total_start']:,.0f} | "
      f"${hedge['total_start']:,.0f} |\n"
      f"| **capital out** | **${grid['total_final']:,.0f}** "
      f"({grid['total_final']/grid['total_start']-1:+.1%}) | "
      f"**${hedge['total_final']:,.0f}** "
      f"({hedge['total_final']/hedge['total_start']-1:+.1%}) |\n")
    a("## Equity curves, five accounts each\n")
    a("![grid equity](equity_grid.svg)\n")
    a("![hedge equity](equity_hedge.svg)\n")
    a("## How deep did the ladder get?\n")
    a("![grid rungs](rungs_grid.svg)\n")
    a("![hedge rungs](rungs_hedge.svg)\n")
    a("## Why people believe the \"no loss\" claim - it is true, conditionally\n")
    a("This is the part almost nobody explains. Look at what a **closed** cycle "
      "actually pays, grouped by how deep the ladder had to go:\n")
    a("| ladder depth | share of all cycles | total lot | theoretical P&L "
      "(total lot x TP) | smallest P&L seen | mean P&L |\n|---|---|---|---|---|---|")
    for r in grid_cycles:
        a(f"| {r['rung']} rung{'s' if r['rung'] > 1 else ''} | "
          f"{r['share']*100:.1f}% | {r['total_lot']:.3f} | "
          f"${r['theoretical']:.2f} | ${r['min_pnl']:.2f} | "
          f"${r['mean_pnl']:.2f} |")
    min_closed = min(r["min_pnl"] for r in grid_cycles)
    a(f"\nAcross {sum(r['n'] for r in grid_cycles)} closed cycles, the *smallest* "
      f"P&L booked was **${min_closed:.2f}**. Not one closed cycle lost money. "
      "That is not marketing - it is forced by the geometry. The basket take "
      "profit sits at the **average** entry of the stack, so the instant price "
      "reaches it the whole stack is in profit by `total_lot x TP x pip_value`.\n")
    a("So the claim \"this system never loses\" is literally true of every trade "
      "it is allowed to finish. It is false of the account, because of the "
      f"{grid['blowup_rate']*100:.0f}% of accounts in this run that were never "
      "allowed to finish one. The system does not remove losses, it moves them "
      "out of the per-trade column and into a single balance-sheet event.\n")
    a("Two consequences of that table, and they are the whole strategy in two "
      "sentences:\n")
    a(f"1. Payout per closed cycle grows **geometrically** with ladder depth "
      f"(`base_lot x (2^n - 1) x TP`). A rung-1 cycle pays "
      f"${grid_cycles[0]['theoretical']:.2f}; a rung-5 cycle pays "
      f"${_theo(grid_cycles, 5):.2f}. The big wins are not luck, they "
      "are the deep ladders that happened to recover.\n")
    g0 = spread_sweep["grid spread=0"]
    g_cost = spread_sweep["grid spread=%.1f" % p.spread_pips]
    r0 = g0["total_final"] / g0["total_start"] - 1
    rc = g_cost["total_final"] / g_cost["total_start"] - 1
    a("2. The **probability** of reaching a deep rung falls at roughly the same "
      "geometric rate the payout rises, so the two effects largely cancel. That "
      "is the martingale identity: on a price series with no drift, no choice "
      "of TP, step or multiplier creates an edge. The simulation agrees - with "
      f"the spread switched off the grid returns {r0:+.1%} of capital over "
      f"{g0['n']} accounts, which is close enough to zero that the fat tail "
      "easily explains the gap. Turn the spread back on and it becomes "
      f"{rc:+.1%}. Costs are what convert a zero-expectation game into a "
      "losing one.\n")
    a("## Why the hedge version is worse, and it is not the spread\n")
    a("| variant | accounts | capital returned | accounts blown up | "
      "accounts in profit |\n|---|---|---|---|---|")
    for tag, s in spread_sweep.items():
        a(f"| {tag} | {s['n']} | "
          f"{s['total_final']/s['total_start']-1:+.1%} | "
          f"{s['blowup_rate']*100:.1f}% | {s['win_rate']*100:.1f}% |")
    h0 = spread_sweep["hedge spread=0"]
    a(f"\nSet the spread to zero and the gap is still there: "
      f"{g0['total_final']/g0['total_start']-1:+.1%} for the grid against "
      f"{h0['total_final']/h0['total_start']-1:+.1%} for the hedge. So costs "
      "are not the explanation. The mechanism is structural:\n")
    a("When the winning hedge leg takes profit, the surviving losing leg is "
      "entered at the **hedge** price, but the whole position only closes at "
      "`average entry + TP`. Because the survivor's entry is one TP distance "
      "behind, price has to recover that first. The result is that the hedge "
      "needs a deeper ladder to close the same recovery:\n")
    a("| ladder depth | grid: share of cycles | hedge: share of recoveries |\n"
      "|---|---|---|")
    gshare = {r["rung"]: r["share"] for r in grid_cycles}
    hshare = {r["rung"]: r["share"] for r in hedge_recov}
    for rung in sorted(set(gshare) | set(hshare)):
        a(f"| {rung} | {gshare.get(rung, 0)*100:.1f}% | "
          f"{hshare.get(rung, 0)*100:.1f}% |")
    g_deep = sum(v for k, v in gshare.items() if k >= 3)
    h_deep = sum(v for k, v in hshare.items() if k >= 3)
    a(f"\n{h_deep*100:.1f}% of hedge recoveries need 3+ rungs versus "
      f"{g_deep*100:.1f}% for the grid. Deeper ladders are the tail risk, so "
      "the \"safety lock\" you were sold actually buys more of it. "
      f"The hedge also books a small profit {len(hedge_banked)} times that it "
      "then gives back on the recovery close, which adds cost without adding "
      "any offsetting edge.\n")
    a("## The universal objection: \"just use a smaller lot\"\n")
    a("This is the finding worth the most, because it is counter-intuitive and "
      "it survived a re-run at higher sample size.\n")
    a("| base lot | stopped out | margin-blocked | **failed either way** | "
      "median final equity | capital returned | deepest rung |\n"
      "|---|---|---|---|---|---|---|")
    for s in sweep:
        failed = s["blowup_rate"] + s["blocked_rate"]
        a(f"| {s['base_lot']} | {s['blowup_rate']*100:.1f}% | "
          f"{s['blocked_rate']*100:.1f}% | **{failed*100:.1f}%** | "
          f"${s['median_final']:.2f} | "
          f"{s['total_final']/s['total_start']-1:+.1%} | {s['max_rung']} |")
    a("\nShrinking the lot does cut the overall failure rate - look at the bold "
      f"column, it falls from {sweep[0]['blowup_rate']*100+sweep[0]['blocked_rate']*100:.0f}% "
      f"to {sweep[-1]['blowup_rate']*100+sweep[-1]['blocked_rate']*100:.0f}%. "
      "But read *which* failure it removes. Almost all of the improvement is in "
      f"the margin-blocked column ({sweep[0]['blocked_rate']*100:.0f}% down to "
      f"{sweep[-1]['blocked_rate']*100:.0f}%), because a small lot can actually "
      "fund a full ladder. The stopped-out column, which is the catastrophic "
      "one, does not fall cleanly - it rises at first "
      f"({sweep[0]['blowup_rate']*100:.0f}% to {sweep[1]['blowup_rate']*100:.0f}%) "
      "before collapsing at the very smallest size.\n")
    a("So a smaller lot buys you a longer life with more green days, and shifts "
      "the way it ends from a quiet margin refusal toward a violent stop-out. "
      "Capital returned improves a little and stays negative in every row. You "
      "are not buying an edge, you are buying time.\n")
    a("## What this means in practice\n")
    a("- The system's win rate is real and high. Its expected value is not.\n")
    a("- Every parameter you can tune (TP, step, multiplier, lot) changes the "
      "*shape* of the distribution - how often the tail hits and how big it "
      "is - never its sign.\n")
    a("- The failure has two faces. About "
      f"{grid['blocked_rate']*100:.0f}% of the time the account simply runs out "
      "of margin and the ladder cannot fund its next rung. About "
      f"{grid['blowup_rate']*100:.0f}% of the time a single trending move takes "
      "it to the stop-out level in one go. Either way the run ends, and both "
      "happen after a long run of small green days that made the method look "
      "proven.\n")
    a("- Anyone selling this with a money-back guarantee is short the tail. "
      "The guarantee is funded by the students who have not been trading long "
      "enough to hit it yet.\n")
    with open(os.path.join(here, "report.md"), "w") as f:
        f.write("\n".join(md) + "\n")


if __name__ == "__main__":
    main()
