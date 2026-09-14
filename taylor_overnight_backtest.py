"""
Taylor Overnight Cycle — minimal backtest skeleton (educational, not trading advice).

Simplified Taylor Buy Day proxy for DAILY data:
  Buy Day candidate = after 2 consecutive down closes (stand-in for "2 days after swing high").
  Buy close -> sell next open (overnight hold only).

With Turn-of-Month flag (T-1 to T+3) to show the academic amplifier.

True Taylor needs INTRADAY data for:
  - low-first vs high-first, close position in range (top 30-40% to hold),
  - Buy Day Low Violation filter, morning-high exit on Sell Day.
Extend this with 60-min bars for full rules (see SECRET_STRATEGY.md 4.3).

Requires: pip install yfinance pandas numpy
Run: python taylor_overnight_backtest.py
"""

import numpy as np
import pandas as pd

TICKER = "SPY"
START = "1993-02-01"

def load(ticker=TICKER, start=START):
    import yfinance as yf
    df = yf.download(ticker, start=start, auto_adjust=False, progress=False)
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)
    df = df.dropna(subset=["Open", "Close"]).copy()
    df["prev_close"] = df["Close"].shift(1)
    df["down"] = df["Close"] < df["Close"].shift(1)
    df["down2"] = df["down"] & df["down"].shift(1)
    # Overnight = today's open / yesterday's close - 1 ; Intraday = close/open - 1
    df["overnight"] = df["Open"] / df["prev_close"] - 1
    df["intraday"] = df["Close"] / df["Open"] - 1
    df["close_to_close"] = df["Close"] / df["prev_close"] - 1
    # Turn-of-month: last trading day of month (T-1 concept) + first 3 trading days
    # Proxy: calendar last day OR day 1-3 of month (good enough for skeleton)
    d = df.index
    is_month_end = (d + pd.offsets.BDay(1)).month != d.month
    df["tom"] = is_month_end | (d.day <= 3)
    return df

def backtest(df):
    # Signal: buy close on day t if down2 on day t, capture overnight t -> t+1 open
    # So trade return = overnight of t+1
    df["signal_buy_close"] = df["down2"]
    df["trade_overnight_next"] = df["overnight"].shift(-1)
    df["trade_tom"] = df["tom"].shift(-1).fillna(False).astype(bool)  # ToM status of exit morning
    trades = df[df["signal_buy_close"]].copy()
    trades["ret"] = trades["trade_overnight_next"]
    # Costs: ~1bp spread+commission each way for SPY; overnight = 2 legs
    COST_BPS = 2.0
    trades["ret_net"] = trades["ret"] - COST_BPS / 1e4
    return trades

def report(df, trades):
    print(f"=== {TICKER} {df.index[0].date()} -> {df.index[-1].date()} ===")
    print(f"Avg close-to-close : {df['close_to_close'].mean()*1e4:7.2f} bps/day")
    print(f"Avg overnight      : {df['overnight'].mean()*1e4:7.2f} bps/day")
    print(f"Avg intraday       : {df['intraday'].mean()*1e4:7.2f} bps/day")
    print()
    print(f"Trades (2-down-days buy-close->next-open): {len(trades)}")
    if len(trades) == 0:
        return
    for label, sub in [("ALL", trades), ("ToM exit", trades[trades['trade_tom']]), ("Non-ToM exit", trades[~trades['trade_tom']])]:
        if len(sub) == 0:
            continue
        hit = (sub["ret_net"] > 0).mean()
        print(f"  {label:12s} n={len(sub):4d}  avg_net={sub['ret_net'].mean()*1e4:6.2f}bps  "
              f"hit={hit:.1%}  total_net={sub['ret_net'].sum()*100:7.2f}%  worst={sub['ret_net'].min()*100:.2f}%")
    print()
    print("Next steps (see SECRET_STRATEGY.md):")
    print(" 1. Add intraday filter: hold only if Buy Day closes top 40% of range (skip Low Violation).")
    print(" 2. Exit = first-hour high / prior-high limit on Sell Day, not just open.")
    print(" 3. Add pre-FOMC/CPI calendar flag; compare drift nights.")
    print(" 4. Single stocks: add 52W proximity+recency + same-month rank filters.")

if __name__ == "__main__":
    try:
        df = load()
    except Exception as e:
        print("Need yfinance + internet. pip install yfinance")
        raise
    trades = backtest(df)
    report(df, trades)
