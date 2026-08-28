#!/usr/bin/env python3
"""Reference port of the MQL4 maths in VWAP_VolumeProfile.mq4 + unit tests.

There is no MetaEditor in this sandbox, so the algorithms are mirrored here
(bar-for-bar, same arithmetic) and asserted against hand-computed values.
If this file and the .mq4 disagree, one of them is wrong; if the tests pass,
the formulas in the indicator are the formulas below.

    python3 tools/reference_check.py
"""
import datetime as dt
import math
import os
import re
import sys

DAY = 86400
EPS = 1.0e-12

# ---------------------------------------------------------------- port of MQL4


def ts(y, m, d, hh=0, mm=0):
    return int(dt.datetime(y, m, d, hh, mm, tzinfo=dt.timezone.utc).timestamp())


def session_id(t, anchor="daily", off_h=0, off_m=0, weekday=1):
    """VVPSessionId()"""
    off = off_h * 3600 + off_m * 60
    dd = math.floor((t - off) / DAY)
    if anchor == "daily":
        return dd
    if anchor == "weekly":
        dow = ((dd + 4) % 7 + 7) % 7
        target = weekday % 7
        since = ((dow - target) % 7 + 7) % 7
        return math.floor((dd - since) / 7)
    if anchor == "monthly":
        x = dt.datetime.fromtimestamp(t, dt.timezone.utc)
        return x.year * 12 + x.month - 1
    raise ValueError(anchor)


def bar_price(b, kind="typical"):
    o, h, l, c = b[:4]
    if kind == "typical":
        return (h + l + c) / 3.0
    if kind == "weighted":
        return (h + l + 2.0 * c) / 4.0
    if kind == "median":
        return (h + l) / 2.0
    return c


def vwap(bars, anchor="daily", off_h=0, off_m=0, weekday=1, price="typical",
         sd1=1.0, sd2=2.0, anchor_time=None, max_bars=10 ** 9):
    """RecalcVWAP(): bars are newest-first, like MT4's arrays."""
    n = len(bars)
    depth = min(n - 1, max_bars)
    first = depth
    t_of = lambda i: bars[i][4]                                   # noqa: E731

    if anchor == "fixed":
        while first >= 0 and t_of(first) < anchor_time:
            first -= 1
    else:
        g = 0
        while first + 1 < n and session_id(t_of(first + 1), anchor, off_h, off_m, weekday) == \
                session_id(t_of(first), anchor, off_h, off_m, weekday) and g < n:
            first += 1
            g += 1

    out = [None] * n
    if first < 0:
        return out

    sv = svp = svp2 = 0.0
    cur = None
    for i in range(first, -1, -1):
        s = session_id(t_of(i), "fixed" if anchor == "fixed" else anchor,
                       off_h, off_m, weekday) if anchor != "fixed" else 1
        if anchor == "fixed":
            s = 1 if t_of(i) >= anchor_time else -1
        if s != cur:
            cur, sv, svp, svp2 = s, 0.0, 0.0, 0.0
        p = bar_price(bars[i], price)
        v = bars[i][5]
        v = 1.0 if v is None or v <= 0 else v
        sv += v
        svp += v * p
        svp2 += v * p * p
        vw = svp / sv if sv > EPS else p
        vr = svp2 / sv - vw * vw if sv > EPS else 0.0
        vr = max(vr, 0.0)
        sd = math.sqrt(vr)
        out[i] = (vw, vw + sd1 * sd, vw - sd1 * sd, vw + sd2 * sd, vw - sd2 * sd)
    return out, first, depth


