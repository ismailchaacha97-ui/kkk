# TrendVolFilter.mq4 — MT4 indicator for strategy #1

The best-performing strategy of the 9,600 tested in this repo, ported to MQL4.

![preview](preview.png)

## The rule

Be **long** only when both conditions hold at the close of a bar:

1. **Trend** — `Close > SMA(200)`
2. **Calm** — annualised realised volatility over the last **120** bars is **below 12%**

Position size = `10% / AnnVol(60)`, capped at **3.0x**. Flat otherwise; never short.

The signal is taken from the **last closed bar** and acted on at the next bar's open —
a deliberate 1-bar lag that matches the backtest. **The indicator does not repaint.**

## Backtested performance

40 liquid US ETFs and mega-caps, 2007-04 → 2017-11, net of 5 bps per trade:

| metric | strategy | SPY buy & hold |
|---|---|---|
| Out-of-sample Sharpe (2014–17) | **1.12** | — |
| Full-period Sharpe | **0.86** | 0.44 |
| CAGR | 3.8% | 7.05% |
| Volatility | 4.5% | — |
| **Max drawdown** | **−8.8%** | −56.5% |
| Calmar | 0.43 | 0.12 |
| Turnover | 23x/yr | — |

On SPY daily it is in the market ~34% of the time, with 17 entries over 10 years —
it sits out crashes rather than trying to trade them.

## Install

1. In MT4: **File → Open Data Folder**
2. Copy `TrendVolFilter.mq4` into `MQL4/Indicators/`
3. In MetaEditor press **F7** to compile (or restart MT4)
4. Drag **TrendVolFilter** from the Navigator onto a chart

## Inputs

| input | default | meaning |
|---|---|---|
| `MA_Period` | 200 | trend moving-average period |
| `Vol_Window` | 120 | vol lookback for the **filter** |
| `Size_Vol_Window` | 60 | vol lookback for **sizing** (deliberately different) |
| `Vol_Max` | 0.12 | vol ceiling; above this, stay flat |
| `Vol_Target` | 0.10 | annualised vol target for position sizing |
| `Leverage_Cap` | 3.0 | maximum position scale |
| `Periods_Per_Year` | 0 | 0 = auto from timeframe (D1 → 252) |
| `Account_Risk_Pct` | 100 | equity % that 1.0x notional represents |
| `Show_Panel` / `Show_Arrows` | true | on-chart status panel and entry/exit arrows |
| `Alert_On_Signal` / `Push_On_Signal` | true / false | popup / mobile alert on state change |

## What it draws

- **Dotted blue** SMA(200); the same line turns **thick green** while a position is open
- **Green up arrow** = go long, **red down arrow** = go flat
- **Status panel** with both filter checks, the current signal, and the position scale
- Reads `LONG 1.63x` or `FLAT` in the top-right corner

## Timeframe note

The strategy was fitted on **daily bars** — run it on **D1**. On other timeframes the
annualisation adapts automatically, but the 200/120/60 parameters were never validated
there and the 12% vol ceiling will behave very differently.

## Verifying the port

`verify_parity.py` transcribes the MQL4 `OnCalculate()` loop back into Python and
compares it against the strategy code used in the search, across all 40 symbols:

```bash
python3 mt4/verify_parity.py
```

Result: **100.00% signal agreement**, worst position-size difference `1.8e-13`
(floating-point noise). The indicator reproduces the backtest exactly.

## Honest caveats

- This is an **indicator, not an EA** — it signals, it does not place orders.
- Backtested on **US equity ETFs**. On FX or crypto the 12% vol ceiling is close to
  meaningless — those assets rarely sit that calm. Re-fit before using elsewhere.
- The sample ends 2017 and its deflated Sharpe is 0.06, i.e. **not statistically
  significant after correcting for 9,600 trials**. Forward-test before risking money.
- Its edge is drawdown control, not return. It underperforms buy & hold on raw CAGR.
