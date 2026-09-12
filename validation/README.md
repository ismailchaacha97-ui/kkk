# Validation harness

The MQL indicators were built in a sandbox without MetaEditor, so their logic was
ported 1:1 into `engine.py` and verified here.

## Files

* `engine.py` — Python mirror of `PremiumDiscount.mq4/.mq5`:
  session detection (previous-day / current-day / Asia anchors with fallbacks),
  level & zone math, time-window (kill-zone) math, and the bar-close alert engine
  with once-per-session firing.
  The only deliberate difference: the MQL code derives the day boundary from the
  broker's D1 candle start; the mirror uses UTC midnight.
* `run_validation.py` — 78 tests: unit tests, no-repaint / determinism tests
  (incremental vs full runs produce identical alert histories for all anchor modes),
  alert-once semantics, kill-zone gating, weekend/holiday fallbacks, real-data smoke
  tests, and a performance check.
* `mql_check.py` — static sanity checks of both MQL sources: bracket/string balance,
  MQL4-vs-MQL5 API-appropriate tokens, defined-function checks, `StringFormat` arg
  counts, duplicate inputs.
* `make_demo.py` — generates the screenshots in `../examples/`.
* `data/` — real market data used by the tests:
  * `gold_daily_2026.csv` — COMEX gold futures (GC=F) daily OHLC, Aug 12 – Sep 10 2026
    (Yahoo Finance v8 chart API).
  * `eurusd_daily_2026.csv` — EURUSD daily closes Jul 1 – Sep 11 2026, converted from
    ECB reference rates (Frankfurter API).
  * `paxg_h1_2026.csv` — PAX Gold (PAXG) hourly closes, Aug 13 – Aug 22 2026
    (CoinGecko market chart API).

## Run

```bash
python3 run_validation.py   # 78 passed, 0 failed
python3 mql_check.py        # All MQL sanity checks passed.
```
