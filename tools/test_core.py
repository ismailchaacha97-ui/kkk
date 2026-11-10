#!/usr/bin/env python3
"""
Compile-and-run test for the market-structure engine.

The functions between the `//=== CORE-BEGIN` and `//=== CORE-END` markers in
MarketStructureSyncScanner.mq4 are extracted VERBATIM (no re-implementation,
no copy of the logic) and compiled with gcc as plain C. Synthetic OHLC
series with a known structure are fed through them and the results are
asserted.

Usage:  python3 tools/test_core.py
"""

import math
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MQ4 = os.path.join(HERE, "..", "mt4", "MQL4", "Indicators",
                   "MarketStructureSyncScanner.mq4")

BEGIN = "=== CORE-BEGIN"
END = "=== CORE-END"

# keep these in sync with the .mq4 (they are asserted against the file below)
ST_NONE, ST_BULL, ST_BEAR, ST_WIDE, ST_INSIDE = 1, 2, 3, 4, 5
RES_INSUFFICIENT, RES_NODATA = -1, -2
SYNC_NONE, SYNC_BULL, SYNC_BEAR = 0, 1, 2
AOI_NONE, AOI_DEMAND, AOI_SUPPLY, AOI_ANY = 0, 1, 2, 3
AOI_FRESH, AOI_TESTED, AOI_INSIDE, AOI_SPENT = 0, 1, 2, 3
ENTRY_NONE, ENTRY_LONG, ENTRY_SHORT = 0, 1, 2
ST_FEW = 6   # display-only, lives outside the core

STATE_NAMES = {
    ST_NONE: "ST_NONE", ST_BULL: "ST_BULL", ST_BEAR: "ST_BEAR",
    ST_WIDE: "ST_WIDE", ST_INSIDE: "ST_INSIDE",
    RES_INSUFFICIENT: "RES_INSUFFICIENT", RES_NODATA: "RES_NODATA",
}


# --------------------------------------------------------------------------
# extract the shipping code
# --------------------------------------------------------------------------
# MQL4 requires `&` on every array parameter (`double &high[]`); C has no such
# syntax. Stripping that one character from parameter declarations is the ONLY
# edit made to the shipping code before compiling it here. The regex is
# deliberately narrow: a type keyword, then `&`, then `identifier[]`.
ARRAY_PARAM = re.compile(
    r"\b(double|long|int|ushort|datetime|bool|string|float|char|color)"
    r"\s+&\s*(\w+)\s*(\[\s*\])")


def core_to_c(core):
    return ARRAY_PARAM.sub(r"\1 \2\3", core)


def assert_faithful(core, c_core):
    """Prove the C we compile differs from the .mq4 only by removed `&`.

    Independent of ARRAY_PARAM: we re-derive the same result from the original
    text using a whitespace-insensitive pattern and require an exact match.
    """
    removed = core.count("&") - c_core.count("&")
    expected = len(ARRAY_PARAM.findall(core))
    if removed != expected:
        raise SystemExit("integrity check failed: removed %d '&' but the array-param "
                         "regex matched %d" % (removed, expected))
    if core.count("&&") != c_core.count("&&"):
        raise SystemExit("integrity check failed: a logical '&&' operator was altered")

    squeeze = lambda s: re.sub(r"\s+", "", s)
    squeezed_pattern = re.compile(
        r"(double|long|int|ushort|datetime|bool|string|float|char|color)&(\w+)(\[\])")
    n_sub = len(squeezed_pattern.findall(squeeze(core)))
    if n_sub != expected:
        raise SystemExit("integrity check failed: whitespace-insensitive pattern found "
                         "%d array params, the other found %d" % (n_sub, expected))
    derived = squeezed_pattern.sub(r"\1\2\3", squeeze(core))
    if derived != squeeze(c_core):
        raise SystemExit("integrity check failed: the compiled C is not the .mq4 core "
                         "with only '&' removed")
    return removed


def extract_core(path):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    b = src.find(BEGIN)
    e = src.find(END)
    if b < 0 or e < 0 or e < b:
        raise SystemExit("CORE markers not found in %s" % path)
    body = src[b:e]
    body = body[body.find("\n") + 1:]           # drop the marker line itself
    # Word-boundary match, not a bare substring: "MovedOut_FindAOI" contains
    # "FindAOI" and would otherwise slip through this guard.
    for fn in ("IsPivotHigh", "IsPivotLow", "CollectPivots",
               "ClassifyStructure", "SyncOf", "MinBarsNeeded", "AnalyzeSeries",
               "FindAOI", "EntrySignal"):
        if not re.search(r"(?<![A-Za-z0-9_])" + re.escape(fn) + r"\s*\(", body):
            raise SystemExit("expected function %s inside the CORE block" % fn)

    c_body = core_to_c(body)
    n = assert_faithful(body, c_body)
    print("extracted CORE verbatim (%d chars); stripped '&' from %d array "
          "parameter declarations for C, nothing else changed" % (len(body), n))
    return c_body


