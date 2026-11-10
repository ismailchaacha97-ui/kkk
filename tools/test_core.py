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
    for fn in ("IsPivotHigh", "IsPivotLow", "CollectPivots",
               "ClassifyStructure", "SyncOf", "MinBarsNeeded", "AnalyzeSeries"):
        if fn not in body:
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
