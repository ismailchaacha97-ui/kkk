#!/usr/bin/env bash
# Everything expensive in one pass.  Each run writes results/grid_<ma>_<mode><tag>.parquet
set -e
cd "$(dirname "$0")/.."
echo "[1/5] daily grid, realistic costs"
python3 scripts/run_study.py
echo "[2/5] weekly-bar grid"
python3 scripts/run_study.py --bar W --out-tag _w
echo "[3/5] frictionless (zero cost) grid"
python3 scripts/run_study.py --cost-mult 0 --out-tag _c0
echo "[4/5] high-cost (3x) grid"
python3 scripts/run_study.py --cost-mult 3 --out-tag _c3
echo "[5/5] SMA control (same grid, simple instead of exponential)"
python3 scripts/run_study.py --ma sma --out-tag _sma
echo "ALL DONE"
