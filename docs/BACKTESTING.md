# Backtesting Guide — QuantumEdge EA

MT4's Strategy Tester is **deterministic on closed bars** by design in this EA (`shift=1`). Use this guide to get trustworthy reports.

## 1. Installation

1. Copy files:
   ```
   MQL4/Experts/QuantumEdge_DualModeEA.mq4  →  <MT4>/MQL4/Experts/
   MQL4/Include/QM_*.mqh                    →  <MT4>/MQL4/Include/
   sets/*.set                               →  <MT4>/MQL4/Presets/
   ```
2. In MetaEditor: Open `QuantumEdge_DualModeEA.mq4` → **Compile** (F7). Zero errors expected.
3. Restart MT4 or refresh Navigator → Expert Advisors → QuantumEdge appears.

## 2. Strategy Tester Settings

| Field | Recommended |
|-------|-------------|
| Symbol | EURUSD, GBPUSD, XAUUSD (start with majors) |
| Period | M15 (balanced), M30 for less noise |
| Model | **Every tick based on real ticks** (not Open Prices) |
| Spread | **Current** or fixed 15-20 for EURUSD, 35-50 for XAU |
| Date Range | 2022-01-01 → 2025-12-31 (3-4y minimum) |
| Forward period | **1/3** of range (Walk-Forward, see §4) |
| Visual Mode | Off for optimization; On for final inspection |
| Deposit | 10,000 (consistent) |
| Leverage | 1:100–1:500 per broker |

> **DO** enable `Optimization` checkbox when searching parameters.

## 3. Parameters to Optimize

In `Inputs`:

| Parameter | Range | Step | Why |
|-----------|-------|------|-----|
| `EMAPeriodFast` | 8–16 | 1 | Curve fits fast; keep < Slow |
| `EMAPeriodSlow` | 30–70 | 5 | Trend baseline |
| `RSIPeriod` | 10–18 | 1 | Usually 14 optimal |
| `RSITrendBullMin` | 50–55 | 1 | Bull gate lower |
| `ATR_SL_Mult` | 1.2–2.5 | 0.1 | Risk tuning |
| `ATR_TP_Mult` | 1.8–3.5 | 0.1 | Reward tuning |
| `RiskPercent` | 0.5–2.0 | 0.25 | **Do not optimize >2.5** |
| `VolatilityHighMult` | 1.3–1.8 | 0.1 | Regime sensitivity |

**Constraints for optimization** (MT4 → Optimization → right-click → Inputs filter):

- Maximize: **Profit Factor** or **Custom** `Profit * (1 - MaxDD/Balance)`.
- Minimum trades: 200 (avoid overfit on few trades).
- Discard runs with `Max Drawdown % > 15%` (equity, not balance).

## 4. Walk-Forward (Anti-Overfit) Protocol

Standard in-sample optimization lies. Use walk-forward:

1. **In-Sample**: 2022-01-01 → 2024-06-30 → Optimize.
2. **Out-of-Sample**: 2024-07-01 → 2025-12-31 → Validate top 5 sets forward.
3. Keep only sets where **OOS Profit Factor > 1.25** and **DD < 4.5%**.

Repeat anchored (expand IS) or rolling (12mo IS → 3mo OOS).

## 5. Interpreting Results

Check **Report** tab:

- **Profit Factor** > 1.4 healthy, >2 suspicious (overfit).
- **Expected Payoff** > spread cost.
- **Max Drawdown % (Equity)** — this must be `< 8%` for live; EA's hard daily 4% halt keeps it lower.
- **Z-Score**, **AHPR/GHPR** for streakiness.

**Critical charts**:

- Equity: smooth stair up, not vertical spikes.
- Drawdown: flat valleys <4% daily; if 20%+ equity DD, Risk% too high.
- Monthly: consistent, not one lucky month.

## 6. Python Backtest (Without MT4)

We ship `backtest/python_backtest.py` — a vectorized pandas backtest replicating the same EMA/RSI/ATR logic. Use it for:

- Quick parameter sweeps (10× faster than MT4).
- Monte Carlo permutations.
- Sharpe/Sortino, Calmar, max DD analytics.

```bash
pip install -r backtest/requirements.txt
python backtest/python_backtest.py --symbol EURUSD --period M15 --start 2022-01-01 --risk 1.0
```

Output: equity curve PNG + CSV + stats JSON.

## 7. From Backtest to Forward

1. Demo forward-test 4–8 weeks with chosen `.set`.
2. Compare live vs backtest execution: slippage, spread widens at news.
3. If live PF drops >30% vs backtest, widen `MaxSpreadPoints` or enable `AvoidFridayClose`.

## 8. Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using `Open Prices` model | Switch to **Every tick**; otherwise SL/TP inside bar unrealistic |
| Optimizing `RiskPercent` together | Optimize strategy first, then **separately** scale risk |
| Survivorship bias (one symbol) | Test on 3+ symbols/timeframes; discard symbol-specific magic |
| Ignoring swap/commission | Set commission in Tester → else profit illusion on many short holds |
| Over-leveraged 10% daily | Keep `RiskPercent ≤ 1.5`; 10% daily requires compounding winners — increase `MaxOpenTrades` only after validation |

## 9. Continuous Optimization Loop

```
Backtest → Walk-Forward → Demo → Micro-adjust (±0.2 ATR mult) → Live (0.01 lot) → Scale
```

Never jump from backtest to full-size live.

