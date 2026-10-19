#!/usr/bin/env bash
# One-command demo: install dependencies if needed, generate synthetic data,
# run both strategies and write the comparison report.
#
# Extra arguments are forwarded to the CLI, e.g.:
#   bash run.sh --days 120 --symbols AAPL MSFT --seed 7
#   bash run.sh --data-dir data_real --no-generate --symbols SPY IBM BAC AIG
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3}"

if ! "$PYTHON" -c "import nautilus_trader, pandas, numpy" >/dev/null 2>&1; then
    echo "Installing Python dependencies (Python 3.11 required)..."
    "$PYTHON" -m pip install -r requirements.txt \
        || "$PYTHON" -m pip install --break-system-packages -r requirements.txt
fi

"$PYTHON" -m daytrader compare --out reports "$@"
echo
echo "Reports:"
echo "  reports/comparison.md"
echo "  reports/orb/summary.md"
echo "  reports/vwap/summary.md"