# --------------------------------------------------------------------------
# synthetic series generator
#
# low(t)  = mid(t)                       -> pivot prices are exact
# high(t) = mid(t) + wick * sin(pi * t)  -> wick vanishes at every pivot
#
# Bars are produced chronologically and then reversed, so index 0 is the
# newest bar exactly like an MT4 timeseries.
# --------------------------------------------------------------------------
def make_series(pivots, bars_per_leg=6, tail_bars=2, lead_bars=4, base_wick=3.0):
    ch, cl = [], []

    # lead-in: approach the first pivot from the opposite side, so that the
    # first pivot has older bars to be confirmed against (a pivot needs
    # rightBars bars behind it, otherwise it is correctly not a pivot).
    first, second = pivots[0], pivots[1]
    is_trough0 = second > first
    lead_len = max(4.0, 0.25 * abs(second - first))
    lead_start = first + lead_len if is_trough0 else first - lead_len
    wick = min(base_wick, 0.15 * lead_len)
    for k in range(lead_bars + 1):
        t = k / lead_bars
        mid = lead_start + (first - lead_start) * t
        cl.append(mid)
        ch.append(mid + wick * math.sin(math.pi * t))

    for seg in range(len(pivots) - 1):
        a, b = pivots[seg], pivots[seg + 1]
        s = b - a
        wick = min(base_wick, 0.15 * abs(s)) if s else 0.0
        for k in range(1, bars_per_leg):      # k=0 is the pivot, already emitted
            t = k / (bars_per_leg - 1)
            mid = a + s * t
            cl.append(mid)
            ch.append(mid + wick * math.sin(math.pi * t))

    last, prev = pivots[-1], pivots[-2]
    direction = -1.0 if last > prev else 1.0        # move away from the last pivot
    tail_len = max(3.0, 0.15 * abs(last - prev))
    wick = min(base_wick, 0.15 * tail_len)
    for k in range(1, tail_bars + 1):
        t = k / (tail_bars + 1)
        mid = last + direction * tail_len * t
        cl.append(mid)
        ch.append(mid + wick * math.sin(math.pi * t))

    high = list(reversed(ch))
    low = list(reversed(cl))
    n = len(high)
    times = [1700000000 + (n - 1 - i) * 3600 for i in range(n)]
    return high, low, times


def c_double_array(vals):
    return "{" + ",".join("%.6f" % v for v in vals) + "}"


def c_long_array(vals):
    return "{" + ",".join("%d" % v for v in vals) + "}"


# --------------------------------------------------------------------------
# test case definitions
# --------------------------------------------------------------------------
CASES = [
    # name                          pivots (chronological)            expected
    ("clean_uptrend",      [100, 110, 105, 118, 112, 126],           ST_BULL),
    ("clean_downtrend",    [130, 118, 124, 108, 116, 100],           ST_BEAR),
    ("expanding_range",    [110, 112, 100, 120,  90, 130],           ST_WIDE),
    ("contracting_range",  [ 80, 140, 100, 130, 110, 125],           ST_INSIDE),
    ("higher_high_lower_low", [120, 130, 100, 140,  90, 150],        ST_WIDE),
    ("longer_uptrend",     [100, 108, 104, 114, 110, 121, 116, 129], ST_BULL),
    ("longer_downtrend",   [150, 140, 146, 132, 138, 125, 130, 118], ST_BEAR),
]

# structure read straight from pivot arrays: newest-first highs/lows
DIRECT = [
    ("equal_highs_no_HH",   [120.0, 120.0], [100.0, 105.0], ST_NONE),
    ("equal_lows_no_HL",    [120.0, 125.0], [100.0, 100.0], ST_NONE),
    ("single_comparison_HH_HL", [125.0, 120.0], [105.0, 100.0], ST_BULL),
    ("single_comparison_LH_LL", [120.0, 125.0], [100.0, 105.0], ST_BEAR),
]

SYNC_MATRIX = [
    (ST_BULL,  ST_BULL,  ST_BULL,  SYNC_BULL),
    (ST_BEAR,  ST_BEAR,  ST_BEAR,  SYNC_BEAR),
    (ST_BULL,  ST_BULL,  ST_BEAR,  SYNC_NONE),
    (ST_BULL,  ST_BEAR,  ST_BULL,  SYNC_NONE),
    (ST_BEAR,  ST_BULL,  ST_BULL,  SYNC_NONE),
    (ST_BULL,  ST_BULL,  ST_WIDE,  SYNC_NONE),
    (ST_BULL,  ST_BULL,  ST_INSIDE, SYNC_NONE),
    (ST_BULL,  ST_BULL,  ST_NONE,  SYNC_NONE),
    (ST_BEAR,  ST_BEAR,  ST_WIDE,  SYNC_NONE),
    (ST_WIDE,  ST_WIDE,  ST_WIDE,  SYNC_NONE),
    (ST_INSIDE, ST_INSIDE, ST_INSIDE, SYNC_NONE),
    (ST_NONE,  ST_NONE,  ST_NONE,  SYNC_NONE),
]

# --------------------------------------------------------------------------
# FindAOI fixtures.  Index 0 is the NEWEST bar, exactly like the .mq4 sees it.
# Hand-built so every level is known: the pivot index, the zone it implies
# (zone = the full candle range of that bar), and what price then did to it.
#
#   wantDir  : AOI_DEMAND / AOI_SUPPLY / AOI_ANY
#   expect   : (direction, state, pivot shift, zone top, zone bottom) or None
#              when the call must return AOI_NONE
# --------------------------------------------------------------------------
UPTREND = {
    "high":  [154, 150, 146, 140, 132, 124, 108, 114, 120, 128, 136, 144, 152, 160],
    "low":   [150, 146, 142, 136, 128, 120, 100, 108, 116, 124, 132, 140, 148, 156],
    "close": [152, 148, 144, 138, 130, 122, 104, 111, 118, 126, 134, 142, 150, 158],
}
DOWNTREND = {
    "high":  [100, 104, 110, 118, 126, 134, 150, 142, 134, 126, 118, 110, 102, 94],
    "low":   [96, 100, 106, 114, 122, 130, 142, 136, 128, 120, 112, 104, 96, 88],
    "close": [98, 102, 108, 116, 124, 132, 146, 139, 131, 123, 115, 107, 99, 91],
}

