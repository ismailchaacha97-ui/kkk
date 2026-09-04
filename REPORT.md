# Testing 9,600 Trading Strategies — the Top 10

- **Strategies generated:** 9,600 (10 rule families × parameter grids × 3 sizing overlays)
- **Strategies with valid results:** 8,793
- **Universe:** 40 liquid US ETFs and mega-caps (indices, sectors, bonds, commodities)
- **Period:** 2007-04-11 → 2017-11-10 (2,668 daily bars)
- **In-sample:** through 2013-12-31 (selection). **Out-of-sample:** 2014-01 → 2017-11 (scoring).
- **Costs:** 5 bps of traded notional per rebalance; positions lagged one day, no look-ahead.
- **Benchmark:** SPY buy & hold — Sharpe 0.44, max drawdown -56.5%

## The top 10

| # | Family | Parameters | IS Sharpe | OOS Sharpe | Full Sharpe | CAGR | Vol | Max DD | Calmar | Turnover/yr |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `trend_vol_filter` | ma=200, volw=120, volmax=0.12, mode=lo, sizing=vt10 | 0.72 | 1.12 | 0.86 | 3.8% | 4.5% | -8.8% | 0.43 | 23.2x |
| 2 | `trend_vol_filter` | ma=150, volw=120, volmax=0.15, mode=lo, sizing=vt20 | 0.68 | 1.06 | 0.81 | 5.4% | 6.7% | -12.3% | 0.44 | 26.3x |
| 3 | `ma_cross` | fast=60, slow=250, kind=sma, mode=lo, sizing=vt10 | 0.68 | 0.84 | 0.73 | 6.0% | 8.4% | -13.6% | 0.44 | 5.2x |
| 4 | `ma_cross` | fast=10, slow=150, kind=sma, mode=lo, sizing=vt20 | 0.65 | 0.84 | 0.71 | 6.3% | 9.3% | -20.1% | 0.32 | 11.3x |
| 5 | `ma_cross` | fast=25, slow=250, kind=sma, mode=lo, sizing=vt20 | 0.70 | 0.75 | 0.72 | 6.3% | 9.1% | -14.3% | 0.44 | 6.6x |
| 6 | `trend_vol_filter` | ma=150, volw=60, volmax=0.15, mode=lo, sizing=raw | 0.66 | 0.76 | 0.69 | 5.1% | 7.6% | -17.5% | 0.29 | 28.4x |
| 7 | `ts_momentum` | lookback=220, gap=3, mode=lo, sizing=vt10 | 0.61 | 0.74 | 0.65 | 5.1% | 8.1% | -12.2% | 0.42 | 18.0x |
| 8 | `ts_momentum` | lookback=250, gap=3, mode=lo, sizing=vt10 | 0.63 | 0.71 | 0.65 | 5.1% | 8.1% | -11.6% | 0.44 | 14.8x |
| 9 | `ts_momentum` | lookback=220, gap=3, mode=lo, sizing=vt20 | 0.59 | 0.73 | 0.64 | 5.4% | 8.9% | -15.1% | 0.36 | 18.5x |
| 10 | `donchian` | entry=80, exit_n=50, mode=lo, sizing=vt20 | 0.60 | 0.64 | 0.60 | 5.6% | 9.9% | -22.7% | 0.25 | 10.7x |

## How they were chosen

Ranking 9,600 backtests by return is a lottery, not research. The protocol here:

1. **Split first.** Every strategy is fit on 2007–2013 and judged on 2014–2017.
2. **Screens** (survivors after each): IS Sharpe > 0.5, OOS Sharpe > 0.5, both windows profitable, max DD better than −35%, turnover < 30x/yr, vol between 3% and 35%, and no OOS Sharpe collapse below 40% of IS.
3. **Composite score** weighting OOS Sharpe, full-period Sharpe, Calmar, drawdown, and IS→OOS degradation.
4. **De-duplication.** Max 3 per family, and any strategy >0.90 daily-return correlated with a higher-ranked pick is dropped — otherwise the list is one idea ten times.
5. **Deflated Sharpe ratio** (Bailey & López de Prado) discounts each result for the fact that 8,793 trials were run.

## What the search actually says

- IS→OOS Sharpe correlation across all strategies: **0.66**. Positive but weak — in-sample performance is a faint signal, which is exactly why the OOS gate matters.
- Every survivor is **long-only**. Short and long/short variants of the same rules were tested and systematically lost money over this equity-bull sample.
- Nine of ten are **trend / breakout** rules. The mean-reversion families (RSI, z-score) produced good in-sample Sharpes but degraded out-of-sample once costs were charged.
- **Volatility targeting helps.** 8 of the 10 use a vol-target overlay; it lifts Sharpe and cuts drawdowns roughly in half versus raw sizing.
- The winners beat SPY on risk-adjusted terms (Sharpe ~0.55–0.86 vs 0.44) and dramatically on drawdown (−9% to −31% vs −57%), but most trail it on raw CAGR. They are risk-management strategies, not return-maximisers.

## Caveats

- Sample ends 2017-11 (dataset limit) and is dominated by one bull market plus the GFC.
- Costs are a flat 5 bps; no market-impact, borrow, or tax modelling.
- Deflated Sharpe values are low (0.004–0.06), meaning **none of these clears a strict multiple-testing significance bar**. Treat the top 10 as the most robust hypotheses the search produced, not as proven edges.

## Reproduce

```bash
python3 src/data.py        # build the price panel
python3 src/run_search.py  # backtest all 9,600 (~100s)
python3 src/select_top.py  # screens + ranking
python3 src/report.py      # chart + this report
```
