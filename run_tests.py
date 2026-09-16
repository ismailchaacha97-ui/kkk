#!/usr/bin/env python3
import subprocess, sys, os

tests = [
    "tests/test_anchor.py",
    "tests/test_vwap.py",
    "tests/test_ssl.py",
    "tests/test_filters.py",
    "tests/test_integration.py"
]

all_ok = True
for t in tests:
    print(f"\n=== Running {t} ===")
    res = subprocess.run([sys.executable, t], cwd=os.path.dirname(__file__) or ".")
    if res.returncode != 0:
        all_ok = False
        print(f"FAILED: {t}")
    else:
        print(f"PASSED: {t}")

print("\n=== Backtest Demo ===")
res = subprocess.run([sys.executable, "src/backtest_demo.py"], cwd=os.path.dirname(__file__) or ".")
if res.returncode != 0:
    all_ok=False

if all_ok:
    print("\nAll tests PASSED - indicator well tested")
else:
    print("\nSome tests FAILED")
    sys.exit(1)