AOI_CASES = [
    # name, series, wantDir, maxLookback, (dir, state, shift, top, bot)
    ("demand_fresh",  UPTREND, AOI_DEMAND, 250, (AOI_DEMAND, AOI_FRESH,  6, 108.0, 100.0)),
    ("demand_tested", {
        "high":  [146, 112, 136, 132, 128, 124, 120, 116, 108, 114, 122, 130, 138, 146],
        "low":   [140, 104, 130, 126, 122, 118, 114, 110, 100, 108, 116, 124, 132, 140],
        "close": [143, 107, 133, 129, 125, 121, 117, 113, 104, 111, 119, 127, 135, 143],
    }, AOI_DEMAND, 250, (AOI_DEMAND, AOI_TESTED, 8, 108.0, 100.0)),
    ("demand_inside", {
        "high":  [108, 112, 136, 132, 128, 124, 120, 116, 108, 114, 122, 130, 138, 146],
        "low":   [104, 104, 130, 126, 122, 118, 114, 110, 100, 108, 116, 124, 132, 140],
        "close": [105, 107, 133, 129, 125, 121, 117, 113, 104, 111, 119, 127, 135, 143],
    }, AOI_DEMAND, 250, (AOI_DEMAND, AOI_INSIDE, 8, 108.0, 100.0)),
    ("demand_spent", {
        "high":  [98, 104, 136, 132, 128, 124, 120, 116, 108, 114, 122, 130, 138, 146],
        "low":   [92, 96, 130, 126, 122, 118, 114, 110, 100, 108, 116, 124, 132, 140],
        "close": [90, 94, 133, 129, 125, 121, 117, 113, 104, 111, 119, 127, 135, 143],
    }, AOI_DEMAND, 250, (AOI_DEMAND, AOI_SPENT, 8, 108.0, 100.0)),

    ("supply_fresh",  DOWNTREND, AOI_SUPPLY, 250, (AOI_SUPPLY, AOI_FRESH, 6, 150.0, 142.0)),    ("supply_tested", {
        "high":  [146, 148, 120, 124, 128, 132, 136, 138, 150, 142, 134, 126, 118, 110],
        "low":   [140, 141, 114, 118, 122, 126, 130, 131, 142, 134, 126, 118, 110, 102],
        "close": [141, 144, 117, 121, 125, 129, 133, 134, 146, 138, 130, 122, 114, 106],
    }, AOI_SUPPLY, 250, (AOI_SUPPLY, AOI_TESTED, 8, 150.0, 142.0)),
    ("supply_spent", {
        "high":  [154, 156, 120, 124, 128, 132, 136, 138, 150, 142, 134, 126, 118, 110],
        "low":   [148, 150, 114, 118, 122, 126, 130, 131, 142, 134, 126, 118, 110, 102],
        "close": [152, 153, 117, 121, 125, 129, 133, 134, 146, 138, 130, 122, 114, 106],
    }, AOI_SUPPLY, 250, (AOI_SUPPLY, AOI_SPENT, 8, 150.0, 142.0)),

    # The bar straight after the pivot almost always overlaps the zone, since
    # the zone IS that bar's full range.  These two fixtures put such a bar in
    # place and then let price leave for good: the correct verdict is FRESH,
    # because a touch only counts once price has left the zone at least once.
    ("demand_fresh_despite_adjacent_overlap", {
        "high":  [154, 150, 146, 140, 132, 110, 108, 114, 120, 128, 136, 144, 152, 160],
        "low":   [150, 146, 142, 136, 128, 105, 100, 108, 116, 124, 132, 140, 148, 156],
        "close": [152, 148, 144, 138, 130, 107, 104, 111, 118, 126, 134, 142, 150, 158],
    }, AOI_DEMAND, 250, (AOI_DEMAND, AOI_FRESH, 6, 108.0, 100.0)),
    ("supply_fresh_despite_adjacent_overlap", {
        "high":  [100, 104, 110, 118, 126, 146, 150, 142, 134, 126, 118, 110, 102, 94],
        "low":   [96, 100, 106, 114, 122, 141, 142, 136, 128, 120, 112, 104, 96, 88],
        "close": [98, 102, 108, 116, 124, 144, 146, 139, 131, 123, 115, 107, 99, 91],
    }, AOI_SUPPLY, 250, (AOI_SUPPLY, AOI_FRESH, 6, 150.0, 142.0)),

    # AOI_ANY has no view: it takes whichever pivot is MORE RECENT.
    # The uptrend has no confirmed swing high inside the window, so the only
    # candidate is the swing low -> demand.  The downtrend mirrors it.
    ("any_picks_demand_when_no_swing_high", UPTREND,   AOI_ANY, 250,
     (AOI_DEMAND, AOI_FRESH, 6, 108.0, 100.0)),
    ("any_picks_supply_when_no_swing_low",  DOWNTREND, AOI_ANY, 250,
     (AOI_SUPPLY, AOI_FRESH, 6, 150.0, 142.0)),

    # Both a swing high and a swing low are present here, so AOI_ANY has a
    # genuine choice to make and must take the more recent of the two.
    # 16 bars, no wick games: mid +/- 4.
    ("any_prefers_recent_low_over_older_high", {
        "high":  [170, 162, 154, 148, 138, 146, 154, 162, 170, 162, 154, 144, 134, 124, 114, 104],
        "low":   [162, 154, 146, 140, 130, 138, 146, 154, 162, 154, 146, 136, 126, 116, 106, 96],
        "close": [166, 158, 150, 144, 134, 142, 150, 158, 166, 158, 150, 140, 130, 120, 110, 100],
    }, AOI_ANY, 250, (AOI_DEMAND, AOI_FRESH, 4, 138.0, 130.0)),
    ("any_prefers_recent_high_over_older_low", {
        "high":  [138, 146, 154, 160, 170, 162, 154, 146, 138, 146, 154, 164, 174, 184, 194, 204],
        "low":   [130, 138, 146, 152, 162, 154, 146, 138, 130, 138, 146, 156, 166, 176, 186, 196],
        "close": [134, 142, 150, 156, 166, 158, 150, 142, 134, 142, 150, 160, 170, 180, 190, 200],
    }, AOI_ANY, 250, (AOI_SUPPLY, AOI_FRESH, 4, 170.0, 162.0)),

    # A requested direction is never silently substituted: the uptrend holds
    # no confirmed swing high in range, so a supply request must yield NONE.
    ("supply_requested_but_absent", UPTREND, AOI_SUPPLY, 250, None),
    ("demand_requested_but_absent", DOWNTREND, AOI_DEMAND, 250, None),

    # maxLookback clamps the pivot scan.  The swing low sits at shift 6, so a
    # lookback of 6 bars cannot reach it but 7 can.
    ("lookback_6_cannot_reach_pivot", UPTREND, AOI_DEMAND, 6, None),
    ("lookback_7_reaches_pivot",      UPTREND, AOI_DEMAND, 7,
     (AOI_DEMAND, AOI_FRESH, 6, 108.0, 100.0)),
]

