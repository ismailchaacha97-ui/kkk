"""Generate demo screenshots showing exactly what the Premium/Discount
indicator draws (zones, levels, labels, panel).

Image 1: XAUUSD M5 - synthetic intraday candles anchored to REAL COMEX gold
         futures daily OHLC (Sep 9-11, 2026); zones from the previous day's
         dealing range (the indicator's default PREV DAY anchor).
Image 2: PAXG H1 - REAL hourly closes of PAX Gold (Aug 13-16, 2026) with the
         zones computed by the actual engine (engine.compute_session).
"""

import os
import random
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine import Params, compute_session, calc_levels, zone_of, seconds_to_open, time_in_window

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from matplotlib.patches import Rectangle

OUT = "/home/user/kkk/examples"
os.makedirs(OUT, exist_ok=True)

BG = "#131722"
GRID = "#232a37"
UP = "#26a69a"
DN = "#ef5350"
C_PREM = (1.0, 0.35, 0.35)
C_DISC = (0.31, 0.75, 0.35)
C_DEEP = (1.0, 0.59, 0.16)
C_EQ = "#ffc107"
C_TOP = "#ff5252"
C_BOT = "#4caf50"
C_DEEP_L = "#ff8c00"
C_EXT = "#9696a0"
C_TXT = "#e1e4e9"
C_PNL_BG = "#161a24"
C_PNL_BD = "#3a4152"


def fmt(v, nd=2):
    return f"{v:.{nd}f}"


# ----------------------------------------------------------------------------
# synthetic M5 candles anchored to real daily OHLC
# ----------------------------------------------------------------------------

def make_day(o, h, l, c, points, n=288, seed=0):
    """Random-walk M5 closes that move between control points (frac, price),
    clipped to [l, h], ending exactly at c, touching h and l."""
    rng = random.Random(seed)
    closes = []
    seg = 0
    for k in range(n):
        f = k / (n - 1)
        while seg < len(points) - 2 and f > points[seg + 1][0]:
            seg += 1
        f0, p0 = points[seg]
        f1, p1 = points[seg + 1]
        u = (f - f0) / (f1 - f0) if f1 > f0 else 0.0
        target = p0 + (p1 - p0) * u
        p = target + rng.gauss(0, 1) * (h - l) * 0.011
        p = min(max(p, l), h)
        closes.append(p)
    closes[-1] = c
    closes[closes.index(min(closes))] = l
    closes[closes.index(max(closes))] = h
    bars = []
    prev = o
    for k in range(n):
        cc = closes[k]
        hi = min(max(prev, cc) * (1 + rng.random() * 0.00005), h)
        lo = max(min(prev, cc) * (1 - rng.random() * 0.00005), l)
        bars.append((prev, hi, lo, cc))
        prev = cc
    return bars


REAL_DAYS = [
    # (label, open, high, low, close)  - real COMEX GC=F daily candles
    ("2026-09-08", 4398.7, 4416.0, 4397.4, 4416.0),   # anchor for Sep 9
    ("2026-09-09", 4418.9, 4420.0, 4330.7, 4364.5),   # collapse day
    ("2026-09-10", 4365.8, 4389.5, 4365.8, 4366.2),   # quiet day
    # Sep 11: real session extremes from the live session (4333.0/4444.9),
    # intraday path simulated
    ("2026-09-11", 4380.0, 4444.9, 4333.0, 4408.9),
]

PLOT_DAYS = REAL_DAYS[1:]   # show Sep 9, 10, 11


def build_m5():
    paths = {
        "2026-09-09": [(0.0, 4418.9), (0.012, 4420.0), (0.30, 4378.0), (0.72, 4330.7), (1.0, 4364.5)],
        "2026-09-10": [(0.0, 4365.8), (0.10, 4368.0), (0.50, 4389.5), (0.80, 4372.0), (1.0, 4366.2)],
        "2026-09-11": [(0.0, 4380.0), (0.30, 4333.0), (0.55, 4362.0), (0.88, 4444.9), (1.0, 4408.9)],
    }
    days = {}
    for (label, o, h, l, c) in PLOT_DAYS:
        days[label] = (o, h, l, c, make_day(o, h, l, c, paths[label], seed=abs(hash(label)) % 1000))
    return days


