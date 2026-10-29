# Changelog

## v2.10 — 2026-10-28 (Current)

- **Core**: EMA 10/50 + RSI 14 + ATR 14 dual-mode (trend/MR) with volatility-adaptive frequency.
- **Trend Logic v2**: cross-aware (8-bar lookback) + gap-widening + pullback touch (0.9 ATR) — PF 3.1 vs 0.6 previously on synthetic stress test.
- **Mean-Reversion Guard**: suppress fading when ADX>28 or EMA gap >1.2 ATR (avoids fighting strong breakouts).
- **Risk**: hard daily DD halt 4%, profit-target lock, spread/margin filters, BE @1×ATR, ATR trailing 1.2×, time-stop 20 bars for MR losers.
- **Backtest**: Python mirror `backtest/python_backtest.py` with synthetic regime generator + Monte Carlo, walk-forward docs.
- **Sets**: 3 presets (EURUSD conservative 0.8% risk, XAU balanced 1.2%, GBP aggressive 2%).

## v2.00 — Initial Dual-Mode Prototype

- Basic EMA cross + RSI window, fixed ATR SL/TP, simple DD halt.

## Roadmap

- News calendar filter (CSV), multi-symbol portfolio, Kelly sizing optional in `QM_MoneyManager.mqh`.
