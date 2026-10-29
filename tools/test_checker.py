#!/usr/bin/env python3
"""
test_checker.py - regression tests for tools/mq4_check.py

The static analyser is the only compile-like gate available here, so it has to
be tested itself. Each case takes the real EA, injects one specific defect of
the kind MetaEditor would reject, and asserts that the analyser reports it.
The clean case asserts it stays quiet.

Usage: python3 tools/test_checker.py
"""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = os.path.join(ROOT, "mt4", "Experts", "QuantEdge", "FTMO_QuantEdge.mq4")
CHECKER = os.path.join(ROOT, "tools", "mq4_check.py")

CASES = []


def case(name, expect):
    def deco(fn):
        CASES.append((name, expect, fn))
        return fn
    return deco


@case("clean source", None)
def _clean(src):
    return src


@case("identifier used but never declared", "dow")
def _undeclared(src):
    # the exact defect MetaEditor reported: 'dow' referenced in TradingAllowed
    broken = src.replace(
        "   int dow  = TimeDayOfWeek(TimeCurrent());\n   int hh   = TimeHour(TimeCurrent());",
        "   int hh   = TimeHour(TimeCurrent());")
    assert broken != src, "injection point not found"
    return broken


@case("function that MQL4 does not have", "iSpread")
def _unknown_function(src):
    broken = src.replace(
        "void SampleSpread()\n  {",
        "void SampleSpread()\n  {\n   double sp = (double)iSpread(g_symbol, g_period, 1);")
    assert broken != src, "injection point not found"
    return broken


@case("unbalanced brace", "unclosed")
def _unbalanced(src):
    return src.rstrip() + "\n\nvoid Extra()\n  {\n   Print(\"x\");\n"


@case("duplicate function definition", "defined 2 times")
def _duplicate(src):
    return src + "\n\nbool TradingAllowed(int dir, string &reason)\n  {\n   return(true);\n  }\n"


@case("input without a semicolon", "input declaration without")
def _bad_input(src):
    return src.replace("input int             InpMagicBase        = 771100;",
                       "input int             InpMagicBase        = 771100")


@case("MQL5-only call", "MQL5-only")
def _mql5_call(src):
    return src.replace("void SampleSpread()\n  {",
                       "void SampleSpread()\n  {\n   int n = PositionsTotal();")


def run_checker(path):
    proc = subprocess.run([sys.executable, CHECKER, path],
                          capture_output=True, text=True)
    return proc.stdout + proc.stderr


def main():
    if not os.path.exists(EA):
        print(f"EA not found: {EA}")
        return 1
    src = open(EA, encoding="utf-8").read()
    failures = 0

    for name, expect, fn in CASES:
        try:
            mutated = fn(src)
        except AssertionError as exc:
            print(f"  SKIP  {name}  ({exc})")
            failures += 1
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".mq4", delete=False,
                                         encoding="utf-8") as fh:
            fh.write(mutated)
            path = fh.name
        try:
            out = run_checker(path)
        finally:
            os.unlink(path)

        if expect is None:
            ok = ("0 error(s)" in out)
            detail = "no errors reported" if ok else "unexpected errors on clean source"
        else:
            ok = (expect in out) and ("ERROR" in out)
            detail = f"expected '{expect}' in the report" if ok else f"'{expect}' NOT reported"
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else f"   [{detail}]"))
        if not ok:
            print("        " + out.strip().replace("\n", "\n        "))
            failures += 1

    print()
    if failures:
        print(f"{failures} of {len(CASES)} checker tests FAILED")
        return 1
    print(f"All {len(CASES)} checker tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