# (name, series, wantDir, leftBars, rightBars, maxLookback) - every one of these
# must come back AOI_NONE with zone[0]/zone[1] left at 0 and info[1] at -1.
AOI_GUARDS = [
    ("bad_wantdir",     UPTREND, 7,          2, 2, 250),
    ("zero_leftbars",   UPTREND, AOI_DEMAND, 0, 2, 250),
    ("zero_rightbars",  UPTREND, AOI_DEMAND, 2, 0, 250),
    ("series_too_short", UPTREND, AOI_DEMAND, 6, 6, 250),   # 14 bars < 6+6+3
    ("lookback_zero",   UPTREND, AOI_DEMAND, 2, 2, 0),
]

# --------------------------------------------------------------------------
# EntrySignal fixtures: (name, zone direction, three entry-TF structures,
#                        minConfirm, (expected signal, expected confirm count))
# A demand zone is bought, so it wants bullish structure underneath it; a
# supply zone is sold, so it wants bearish. Anything else is not a trigger.
# --------------------------------------------------------------------------
ENTRY_CASES = [
    ("demand_all3_confirm_min1",   AOI_DEMAND, (ST_BULL, ST_BULL, ST_BULL), 1, (ENTRY_LONG, 3)),
    ("demand_all3_confirm_min3",   AOI_DEMAND, (ST_BULL, ST_BULL, ST_BULL), 3, (ENTRY_LONG, 3)),
    ("demand_2of3_min2",           AOI_DEMAND, (ST_BULL, ST_NONE, ST_BULL), 2, (ENTRY_LONG, 2)),
    ("demand_2of3_min3_blocked",   AOI_DEMAND, (ST_BULL, ST_NONE, ST_BULL), 3, (ENTRY_NONE, 2)),
    ("demand_1of3_min1",           AOI_DEMAND, (ST_NONE, ST_BULL, ST_NONE), 1, (ENTRY_LONG, 1)),
    ("demand_1of3_min2_blocked",   AOI_DEMAND, (ST_NONE, ST_BULL, ST_NONE), 2, (ENTRY_NONE, 1)),
    ("demand_zero_confirm",        AOI_DEMAND, (ST_BEAR, ST_BEAR, ST_BEAR), 1, (ENTRY_NONE, 0)),
    # the wrong-way structure is not a near miss, it is the opposite trade
    ("demand_against_bearish",     AOI_DEMAND, (ST_BEAR, ST_BEAR, ST_BEAR), 1, (ENTRY_NONE, 0)),
    ("supply_all3_confirm",        AOI_SUPPLY, (ST_BEAR, ST_BEAR, ST_BEAR), 1, (ENTRY_SHORT, 3)),
    ("supply_2of3_min2",           AOI_SUPPLY, (ST_BEAR, ST_WIDE, ST_BEAR), 2, (ENTRY_SHORT, 2)),
    ("supply_against_bullish",     AOI_SUPPLY, (ST_BULL, ST_BULL, ST_BULL), 1, (ENTRY_NONE, 0)),
    # sideways structures never confirm anything, in either direction
    ("demand_wide_and_inside",     AOI_DEMAND, (ST_WIDE, ST_INSIDE, ST_NONE), 1, (ENTRY_NONE, 0)),
    ("supply_wide_and_inside",     AOI_SUPPLY, (ST_WIDE, ST_INSIDE, ST_NONE), 1, (ENTRY_NONE, 0)),
    # A zone with no direction has nothing to align the entry against. Both
    # polarities are needed: without them this guard can be deleted without
    # any test noticing, because the surviving code defaults to wanting
    # bearish structure and an all-bullish input confirms nothing either way.
    ("no_zone_direction",          AOI_NONE,   (ST_BULL, ST_BULL, ST_BULL), 1, (ENTRY_NONE, 0)),
    ("no_zone_bearish_not_short",  AOI_NONE,   (ST_BEAR, ST_BEAR, ST_BEAR), 1, (ENTRY_NONE, 0)),
    ("any_is_not_a_direction",     AOI_ANY,    (ST_BULL, ST_BULL, ST_BULL), 1, (ENTRY_NONE, 0)),
    ("any_bearish_not_short",      AOI_ANY,    (ST_BEAR, ST_BEAR, ST_BEAR), 1, (ENTRY_NONE, 0)),
    ("bogus_direction",            7,          (ST_BEAR, ST_BEAR, ST_BEAR), 1, (ENTRY_NONE, 0)),
    # ST_FEW is what ScanEntries feeds in when a symbol has history but not
    # enough swings yet. It is display-only and means "unknown", so it must
    # never count toward the tally - a symbol with no readable entry
    # structure has not confirmed anything.
    ("few_counts_as_nothing",      AOI_DEMAND, (ST_FEW, ST_FEW, ST_FEW),   1, (ENTRY_NONE, 0)),
    ("few_supply_counts_nothing",  AOI_SUPPLY, (ST_FEW, ST_FEW, ST_FEW),   1, (ENTRY_NONE, 0)),
    ("one_real_among_few",         AOI_DEMAND, (ST_FEW, ST_BULL, ST_FEW),  1, (ENTRY_LONG, 1)),
    ("few_cannot_reach_min2",      AOI_DEMAND, (ST_FEW, ST_BULL, ST_FEW),  2, (ENTRY_NONE, 1)),
    ("few_mixed_with_opposite",    AOI_SUPPLY, (ST_FEW, ST_BULL, ST_FEW),  1, (ENTRY_NONE, 0)),
    # minConfirm is clamped, so nonsense settings cannot disable or force it
    ("min0_clamps_to_1",           AOI_DEMAND, (ST_NONE, ST_NONE, ST_NONE), 0, (ENTRY_NONE, 0)),
    ("min0_still_fires_on_one",    AOI_DEMAND, (ST_NONE, ST_NONE, ST_BULL), 0, (ENTRY_LONG, 1)),
    ("min99_clamps_to_3",          AOI_DEMAND, (ST_BULL, ST_BULL, ST_BULL), 99, (ENTRY_LONG, 3)),
    ("min99_blocked_by_two",       AOI_DEMAND, (ST_BULL, ST_BULL, ST_NONE), 99, (ENTRY_NONE, 2)),
    ("negative_min_clamps",        AOI_SUPPLY, (ST_BEAR, ST_NONE, ST_NONE), -5, (ENTRY_SHORT, 1)),
]