def draw_zones(ax, day_start_dt, day_end_dt, sess, t_end):
    """Draw premium/discount bands + levels for one day segment."""
    x0 = mdates.date2num(day_start_dt)
    x1 = mdates.date2num(day_end_dt)
    lv = calc_levels(sess)
    ax.fill_between([x0, x1], lv.eq, lv.top, color=C_PREM, alpha=0.11, linewidth=0, zorder=1)
    ax.fill_between([x0, x1], lv.bot, lv.eq, color=C_DISC, alpha=0.11, linewidth=0, zorder=1)
    ax.fill_between([x0, x1], lv.deep_prem, lv.top, color=C_DEEP, alpha=0.13, linewidth=0, zorder=1)
    ax.fill_between([x0, x1], lv.bot, lv.deep_disc, color=C_DEEP, alpha=0.13, linewidth=0, zorder=1)
    styles = [(lv.top, C_TOP, "-", 1.4), (lv.bot, C_BOT, "-", 1.4),
              (lv.deep_prem, C_DEEP_L, "--", 0.9), (lv.deep_disc, C_DEEP_L, "--", 0.9),
              (lv.ext_prem, C_EXT, ":", 0.8), (lv.ext_disc, C_EXT, ":", 0.8)]
    for p, col, ls, lw in styles:
        ax.hlines(p, x0, x1, colors=col, linestyles=ls, linewidths=lw, zorder=5)
    ax.hlines(lv.eq, x0, x1, colors=C_EQ, linestyles="-", linewidths=1.6, zorder=5)
    return lv


