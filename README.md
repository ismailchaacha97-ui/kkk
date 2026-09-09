# EMA pair study — which fast/slow exponential moving average actually works?

A from-scratch grid-search backtest of **every (fast, slow) EMA pair** you would plausibly consider —
9,299 of them, plus a 13,368-pair extension to 1,200-bar slow EMAs — evaluated on **82 daily markets**
(US large caps, US equity indices, US ETFs, global equity-index futures, FX futures, commodities,
rates, crypto) spanning **1970-06-15 to 2026-03-28**. **9,761,738 backtests** in total, including the
zero-cost, triple-cost, weekly-bar and simple-moving-average control runs.

Candidates are judged by *robustness*, never by the best in-sample number:

* cross-market consensus — does the pair work in many unrelated markets?
* plateau / worst-neighbour scoring — is the win a broad flat region or a lucky spike?
* two out-of-sample referees: 6-fold walk-forward re-optimisation, **and** a cross-market split-sample
  test in which the pair is chosen on the older 60% of every market and scored on the newer 40%
* per-decade stability, rolling 3-year consistency
* transaction-cost sensitivity (0×, 1×, 3×) and execution-model sensitivity (signal close vs next open)
* weekly-bar and SMA controls, to test whether *EMA* specifically is doing any work
* a diversified 82-market trend book with vol targeting, scored against buy & hold on an identical
  market set and identical per-market start dates
* a deflated-Sharpe multiple-testing penalty for having looked at 9,299 pairs
* a negative control: deliberately contaminated FX data, to show what a stale timestamp does to a
  fast-EMA backtest

**Read [`REPORT.md`](REPORT.md) for the answer.** Headline: on daily bars, long/flat, the optimum is a
broad plateau at **fast ≈ 40-80 / slow ≈ 115-165 bars**, best single pair **60/132** — median
cross-market Sharpe 0.431, positive in 94% of the 82 markets, ~1.5 round trips a year, and it survives
tripling costs. The popular pairs are the *bad* ones: 12/26 (MACD) ranks 9,177th of 9,299, 50/200
(golden cross) 2,219th, and 10/20 long/short has a median Sharpe of 0.001 with a negative
neighbourhood floor. On Sharpe, nothing here beats holding the basket; on drawdown it does — at a
matched 10% volatility the book's worst episode goes from −63% to −21% (Calmar 0.11 → 0.43).
Re-tuning the pair per market or per year is worse than not trying at all (§5).

## Layout

```
scripts/fetch_data.py         download + normalise the raw price files, with hygiene screens
scripts/run_study.py          one grid sweep (mode, bar size, cost multiplier, MA type)
scripts/run_all.sh            the full sweep: daily, weekly, 0x/3x cost, SMA control, extended grid
scripts/analyze.py            rankings, plateau scoring, walk-forward, DSR, figures, summary.json
scripts/analyze_surfaces.py   banded surfaces, ridges, "given your fast line..." tables, vol scaling
scripts/analyze_shortlist.py  per-asset-class tables, 3-year consistency, decade books, home markets
scripts/benchmark_book.py     buy & hold rebuilt on the identical book, window and per-market starts
scripts/key_results.py        every number quoted in REPORT.md, read back out of the result files
scripts/fix_annualisation.py  exact rescale of cached grids when annualisation changes (+ self-check)
src/ema_study/data.py         loader, annualisation from bars-per-calendar-year, hygiene screens
src/ema_study/engine.py       EMA, position/state construction, metrics, single-pair backtests
src/ema_study/grid.py         batched full-grid evaluator (grouped by slow period)
src/ema_study/robust.py       aggregation, plateau/robustness scoring, walk-forward, split-sample, DSR
src/ema_study/plots.py        figures
tests/test_engine.py          19 tests: EMA definition, no-lookahead, cost accounting, batched-vs-loop
                              parity, drawdown/warm-up definitions, annualisation, return-model edges
tests/test_robust.py          10 tests: plateau scoring, walk-forward, split-sample, trend book
results/                      tables/ (CSV+MD), figs/ (PNG), summary*.json, fact_sheet.txt [generated]
```

## Reproduce

```bash
pip install --break-system-packages pandas numpy matplotlib pyarrow scipy pytest

python3 scripts/fetch_data.py        # 94 series, via the GitHub contents/blob API
bash scripts/run_all.sh              # the expensive part: ~25 min on 2 cores
python3 scripts/analyze.py           # rankings + walk-forward + figures
python3 scripts/analyze_surfaces.py  # shape of the surface, practical tables
python3 scripts/analyze_shortlist.py # per-class and consistency tables for the chosen pairs
python3 scripts/benchmark_book.py    # the buy & hold reference book
python3 scripts/key_results.py       # prints results/fact_sheet.txt
python3 -m pytest tests/ -q          # engine correctness
```

Environment: `KKK_DATA` overrides the data directory (default `/home/user/data`).
Everything is deterministic — no randomness outside the explicit seeds in `tests/`.
If you change the annualisation convention, `scripts/fix_annualisation.py` repairs the cached grids in
place instead of requiring a 25-minute re-run, and verifies itself against a fresh sweep.

## Data

| source | what | span |
|---|---|---|
| `jiewwantan/StarTrader` (GitHub) | 26 US large caps, ^GSPC/^IXIC/^DJI/^RUT, ^TNX/^VIX, SPY/QQQ/GLD/SHY — daily OHLCV, adjusted close | 2008-2019 |
| `pst-group/pysystemtrade` (GitHub) | 16 FX futures, 10 global equity-index, 10 commodity, 7 rate futures — daily continuous marks | 1970s-2026 |
| `arch` (PyPI, bundled) | S&P 500 and Nasdaq Composite daily OHLCV | 1999-2018 |
| `whchien/ai-trader`, `notadamking/RLTrader` (GitHub) | BTC-USD, ETH-USD daily | 2014-2026 |

Only `pypi.org` and `api.github.com` are reachable from this sandbox, so data is fetched through the
GitHub contents/blob API. The automatic hygiene screen (`ema_study.data.load_universe`) **dropped 9
series on purpose**; the reasons are in `results/tables/data_hygiene.csv` and the report — including a
set of FX *spot* feeds whose fixed-clock timestamps create +0.18…+0.39 lag-1 autocorrelation, 33-62%
zero returns, and thereby *manufacture* trend alpha for fast EMAs (§8 of the report measures exactly
how much fake Sharpe they add).

## Caveats

* Backtests of trend filters on one long historical sample are heavily influenced by which decades are
  in the sample. That is why the recommended settings come from plateau/worst-neighbour and
  out-of-sample criteria, not from the in-sample argmax — and why the report states the answer as a
  range, with per-decade and split-sample evidence, rather than as a single pair.
* Costs are modelled per asset class in bps of notional at each position change (10 stocks, 6
  ETFs/indices, 4 futures, 3 FX futures, 20 crypto); no funding, borrow, roll or margin model, and
  shorting equities is cheaper here than in reality.
* Continuous futures series are additively roll-adjusted; percentage returns are computed as price
  differences over a trailing median price level, and bars where the adjusted level is within 25% of
  zero are dropped (`apply_level_filter`).
* Annualisation is measured from each series (bars per calendar year: 252 for US equities, 357-365 for
  crypto, 240-328 for futures with weekend sessions, 52 for weekly bars) rather than assumed. Getting
  this wrong is a silent 20% inflation of every equity Sharpe — see §2 of the report.
* Nothing here is investment advice; it is a measurement of what these settings did.