def aoi_case_c(name, series, wantdir, lb, rb, lookback, expected):
    """Emit one FindAOI fixture as a C block. `expected` is None when the call
    must return AOI_NONE."""
    h, l, c = series["high"], series["low"], series["close"]
    assert len(h) == len(l) == len(c), name
    n = len(h)
    for i in range(n):
        assert h[i] >= l[i], "%s: high[%d] below low[%d]" % (name, i, i)
    tm = [1700000000 + (n - 1 - i) * 3600 for i in range(n)]   # index 0 = newest

    out = []
    out.append("  {")
    out.append("    double hi[] = %s;" % c_double_array(h))
    out.append("    double lo[] = %s;" % c_double_array(l))
    out.append("    double cl[] = %s;" % c_double_array(c))
    out.append("    long   tm[] = %s;" % c_long_array(tm))
    out.append("    double zone[2]; long tOut[1]; int info[3];")
    out.append("    int r = FindAOI(hi, lo, cl, tm, %d, %d, %d, %d, %d, zone, tOut, info);"
               % (n, lb, rb, wantdir, lookback))
    if expected is None:
        out.append('    expect_aoi("%s", r, AOI_NONE);' % name)
        out.append('    expect_near("%s zone cleared", zone[0], 0.0);' % name)
        out.append('    expect_near("%s zone cleared", zone[1], 0.0);' % name)
        out.append('    expect_int("%s shift", info[1], -1);' % name)
    else:
        d, st, shift, top, bot = expected
        out.append('    expect_aoi("%s dir", r, %d);' % (name, d))
        out.append('    expect_aoi("%s info[0]", info[0], %d);' % (name, d))
        out.append('    expect_aoistate("%s state", info[2], %d);' % (name, st))
        out.append('    expect_int("%s pivot shift", info[1], %d);' % (name, shift))
        out.append('    expect_near("%s zone top", zone[0], %.6f);' % (name, top))
        out.append('    expect_near("%s zone bot", zone[1], %.6f);' % (name, bot))
        out.append('    expect_int("%s zone time", (int)tOut[0], %d);' % (name, tm[shift]))
    out.append("  }")
    return out