def build_profile(bars, bins=10, model="uniform", mode="vol", va_pct=70.0, avg_vol=None):
    """BuildProfile(): bars newest-first for this session, oldest-last."""
    lo = min(b[2] for b in bars)                                   # Low
    hi = max(b[1] for b in bars)                                   # High
    if not hi > lo:
        pad = 1e-5 * bins * 0.5
        lo, hi = lo - pad, hi + pad
    bp = (hi - lo) / bins
    hist = [0.0] * bins

    use_vol = mode != "tpo"
    use_tpo = mode != "vol"
    if avg_vol is None:
        vs = [b[5] if b[5] and b[5] > 0 else 1.0 for b in bars]
        avg_vol = sum(vs) / len(vs) if vs else 1.0
    tpo_w = (avg_vol if use_vol else 1.0) if use_tpo else 0.0

    bin_of = lambda p: min(bins - 1, max(0, math.floor((p - lo) / bp)))   # noqa: E731

    for b in bars:
        o, h, l, c = b[:4]
        v = b[5]
        v = 1.0 if v is None or v <= 0 else v
        vol = v if use_vol else 0.0
        rng = h - l
        b0, b1 = bin_of(l), bin_of(h)
        if tpo_w > 0.0:
            for j in range(b0, b1 + 1):
                hist[j] += tpo_w
        if not use_vol:
            continue
        if rng <= EPS or b1 < b0:
            hist[bin_of(c)] += vol
            continue
        if model == "ohlc":
            hist[bin_of(c)] += vol * 0.25
            hist[bin_of(o)] += vol * 0.10
            hist[bin_of(h)] += vol * 0.075
            hist[bin_of(l)] += vol * 0.075
            rest = vol * 0.50
            for j in range(b0, b1 + 1):
                ov = min(h, lo + (j + 1) * bp) - max(l, lo + j * bp)
                if ov > 0.0:
                    hist[j] += rest * ov / rng
        else:
            for j in range(b0, b1 + 1):
                ov = min(h, lo + (j + 1) * bp) - max(l, lo + j * bp)
                if ov > 0.0:
                    hist[j] += vol * ov / rng

    tot, mx, poc = sum(hist), 0.0, 0
    for j, x in enumerate(hist):
        if x > mx:
            mx, poc = x, j
    if tot <= EPS or mx <= EPS:
        return None

    target = min(tot, tot * va_pct / 100.0)
    up = dn = poc
    acc = hist[poc]
    for _ in range(bins + 2):
        if acc >= target:
            break
        can_up, can_dn = up < bins - 1, dn > 0
        if not can_up and not can_dn:
            break
        vu = hist[up + 1] if can_up else -1.0
        vd = hist[dn - 1] if can_dn else -1.0
        if vu >= vd:
            up += 1
            acc += hist[up]
        else:
            dn -= 1
            acc += hist[dn]
    return dict(hist=hist, lo=lo, hi=hi, bp=bp, tot=tot, max=mx, poc_idx=poc,
                poc=lo + (poc + 0.5) * bp, vah=lo + (up + 1) * bp, val=lo + dn * bp,
                va_up=up, va_dn=dn, va_share=acc / tot)


# ---------------------------------------------------------------- source guards

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                   "MQL4", "Indicators", "VWAP_VolumeProfile.mq4")


def read_src():
    return open(SRC, encoding="utf-8", errors="replace").read()


def code_only(src):
    """comments and string contents removed, so API greps cannot hit prose"""
    out, i, n = [], 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if two == "/*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if src[i] == '"':
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == "\\" else 1
            i += 1
            out.append('""')
            continue
        out.append(src[i])
        i += 1
    return "".join(out)


# ---------------------------------------------------------------- tests
FAILS = []


def ok(cond, msg):
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    if not cond:
        FAILS.append(msg)


def close(a, b, tol=1e-9):
    return a is not None and abs(a - b) <= tol