def demo_m5():
    days = build_m5()
    fig, ax = plt.subplots(figsize=(16, 9), dpi=110)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)

    anchors = {p[0]: Params(anchor_mode=0, point=0.01) for p in PLOT_DAYS}
    # daily sessions (anchor = previous day's range), same math as the indicator
    sess_by_day = {}
    for i, (label, o, h, l, c) in enumerate(REAL_DAYS):
        if label == "2026-09-08":
            continue
        anchor = REAL_DAYS[i - 1]
        from engine import Session
        s = Session(start=0, end=0, high=anchor[2], low=anchor[3], open=anchor[1], valid=True)
        s.eq = (s.high + s.low) / 2
        s.tag = "PREV DAY"
        sess_by_day[label] = s

    t_last = None
    for label, (o, h, l, c, bars) in days.items():
        t0 = datetime.strptime(label, "%Y-%m-%d").replace(tzinfo=timezone.utc)
        xs, ys_open, ys_hi, ys_lo, ys_cl = [], [], [], [], []
        for k, (bo, bh, bl, bc) in enumerate(bars):
            t = t0 + timedelta(minutes=5 * k)
            xs.append(mdates.date2num(t))
            ys_open.append(bo); ys_hi.append(bh); ys_lo.append(bl); ys_cl.append(bc)
        t_end = t0 + timedelta(days=1)
        lv = draw_zones(ax, t0, t_end, sess_by_day[label], t_end)
        for x, bo, bh, bl, bc in zip(xs, ys_open, ys_hi, ys_lo, ys_cl):
            col = UP if bc >= bo else DN
            ax.vlines(x, bl, bh, color=col, linewidth=0.7, zorder=4)
            ax.vlines(x, min(bo, bc), max(bo, bc), color=col, linewidth=2.6, zorder=4)
        t_last = t_end

    # --- labels for the final (current) session, rayed to the right edge
    last_label = PLOT_DAYS[-1][0]
    lv = calc_levels(sess_by_day[last_label])
    xR = mdates.date2num(t_last)
    xend = mdates.date2num(t_last + timedelta(hours=2))
    t0n = mdates.date2num(datetime.strptime(last_label, "%Y-%m-%d").replace(tzinfo=timezone.utc))
    for p, col, ls, lw in [(lv.top, C_TOP, "-", 1.4), (lv.bot, C_BOT, "-", 1.4),
                           (lv.deep_prem, C_DEEP_L, "--", 0.9), (lv.deep_disc, C_DEEP_L, "--", 0.9),
                           (lv.ext_prem, C_EXT, ":", 0.8), (lv.ext_disc, C_EXT, ":", 0.8)]:
        ax.hlines(p, t0n, xend, colors=col, linestyles=ls, linewidths=lw, zorder=5)
    ax.hlines(lv.eq, t0n, xend, colors=C_EQ, linewidths=1.6, zorder=5)

    labels = [
        (lv.top, C_TOP, f"RANGE HIGH 100%   {fmt(lv.top)}"),
        (lv.deep_prem, C_DEEP_L, f"DEEP PREMIUM 70.5%   {fmt(lv.deep_prem)}"),
        (lv.eq, C_EQ, f"EQ 50%   {fmt(lv.eq)}"),
        (lv.deep_disc, C_DEEP_L, f"DEEP DISCOUNT 29.5%   {fmt(lv.deep_disc)}"),
        (lv.bot, C_BOT, f"RANGE LOW 0%   {fmt(lv.bot)}"),
    ]
    for p, col, txt in labels:
        ax.text(xend + 0.012, p, txt, color=col, fontsize=8, va="center",
                fontfamily="monospace", zorder=5)
    ax.text(xend + 0.012, lv.ext_prem, f"TARGET +50%   {fmt(lv.ext_prem)}", color=C_EXT,
            fontsize=8, va="center", fontfamily="monospace", zorder=5)
    ax.text(xend + 0.012, lv.ext_disc, f"TARGET -50%   {fmt(lv.ext_disc)}", color=C_EXT,
            fontsize=8, va="center", fontfamily="monospace", zorder=5)

    # --- annotations (the buy-cheap / sell-high story)
    t11 = datetime.strptime("2026-09-11", "%Y-%m-%d").replace(tzinfo=timezone.utc)
    ax.annotate("Asia sweep of DISCOUNT 4333.0\nBUY cheap - target EQ",
                xy=(mdates.date2num(t11 + timedelta(hours=7, minutes=30)), 4341),
                xytext=(mdates.date2num(t11 + timedelta(hours=9)), 4305),
                color=C_BOT, fontsize=9, fontweight="bold",
                arrowprops=dict(arrowstyle="->", color=C_BOT, lw=1.2))
    ax.annotate("NY rally into EXTREME PREMIUM 4444.9\nSELL high - target EQ",
                xy=(mdates.date2num(t11 + timedelta(hours=21, minutes=10)), 4438),
                xytext=(mdates.date2num(t11 + timedelta(hours=16)), 4495),
                color=C_TOP, fontsize=9, fontweight="bold",
                arrowprops=dict(arrowstyle="->", color=C_TOP, lw=1.2))
    t9 = datetime.strptime("2026-09-09", "%Y-%m-%d").replace(tzinfo=timezone.utc)
    ax.annotate("Opened ABOVE range high\n= extreme premium -> SELL",
                xy=(mdates.date2num(t9 + timedelta(minutes=20)), 4417),
                xytext=(mdates.date2num(t9 + timedelta(hours=5)), 4490),
                color=C_TOP, fontsize=9, fontweight="bold",
                arrowprops=dict(arrowstyle="->", color=C_TOP, lw=1.2))

    # --- info panel (mimics the MT panel)
    px = PLOT_DAYS[-1][3]
    side, pct, deep = zone_of(px, lv)
    pcttxt = f"PREMIUM {pct:.1f}%" if side == "premium" else f"DISCOUNT {pct:.1f}%"
    if px > lv.top:
        zone = "EXTREME PREMIUM - SELL AREA"; zc = C_TOP
    elif px > lv.deep_prem:
        zone = "DEEP PREMIUM - SELL AREA"; zc = C_DEEP_L
    elif px > lv.eq:
        zone = "PREMIUM - SELL AREA"; zc = C_TOP
    elif px < lv.bot:
        zone = "EXTREME DISCOUNT - BUY AREA"; zc = C_BOT
    elif px < lv.deep_disc:
        zone = "DEEP DISCOUNT - BUY AREA"; zc = C_DEEP_L
    elif px < lv.eq:
        zone = "DISCOUNT - BUY AREA"; zc = C_BOT
    else:
        zone = "AT EQUILIBRIUM - NEUTRAL"; zc = C_TXT

    now = t11 + timedelta(hours=23, minutes=55)
    london = f"London KZ: {'OPEN NOW' if time_in_window(int(now.timestamp()),7,0,10,0) else 'in ' + str(timedelta(seconds=seconds_to_open(int(now.timestamp()),7,0)))}"
    ny = f"New York KZ: {'OPEN NOW' if time_in_window(int(now.timestamp()),13,0,16,0) else 'in ' + str(timedelta(seconds=seconds_to_open(int(now.timestamp()),13,0)))}"
    main_txt = ("PREMIUM / DISCOUNT   XAUUSD M5\n"
                f"Anchor: PREV DAY   (2026.09.10)\n"
                f"Range:  {fmt(lv.bot)} - {fmt(lv.top)}   ({fmt(lv.top-lv.bot)})\n"
                f"EQ:     {fmt(lv.eq)} (50%)\n"
                f"Price:  {fmt(px)}")
    ax.text(0.012, 0.985, main_txt, transform=ax.transAxes, color=C_TXT, fontsize=9,
            va="top", ha="left", fontfamily="monospace", linespacing=1.5,
            bbox=dict(facecolor=C_PNL_BG, edgecolor=C_PNL_BD, alpha=0.94, boxstyle="round,pad=0.5"))
    zone_txt = f"Position: {pcttxt}   >>   {zone}"
    ax.text(0.012, 0.985 - 0.115, zone_txt, transform=ax.transAxes, color=zc, fontsize=9.5,
            va="top", ha="left", fontfamily="monospace", fontweight="bold")
    rest_txt = (f"Deep prem: {fmt(lv.deep_prem)}   Deep disc: {fmt(lv.deep_disc)}\n"
                f"{london}\n{ny}")
    ax.text(0.012, 0.985 - 0.155, rest_txt, transform=ax.transAxes, color=C_TXT, fontsize=9,
            va="top", ha="left", fontfamily="monospace", linespacing=1.5)

    # --- axes cosmetics
    ax.set_xlim(mdates.date2num(datetime.strptime("2026-09-09", "%Y-%m-%d").replace(tzinfo=timezone.utc) - timedelta(hours=1)),
                mdates.date2num(t_last + timedelta(hours=4)))
    ax.set_ylim(4280, 4520)
    ax.grid(color=GRID, linewidth=0.5, alpha=0.6)
    ax.tick_params(colors="#9aa4b2", labelsize=9)
    for spine in ax.spines.values():
        spine.set_color(GRID)
    loc = mdates.HourLocator(byhour=[0, 6, 12, 18])
    ax.xaxis.set_major_locator(loc)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d\n%H:%M", tz=timezone.utc))
    ax.set_title("Premium/Discount indicator - XAUUSD M5  (ICT dealing range, PREV DAY anchor)",
                 color=C_TXT, fontsize=13, loc="left", pad=12)
    ax.text(0.995, 0.012,
            "Daily anchors = real COMEX gold futures (GC=F) Sep 8-10 2026; Sep 11 intraday path simulated from the real session extremes",
            transform=ax.transAxes, color="#8a93a3", fontsize=8.5, ha="right")
    fig.savefig(f"{OUT}/premium_discount_gold_m5_demo.png", facecolor=BG, bbox_inches="tight")
    plt.close(fig)
    print("wrote", f"{OUT}/premium_discount_gold_m5_demo.png")


