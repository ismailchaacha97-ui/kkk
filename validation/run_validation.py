"""Validation suite for the Premium/Discount indicator logic.

Runs unit tests, no-repaint / determinism checks and real-data smoke tests
against engine.py (the Python mirror of PremiumDiscount.mq4/.mq5), plus a
performance check on 3 months of synthetic M5 bars.
"""

import csv
import os
import random
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine import (DAY, ANCHOR_ASIA, ANCHOR_CUR_DAY, ANCHOR_PREV_DAY,
                    AlertEngine, Params, Session, asia_window, calc_levels,
                    compute_session, seconds_to_open, time_in_window,
                    zone_of)

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  [PASS] {name}")
    else:
        FAIL += 1
        print(f"  [FAIL] {name}  {detail}")


def utc_ts(y, mo, d, h=0, mi=0):
    return int(datetime(y, mo, d, h, mi, tzinfo=timezone.utc).timestamp())


def load_csv(name):
    rows = []
    with open(os.path.join(DATA, name)) as f:
        for r in csv.DictReader(f):
            if "t_ms" in r:
                t = int(r["t_ms"]) // 1000
                c = float(r["close"])
                rows.append({"t": t, "o": c, "h": c, "l": c, "c": c})
            else:
                d = datetime.strptime(r["date"], "%Y-%m-%d").replace(tzinfo=timezone.utc)
                t = int(d.timestamp())
                if "open" in r:
                    o, h, l, c = (float(r[k]) for k in ("open", "high", "low", "close"))
                else:
                    # ECB daily rate (close only): synthesize a plausible
                    # daily range so the range-based engine can be exercised
                    c = float(r["close"])
                    o = c * (1 - 0.0012)
                    h = c * (1 + 0.0055)
                    l = c * (1 - 0.0055)
                rows.append({"t": t, "o": o, "h": h, "l": l, "c": c})
    rows.sort(key=lambda b: b["t"])
    return rows


# ----------------------------------------------------------------------------
# synthetic M5 generator: Mon-Fri, session-shaped volatility, trend regimes
# ----------------------------------------------------------------------------