def main():
    raw = read_src()
    src = code_only(raw)          # comments/strings removed: no prose false positives
    print("[source consistency]")
    ok("#property strict" in src, "compiled with #property strict")
    ok("indicator_chart_window" in src, "drawn in the chart window")
    ok(src.count("ObjectCreate(nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2)") == 1,
       "ObjectCreate uses the MQL4 (name, type, sub_window, t1, p1, ...) form")
    ok("ObjectMove(nm, 0," in src and "ObjectMove(nm, 1," in src,
       "both rectangle/trend anchor points are moved (MQL4 ObjectMove takes one point)")
    ok("int init()" in src and "int start()" in src and "int deinit()" in src,
       "classic MT4 init()/start()/deinit() entry points")
    ok("OnCalculate" not in src, "no MT5-only OnCalculate")
    # every MQL4 call we rely on must exist in MT4
    for fn in ["SetIndexStyle", "SetIndexBuffer", "SetIndexEmptyValue", "SetIndexLabel",
               "IndicatorBuffers", "IndicatorDigits", "IndicatorShortName",
               "ObjectSet", "ObjectSetInteger", "ObjectSetText", "ObjectFind",
               "ObjectDelete", "iVolume", "TimeYear", "TimeMonth", "StrToTime",
               "TimeToString", "ArrayResize", "ArraySize", "PlaySound", "Alert",
               "Comment", "StringReplace", "StringTrimLeft", "GetTickCount"]:
        ok(fn + "(" in src, f"uses documented MQL4 function {fn}()")
    for bad in ["PeriodSeconds(", "ChartRedraw(", "IndicatorSetString(",
                "IndicatorSetInteger(", "PlotIndexSet"]:
        pat = r"(?<!VVP)" + re.escape(bad[:-1]) + r"\("
        ok(re.search(pat, src) is None, f"avoids ambiguous/newer API: {bad[:-1]}")
    # MQL4 has no SetIndexEmpty() - the reference name is SetIndexEmptyValue()
    ok("SetIndexEmpty(" not in src, "no SetIndexEmpty() (that is not an MQL4 function)")
    # no chart-object list walking either: cleanup is prefix based
    for gone in ["ObjectsTotal(", "ObjectName(", "ObjectGetInteger(", "ObjectSetDouble("]:
        ok(gone not in src, f"does not depend on {gone[:-1]}")
    ok("ObjectsDeleteAll(0, g_tag)" in src, "orphan cleanup uses ObjectsDeleteAll(chart, prefix)")
    ok(re.search(r"ObjectCreate\(\s*0\s*,", src) is None,
       "no chart_id-first ObjectCreate (MQL5 form) - MQL4 legacy form only")
    # arity/paren-shape mistakes are verified by the static linter, which does
    # real paren matching; run it here so this file has one source of truth.
    import subprocess
    lint = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "mql4_lint.py"), SRC], capture_output=True, text=True)
    ok(lint.returncode == 0 and "no static errors" in lint.stdout,
       "tools/mql4_lint.py reports no static errors (arities, scopes, MQL5 leakage)")
    if lint.returncode != 0:
        for l in lint.stdout.splitlines():
            if "ERROR" in l:
                print("     " + l.strip())
    # datetime arithmetic must not lean on implicit int->datetime conversions
    ok(not re.search(r"Time\[[^\]]*\]\s*\+\s*VVPPeriodSeconds\(\)", src),
       "datetime offsets are explicitly cast, so no 'possible loss of data' warnings")
    ok(re.search(r"int minMs = 50;", src) is not None,
       "tick throttle uses ints, not MathMax(double)")
    for prop in ["OBJPROP_COLOR", "OBJPROP_STYLE", "OBJPROP_WIDTH", "OBJPROP_BACK",
                 "OBJPROP_RAY", "OBJPROP_FILL", "OBJPROP_SELECTABLE", "OBJPROP_HIDDEN"]:
        ok(prop in src, f"object property {prop} referenced")

    print("\n[session keys]")
    mon, tue, fri = ts(2026, 8, 24), ts(2026, 8, 25), ts(2026, 8, 28)
    ok(dt.datetime.fromtimestamp(mon, dt.timezone.utc).weekday() == 0, "2026.08.24 is a Monday")
    ok(session_id(mon, "daily") == session_id(fri, "daily") - 4, "daily keys step by one day")
    ok(session_id(ts(2026, 8, 30), "weekly", weekday=1) == session_id(mon, "weekly", weekday=1),
       "Mon..Sun stay in one weekly session (week starts Monday)")
    ok(session_id(ts(2026, 8, 31), "weekly", weekday=1) != session_id(mon, "weekly", weekday=1),
       "next Monday opens a new weekly session")
    ok(session_id(mon, "weekly", weekday=7) == session_id(ts(2026, 8, 26), "weekly", weekday=7),
       "Sun-start week groups Sat+Sun together")
    ok(session_id(ts(2026, 8, 1), "monthly") == session_id(fri, "monthly"),
       "monthly anchor groups the whole month")
    # 22:00 offset => the session starting 21:00 UTC stays on the same day key
    ok(session_id(ts(2026, 8, 24, 23, 0), "daily", off_h=22) ==
       session_id(ts(2026, 8, 24, 22, 30), "daily", off_h=22),
       "offset shifts the day boundary, not the count")

    print("\n[VWAP]")
    # one session, three bars: tp = (H+L+C)/3
    bars = [  # o,h,l,c,t,v  (newest first)
        (103, 104, 102, 103, ts(2026, 8, 24, 3), 30),
        (102, 103, 101, 102, ts(2026, 8, 24, 2), 20),
        (101, 102, 100, 101, ts(2026, 8, 24, 1), 10),
    ]
    res, first, depth = vwap(bars)
    manual = sum(v * ((h + l + c) / 3.0) for (o, h, l, c, t, v) in reversed(bars)) / 60.0
    ok(close(res[0][0], manual, 1e-9), f"cumulative VWAP of the session = {manual:.6f}")
    ok(close(res[2][0], ((102 + 100 + 101) / 3.0), 1e-9),
       "VWAP of the first bar of a session equals that bar's typical price")
    var = sum(v * (((h + l + c) / 3.0 - manual) ** 2) for (o, h, l, c, t, v) in reversed(bars)) / 60.0
    ok(close(res[0][1] - res[0][0], math.sqrt(var), 1e-9), "+1 SD band = volume-weighted sigma")
    ok(close(res[0][3] - res[0][0], 2 * math.sqrt(var), 1e-9), "+2 SD band = 2 sigma")
    ok(res[0][1] - res[0][0] == res[0][0] - res[0][2], "bands are symmetric around VWAP")

    # reset across sessions: a huge previous-session bar must not leak in
    prev_day = (110, 112, 109, 111, ts(2026, 8, 23, 5), 999)
    oldest_first = [prev_day] + list(reversed(bars))
    allb = list(reversed(oldest_first))                         # newest first
    r2, _, _ = vwap(allb)
    ok(r2[0] is not None and close(r2[0][0], manual, 1e-9),
       "new session's VWAP ignores the previous session's volume (no leak)")
    ok(close(r2[3][0], (112 + 109 + 111) / 3.0, 1e-9),
       "VWAP resets at the session boundary (previous day = its own typical price)")

    # flat market -> zero deviation
    flat = [(100, 100, 100, 100, ts(2026, 8, 24, i), 5 + i) for i in range(1, 6)][::-1]
    rf, _, _ = vwap(flat)
    ok(close(rf[0][0], 100.0) and close(rf[0][1], 100.0) and close(rf[0][3], 100.0),
       "flat market: SD = 0 so every band collapses onto the VWAP")

    # empty volume feed must not divide by zero
    novol = [(100, 105, 95, 102, ts(2026, 8, 24, i + 1), 0) for i in range(3)][::-1]
    rn, _, _ = vwap(novol)
    ok(all(x is not None and math.isfinite(x[0]) for x in rn),
       "zero-volume bars fall back to weight 1 (no NaN/Inf)")

    print("\n[profile: volume conservation]")
    sess = [
        (100.0, 101.0, 99.0, 100.5, ts(2026, 8, 24, 1), 100),
        (100.5, 102.0, 100.0, 101.5, ts(2026, 8, 24, 2), 50),
        (101.5, 101.6, 101.4, 101.5, ts(2026, 8, 24, 3), 25),
    ]
    for model in ("uniform", "ohlc"):
        p = build_profile(sess, bins=8, model=model)
        ok(close(p["tot"], 175.0, 1e-9), f"{model}: bin totals == sum of bar volumes (175)")
    p = build_profile(sess, bins=8, model="uniform", mode="both")
    ok(p["tot"] > 175.0, "vol+TPO blend adds the time-in-row component")
    tpo = build_profile(sess, bins=8, model="uniform", mode="tpo")
    touched = sum(1 for x in tpo["hist"] if x > 0)
    ok(touched == len([j for j in tpo["hist"] if j > 0]) and touched <= 8,
       f"tpo mode counts only rows actually traded ({touched} rows)")

    print("\n[profile: POC and value area]")
    # 9 doji bars stacked on one price -> 90 of 91 volume lands in a single row
    stack = [(105.0, 105.0, 105.0, 105.0, ts(2026, 8, 24, i + 1), 10) for i in range(9)]
    stack += [(99.0, 99.0, 99.0, 99.0, ts(2026, 8, 24, 20), 1)]
    sp = build_profile(stack, bins=10)
    ok(sp["poc"] > 104.0, f"POC sits in the crowded top of the range ({sp['poc']:.3f})")
    ok(sp["vah"] >= sp["poc"] >= sp["val"], "VAL <= POC <= VAH always holds")
    ok(sp["va_up"] == sp["poc_idx"] == sp["va_dn"] and abs(sp["va_share"] - 90.0 / 91.0) < 1e-9,
       "one row already holds >70% of volume -> value area is exactly that row")

    # deterministic greedy walk: hist = [5,10,30,25,10], total 80, target 56
    # POC row 2 (30) -> heavier neighbour is row 3 (25) -> 55, then row 4 (10) -> 65 >= 56.
    ladder = [(p, p, p, p, ts(2026, 8, 24, i + 1), v)
              for i, (p, v) in enumerate([(0.1, 5), (0.3, 10), (0.5, 30), (0.7, 25), (0.9, 10)])]
    lp = build_profile(list(reversed(ladder)), bins=5, model="uniform")
    ok([round(x, 6) for x in lp["hist"]] == [5, 10, 30, 25, 10],
       f"one-row-per-bar histogram is built exactly: {[round(x,3) for x in lp['hist']]}")
    ok(lp["poc_idx"] == 2 and lp["va_dn"] == 2 and lp["va_up"] == 4,
       "value area grows toward the heavier neighbour (rows 2..4, not 1..2)")
    ok(abs(lp["va_share"] - 65.0 / 80.0) < 1e-9, f"value area = 81.25% of volume ({lp['va_share']*100:.1f}%)")
    ok(abs(lp["val"] - lp["lo"] - 2 * lp["bp"]) < 1e-9 and abs(lp["vah"] - lp["hi"]) < 1e-9,
       "VAL/VAH are the outer edges of the included rows")
    full = build_profile(stack, bins=10, va_pct=100.0)
    ok(full["va_up"] == 9 and full["va_dn"] == 0, "100% value area spans every row")
    one = build_profile(stack, bins=10, va_pct=0.0)
    ok(one["va_up"] == one["poc_idx"] == one["va_dn"], "0% value area collapses to the POC row")

    # symmetric distribution -> value area centred on the POC
    sym = [(100 + i, 100.5 + i, 99.5 + i, 100 + i, ts(2026, 8, 24, 10 + i), 10) for i in range(5)]
    sy = build_profile(list(reversed(sym)), bins=5, model="uniform")
    ok(sy["val"] <= sy["poc"] <= sy["vah"], "symmetric ladder keeps POC inside the value area")

    # single-price session (all bars identical) must still produce a usable profile
    doji = [(100, 100, 100, 100, ts(2026, 8, 24, i + 1), 7) for i in range(4)][::-1]
    dp = build_profile(doji, bins=6)
    ok(dp is not None and close(dp["tot"], 28.0, 1e-9), "flat/doji session does not divide by zero")

    print("\n[render geometry & object budget]")
    # mirror VVPRender(): row widths, heights and the object count per session
    BUDGET = int(re.search(r"#define VVP_OBJ_BUDGET\s+(\d+)", src).group(1))
    prof = build_profile(list(reversed(sess)), bins=12, model="uniform")
    for clip in (False, True):
        objs = []
        for b in range(12):
            v = prof["hist"][b]
            if v <= 0.0:
                continue                      # InpSkipEmpty -> VVPDrop
            frac = min(1.0, v / prof["max"])
            rows = max(1, int(round(frac * 24)))
            te = 1_000_000 + rows * 3600
            t2 = 1_000_000 + 6 * 3600
            if clip and te > t2:
                te = t2
            pad = prof["bp"] * (100.0 - 80.0) / 100.0 * 0.5
            assert abs((prof["lo"] + (b + 1) * prof["bp"] - pad)
                       - (prof["lo"] + b * prof["bp"] + pad) - 0.8 * prof["bp"]) < 1e-12
            p1 = prof["lo"] + b * prof["bp"] + pad
            p2 = prof["lo"] + (b + 1) * prof["bp"] - pad
            objs.append((te, p1, p2))
        ok(all(t > 1_000_000 for t, a_, b_ in objs), f"clip={clip}: every row extends right of t1")
        ok(all(b_ > a_ for _, a_, b_ in objs), f"clip={clip}: row top is always above its bottom")
        if clip:
            ok(all(t <= t2 for t, _, _ in objs), "clip=true: no row escapes the session end")
        else:
            ok(any(t > t2 for t, _, _ in objs), "clip=false: heavy rows may project past the session")
    # object accounting must match the budget formula in BuildSessions()
    for bins in (3, 12, 40, 120, 400):
        per = bins + 8
        nmax = min(512, max(1, BUDGET // per))
        ok(nmax * per <= BUDGET, f"bins={bins}: {nmax} sessions x {per} objects stays <= {BUDGET}")
    tags = re.findall('VVPName\\(key, "(\\w)", ', raw)   # raw: code_only() blanks literals
    ok(set(tags) <= {"b", "l", "x", "t"}, f"object kinds are short single letters: {sorted(set(tags))}")

    print("\n[indicator source invariants]")
    ok(re.search(r"while\(first >= 0 && Time\[first\] < a\)", src) is not None,
       "fixed-anchor mode starts the accumulation at the anchor bar")
    ok("for(int i = first; i >= 0; i--)" in src, "VWAP accumulates oldest -> newest (index descending)")
    ok("g_pBin[VVPBinOf(Close[i])] += vol * 0.25" in src, "OHLC model weights the close row 25%")
    ok(src.count("0.25") + src.count("0.10") + src.count("0.075") + src.count("0.50") >= 4,
       "OHLC weights present (0.25+0.10+0.075+0.075+0.50 = 1.0)")
    w = [0.25, 0.10, 0.075, 0.075, 0.50]
    ok(abs(sum(w) - 1.0) < 1e-12, f"OHLC weights sum to exactly 1.0 (got {sum(w)})")
    ok("ObjectSet(nm, OBJPROP_RAY,   0)" in src, "trend lines do not ray to the right")
    ok("g_pBinPx * (100.0 - VVPRowHeight()) / 100.0 * 0.5" in src,
       "row pad shrinks each row to RowHeightPct of its bin (no overlapping rows)")
    ok("double pad   = g_pBinPx * (1.0 - VVPRowHeight())" not in src,
       "the inverted (1.0 - pct) pad formula is gone")
    ok("VVP_OBJ_BUDGET  2400" in src, "chart object budget is capped")

    print("\n" + ("ALL CHECKS PASSED" if not FAILS else f"{len(FAILS)} FAILURE(S):"))
    for f in FAILS:
        print("   - " + f)
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
