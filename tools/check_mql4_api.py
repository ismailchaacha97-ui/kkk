#!/usr/bin/env python3
"""
Verify that every MQL4 built-in function and constant this indicator relies on
really exists in MQL4 code in the wild.

There is no MetaEditor available here, so instead of compiling against the MT4
API we cross-check each identifier against real .mq4 sources indexed on GitHub.
An identifier with zero hits in the whole MQL4 corpus is almost certainly a
typo or an MQL5-only name.

Usage:  python3 tools/check_mql4_api.py            # check everything
        python3 tools/check_mql4_api.py --quick    # every 4th identifier
"""

import json
import subprocess
import sys
import time

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from lint_mq4 import BUILTINS, CONSTANTS          # noqa: E402

DELAY = 2.1        # authenticated code search allows ~30 requests/minute


def search(ident):
    """Return the number of MQL4 files mentioning ident, or None on failure."""
    for attempt in range(4):
        p = subprocess.run(
            ["gh", "api", "-X", "GET", "search/code",
             "-f", "q=%s language:MQL4" % ident, "-f", "per_page=1"],
            capture_output=True, text=True)
        if p.returncode == 0:
            try:
                return json.loads(p.stdout).get("total_count")
            except json.JSONDecodeError:
                pass
        if "rate limit" in (p.stdout + p.stderr).lower():
            time.sleep(20)
            continue
        time.sleep(3 * (attempt + 1))
    return None


def main():
    idents = sorted(BUILTINS) + sorted(CONSTANTS)
    if "--quick" in sys.argv:
        idents = idents[::4]

    print("checking %d MQL4 identifiers against real .mq4 sources on GitHub\n" % len(idents))

    missing, failed = [], []
    for i, ident in enumerate(idents, 1):
        n = search(ident)
        if n is None:
            failed.append(ident)
            print("  ??   %-26s query failed" % ident)
        elif n == 0:
            missing.append(ident)
            print("  MISS %-26s 0 hits in the MQL4 corpus" % ident)
        else:
            print("  ok   %-26s %d file(s)" % (ident, n))
        if i < len(idents):
            time.sleep(DELAY)

    print("\n%d ok, %d with zero hits, %d query failures"
          % (len(idents) - len(missing) - len(failed), len(missing), len(failed)))
    if missing:
        print("NOT FOUND IN ANY .mq4 FILE: %s" % ", ".join(missing))
        return 1
    if failed:
        print("could not verify: %s" % ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