# ----------------------------------------------------------------------------
# real PAXG hourly data with the actual engine
# ----------------------------------------------------------------------------

def load_paxg():
    import csv
    rows = []
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "paxg_h1_2026.csv")) as f:
        for r in csv.DictReader(f):
            t = int(r["t_ms"]) // 1000
            c = float(r["close"])
            rows.append({"t": t, "o": c, "h": c, "l": c, "c": c})
    rows.sort(key=lambda b: b["t"])
    # keep Aug 13 00:00 -> Aug 17 00:00 UTC (Aug 13 is anchor data only)
    start = datetime(2026, 8, 13, tzinfo=timezone.utc).timestamp()
    end = datetime(2026, 8, 17, tzinfo=timezone.utc).timestamp()
    return [b for b in rows if start <= b["t"] < end]


def demo_paxg():
    bars = load_paxg()
    p = Params(anchor_mode=0, point=0.01)
    fig, ax = plt.subplots(figsize=(16, 9), dpi=110)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)

    # group by session (day), using the engine
    sess_map = {}
    for i, b in enumerate(bars):
        s = compute_session(bars, i, p)
        if s is not None:
            sess_map[b["t"]] = s
    days = {}
    for b in bars:
        d = datetime.fromtimestamp(b["t"], timezone.utc).date()
        days.setdefault(d, []).append(b)

    for d, dbars in days.items():
        if d == datetime(2026, 8, 13, tzinfo=timezone.utc).date():
            continue  # anchor data only, not plotted
        t0 = datetime(d.year, d.month, d.day, tzinfo=timezone.utc)
        t1 = t0 + timedelta(days=1)
        s = None
        for b in dbars:
            if b["t"] in sess_map:
                s = sess_map[b["t"]]
        if s is None:
            continue  # day without a resolved anchor (no previous-day data)
        x0, x1 = mdates.date2num(t0), mdates.date2num(t1)
        lv = calc_levels(s)
        ax.fill_between([x0, x1], lv.eq, lv.top, color=C_PREM, alpha=0.10, linewidth=0, zorder=1)
        ax.fill_between([x0, x1], lv.bot, lv.eq, color=C_DISC, alpha=0.10, linewidth=0, zorder=1)
        for p_, col, ls, lw in [(lv.top, C_TOP, "-", 1.3), (lv.bot, C_BOT, "-", 1.3),
                                (lv.deep_prem, C_DEEP_L, "--", 0.9), (lv.deep_disc, C_DEEP_L, "--", 0.9)]:
            ax.hlines(p_, x0, x1, colors=col, linestyles=ls, linewidths=lw, zorder=5)
        ax.hlines(lv.eq, x0, x1, colors=C_EQ, linewidths=1.5, zorder=5)

    xs = [mdates.date2num(datetime.fromtimestamp(b["t"], timezone.utc)) for b in bars]
    cs = [b["c"] for b in bars]
    ax.plot(xs, cs, color="#7aa2f7", linewidth=1.4, zorder=4)
    ax.plot(xs, cs, color="#7aa2f7", marker="o", markersize=2.2, linewidth=0, zorder=4)

    # final session labels
    last_s = sess_map[bars[-1]["t"]]
    lv = calc_levels(last_s)
    t_last = mdates.date2num(datetime.fromtimestamp(bars[-1]["t"], timezone.utc))
    xend = t_last + 0.12
    t0n = mdates.date2num(datetime(2026, 8, 15, tzinfo=timezone.utc))
    for p_, col, ls, lw in [(lv.top, C_TOP, "-", 1.3), (lv.bot, C_BOT, "-", 1.3),
                            (lv.deep_prem, C_DEEP_L, "--", 0.9), (lv.deep_disc, C_DEEP_L, "--", 0.9)]:
        ax.hlines(p_, t0n, xend, colors=col, linestyles=ls, linewidths=lw, zorder=5)
    ax.hlines(lv.eq, t0n, xend, colors=C_EQ, linewidths=1.5, zorder=5)
    for p_, col, txt in [(lv.top, C_TOP, f"RANGE HIGH 100%   {fmt(lv.top)}"),
                         (lv.deep_prem, C_DEEP_L, f"DEEP PREMIUM 70.5%   {fmt(lv.deep_prem)}"),
                         (lv.eq, C_EQ, f"EQ 50%   {fmt(lv.eq)}"),
                         (lv.deep_disc, C_DEEP_L, f"DEEP DISCOUNT 29.5%   {fmt(lv.deep_disc)}"),
                         (lv.bot, C_BOT, f"RANGE LOW 0%   {fmt(lv.bot)}")]:
        ax.text(xend + 0.012, p_, txt, color=col, fontsize=8, va="center", fontfamily="monospace")

    px = bars[-1]["c"]
    side, pct, deep = zone_of(px, lv)
    if side == "premium":
        pcttxt, zone, zc = f"PREMIUM {pct:.1f}%", ("DEEP PREMIUM - SELL AREA" if deep else "PREMIUM - SELL AREA"), C_TOP
    else:
        pcttxt, zone, zc = f"DISCOUNT {pct:.1f}%", ("DEEP DISCOUNT - BUY AREA" if deep else "DISCOUNT - BUY AREA"), C_BOT
    main_txt = ("PREMIUM / DISCOUNT   PAXG H1\n"
                f"Anchor: PREV DAY   (2026.08.15)\n"
                f"Range:  {fmt(lv.bot)} - {fmt(lv.top)}   ({fmt(lv.top-lv.bot)})\n"
                f"EQ:     {fmt(lv.eq)} (50%)\n"
                f"Price:  {fmt(px)}")
    ax.text(0.012, 0.985, main_txt, transform=ax.transAxes, color=C_TXT, fontsize=9,
            va="top", ha="left", fontfamily="monospace", linespacing=1.5,
            bbox=dict(facecolor=C_PNL_BG, edgecolor=C_PNL_BD, alpha=0.94, boxstyle="round,pad=0.5"))
    ax.text(0.012, 0.985 - 0.115, f"Position: {pcttxt}   >>   {zone}", transform=ax.transAxes,
            color=zc, fontsize=9.5, va="top", ha="left", fontfamily="monospace", fontweight="bold")

    ax.set_xlim(mdates.date2num(datetime(2026, 8, 14, tzinfo=timezone.utc) - timedelta(hours=2)),
                mdates.date2num(datetime(2026, 8, 17, 6, tzinfo=timezone.utc)))
    ax.set_ylim(min(cs) - 18, max(cs) + 14)
    ax.grid(color=GRID, linewidth=0.5, alpha=0.6)
    ax.tick_params(colors="#9aa4b2", labelsize=9)
    for spine in ax.spines.values():
        spine.set_color(GRID)
    ax.xaxis.set_major_locator(mdates.DayLocator(tz=timezone.utc))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %d", tz=timezone.utc))
    ax.set_title("Premium/Discount indicator - REAL DATA: PAX Gold (PAXG) hourly, Aug 14-16 2026",
                 color=C_TXT, fontsize=13, loc="left", pad=12)
    ax.text(0.995, 0.012, "Zones = previous-day dealing range, computed by the same engine as the MQL indicator (real data)",
            transform=ax.transAxes, color="#8a93a3", fontsize=8.5, ha="right")
    fig.savefig(f"{OUT}/premium_discount_paxg_h1_real.png", facecolor=BG, bbox_inches="tight")
    plt.close(fig)
    print("wrote", f"{OUT}/premium_discount_paxg_h1_real.png")


if __name__ == "__main__":
    demo_m5()
    demo_paxg()
