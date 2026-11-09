#!/bin/bash
# ============================================================
#  MERIDIAN CAPITAL - 3D Trading Floor  (Linux)
#  Run:  ./start.sh        (or double-click if your file manager allows it)
# ============================================================
cd "$(dirname "$0")" || exit 1

echo ""
echo "  ============================================"
echo "    MERIDIAN CAPITAL - 3D TRADING FLOOR"
echo "  ============================================"
echo ""

if ! command -v node >/dev/null 2>&1; then
  echo "  [!] Node.js is not installed."
  echo "      Install it with your package manager, for example:"
  echo "        Ubuntu/Debian:  sudo apt install nodejs npm"
  echo "        Fedora:         sudo dnf install nodejs npm"
  echo "      Or download the LTS build from https://nodejs.org"
  echo ""
  exit 1
fi
echo "  Node.js found: $(node -v)"

if [ ! -d "node_modules" ]; then
  echo ""
  echo "  First run detected - downloading the 3D engine and React (~30s)..."
  npm install --no-audit --no-fund || { echo "  [!] Install failed."; exit 1; }
fi

echo ""
echo "  Starting the trading floor on http://localhost:8787"
echo "  Keep this terminal open. Ctrl+C to stop."
echo ""
( sleep 2; xdg-open "http://localhost:8787" >/dev/null 2>&1 ) &
npm run dev
