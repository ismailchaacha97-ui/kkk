# kkk — Forgotten Edges: Taylor's 3-Day Overnight Cycle

Research dossier + tradeable system from old trading books + academic papers.
Thesis: buy late on Buy-Day dips, hold **overnight**, sell morning strength — and size up
when turn-of-month / pre-macro / leadership tailwinds align.

| File | What it is |
|---|---|
| `SECRET_STRATEGY.md` | Part 1 — thesis: books + papers, tradeable rules, worked example |
| `DEEP_DIVE.md` | **Part 2 — quantified manual: every formula, threshold, fill assumption** |
| `DAYTRADING.md` | Day-trade adaptation: 5 intraday setups, flat every close |
| `MQL4/Indicators/TaylorCycle.mq4` | **MT4 indicator: labels, arrows, dashboard, alerts** (see `MT4_GUIDE.md`) |
| `MT4_GUIDE.md` | MT4 install + inputs + workflow |
| `mt4_cal_input.py` | Prints `InpMacroDates` string from `data/*.csv` |
| `taylor_engine.py` | v2 backtest + screener (`--demo` runs fully offline) |
| `taylor_overnight_backtest.py` | v1 skeleton (reference; v2 supersedes it) |
| `data/fomc_dates.csv` | FOMC announcements 2023–2026 (verified vs federalreserve.gov) |
| `data/macro_dates.csv` | CPI + NFP releases (verified vs bls.gov) |
| `fetch_calendars.py` | Extends calendars by scraping Fed + BLS |
| `TAYLOR_BOOK.csv` | Daily journal template |
| `SOURCES.md` | All sources with links |

Quickstart (needs `pip install pandas numpy yfinance` for live data; `--demo` needs only pandas+numpy):

```bash
python taylor_engine.py --demo                                   # offline sanity check
python taylor_engine.py --ticker SPY --start 2015-01-01 --source stooq
python taylor_engine.py --ticker SPY --start 2015-01-01 --source stooq --exit limit --shorts --no-friday
python taylor_engine.py --screen SPY,QQQ,AAPL,MSFT,NVDA --source stooq   # nightly screen
python fetch_calendars.py                                        # extend data/*.csv
```

**Not financial advice.** Educational research. Overnight holds have gap risk — backtest,
paper-trade 30 trades (see `DEEP_DIVE.md` §9), then decide.