def synth_m5(days=60, seed=7, start_ts=None, start_price=4400.0, drift=0.15):
    """days trading days of 288 M5 bars each (00:00-23:55 UTC)."""
    rng = random.Random(seed)
    if start_ts is None:
        start_ts = utc_ts(2026, 6, 1)
    bars = []
    t = start_ts
    price = start_price
    day_count = 0
    while day_count < days:
        wd = datetime.fromtimestamp(t, timezone.utc).weekday()
        if wd >= 5:  # skip weekend
            t += DAY
            continue
        d_open = price
        regime = rng.choice([-1, 0, 0, 1])  # trend days mixed with chop
        day_range = price * (0.004 + 0.006 * rng.random())
        for k in range(288):
            hh = (k // 12)  # hour of day
            if hh < 6:      mult = 0.55      # Asia
            elif hh < 10:   mult = 1.25      # London open
            elif hh < 13:   mult = 0.9
            elif hh < 16:   mult = 1.45      # NY open
            else:           mult = 0.7
            # soft pull toward the day's trend target
            frac = k / 287.0
            target = d_open + regime * day_range * 0.7
            pull = (target - price) * 0.012
            step = (rng.gauss(0, 1) * price * 0.00045 * mult) + pull + drift
            o = price
            price = max(o + step, 0.0001)
            h = max(o, price) * (1 + rng.random() * 0.00012)
            l = min(o, price) * (1 - rng.random() * 0.00012)
            bars.append({"t": t + k * 300, "o": o, "h": h, "l": l, "c": price})
        t += DAY
        day_count += 1
        drift *= 0.995
    return bars


# ----------------------------------------------------------------------------
# unit tests
# ----------------------------------------------------------------------------

def test_windows():
    print("== time window math ==")
    # London KZ 07:00-10:00, NY 13:00-16:00
    t = utc_ts(2026, 9, 10, 8, 30)
    check("in London KZ", time_in_window(t, 7, 0, 10, 0) is True)
    check("not in NY KZ at 08:30", time_in_window(t, 13, 0, 16, 0) is False)
    t = utc_ts(2026, 9, 10, 14, 0)
    check("in NY KZ at 14:00", time_in_window(t, 13, 0, 16, 0) is True)
    t = utc_ts(2026, 9, 10, 16, 0)
    check("16:00 is outside (end exclusive)", time_in_window(t, 13, 0, 16, 0) is False)
    t = utc_ts(2026, 9, 10, 6, 59)
    check("06:59 not in London KZ", time_in_window(t, 7, 0, 10, 0) is False)
    # cross-midnight window 22:00-02:00
    t = utc_ts(2026, 9, 10, 23, 30)
    check("cross-midnight 23:30 in 22:00-02:00", time_in_window(t, 22, 0, 2, 0) is True)
    t = utc_ts(2026, 9, 11, 1, 30)
    check("cross-midnight 01:30 in 22:00-02:00", time_in_window(t, 22, 0, 2, 0) is True)
    t = utc_ts(2026, 9, 11, 3, 0)
    check("cross-midnight 03:00 not in 22:00-02:00", time_in_window(t, 22, 0, 2, 0) is False)
    # seconds to next open
    t = utc_ts(2026, 9, 10, 5, 0)
    check("next KZ open in 7200s", seconds_to_open(t, 7, 0) == 7200)
    # asia window selection
    p = Params(anchor_mode=ANCHOR_ASIA, asia_start=(0, 0), asia_end=(6, 0))
    t = utc_ts(2026, 9, 10, 3, 0)          # Asia not finished -> yesterday's
    s, e = asia_window(t, p)
    check("asia at 03:00 uses yesterday", (e - s == 6 * 3600) and e == utc_ts(2026, 9, 10, 6, 0) - DAY)
    t = utc_ts(2026, 9, 10, 7, 0)          # after end -> today's completed
    s, e = asia_window(t, p)
    check("asia at 07:00 uses today", s == utc_ts(2026, 9, 10, 0, 0) and e == utc_ts(2026, 9, 10, 6, 0))


def test_levels():
    print("== level / zone math ==")
    s = Session(start=0, end=DAY, high=100.0, low=0.0, open=50.0, valid=True)
    s.eq = 50.0
    lv = calc_levels(s)
    check("EQ = 50", abs(lv.eq - 50.0) < 1e-9)
    check("deep premium = 70.5", abs(lv.deep_prem - 70.5) < 1e-9)
    check("deep discount = 29.5", abs(lv.deep_disc - 29.5) < 1e-9)
    check("ext premium = 150", abs(lv.ext_prem - 150.0) < 1e-9)
    check("ext discount = -50", abs(lv.ext_disc + 50.0) < 1e-9)
    side, pct, deep = zone_of(75.0, lv)
    check("75 -> premium 50% deep", side == "premium" and abs(pct - 50.0) < 1e-9 and deep)
    side, pct, deep = zone_of(60.0, lv)
    check("60 -> premium 20%", side == "premium" and abs(pct - 20.0) < 1e-9 and not deep)
    side, pct, deep = zone_of(71.0, lv)
    check("71 -> deep premium", side == "premium" and deep)
    side, pct, deep = zone_of(25.0, lv)
    check("25 -> discount 50% deep", side == "discount" and abs(pct - 50.0) < 1e-9 and deep)
    side, pct, deep = zone_of(120.0, lv)
    check("120 -> premium 140% (beyond range)", side == "premium" and abs(pct - 140.0) < 1e-9)
    # open-based EQ
    s2 = Session(start=0, end=DAY, high=100.0, low=0.0, open=60.0, valid=True)
    s2.eq = 60.0
    lv2 = calc_levels(s2)
    side, pct, deep = zone_of(80.0, lv2)
    check("open-EQ: 80 -> premium 50%", side == "premium" and abs(pct - 50.0) < 1e-9)


def test_session_selection():
    print("== session selection ==")
    bars = synth_m5(days=12, seed=3)
    i = len(bars) - 1
    p = Params(anchor_mode=ANCHOR_PREV_DAY, point=0.01)
    s = compute_session(bars, i, p)
    now = bars[i]["t"]
    check("prev-day session found", s is not None and s.valid)
    check("prev-day window correct",
          s is not None and s.start == (now // DAY - 1) * DAY and s.end == (now // DAY) * DAY)
    check("prev-day range plausible",
          s is not None and 0 < s.high - s.low < 1000.0)
    # CUR_DAY
    p = Params(anchor_mode=ANCHOR_CUR_DAY, point=0.01)
    s = compute_session(bars, i, p)
    check("cur-day session found", s is not None and s.valid and s.start == (now // DAY) * DAY)
    # ASIA completed
    p = Params(anchor_mode=ANCHOR_ASIA, asia_start=(0, 0), asia_end=(6, 0), point=0.01)
    s = compute_session(bars, i, p)
    check("asia session found", s is not None and s.valid and s.tag == "ASIA")
    # tiny-range guard
    flat = [{"t": bars[j]["t"], "o": 100.0, "h": 100.001, "l": 99.999, "c": 100.0} for j in range(len(bars))]
    p = Params(anchor_mode=ANCHOR_PREV_DAY, point=0.01)
    s = compute_session(flat, i, p)
    check("flat bars -> no valid session", s is None)
    # weekend: Monday 02:00, asia 00-06 not finished -> falls back to Friday's asia,
    # then (no bars) to prev-day chain -> Friday range
    mon = utc_ts(2026, 9, 7, 2, 0)
    bars2 = synth_m5(days=5, seed=4, start_ts=mon - 5 * DAY)
    i2 = len(bars2) - 1
    while bars2[i2]["t"] >= mon - 300:
        i2 -= 1
    i2 += 1
    p = Params(anchor_mode=ANCHOR_ASIA, asia_start=(0, 0), asia_end=(6, 0), point=0.01)
    s = compute_session(bars2, i2, p)
    check("Monday 02:00 asia falls back to a valid older range", s is not None and s.valid)


def test_no_repaint():
    print("== no-repaint / determinism ==")
    for mode in (ANCHOR_PREV_DAY, ANCHOR_CUR_DAY, ANCHOR_ASIA):
        for kz in (False, True):
            bars = synth_m5(days=35, seed=11 + mode)
            p = Params(anchor_mode=mode, point=0.01,
                       alert_only_killzones=kz)
            eng_full = AlertEngine(p)
            evs_full = []
            for i in range(2, len(bars)):
                sess = compute_session(bars, i, p)
                evs_full += eng_full.process(bars, i, sess, bars[i]["t"])
            # incremental run must produce identical history at every step
            eng_inc = AlertEngine(p)
            ok = True
            for i in range(2, len(bars)):
                sess = compute_session(bars, i, p)
                evs = eng_inc.process(bars, i, sess, bars[i]["t"])
                if eng_inc.events != eng_full.events[:len(eng_inc.events)]:
                    ok = False
                    break
            check(f"mode={mode} kz={kz}: incremental == full run", ok)
            # session lookup must not change when MORE bars arrive (same clock time,
            # deeper history) -- the only lookahead risk
            ok2 = True
            for i in range(100, len(bars), 97):
                s1 = compute_session(bars[:i + 1], i, p)
                s2 = compute_session(bars[:min(i + 50, len(bars))], i, p)
                if (s1 is None) != (s2 is None):
                    ok2 = False
                elif s1 is not None:
                    if s1.start != s2.start or s1.high != s2.high or s1.low != s2.low:
                        ok2 = False
            check(f"mode={mode} kz={kz}: session lookup stable vs deeper history", ok2)


def test_alert_firing():
    print("== alert firing semantics ==")
    bars = synth_m5(days=2, seed=42)
    p = Params(anchor_mode=ANCHOR_PREV_DAY, point=0.01, alert_only_killzones=False)
    eng = AlertEngine(p, symbol="TEST", tf="M5")
    n_events = 0
    types = set()
    for i in range(2, len(bars)):
        sess = compute_session(bars, i, p)
        evs = eng.process(bars, i, sess, bars[i]["t"])
        for (t, ev, text) in evs:
            types.add(ev)
            n_events += 1
            check(f"event {ev} has text", len(text) > 0)
    check("some events fired on 2 volatile days", n_events > 0, f"got {n_events}")
    # duplicates: same type+session must fire at most once
    keys = [(t, ev) for (t, ev, _) in eng.events]
    check("no duplicate (time,type) events", len(keys) == len(set(keys)))
    # killzone gating: same series with kz filter on, events only inside KZs
    p2 = Params(anchor_mode=ANCHOR_PREV_DAY, point=0.01, alert_only_killzones=True)
    eng2 = AlertEngine(p2, symbol="TEST", tf="M5")
    for i in range(2, len(bars)):
        sess = compute_session(bars, i, p2)
        eng2.process(bars, i, sess, bars[i]["t"])
    ok_kz = all(time_in_window(t, 7, 0, 10, 0) or time_in_window(t, 13, 0, 16, 0)
                for (t, _, _) in eng2.events)
    check("killzone filter: every alert inside a KZ", ok_kz)
    check("killzone filter reduces event count", len(eng2.events) <= len(eng.events))


def test_real_data():
    print("== real-data smoke tests ==")
    gold = load_csv("gold_daily_2026.csv")
    eurusd = load_csv("eurusd_daily_2026.csv")
    paxg = load_csv("paxg_h1_2026.csv")
    check("gold daily loaded", len(gold) == 22)
    check("eurusd daily loaded", len(eurusd) == 53)
    check("paxg hourly loaded", len(paxg) >= 200)
    for name, bars, point in (("gold", gold, 0.1), ("eurusd", eurusd, 0.0001), ("paxg", paxg, 0.01)):
        p = Params(anchor_mode=ANCHOR_PREV_DAY, point=point, alert_only_killzones=False)
        eng = AlertEngine(p, symbol=name.upper(), tf="H1" if name == "paxg" else "D1")
        sess_ok = 0
        total = 0
        zone_stat = {"premium": 0, "discount": 0, "eq": 0}
        for i in range(2, len(bars)):
            sess = compute_session(bars, i, p)
            if sess is None:
                continue
            sess_ok += 1
            eng.process(bars, i, sess, bars[i]["t"])
            side, pct, deep = zone_of(bars[i - 1]["c"], calc_levels(sess))
            zone_stat[side] += 1
            total += 1
        check(f"{name}: sessions resolved", sess_ok > 0)
        check(f"{name}: zone classification ran on {total} bars", total > 0)
        check(f"{name}: alerts ran without error", True)
        if name == "paxg":
            check("paxg: closes both sides of EQ exist", zone_stat["premium"] > 0 and zone_stat["discount"] > 0)
        print(f"    {name}: zone distribution {zone_stat}, events={len(eng.events)}")
        for (t, ev, text) in eng.events[:4]:
            print(f"      sample alert: {text}")


def test_perf():
    print("== performance ==")
    bars = synth_m5(days=60, seed=1)
    p = Params(anchor_mode=ANCHOR_PREV_DAY, point=0.01)
    t0 = time.time()
    n = 0
    for i in range(2, len(bars)):
        if compute_session(bars, i, p):
            n += 1
    dt = time.time() - t0
    print(f"  {len(bars)} bars, {n} sessions computed in {dt:.2f}s "
          f"({len(bars)/dt:.0f} bars/s) - MQL5 runs this only on new bars")
    check("no pathological slowdown", dt < 60.0)


if __name__ == "__main__":
    test_windows()
    test_levels()
    test_session_selection()
    test_no_repaint()
    test_alert_firing()
    test_real_data()
    test_perf()
    print(f"\n{PASS} passed, {FAIL} failed")
    sys.exit(1 if FAIL else 0)
