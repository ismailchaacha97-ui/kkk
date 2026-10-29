# FTMO QuantEdge — statistical Expert Advisor for MetaTrader 4

An MT4 Expert Advisor whose trades are a closed-form function of price history,
wrapped in a risk layer designed around FTMO's evaluation rules.

> **Research status: no demonstrated edge.** Backtested on two independent
> datasets (FTMO-Server4 2025-26, plus six years of 2008-2018), three timeframes
> and three risk configurations: no configuration stayed positive out of sample.
> The risk layer is verified and behaves as specified; the signal layer does not
> pay for its costs. **Do not run this on a paid evaluation expecting profit.**
> Full measurement: [`docs/RESEARCH_RESULTS.md`](docs/RESEARCH_RESULTS.md).

* **Signal** — a bounded composite score `s ∈ [-1, +1]` built from a robust
  z-score, normalised momentum, a variance-ratio regime tilt, a Dickey–Fuller-gated
  Ornstein–Uhlenbeck half-life and Fibonacci confluence.
* **Risk** — equity-anchored daily-loss governor (5% rule, halts at 3.5%), static
  total-loss governor (10% rule, halts at 8%), risk-based sizing (0.5% default)
  with four independent caps and an FTMO-only hard circuit breaker.
* **Prohibited-practice guards** — no martingale, no grid, no hedging, no gap
  trading, no tick scalping: entries only on closed bars, ≥30 s apart, ≤6 per day,
  positions held ≥120 s.

```
mt4/
  Experts/QuantEdge/FTMO_QuantEdge.mq4     the EA (single file, 104 inputs, no includes)
  Presets/*.set                            6 ready configurations
docs/
  FTMO_QuantEdge_Manual.md                 maths, FTMO compliance map, full input reference,
                                           testing protocol, known limitations
  RESEARCH_RESULTS.md                      the out-of-sample study: data, method, controls,
                                           every table, and the honest verdict
  VALIDATION.md                            what was verified and what was not
research/
  study.py                                 matrix / sweep / walk-forward harness
  eventstudy.py                            cost, autocorrelation and conditional-drift tests
tools/
  prepare_data.py                          builds the research dataset (two sources)
  backtest.py                              bar-by-bar engine mirroring the EA logic
  mq4_check.py                             static analyser for the MQL4 source
  validate_math.py                         Python mirror of every formula, 52 numerical checks
  gen_presets.py                           regenerates the .set files from the EA's inputs
  test_checker.py                          regression tests for the static analyser
```

## Quick start

1. Copy `mt4/Experts/QuantEdge/FTMO_QuantEdge.mq4` to `MQL4/Experts/QuantEdge/`
   in your terminal data folder and compile it with **F7** in MetaEditor.
2. Attach to an **M15** chart, allow live trading, and load
   `mt4/Presets/FTMO_Challenge_Conservative.set` (paid evaluation) or
   `FTMO_Challenge_Balanced.set` (demo / tester).
3. Set `InpDayRollHour = 1` if your server is GMT+2/GMT+3 (FTMO's are: CET
   midnight lands on 01:00 server). The FTMO presets already ship with this.
4. Run the Strategy Tester on **every tick** for at least 12 months before
   believing anything. Read §8 of the manual first.

## Verification

```bash
python3 tools/mq4_check.py mt4/Experts/QuantEdge/FTMO_QuantEdge.mq4   # 0 errors, 0 warnings
python3 tools/validate_math.py                                       # 52/52 checks pass
python3 tools/gen_presets.py                                         # regenerate presets
python3 tools/test_checker.py                                        # 9/9 checker self-tests
```

The Python tools exist because there is no MQL4 compiler in the build
environment: `mq4_check.py` covers what a compiler would catch (it reproduces the
two errors the first MetaEditor build found, on the same lines),
`validate_math.py` covers what a compiler would *not* — that the statistics are
actually statistics — and `test_checker.py` keeps the analyser honest.
Details and the honest limits are in [`docs/VALIDATION.md`](docs/VALIDATION.md).

## Important

This software is provided for research and education. It is not financial advice,
it does not guarantee FTMO compliance, and it makes no claim of profitability.
Compile it, test it on demo, and use money you can afford to lose. You are
responsible for your own account.
