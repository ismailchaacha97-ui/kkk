# daytrader — a day-trading research lab on NautilusTrader

A small, fully runnable intraday (day-trading) research stack built on
[**NautilusTrader**](https://github.com/nautechsystems/nautilus_trader), the
30k-star, Rust-native, event-driven trading engine. It ships two rule-based
reference strategies (opening-range breakout and session-VWAP mean reversion),
risk-based position sizing, bracket orders with an end-of-day flatten, realistic
costs, and reproducible reports.

> **This is a research scaffold, not a profitable system and not financial
> advice.** The bundled strategies are deliberately simple references. Results
> below are honest: after costs, both lose on the bundled samples. That is the
> point of a good test harness — it tells you the truth quickly.

---

## TL;DR

```bash
python3 -m pip install -r requirements.txt     # Python 3.11 required for the pin
python3 -m daytrader compare --days 60 --out reports
# → reports/comparison.md, reports/orb/summary.md, reports/vwap/summary.md
```

or just:

```bash
bash run.sh
```

Everything is generated locally, with no API keys: a deterministic synthetic
1-minute dataset, two backtests, CSV artefacts, Markdown summaries and charts.

---

## Why this repo (the “best repo” decision)

Candidates were compared on **stars, maintenance, asset coverage, live-trading
capability and fit for intraday work** (star counts and last-push dates as of
2026-10-19):

| Repository | ★ | Stack | License | Verdict |
|---|---:|---|---|---|
| **nautechsystems/nautilus_trader** | **30.3k** | Rust + Python | LGPL-3.0 | **Chosen.** Event-driven, nanosecond timestamps, same `Strategy` class for backtest and live, adapters for IB/Databento/Binance/Bybit, active daily. |
| freqtrade/freqtrade | 55.6k | Python | GPL-3.0 | Excellent crypto bot, but crypto-only and retail-bot shaped. |
| QuantConnect/Lean | 22.1k | C#/.NET + Python | Apache-2.0 | Very strong engine; heavier toolchain, cloud/CLI-centric. |
| mementum/backtrader | 23.5k | Python | GPL-3.0 | Beloved API, but no release since 2023 and last push in 2024. |
| jesse-ai/jesse | 8.7k | Python | MIT | Clean and modern, crypto-only. |
| polakowo/vectorbt | 9.4k | Python | Apache-2.0 + Commons Clause | Superb vectorised research, no live execution. |
| microsoft/qlib | 49.5k | Python | MIT | AI/quant research platform, not an execution engine. |
| ranaroussi/yfinance | 25.6k | Python | Apache-2.0 | Data downloader, not a trading system. |

**Why NautilusTrader won for day trading**

1. **Backtest == live.** The same `Strategy` subclass runs in the backtest engine
   and in a live `TradingNode`; there is no rewrite step.
2. **Intraday is the native mode.** Bars, ticks, quotes, order books and
   nanosecond event timestamps are first-class.
3. **Realistic execution.** Bracket/OCO orders, stop and limit trigger models,
   latency and probabilistic fill/slippage models, venue-specific OMS models.
4. **Performance.** Rust core; a 60-session, 3-symbol, 1-minute backtest here
   finishes in a few seconds.
5. **Maintenance.** Pushed to on the day this was installed; regular releases.

Licensing note: NautilusTrader is **LGPL-3.0-or-later**. Using it as a library is
fine; if you modify the engine itself and distribute it, LGPL obligations apply.
No license file is included for *this* repository's own code — add one before
distributing it.

---

## Installed here

| Component | Version |
|---|---|
| Python | 3.11.2 |
| `nautilus_trader` | **1.221.0** |
| numpy / pandas / matplotlib | 2.4.6 / 2.3.3 / 3.11.2 |

`1.221.0` is the **last NautilusTrader release that supports Python 3.11**.
Releases 1.222.0+ require Python 3.12/3.13. See [`docs/UPSTREAM.md`](docs/UPSTREAM.md)
for the pinned tag, upgrade path and API notes.

---

## What is in the repo

```text
daytrader/
  config.py             typed BacktestConfig / ORBParams / VWAPParams / RiskConfig
  data.py               synthetic session generator + CSV loader + validation
  instruments.py        cash-equity instrument factory + bar types
  indicators.py         ATR, session VWAP and band calculations (pure pandas)
  risk.py               stop-distance position sizing with a notional cap
  metrics.py            performance stats from orders/fills/positions
  backtest.py           engine wiring: venue, costs, slippage, strategies, reports
  reporting.py          Markdown/JSON/CSV reports and equity/drawdown charts
  cli.py                `python -m daytrader {generate-data,backtest,compare}`
  strategies/
    base.py             session cycle, ATR, sizing, bracket orders, EOD flatten
    orb.py              Opening Range Breakout
    vwap.py             Session-VWAP mean reversion
scripts/
  fetch_lean_sample.py  downloads real 1-minute bars from QuantConnect's LEAN repo
  param_sweep.py        in-sample grid search helper
tests/                  29 unit + end-to-end tests (unittest, no network)
data/                   generated CSVs (gitignored)
reports/                backtest artefacts (gitignored)
```

---

## How it works

```text
CSV 1-min bars ──► instruments ──► BacktestEngine (XNAS, margin, fees, slippage)
                                      │
                          ┌───────────┴────────────┐
                     ORB strategy           VWAP strategy
                          │                        │
                     bracket orders (market entry + OCO stop/target)
                          │
                 end-of-day flatten at 15:55 ET
                          │
             positions/fills/orders/account reports
                          │
        metrics ──► Markdown + JSON + CSV + PNG
```

Execution assumptions:

* Signals are evaluated on **bar close**; market entries fill at that bar's
  close (the next bar's open is the same price in continuous 1-minute data).
* Every entry is a **bracket order**: market entry, protective stop-market, and
  a take-profit limit. The children are OCO; a filled target cancels the stop.
* **Costs:** 1 bp per side on both maker and taker fills (deliberately
  conservative), plus NautilusTrader's `FillModel` with a 50 % chance of one
  tick of slippage on triggered orders.
* **Risk:** 0.5 % of equity per trade (0.4 % for VWAP), capped at 25 % notional;
  quantity is floored to whole shares.
* **No overnight risk:** all positions are closed at 15:55 ET, verified by tests.
* Positions are **net** per symbol (one position at a time), max 2–3 round trips
  per symbol per day.

---

## The strategies

### Opening Range Breakout (`orb`)

| Parameter | Default | Meaning |
|---|---|---|
| `opening_range_minutes` | 15 | First 09:30–09:45 ET bars define the range |
| `breakout_buffer_bps` | 2 | Close must clear the boundary by 2 bp |
| `volume_mult` | 1.2 | Breakout bar volume ≥ 1.2 × median OR volume |
| `max_or_width_pct` | 3.0 | Skip days whose opening range is > 3 % wide |
| `min_stop_bps` / `max_stop_bps` | 15 / 80 | Clamp the structural stop distance |
| `reward_risk` | 2.0 | Take-profit at 2R |
| `entry_cutoff` | 14:30 | No new entries after this time |
| `flatten_time` | 15:55 | Hard end-of-day exit |

One trade per direction per day, long and short. Stops sit at the opposite side
of the opening range, with a minimum distance so a tight range cannot produce a
sub-tick stop.

### Session-VWAP mean reversion (`vwap`)

| Parameter | Default | Meaning |
|---|---|---|
| `band_k` | 2.0 | Standard-deviation band around session VWAP |
| `atr_stop_mult` | 1.5 | Stop distance in ATRs (also outside the signal bar) |
| `min_reward_risk` | 1.0 | Require at least 1:1 to the VWAP target |
| `entry_start` / `entry_cutoff` | 09:45 / 15:00 | Trading window |
| `flatten_time` | 15:55 | Hard end-of-day exit |

The trade triggers when price closes back **inside** the band after an
extension (a failed breakout), targets the session VWAP, and stops one ATR
beyond the signal bar. Up to three round trips per symbol per day.

---

## Measured results

All runs use $100,000 starting equity, 1 bp per side, one-tick slippage at 50 %,
and the same risk limits.

### Synthetic sample — 60 sessions, AAPL/MSFT/NVDA, seed 42

| Metric | ORB | VWAP |
|---|---:|---:|
| Net PnL | **−$2,876.48** | **−$1,918.88** |
| Return | −2.88 % | −1.92 % |
| Trades | 113 | 538 |
| Win rate | 31.0 % | 33.5 % |
| Profit factor | 0.77 | 0.91 |
| Max drawdown | −4.61 % | −3.20 % |
| Sharpe (daily, annualised) | −2.25 | −1.63 |

**Where the money went:** ORB gross PnL was −$2,323 with $554 of costs; VWAP
gross PnL was **+$724** with **$2,642** of costs. So VWAP found a small gross
edge in the mean-reverting synthetic process, but its 538 round trips consumed
it. Turnover is the enemy.

### Real sample — 7 sessions, SPY/IBM/BAC/AIG

Loaded from QuantConnect's open-source LEAN repository (see below), so this is
real price action, just a very short window.

| Metric | ORB | VWAP |
|---|---:|---:|
| Net PnL | −$125.97 | −$342.10 |
| Return | −0.13 % | −0.34 % |
| Trades | 23 | 65 |
| Win rate | 43.5 % | 29.2 % |
| Profit factor | 0.92 | 0.81 |
| Max drawdown | −0.22 % | −0.35 % |

Gross PnL was roughly flat on this sample (−$11 ORB, −$19 VWAP); again, costs
turn flat into negative. Six sessions cannot validate anything — use this to
check the plumbing, not to choose a strategy.

### Parameter sweep (in-sample, for illustration)

`scripts/param_sweep.py` runs a 12- and 18-combination grid. The best VWAP
variant (`band_k=2.5`, `atr_stop_mult=1.0`) returns **+1.37 %** over the same 60
synthetic sessions; the best ORB variant is still negative. This is **in-sample
selection** — with 18 tries on 60 sessions, some positive result is expected by
chance. Treat it as a workflow demo, not an edge.

---

## Quickstart

```bash
# 1. Install (Python 3.11)
python3 -m pip install -r requirements.txt

# 2. Generate synthetic data + run both strategies + compare
python3 -m daytrader compare --days 60 --symbols AAPL MSFT NVDA --seed 42 --out reports

# 3. Inspect
open reports/comparison.md
open reports/orb/equity_curve.png
```

Useful variants:

```bash
# single strategy, longer sample, different seed
python3 -m daytrader backtest --strategy orb --days 120 --seed 7 --out reports/orb_120

# only generate data
python3 -m daytrader generate-data --days 60 --symbols AAPL MSFT NVDA

# tune one parameter from the CLI
python3 -m daytrader backtest --strategy orb --orb-minutes 30 --reward-risk 3 --risk-pct 0.25
```

Every run writes `orders.csv`, `fills.csv`, `positions.csv`, `account.csv`,
`daily.csv`, `summary.json`, `stats.txt`, `summary.md` and `equity_curve.png`
(plus `comparison.md` / `comparison.png` in compare mode).

---

## Using real data

### Option A — LEAN sample (no keys, real prices)

```bash
python3 scripts/fetch_lean_sample.py --out data_real
python3 -m daytrader compare \
    --symbols SPY IBM BAC AIG --data-dir data_real --no-generate --out reports/real
```

The script pulls the small minute-bar sample that ships in
[QuantConnect/Lean](https://github.com/QuantConnect/Lean), converts LEAN's
millisecond/scaled-integer format into this project's CSV schema, and caches it
under `data_real/` (gitignored). The data is not redistributed by this repo.
Only a handful of sessions exist there; it is a plumbing check, not a study.

### Option B — your own CSV

One file per symbol, 1-minute bars, regular session only, named
`<SYMBOL>_1min.csv` (or `<SYMBOL>_5min.csv` with `--bar-minutes 5`):

```csv
timestamp,open,high,low,close,volume
2026-01-05 09:30:00,224.92,225.19,224.86,225.13,247891
2026-01-05 09:31:00,225.13,225.45,225.10,225.41,209680
```

* Naive timestamps are interpreted as **exchange-local** (`America/New_York`);
  tz-aware timestamps are converted automatically.
* `date` + `time` columns are accepted too; `volume` is optional.
* Bar size must match `--bar-minutes`; the loader raises a precise error on
  mismatched intervals, duplicate or unsorted timestamps, and broken OHLC.
* Put the files in a directory and pass `--data-dir <dir> --no-generate`.

```bash
python3 -m daytrader compare --symbols SPY QQQ --data-dir /path/to/csvs \
    --no-generate --out reports/vendor
```

---

## CLI reference

```text
python -m daytrader generate-data [options]
python -m daytrader backtest --strategy {orb,vwap} [options]
python -m daytrader compare [options]
```

| Option | Default | Notes |
|---|---|---|
| `--symbols` | `AAPL MSFT NVDA` | one or more tickers |
| `--days` | 60 | synthetic sessions (ignored for existing real files) |
| `--seed` | 42 | generator + slippage seed |
| `--start-date` | 2026-01-05 | first synthetic session |
| `--bar-minutes` | 1 | must divide 30 |
| `--data-dir` / `--out` | `data` / `reports` | inputs / outputs |
| `--balance` / `--leverage` | 100000 / 2.0 | account |
| `--fee-bps` / `--slippage-prob` | 1.0 / 0.5 | costs |
| `--no-generate` | off | fail on missing CSVs instead of inventing data |
| `--force-data` | off | regenerate synthetic files |
| `--risk-pct`, `--max-trades` | strategy defaults | risk overrides |
| `--orb-minutes`, `--reward-risk`, `--band-k` | strategy defaults | strategy overrides |

Research helper:

```bash
python3 scripts/param_sweep.py --strategy all --days 60 --top 8
# writes reports/sweep_orb.{csv,md} and reports/sweep_vwap.{csv,md}
```

---

## Going live later

The strategies are ordinary `nautilus_trader.trading.strategy.Strategy`
subclasses, so the move from backtest to live is an engine swap, not a rewrite:

1. Install the adapter extra you need, e.g. Interactive Brokers:
   `pip install "nautilus_trader[ib]"`. Databento, Binance, Bybit and other
   adapters ship with the core package in this version — check the docs for your
   exact version.
2. Build a `TradingNode` with an instrument provider, data client and execution
   client instead of `BacktestEngine`.
3. Keep the identical strategy classes, and **paper trade first** on a broker
   sandbox.
4. Add operational safeguards before real money: a kill switch, daily loss limit,
   maximum position/correlation caps, reconcile-on-start, alerting and a
   heartbeat monitor.

Nothing in this repo is wired for live order routing — that requires credentials,
broker-specific configuration and a risk review, and it is deliberately out of
scope.

---

## Tests

```bash
python3 -m unittest discover -s tests -v
# Ran 29 tests ... OK
```

Coverage includes indicator math, position sizing, generator determinism and
OHLC invariants, CSV edge cases (naive timestamps, date/time columns, bad bars),
end-to-end runs for both strategies, the absence of overnight positions, and the
consistency of the equity/daily-PnL aggregation.

Lint/format (optional): `ruff check . && ruff format --check .`

---

## Assumptions and limitations

* **Synthetic data is a fixture.** It models gaps, opening volatility, U-shaped
  volume, trend days and mean-reverting dislocations, but it is not a market.
  Profitability on it is meaningless; the generator is deliberately not rigged
  to make the strategies win.
* **Bar-close execution** is optimistic by roughly one tick; the slippage model
  partially compensates and can print one tick through a limit price (a known
  NautilusTrader `FillModel` simplification).
* No queue position, no partial fills on market orders, no latency, no borrow
  fees/locate availability for shorts, no corporate actions or dividends, no
  holidays, no survivorship-free universe, no market impact.
* The real sample is 6–7 sessions of 4 large caps; every annualised number on
  such a sample is noise.
* Parameter defaults are illustrative, chosen before any backtest. The sweep is
  in-sample and selection-biased.
* **No financial advice.** Markets can and do gap through stops; live results
  will differ materially from any backtest.

---

## Attribution

* Engine: [nautechsystems/nautilus_trader](https://github.com/nautechsystems/nautilus_trader),
  v1.221.0, LGPL-3.0-or-later. See [`docs/UPSTREAM.md`](docs/UPSTREAM.md).
* Real-data sample: [QuantConnect/Lean](https://github.com/QuantConnect/Lean)
  minute bars (Apache-2.0 code; data remains subject to QuantConnect's terms).
  Downloaded on demand, never committed.
* Everything else in this repository was written for this project.