def build_c(core):
    out = []
    out.append("#include <stdio.h>")
    out.append("#include <string.h>")
    out.append("")
    out.append("/* ---- verbatim from MarketStructureSyncScanner.mq4 ---- */")
    out.append(core)
    out.append("/* ---- end verbatim ---- */")
    out.append("")
    out.append("static int g_fail = 0;")
    out.append("static int g_pass = 0;")
    out.append("")
    out.append("""
/* ST_* and SYNC_* deliberately share small integer values, so they need
   separate name lookups (a single switch would have duplicate cases). */
static const char *stname(int v)
{
  switch(v){
    case ST_NONE: return "ST_NONE";
    case ST_BULL: return "ST_BULL";
    case ST_BEAR: return "ST_BEAR";
    case ST_WIDE: return "ST_WIDE";
    case ST_INSIDE: return "ST_INSIDE";
    case RES_INSUFFICIENT: return "RES_INSUFFICIENT";
    case RES_NODATA: return "RES_NODATA";
  }
  return "?";
}

static const char *syncname(int v)
{
  switch(v){
    case SYNC_NONE: return "SYNC_NONE";
    case SYNC_BULL: return "SYNC_BULL";
    case SYNC_BEAR: return "SYNC_BEAR";
  }
  return "?";
}

static const char *aoiname(int v)
{
  switch(v){
    case AOI_NONE:   return "AOI_NONE";
    case AOI_DEMAND: return "AOI_DEMAND";
    case AOI_SUPPLY: return "AOI_SUPPLY";
    case AOI_ANY:    return "AOI_ANY";
  }
  return "?";
}

static const char *aostatename(int v)
{
  switch(v){
    case AOI_FRESH:  return "FRESH";
    case AOI_TESTED: return "TESTED";
    case AOI_INSIDE: return "INSIDE";
    case AOI_SPENT:  return "SPENT";
  }
  return "?";
}

static const char *entryname(int v)
{
  switch(v){
    case ENTRY_NONE:  return "ENTRY_NONE";
    case ENTRY_LONG:  return "ENTRY_LONG";
    case ENTRY_SHORT: return "ENTRY_SHORT";
  }
  return "?";
}

static void expect_entry(const char *label, int got, int want)
{
  if(got == want){ g_pass++; printf("  ok   %-34s -> %s\\n", label, entryname(got)); }
  else { g_fail++; printf("  FAIL %-34s -> %s (expected %s)\\n", label, entryname(got), entryname(want)); }
}

static void expect_sync(const char *label, int got, int want)
{
  if(got == want){ g_pass++; printf("  ok   %-34s -> %s\\n", label, syncname(got)); }
  else { g_fail++; printf("  FAIL %-34s -> %s (expected %s)\\n", label, syncname(got), syncname(want)); }
}

static void expect_state(const char *label, int got, int want)
{
  if(got == want){ g_pass++; printf("  ok   %-34s -> %s\\n", label, stname(got)); }
  else { g_fail++; printf("  FAIL %-34s -> %s (expected %s)\\n", label, stname(got), stname(want)); }
}

static void expect_aoi(const char *label, int got, int want)
{
  if(got == want){ g_pass++; printf("  ok   %-34s -> %s\\n", label, aoiname(got)); }
  else { g_fail++; printf("  FAIL %-34s -> %s (expected %s)\\n", label, aoiname(got), aoiname(want)); }
}

static void expect_aoistate(const char *label, int got, int want)
{
  if(got == want){ g_pass++; printf("  ok   %-34s -> %s\\n", label, aostatename(got)); }
  else { g_fail++; printf("  FAIL %-34s -> %s (expected %s)\\n", label, aostatename(got), aostatename(want)); }
}

static void expect_int(const char *label, int got, int want)
{
  if(got == want){ g_pass++; printf("  ok   %-34s -> %d\\n", label, got); }
  else { g_fail++; printf("  FAIL %-34s -> %d (expected %d)\\n", label, got, want); }
}

static void expect_near(const char *label, double got, double want)
{
  if(got > want - 1e-6 && got < want + 1e-6){ g_pass++; printf("  ok   %-34s -> %.4f\\n", label, got); }
  else { g_fail++; printf("  FAIL %-34s -> %.4f (expected %.4f)\\n", label, got, want); }
}
""")

    # --- AnalyzeSeries over generated series -------------------------------
    out.append("static void run_generated(void)")
    out.append("{")
    out.append('  printf("\\n[AnalyzeSeries on synthetic series] (fractal 2/2, pivots per side 2)\\n");')
    for i, (name, pivots, expected) in enumerate(CASES):
        h, l, t = make_series(pivots, tail_bars=2)
        out.append("  {")
        out.append("    double hi[] = %s;" % c_double_array(h))
        out.append("    double lo[] = %s;" % c_double_array(l))
        out.append("    long   tm[] = %s;" % c_long_array(t))
        out.append("    int out[3]; double outP[2];")
        out.append("    int r = AnalyzeSeries(hi, lo, tm, %d, 2, 2, 2, 250, 0, out, outP);" % len(h))
        out.append('    expect_state("%s", r, %d);' % (name, expected))
        out.append('    expect_int("%s age", out[1], 2);' % name)
        out.append("  }")
    out.append("}")
    out.append("")

    # --- newest-first ordering + prices ------------------------------------
    name, pivots, _ = CASES[0]
    h, l, t = make_series(pivots, tail_bars=2)
    out.append("static void run_pivot_order(void)")
    out.append("{")
    out.append('  printf("\\n[pivot ordering / prices] newest-first, uptrend series\\n");')
    out.append("  double hi[] = %s;" % c_double_array(h))
    out.append("  double lo[] = %s;" % c_double_array(l))
    out.append("  long   tm[] = %s;" % c_long_array(t))
    out.append("  double hiP[3], loP[3]; long hiT[3], loT[3]; int hiS[3], loS[3];")
    out.append("  int got = CollectPivots(hi, lo, tm, %d, 2, 2, 3, 250, hiP, hiT, hiS, loP, loT, loS);" % len(h))
    out.append('  expect_int("collect 3 per side", got, 3);')
    out.append('  expect_near("newest swing high == 126", hiP[0], 126.0);')
    out.append('  expect_near("previous swing high == 118", hiP[1], 118.0);')
    out.append('  expect_near("oldest swing high == 110", hiP[2], 110.0);')
    out.append('  expect_near("newest swing low == 112", loP[0], 112.0);')
    out.append('  expect_near("previous swing low == 105", loP[1], 105.0);')
    out.append('  expect_near("oldest swing low == 100", loP[2], 100.0);')
    out.append('  if(hiS[0] < hiS[1] && hiS[1] < hiS[2]){ g_pass++; printf("  ok   %-34s\\n", "high shifts ascend into the past"); }')
    out.append('  else { g_fail++; printf("  FAIL %-34s\\n", "high shifts ascend into the past"); }')
    out.append('  if(loS[0] < loS[1] && loS[1] < loS[2]){ g_pass++; printf("  ok   %-34s\\n", "low shifts ascend into the past"); }')
    out.append('  else { g_fail++; printf("  FAIL %-34s\\n", "low shifts ascend into the past"); }')
    out.append('  if(hiT[0] > hiT[1] && hiT[1] > hiT[2]){ g_pass++; printf("  ok   %-34s\\n", "high times descend (newest first)"); }')
    out.append('  else { g_fail++; printf("  FAIL %-34s\\n", "high times descend (newest first)"); }')
    out.append("}")
    out.append("")

    # --- plateau handling ---------------------------------------------------
    # MT4 order (index 0 = newest). Chronologically the series is:
    #   100 104 108 112 [116 116] 111 107 [106] 110 114 118 [120] 117 114
    # with a FLAT TOP (116 twice) and single-bar peak 120 / trough 106.
    out.append("static void run_plateau(void)")
    out.append("{")
    out.append('  printf("\\n[flat top / flat bottom] the NEWEST bar of a plateau is the pivot\\n");')
    out.append("  double hi[] = {114,117,120,118,114,110,106,107,111,116,116,113,109,105,101};")
    out.append("  double lo[] = {112,115,118,116,112,108,104,105,109,114,114,111,107,103, 99};")
    out.append("  long   tm[] = {15,14,13,12,11,10,9,8,7,6,5,4,3,2,1};")
    out.append("  double hiP[3], loP[3]; long hiT[3], loT[3]; int hiS[3], loS[3];")
    out.append("")
    out.append("  /* the two flat-top bars: only the newer one may be the pivot */")
    out.append('  expect_int("IsPivotHigh newer plateau bar (i=9)",  IsPivotHigh(hi,15, 9,1,1), 1);')
    out.append('  expect_int("IsPivotHigh older plateau bar (i=10)", IsPivotHigh(hi,15,10,1,1), 0);')
    out.append("")
    out.append("  /* mirror case: a flat bottom */")
    out.append("  double flo[] = {112,108,104,104,108,112,116};")
    out.append('  expect_int("IsPivotLow newer plateau bar (i=2)",  IsPivotLow(flo,7,2,1,1), 1);')
    out.append('  expect_int("IsPivotLow older plateau bar (i=3)",  IsPivotLow(flo,7,3,1,1), 0);')
    out.append("")
    out.append("  /* collecting: the scanner walks newest -> oldest and stops when it has enough */")
    out.append("  int got = CollectPivots(hi, lo, tm, 15, 1, 1, 1, 250, hiP, hiT, hiS, loP, loT, loS);")
    out.append('  expect_int("collect 1 per side", got, 1);')
    out.append('  expect_near("newest swing high is peak 120", hiP[0], 120.0);')
    out.append('  expect_int("  at bar index", hiS[0], 2);')
    out.append('  expect_near("newest swing low is trough 104", loP[0], 104.0);')
    out.append('  expect_int("  at bar index", loS[0], 6);')
    out.append("}")
    out.append("")

    # --- guards --------------------------------------------------------------
    out.append("static void run_guards(void)")
    out.append("{")
    out.append('  printf("\\n[guards]\\n");')
    h, l, t = make_series(CASES[0][1], tail_bars=2)
    out.append("  double hi[] = %s;" % c_double_array(h))
    out.append("  double lo[] = %s;" % c_double_array(l))
    out.append("  long   tm[] = %s;" % c_long_array(t))
    out.append("  int out[3]; double outP[2];")
    out.append("  int r;")
    out.append('  expect_int("MinBarsNeeded(2,2,2)", MinBarsNeeded(2,2,2), 22);')
    out.append('  expect_int("MinBarsNeeded(2,2,3)", MinBarsNeeded(2,2,3), 26);')
    out.append("  r = AnalyzeSeries(hi, lo, tm, 10, 2, 2, 2, 250, 0, out, outP);")
    out.append('  expect_state("series too short -> RES_NODATA", r, RES_NODATA);')
    # flat series: no pivot can ever be confirmed
    out.append("  {")
    out.append("    double fh[60], fl[60]; long ft[60];")
    out.append("    for(int i=0;i<60;i++){ fh[i]=1.10; fl[i]=1.10; ft[i]=1000+i; }")
    out.append("    r = AnalyzeSeries(fh, fl, ft, 60, 2, 2, 2, 250, 0, out, outP);")
    out.append('    expect_state("flat series -> RES_INSUFFICIENT", r, RES_INSUFFICIENT);')
    out.append("  }")
    # maxLookback too small to reach the older pivots
    out.append("  r = AnalyzeSeries(hi, lo, tm, %d, 2, 2, 3, 12, 0, out, outP);" % len(h))
    out.append('  expect_state("lookback too small for 3 pivots", r, RES_INSUFFICIENT);')
    # staleness flag
    out.append("  r = AnalyzeSeries(hi, lo, tm, %d, 2, 2, 2, 250, 1, out, outP);" % len(h))
    out.append('  expect_state("maxAge=1, age=2 -> still classifies", r, ST_BULL);')
    out.append('  expect_int("maxAge=1 -> stale flag set", out[2], 1);')
    out.append("  r = AnalyzeSeries(hi, lo, tm, %d, 2, 2, 2, 250, 10, out, outP);" % len(h))
    out.append('  expect_int("maxAge=10 -> stale flag clear", out[2], 0);')
    # prices surfaced for reference levels
    out.append("  r = AnalyzeSeries(hi, lo, tm, %d, 2, 2, 2, 250, 0, out, outP);" % len(h))
    out.append('  expect_near("outP[0] newest swing high", outP[0], 126.0);')
    out.append('  expect_near("outP[1] newest swing low",  outP[1], 112.0);')
    out.append("}")
    out.append("")

    # --- three-pivot (stricter) mode ----------------------------------------
    out.append("static void run_three_pivots(void)")
    out.append("{")
    out.append('  printf("\\n[PivotsPerSide=3] two consecutive HH and two consecutive HL\\n");')
    for name, pivots, expected in CASES:
        h, l, t = make_series(pivots, tail_bars=2)
        if len(h) < 26:
            continue
        out.append("  {")
        out.append("    double hi[] = %s;" % c_double_array(h))
        out.append("    double lo[] = %s;" % c_double_array(l))
        out.append("    long   tm[] = %s;" % c_long_array(t))
        out.append("    int out[3]; double outP[2];")
        out.append("    int r = AnalyzeSeries(hi, lo, tm, %d, 2, 2, 3, 250, 0, out, outP);" % len(h))
        out.append('    expect_state("%s (3 pivots)", r, %d);' % (name, expected))
        out.append("  }")
    out.append("}")
    out.append("")

    # --- wider fractal -------------------------------------------------------
    out.append("static void run_wide_fractal(void)")
    out.append("{")
    out.append('  printf("\\n[fractal 3/3] stronger pivots, same verdict\\n");')
    for name, pivots, expected in CASES:
        h, l, t = make_series(pivots, bars_per_leg=8, tail_bars=3)
        out.append("  {")
        out.append("    double hi[] = %s;" % c_double_array(h))
        out.append("    double lo[] = %s;" % c_double_array(l))
        out.append("    long   tm[] = %s;" % c_long_array(t))
        out.append("    int out[3]; double outP[2];")
        out.append("    int r = AnalyzeSeries(hi, lo, tm, %d, 3, 3, 2, 250, 0, out, outP);" % len(h))
        out.append('    expect_state("%s (3/3)", r, %d);' % (name, expected))
        out.append("  }")
    out.append("}")
    out.append("")

    # --- ClassifyStructure directly ------------------------------------------
    out.append("static void run_direct(void)")
    out.append("{")
    out.append('  printf("\\n[ClassifyStructure] hand-set pivot arrays\\n");')
    for name, hi, lo, expected in DIRECT:
        out.append("  {")
        out.append("    double hiP[] = %s;" % c_double_array(hi))
        out.append("    double loP[] = %s;" % c_double_array(lo))
        out.append('    expect_state("%s", ClassifyStructure(hiP, loP, 1), %d);' % (name, expected))
        out.append("  }")
    out.append("}")
    out.append("")

    # --- sync matrix ----------------------------------------------------------
    out.append("static void run_sync(void)")
    out.append("{")
    out.append('  printf("\\n[SyncOf] all three timeframes must agree\\n");')
    for a, b, c, expected in SYNC_MATRIX:
        out.append('  expect_sync("SyncOf(%s,%s,%s)", SyncOf(%d,%d,%d), %d);'
                   % (STATE_NAMES.get(a, a), STATE_NAMES.get(b, b), STATE_NAMES.get(c, c),
                      a, b, c, expected))
    out.append("}")
    out.append("")

    # --- FindAOI ------------------------------------------------------------
    out.append("static void run_aoi(void)")
    out.append("{")
    out.append('  printf("\\n[FindAOI] Weekly/Daily areas of interest\\n");')
    for name, series, wantdir, lookback, expected in AOI_CASES:
        out.extend(aoi_case_c(name, series, wantdir, 2, 2, lookback, expected))
    for name, series, wantdir, lb, rb, lookback in AOI_GUARDS:
        out.extend(aoi_case_c(name, series, wantdir, lb, rb, lookback, None))
    out.append("}")
    out.append("")

    # --- EntrySignal -------------------------------------------------------
    out.append("static void run_entry(void)")
    out.append("{")
    out.append('  printf("\\n[EntrySignal] entry timeframes vs the zone direction\\n");')
    for name, aoidir, sts, minconf, (sig, conf) in ENTRY_CASES:
        out.append("  {")
        out.append("    int eo[2];")
        out.append("    int r = EntrySignal(%d, %d, %d, %d, %d, eo);"
                   % (aoidir, sts[0], sts[1], sts[2], minconf))
        out.append('    expect_entry("%s", r, %d);' % (name, sig))
        out.append('    expect_entry("%s out[0]", eo[0], %d);' % (name, sig))
        out.append('    expect_int("%s confirm", eo[1], %d);' % (name, conf))
        out.append("  }")
    out.append("}")
    out.append("")

    out.append("""
int main(void)
{
  run_generated();
  run_pivot_order();
  run_plateau();
  run_guards();
  run_three_pivots();
  run_wide_fractal();
  run_direct();
  run_sync();
  run_aoi();
  run_entry();
  printf("\\n%d passed, %d failed\\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
""")
    return "\n".join(out)


def main():
    core = extract_core(os.path.normpath(MQ4))
    c_src = build_c(core)

    tmp = tempfile.mkdtemp(prefix="mss_core_")
    c_path = os.path.join(tmp, "core_test.c")
    bin_path = os.path.join(tmp, "core_test")
    with open(c_path, "w", encoding="utf-8") as fh:
        fh.write(c_src)

    print("compiling extracted core with gcc ...")
    cc = subprocess.run(
        ["gcc", "-std=c99", "-Wall", "-Wextra", "-Wno-unused-parameter",
         "-o", bin_path, c_path],
        capture_output=True, text=True)
    if cc.stdout.strip():
        print(cc.stdout)
    if cc.stderr.strip():
        print(cc.stderr)
    if cc.returncode != 0:
        print("gcc FAILED - the extracted core does not compile as C")
        return 1

    run = subprocess.run([bin_path], capture_output=True, text=True)
    print(run.stdout, end="")
    if run.stderr.strip():
        print(run.stderr, end="")
    print("\nc source kept at: %s" % c_path)
    return run.returncode


if __name__ == "__main__":
    sys.exit(main())
