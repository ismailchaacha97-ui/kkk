#!/bin/bash
# ============================================================
#  MERIDIAN CAPITAL - 3D Trading Floor  (macOS)
#  Double-click this file to start the floor.
# ============================================================
cd "$(dirname "$0")" || exit 1

echo ""
echo "  ============================================"
echo "    MERIDIAN CAPITAL - 3D TRADING FLOOR"
echo "  ============================================"
echo ""

# --- 1. is Node.js installed? ---
if ! command -v node >/dev/null 2>&1; then
  echo "  [!] Node.js is not installed on this Mac."
  echo ""
  echo "      Opening the download page for you..."
  open "https://nodejs.org/en/download" 2>/dev/null
  echo ""
  echo "      1. Download the macOS installer (.pkg) for the LTS version"
  echo "      2. Run it and click Continue until it finishes"
  echo "      3. Close this window, then double-click start.command again"
  echo ""
  read -r -p "  Press Enter to close..." _
  exit 1
fi
echo "  Node.js found: $(node -v)"

# --- 2. install dependencies the first time ---
if [ ! -d "node_modules" ]; then
  echo ""
  echo "  First run detected - downloading the 3D engine and React."
  echo "  This takes about 30 seconds. Please wait..."
  echo ""
  npm install --no-audit --no-fund || {
    echo ""
    echo "  [!] Installation failed. Check your internet connection and try again."
    read -r -p "  Press Enter to close..." _
    exit 1
  }
fi

# --- 3. start the floor ---
echo ""
echo "  Starting the trading floor..."
echo "  Your browser will open at http://localhost:8787"
echo ""
echo "  KEEP THIS WINDOW OPEN while you use the floor."
echo "  Press Ctrl+C (or close this window) to stop it."
echo ""
( sleep 2; open "http://localhost:8787" 2>/dev/null ) &
npm run dev
