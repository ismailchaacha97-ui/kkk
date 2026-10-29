# QuantumEdge Dual-Mode Strategy — Deep Dive

## 1. Philosophy

Retail EAs fail because they are **mono-strategy**: trend EAs die in ranges, mean-reversion EAs die in trends. QuantumEdge is **dual-mode**:

| Regime | Condition | Active Strategy | Why |
|--------|-----------|----------------|-----|
| **High Volatility** | `ATR > MA(ATR) * 1.6` | **Trend-Only** + ADX confirmation + Cooldown | In breakouts, counter-trend entries are whipsaw traps. Reduce frequency, demand trend proof. |
| **Low Volatility** | `ATR < MA(ATR) * 0.8` | **Mean-Reversion Primary** | Range expansion hasn't happened; price oscillates around VWAP/MA. Fade extremes with RSI + distance filter. |
| **Normal** | else | **Trend Preferred, MR Fallback** | Healthy trends with occasional pullback fades. |

Adaptive frequency: `VolCooldownBars = 3` skips N bars after a high-vol entry — prevents over-trading during news spikes.

## 2. Indicators

### EMA Crossover (Trend Engine)
- **Fast 10, Slow 50** (optimized: 8-12 / 40-60 walk-forward).
- Signal bar = **closed bar[1]** — eliminates intrabar repaint, critical for backtest validity.
- Gap filter: `|EMAfast - EMAslow| > ATR * 0.85` ensures trend has magnitude; cuts chop.

### RSI(14) — Pullback Timer
Not used as standalone trigger — used as **gatekeeper**:

- **Trend Long**: `RSI ∈ [52,68]` → price pulled back but still bullish (not OB, not bearish).
- Extra: RSI cross-up 50 → momentum regime shift early entry.
- **Trend Short**: symmetric `RSI ∈ [32,48]`.
- **Mean-Reversion**:
  - Oversold ≤30 + price >1.7×ATR below MA → reversal buy, **but only if RSI turning up** (`RSI[1] > RSI[2]`) to avoid falling knife. Deep ≤25 overrides.
  - Overbought mirror.

### ATR(14) — Volatility & Risk Unit
Everything is ATR-normalized:
- `SL = ATR * 1.8` (≈ 1.5-2.5 optimized per symbol)
- `TP = ATR * 2.7` → Reward:Risk ≈ 1.5:1, compensating for win-rate ~45-52%.
- Breakeven: profit > `ATR*1.0` → lock BE+5pts.
- Trailing: `ATR*1.2` distance, step 10pts.

### ADX(14) > 22 Confirmation (optional)
Only in HIGH VOL regime; filters news wicks that look like trends but have no structure.

## 3. Mean-Reversion Module

Condition:
```
dist = |Close - SlowMA| / ATR
if dist > 1.7 AND RSI ≤ 30 AND Close < SlowMA AND ( RSI rising OR RSI ≤ 25 )
  => MR Buy (TP 1.4×ATR, SL 1.6×ATR, time stop 20 bars)
```

- Optional Bollinger Band confirmation: require touch of outer band.
- **Time Stop**: losing MR trade held ≥20 bars → close; prevents bag-holding when range breaks into trend.

## 4. Money Management — Capital Preservation First

### Fixed-Fractional Sizing
```
riskMoney = Equity * RiskPercent / 100
slTicks   = SLpoints * Point / TickSize
lots      = riskMoney / (slTicks * TickValue)
```
- Normalized to `MODE_LOTSTEP`, capped `MinLot`/`MaxLot`.
- **Margin check**: `AccountFreeMarginCheck()` before send; half-lot retry.

### Daily Hard Stops
- Track `g_dailyStartEquity` at D1 bar open.
- If `DD% = (Start - Current)/Start >= MaxDailyDrawdownPct` (default 4%) → **close all, halt new entries until next D1**.
- Profit target mirror: if `Profit% >= 10%` → halt (configurable to lock gains).

### Spread & Margin Filters
- Skip entry if `Spread > MaxSpreadPoints` (30 pts).
- Skip if `Equity/Balance < MinEquityPercent%` or `FreeMargin < 100`.

## 5. Trade Management Ladder

1. **Entry**: SL/TP precomputed from ATR + buffers, respecting `MODE_STOPLEVEL`.
2. **Breakeven**: automatic at +1×ATR profit.
3. **Trailing**: ATR-based, only advances (never widens).
4. **RSI Exhaustion Exit**: if long & RSI>72 with profit → close (trend blowoff).
5. **Time Stop**: MR losing holds beyond N bars.

All modifications validated against `StopLevel` to avoid error 130 spam.

## 6. Why NOT 10% Daily on Autopilot

Compounding math: `1.10^20 ≈ 6.7×` in 20 trading days. To hit 10% daily with <4% DD would require:

- Win-rate > ~70% at R:R 1:1.5 **or** near-perfect trade selection.
- Leverage that **any** 4% adverse move wipes account.

Realistic sustainable target: **0.4–1.2% daily on high-volatility instruments (XAU, GBP)** with strict discipline ≈ 8–25% monthly if compounding holds — still elite. Aggressive `.set` files push toward 3-5% daily but DD rises to 6-10%.

> This EA is tuned for **risk-adjusted return (Sharpe/Sortino)**, not fantasy equity curves.

## 7. Extensibility

- Add `iCCI`, `iBands`, `Market Sentiment` via `GenerateSignal()` switch.
- Replace `LOT_RISK_BASED` with Kelly: `f* = (p*b - q)/b`.
- Add news calendar CSV filter in `IsWithinTradingHours()`.

