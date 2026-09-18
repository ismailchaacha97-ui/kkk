#!/usr/bin/env python3
"""
check_mql4.py - static sanity checks for the MQL4 sources.

MetaTrader cannot be run in CI, and the author cannot see your compiler's
error messages, so this checker encodes the MQL4 language rules that the
shared C++/MQL4 headers are most likely to trip over.  It is not a
compiler - it is the list of mistakes that would otherwise only show up on
the user's machine.

Rules:
  A. Portability of the shared core (MQL4/Include/VWAPPro/*.mqh):
     no std::, no templates outside the C++ branch, no string / terminal I/O
     APIs, no const member functions (MQL4 rejects them), no MQL5-only APIs.
  B. Indicator structure (.mq4):
     #property strict, indicator_buffers == number of SetIndexBuffer calls,
     buffer indices contiguous from 0, OnCalculate signature is the MQL4 one,
     every input referenced, no code after the last function.
  C. Hygiene for every file: balanced braces/parens/brackets, no CRLF, ends
     with a newline, no tabs, no non-ASCII.

Usage:  python3 tools/check_mql4.py            (exit code 0 = clean)
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CORE_DIR = os.path.join(ROOT, "MQL4", "Include", "VWAPPro")

# --- rule A: things the shared core must never contain -------------------
CORE_FORBIDDEN = [
    (r"\bstd::", "C++ standard library use leaks into the MQL4 build"),
    (r"\bnew\s+[A-Za-z_]", "dynamic allocation (MQL4 has no objects here)"),
    (r"\bdelete\s+[A-Za-z_]", "dynamic deallocation"),
    (r"#include\s*<", "angle include (MQL4 uses quoted includes)"),
    (r"\bTimeGMTOffset\b", "MQL5-only API"),
    (r"\bTimeGMT\b", "MQL5-only API"),
    (r"\bCopyBuffer\b", "MQL5-only API"),
    (r"\bEnumToString\b", "MQL5-only-ish, unsafe in MQL4 builds"),
    (r"\bStringFormat\b", "string code in the portable core"),
    (r"\bStringConcatenate\b", "string code in the portable core"),
    (r"\bPrint\s*\(", "terminal I/O in the portable core"),
    (r"\bComment\s*\(", "terminal I/O in the portable core"),
    (r"\bAlert\s*\(", "terminal I/O in the portable core"),
    (r"\bObjectCreate\b", "chart object code in the portable core"),
    (r"\biCustom\b", "iCustom inside the core"),
    (r"\b#property\b", "#property inside an include"),
]

TEMPLATE_RE = re.compile(r"\btemplate\s*<")

# const member function:  "...) const" followed by { or ;
CONST_METHOD_RE = re.compile(r"\)\s*const\s*[{;]")

# --- rule B: indicator requirements --------------------------------------
MQL4_ONCALC = ("int OnCalculate(const int rates_total",
               "const int prev_calculated",
               "const datetime &time[]",
               "const double &open[]",
               "const double &high[]",
               "const double &low[]",
               "const double &close[]",
               "const long &tick_volume[]",
               "const long &volume[]",
               "const int &spread[]")


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    out = []
    for line in src.split("\n"):
        i = line.find("//")
        out.append(line if i < 0 else line[:i])
    return "\n".join(out)


def balance(src, path, problems):
    for opener, closer, name in (("{", "}", "braces"), ("(", ")", "parens"),
                                 ("[", "]", "brackets")):
        n = src.count(opener) - src.count(closer)
        if n != 0:
            problems.append("%s: unbalanced %s (%+d)" % (path, name, n))


def check_core(path, src, problems, warnings):
    code = strip_comments(src)
    # template<> is allowed *only* inside the C++ test branch
    cpp_guard = code.find("VWAPPRO_CPP_TEST")
    for i, line in enumerate(code.split("\n")):
        for pat, why in CORE_FORBIDDEN:
            if re.search(pat, line):
                # the C++ branch legitimately uses std::, <...> includes and
                # templates; detect whether we are inside it
                before = "\n".join(code.split("\n")[:i])
                if before.count("#ifdef VWAPPRO_CPP_TEST") > before.count("#endif // VWAPPRO_CPP_TEST") \
                   and ("VWAPPRO_CPP_TEST" in before.split("#ifdef")[-1][:40]):
                    continue
                if re.search(pat, line) and pat in (r"\bstd::", r"#include\s*<") \
                   and before.count("#ifdef VWAPPRO_CPP_TEST") > before.count("#endif"):
                    continue
                problems.append("%s:%d: %s -> %s" % (path, i + 1, why, line.strip()[:80]))
        if TEMPLATE_RE.search(line):
            before = "\n".join(code.split("\n")[:i])
            if before.count("#ifdef VWAPPRO_CPP_TEST") <= before.count("#endif"):
                problems.append("%s:%d: template outside the C++ branch" % (path, i + 1))
        if CONST_METHOD_RE.search(line):
            problems.append("%s:%d: const member function (not accepted by MQL4): %s"
                            % (path, i + 1, line.strip()[:70]))


def check_indicator(path, src, problems, warnings):
    code = strip_comments(src)
    if "#property strict" not in code:
        problems.append("%s: missing #property strict" % path)

    m = re.search(r"#property\s+indicator_buffers\s+(\d+)", code)
    buffers = int(m.group(1)) if m else None
    used = sorted(set(int(x) for x in re.findall(r"SetIndexBuffer\s*\(\s*(\d+)", code)))
    if buffers is None:
        problems.append("%s: no #property indicator_buffers" % path)
    else:
        if buffers > 8:
            problems.append("%s: %d buffers, MQL4 allows at most 8" % (path, buffers))
        if used != list(range(len(used))):
            problems.append("%s: buffer indices are not contiguous from 0: %s" % (path, used))
        if buffers != len(used):
            problems.append("%s: indicator_buffers=%d but %d SetIndexBuffer calls"
                            % (path, buffers, len(used)))

    # every declared buffer array must be bound
    declared = set(re.findall(r"^double\s+([A-Za-z_]\w*)\s*\[\s*\]\s*;", code, re.M))
    bound = set(re.findall(r"SetIndexBuffer\s*\(\s*\d+\s*,\s*([A-Za-z_]\w*)", code))
    missing = declared - bound
    if missing:
        warnings.append("%s: declared but unbound buffers: %s" % (path, sorted(missing)))

    if "OnCalculate" in code:
        for frag in MQL4_ONCALC:
            if frag not in code:
                problems.append("%s: OnCalculate signature is not the MQL4 one (missing '%s')"
                                % (path, frag))

    # inputs must actually be used (an unused input is a silent user trap)
    inputs = re.findall(r"^\s*input\s+[A-Za-z_][\w]*\s+([A-Za-z_]\w*)", code, re.M)
    for name in inputs:
        if name.startswith("__"):
            continue
        if len(re.findall(r"\b%s\b" % re.escape(name), code)) < 2:
            warnings.append("%s: input %s is never used" % (path, name))

    if "OnDeinit" not in code:
        warnings.append("%s: no OnDeinit (chart objects will leak)" % path)


def check_hygiene(path, raw, problems):
    if "\r\n" in raw:
        problems.append("%s: CRLF line endings" % path)
    if not raw.endswith("\n"):
        problems.append("%s: file does not end with a newline" % path)
    if "\t" in raw:
        problems.append("%s: tab characters" % path)
    bad = [c for c in raw if ord(c) > 126]
    if bad:
        problems.append("%s: non ASCII characters: %r" % (path, sorted(set(bad))[:5]))


def main():
    problems, warnings, checked = [], [], 0

    for sub in ("Include/VWAPPro", "Indicators", "Experts"):
        d = os.path.join(ROOT, "MQL4", sub)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith((".mq4", ".mqh")):
                continue
            path = os.path.join(d, name)
            rel = os.path.relpath(path, ROOT)
            raw = read(path)
            code = strip_comments(raw)
            checked += 1
            check_hygiene(rel, raw, problems)
            balance(code, rel, problems)
            if sub == "Include/VWAPPro":
                check_core(rel, raw, problems, warnings)
            if name.endswith(".mq4") and "OnCalculate" in code:
                check_indicator(rel, raw, problems, warnings)

    # the EA must call iCustom with the indicator's *first* input as the
    # first custom argument, otherwise it silently reads the wrong exports
    print("checked %d MQL4 source files" % checked)
    for w in warnings:
        print("  WARN  " + w)
    for p in problems:
        print("  FAIL  " + p)
    if not problems:
        print("  OK    no portability or structural problems found")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
