# kkk

**Three candle-trading methods, one honest backtester, and the tooling to find
out which of them actually has an edge on your data.**

Built for Forex + Gold on MT5. No look-ahead, no optimistic fills, and every
parameter is exposed so you can see how easy it is to fool yourself.

> Read [`docs/METHODS.md`](docs/METHODS.md) for the method-by-method verdict.
> Read [`docs/data.md`](docs/data.md) before feeding it data.

---

## Install

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Try it in 10 seconds (no data needed)

```bash
.venv/bin/python -m kkk.cli demo
```

This runs all three methods on a deterministic pseudo-market. It proves the
plumbing works. It proves **nothing** about profitability — that data has no
real edge in it by construction.

## Or with a realistic MT5-shaped file

```bash
.venv/bin/python scripts/make_sample.py          # writes data/XAUUSD_H1_sample.csv
.venv/bin/python -m kkk.cli compare data/XAUUSD_H1_sample.csv --symbol XAUUSD
```

Tab-separated, broker server time, `<SPREAD>` column — the awkward shape a
real export has, so the loader gets properly tested. Still synthetic, still
no real edge.

## Use it properly

```bash
# 1. export XAUUSD H1 from MT5 (docs/data.md), then:
.venv/bin/python -m kkk.cli compare data/XAUUSD_H1.csv --symbol XAUUSD --out runs/xau

# 2. or sweep one method honestly (70/30 time split, out-of-sample check)
.venv/bin/python -m kkk.cli sweep data/XAUUSD_H1.csv --symbol XAUUSD -s magic_candle

# 3. list what's available / override any parameter
.venv/bin/python -m kkk.cli list
.venv/bin/python -m kkk.cli compare data/XAUUSD_H1.csv --param rr=2.5 --param body_atr_mult=1.5
```

## The three methods

| key | method | entry style | signal frequency |
|---|---|---|---|
| `magic_candle` | long-body candle, limit at 50% of the body | limit | medium |
| `liquidity_candle` | sweep of resting stops + reclaim | market | high |
| `structure_break` | swing structure + change of character (BOS) | market | low |

Each is a plain function `generate(df, **params) -> list[Signal]`, documented
in its own module. Adding a fourth method means adding one file and one line
in `kkk/strategies/__init__.py`.

## Why you should believe the numbers

The two ways a backtest lies to you are look-ahead and optimistic fills. Both
are handled explicitly, and both are covered by tests:

- **No look-ahead.** Strategies are evaluated at bar close and can only act
  from the *next* bar. Swing detection only reveals a swing `right` bars after
  it prints. `tests/test_engine.py::test_no_lookahead_on_the_signal_bar`
  pins this down.
- **Ambiguous bars are pessimistic.** When one bar touches both your stop and
  your target, the default is that the stop was hit. Turn this off with
  `--optimistic-fill` and watch your equity curve inflate — that difference is
  the size of the lie.
- **Costs are charged both ways.** Half-spread plus slippage against you on
  entry and exit, plus optional commission per lot per side.
- **A coin-flip baseline is printed on every run.** Random entries, same risk
  model, 200 trials. If your best method does not clear that noise band, the
  tool says so out loud.
- **A sweep reports in-sample and out-of-sample side by side**, with a
  `robust` flag. A parameter set that only wins in-sample is a curve fit and
  is labelled as one.

## Layout

```
kkk/
  config.py          instruments (XAUUSD, EURUSD, US30...), risk, costs
  data.py            MT5 / TradingView CSV loading, resampling, sessions
  engine.py          the bar-by-bar backtester
  metrics.py         expectancy, profit factor, drawdown, random baseline
  primitives.py      candles, swings, ranges, FVGs — all look-ahead safe
  strategies/
    magic_candle.py
    liquidity_candle.py
    structure_break.py
    params.py        grid sweep with out-of-sample guard
  cli.py             `list` / `demo` / `compare` / `sweep`
tests/               33 tests, incl. hand-computed engine arithmetic
docs/
  METHODS.md         the verdict: which method fits you, and why
  data.md            getting MT5 data in without ruining it
```

## Tests

```bash
.venv/bin/python -m pytest tests/ -q
```

The engine tests check arithmetic against hand-worked answers (a 2R win on a
10,000 account risking 1% must be exactly +200 currency), not just that the
code runs.

## Status

Working: engine, all three methods, metrics, sweep, CLI, tests.
Not yet: MT5 `.ex5` indicator export, walk-forward analysis, multi-symbol
portfolio runs, position scaling.

---

*Not financial advice. A backtest is a hypothesis, not a promise. Set your
broker's real spread, slippage and commission before believing any result.*
