#!/usr/bin/env python3
"""
Mutation check for the AOI test fixtures.

A green test suite proves nothing on its own - it has to go red when the
code it claims to cover is broken. This script applies a series of small
deliberate defects to FindAOI, re-runs tools/test_core.py after each one,
and requires every mutation to be caught. The file is restored afterwards.
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MQ4 = os.path.join(ROOT, "mt4", "MQL4", "Indicators",
                   "MarketStructureSyncScanner.mq4")

MUTATIONS = [
    ("INSIDE ignores the zone ceiling",
     "else if(close[0] >= zBot && close[0] <= zTop)  state = AOI_INSIDE;",
     "else if(close[0] >= zBot)                            state = AOI_INSIDE;"),

    ("demand touch no longer requires price to leave first",
     "else if(left == 1 && low[i] <= zTop) touched = 1;",
     "else if(low[i] <= zTop)                     touched = 1;"),

    ("supply touch no longer requires price to leave first",
     "else if(left == 1 && high[i] >= zBot) touched = 1;",
     "else if(high[i] >= zBot)                      touched = 1;"),

    ("AOI_ANY ignores which pivot is more recent",
     "if(pL >= 0 && (pH < 0 || pL < pH)) { p = pL; dir = AOI_DEMAND; }",
     "if(pL >= 0)                                { p = pL; dir = AOI_DEMAND; }"),

    ("demand break condition dropped",
     "if(close[i] < zBot)                  broken  = 1;",
     "if(0)                                broken  = 1;"),

    ("supply break condition dropped",
     "if(close[i] > zTop)                    broken  = 1;",
     "if(0)                                  broken  = 1;"),

    # anchored on two lines: the same clamp also appears in CollectPivots
    ("maxLookback clamp ignored",
     "if(stop > maxLookback - 1) stop = maxLookback - 1;\n   if(stop < start) return(AOI_NONE);",
     "if(0)                              stop = maxLookback - 1;\n   if(stop < start) return(AOI_NONE);"),

    ("zone taken from the pivot's close instead of its range",
     "double zTop = high[p];\n   double zBot = low[p];",
     "double zTop = close[p];\n   double zBot = close[p];"),

    ("pivot time output dropped",
     "tOut[0] = tArr[p];",
     "tOut[0] = 0;"),
]


def run_tests():
    r = subprocess.run([sys.executable, os.path.join(HERE, "test_core.py")],
                       capture_output=True, text=True, cwd=ROOT)
    tail = [l for l in r.stdout.strip().splitlines() if "passed," in l]
    if tail:
        return r.returncode, tail[0].strip(), True
    # no result line means the generated C never compiled, which tells us
    # nothing about whether an assertion would have fired
    last = [l for l in (r.stdout + r.stderr).strip().splitlines() if l.strip()]
    return r.returncode, (last[-1][:110] if last else "no output"), False


def main():
    backup = os.path.join(os.environ.get("TMPDIR", "/tmp"), "mq4_mutation_backup.mq4")
    shutil.copyfile(MQ4, backup)

    src = open(backup, encoding="utf-8").read()
    missed = []
    try:
        rc, line, compiled = run_tests()
        print("baseline (unmutated)     : %s  [%s]" % (line, "pass" if rc == 0 else "FAIL"))
        if rc != 0:
            print("refusing to continue: the baseline suite is not green")
            return 1

        for label, old, new in MUTATIONS:
            assert src.count(old) == 1, \
                "mutation anchor not unique (%d hits): %s" % (src.count(old), old)
            with open(MQ4, "w", encoding="utf-8") as fh:
                fh.write(src.replace(old, new))
            rc, line, compiled = run_tests()
            caught = rc != 0
            # a compile error is not evidence that an assertion fired
            verdict = "CAUGHT" if caught and compiled else (
                "compile error (inconclusive)" if caught else "NOT CAUGHT")
            print("  %-52s %-28s [%s]" % (label, verdict, line))
            if not caught or not compiled:
                missed.append(label)
    finally:
        shutil.copyfile(backup, MQ4)

    rc, line, compiled = run_tests()
    print("restored                 : %s  [%s]" % (line, "pass" if rc == 0 else "FAIL"))

    if missed or rc != 0:
        print("\nFAIL: %d mutation(s) went undetected: %s" % (len(missed), missed))
        return 1
    print("\nok: all %d mutations were caught by the AOI fixtures" % len(MUTATIONS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
