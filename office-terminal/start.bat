@echo off
REM ============================================================
REM  MERIDIAN CAPITAL - 3D Trading Floor
REM  Double-click this file to start the floor on Windows.
REM ============================================================
title Meridian Capital - 3D Trading Floor
cd /d "%~dp0"

echo.
echo  ============================================
echo    MERIDIAN CAPITAL - 3D TRADING FLOOR
echo  ============================================
echo.

REM --- 1. is Node.js installed? ---
where node >nul 2>nul
if errorlevel 1 (
  echo  [!] Node.js is not installed on this PC.
  echo.
  echo      Opening the download page for you...
  start https://nodejs.org/en/download
  echo.
  echo      1. Download the "LTS" Windows installer (.msi)
  echo      2. Run it and click Next / Next / Install
  echo      3. IMPORTANT: close this window, then double-click start.bat again
  echo.
  pause
  exit /b 1
)

for /f "tokens=*" %%v in ('node -v') do set NODEV=%%v
echo  Node.js found: %NODEV%

REM --- 2. install dependencies the first time ---
if not exist "node_modules" (
  echo.
  echo  First run detected - downloading the 3D engine and React.
  echo  This takes about 30 seconds. Please wait...
  echo.
  call npm install --no-audit --no-fund
  if errorlevel 1 (
    echo.
    echo  [!] Installation failed. Check your internet connection and try again.
    pause
    exit /b 1
  )
)

REM --- 3. start the floor ---
echo.
echo  Starting the trading floor...
echo  Your browser will open at http://localhost:8787
echo.
echo  KEEP THIS WINDOW OPEN while you use the floor.
echo  Press Ctrl+C (or close this window) to stop it.
echo.
start "" http://localhost:8787
call npm run dev

pause
