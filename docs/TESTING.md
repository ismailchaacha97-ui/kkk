# VWAP Pro — how it is tested

The core of VWAP Pro (`MQL4/Include/VWAPPro/*.mqh`) is written in the
intersection of MQL4 and C++14-minus-modern-features. That is not a stylistic
choice: it means the *exact same header files* that MetaTrader compiles are
compiled by `g++` and driven by 1,779 assertions, with no MetaTrader present.

```bash
make test     # build and run all five suites
make check    # static MQL4 rules + numpy cross check + the JS port check
make bench    # O(1) per bar? measure it at 10k / 100k / 1M bars
```

The engine therefore exists in three independent implementations - the C++
headers, a NumPy reference, and a JavaScript port - and all three are compared
against each other on the same 16,200 bars:

| comparison | agreement |
|---|---|
| engine vs `np.float128` NumPy reference (`tools/crosscheck.py`) | anchor **2.1e-16**, σ 5.8e-13 median |
| engine vs the JavaScript port (`tools/check_js_port.js`) | **17 of 18 outputs bit-identical**; the composite score differs by 4.4e-13 |
| engine vs the textbook estimator, per bar (in-suite) | **2.9e-15** worst relative error |

## The five suites

| Suite | Checks | What it establishes |
|---|---|---|
| `test_time` | 46 | The calendar. Every date is verified against Python's proleptic Gregorian arithmetic: leap years, century rules, the 1900 and 1600 boundaries, weekday index, day-of-year, week start, timezone shifting, DST-anchored `HH:MM` anchoring. |
| `test_math` | 65 | The statistics. Compensated means/variances against long-double references, merge formulas, OLS slopes on exact lines (`σ = 0`, `R² = 1`), ATR/ADX on constructed series, Hurst exponent on a known random walk, and the precision table in `EVIDENCE.md` §2. |
| `test_volume` | 30 | The feed logic. Probe detection for constant/absent/negative volume, the tick-rule split, monotonicity of `f_buy` in the close's position in the range, the deliberate absence of small-body damping, the inverse-variance weighting family, and degenerate inputs. |
| `test_engine` | 1623 | The engine itself — the bulk of the suite. Textbook-VWAP reproduction, the definition of σ, origin-shift accuracy at three price levels, translation and scale invariance, anchor rollover and re-anchoring, prior shrinkage, band ordering, slope/skew/kurtosis accumulation, clone equivalence (incremental vs batch), the fuzz battery, and the composite score on synthetic regimes. |
| `test_data` | 15 | The whole thing on a market-like series: `tests/fixtures/synth_m1_eurusd.csv`, 16,200 M1 bars. Distributional calibration, determinism, degraded-feed behaviour, and agreement between weighting families. Runs over *every* CSV in `tests/fixtures/`, so you can point it at real data. |

## Design of the tests

**References are independent.** The brute-force VWAP reference in
`test_engine.cpp` is written with `long double` accumulators and the obvious
definitions; the NumPy reference in `tools/crosscheck.py` is written in a
different language with a different summation strategy in extended precision.
The engine is never compared against a re-implementation of itself.

**Constructed series, not vibes.** Slope tests use a line with an exact answer;
`σ = 0` and `R² = 1` are asserted; the tick-rule test uses bars that close
exactly on their high or on their low; the regime test uses a perfect trend and
a perfect oscillation. A test only exists where the correct output is known
before the code runs.

**Every failure mode in the docs has a test.** The five failure modes in the
README table each have a corresponding test that *fails* if the mitigation is
removed, plus a printed measurement so the magnitude is visible in `make test`
output. If you delete the shrinkage prior, `test_engine` reports a zero-width
band at the session open; if you swap the accumulator for the naive one,
`test_math` prints the 104% error; if you disable the sanitiser, the fuzz suite
finds a crossed band.

**Adversarial input.** 60,000 bars drawn from twelve families of garbage (NaN
volume, negative prices, 1e300 spikes, inverted ranges, flat bars, zero ranges)
assert three invariants: no non-finite output ever reaches a buffer, bands are
never crossed, and `|z|` never exceeds its documented clamp. The invariant is
checked, so the defensive branches in the engine are proven unreachable rather
than merely present.

**Nothing repaints.** The incremental path (closed bars committed; the live bar
evaluated on a clone) must agree bit-for-bit with the batch path (a fresh engine
fed the same closed bars). 500 live bars × 3 ticks each, compared after every
tick, 0 mismatches.

## The cross-check

```bash
python3 tools/crosscheck.py tests/fixtures/synth_m1_eurusd.csv
```

re-implements §1 of `ALGORITHM.md` in NumPy, in `np.float128`, reads the
engine's per-bar state dumped by `tests/dump_bars` (printed with `%.17g` so that
the comparison measures the engine, not the print), and reports:

* agreement of the anchor and σ at every bar;
* the same reference computed in plain `float64` — i.e. what a normal indicator
  library produces — so the numerical gap is quantified, not asserted;
* out-of-sample containment of the next close in the 1/2/3σ bands;
* the dispersion profile by bar-of-session;
* the regression and score summary statistics.

## The MQL4 static checker

```bash
python3 tools/check_mql4.py
```

There is no MQL4 compiler in a CI sandbox, so `tools/check_mql4.py` enforces the
rules that a compiler would otherwise catch, and that MQL4 in particular is
easy to get wrong:

* no `std::`, templates, `auto`, range-`for`, or `nullptr` outside the C++-test
  branch (MQL4 has none of them);
* no string-returning code in the portable core (the engine must live in both
  dialects);
* no terminal I/O (`Print`, `Alert`, `Comment`) inside the core;
* no `const` member functions, no default arguments, no reference parameters
  that MQL4 would reject;
* for the indicator: `#property indiator_buffers` matches the number and the
  contiguity of `SetIndexBuffer` calls, the MQL4 `OnCalculate` signature is the
  MT4 one, every `input`/`extern` is actually used, `OnDeinit` exists and
  releases what `OnInit` created;
* hygiene: CRLF line endings, no tabs, ASCII only, balanced braces, trailing
  newline.

It exits non-zero on any violation, so `make check` is a real gate.

## What the tests deliberately do not cover

* **Fills, spread and slippage.** This is an indicator; it does not trade. The
  reference EA shows the plumbing, not a strategy.
* **MetaTrader's rendering.** Buffer semantics are tested (constants, ordering,
  `EMPTY_VALUE`), but how your terminal paints them is out of scope.
* **Broker history quality.** `test_data.cpp` reports what it finds (including
  rejected bars) rather than assuming a clean feed.
