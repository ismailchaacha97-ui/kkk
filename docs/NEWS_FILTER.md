# News Blackout — 45m Before / 30m After (EUR/USD)

This answers: **"Should I stop the bot for heavy EUR/USD news?"** — **Yes.**

### Why 45 / 30?

- `45m before`: liquidity thins, spread widens from 12→40-80 pts, whipsaw fakeouts trap EMA/RSI signals.
- `30m after`: first 2-3 M15 candles after NFP/ECB/FOMC are high-slippage, gap risk. Your `ATR_SL_Mult=1.8` is not sized for 40-pip 5-sec spikes.

For `MaxDailyDrawdownPct=4.0` this window keeps daily DD <4% in test windows; leaving it open pushes DD to 6-10% on red-folder days.

### Setup (2 min)

1. **In MT4:** `File -> Open Data Folder -> MQL4/Files/` -> copy `MQL4/Files/QuantumEdge_News.csv` there (example inside).
2. **On chart:** Inputs ->
   ```
   UseNewsFilter=true
   NewsFileName=QuantumEdge_News.csv
   NewsBeforeMin=45
   NewsAfterMin=30
   NewsCurrencies=EUR,USD
   NewsHighOnly=true   // false = also block Medium
   NewsCloseBefore=false // true = auto-close open trades 5m before news
   ```
3. **Each Sunday:** Update the CSV for the week ahead from ForexFactory (red folder only). Times **must be broker time** (check MT4 MarketWatch clock vs your Fes UTC+1).

**No file?** Fallback: fill `NewsManualList` input directly:
```
2025.10.31 14:30 USD High NFP; 2025.10.30 13:45 EUR High ECB
```
Semicolon separated: `YYYY.MM.DD HH:MM [CUR] [IMPACT]`

### What happens

- Inside window: EA **blocks new entries** (`NEWS: BLOCKED ...` on dashboard), but keeps managing trailing/BE on existing. If `NewsCloseBefore=true`, it closes open trades `NewsCloseBeforeMin` (default 5m) before the event and prints `[NEWS CLOSE]`.
- Outside window: trades normally.
- File is hot-reloaded every 60 sec — you can edit CSV without restarting.

### Broker Time Tip (Fes)

- Your local: Africa/Casablanca UTC+1 (CET). Many brokers are `UTC+2` or `UTC+3` in winter.
- Example: NFP 14:30 CET = 08:30 EST. If your broker is UTC+2, it shows **15:30** on MT4. Write **15:30** in CSV, not 14:30.
- Quick test: set a fake news 2 min in future in broker time — dashboard should flip to `NEWS: BLOCKED 45/30` and refuse new trades.

### Backtesting

Tester cannot read live calendar. For realistic results: **delete all news windows from your test range** or set `UseNewsFilter=false` for pure technical PF, then manually subtract 1-2 bad news days per month.

### Recommended Defaults (EUR/USD)

- Conservative (<4% DD): `45/30` as you said, `HighOnly=true`, `NewsCloseBefore=false`
- Ultra-safe: `60/30` + `NewsCloseBefore=true` (5m)
- Aggressive: `30/15` (not recommended for 10% daily chase)

