# VWAP Pro — evidence

Every number in this document is produced by a command in this repository.
Nothing here is a claim that cannot be re-run.

```bash
make test                                        # 1746 assertions
make check                                       # static rules + two cross checks
make bench                                       # per-bar cost at 10k / 100k / 1M bars
python3 tools/crosscheck.py tests/fixtures/synth_m1_eurusd.csv
```

---

## 0. Three implementations, one answer

The engine is written once (MQL4/C++ headers), re-derived once in NumPy
float128 (`tools/crosscheck.py`) and ported once to JavaScript
(`web/vwap.js`, which drives the in-browser demonstration). All three are fed
the same 16,200 fixture bars:

| pair | agreement |
|---|---|
| C++ engine vs NumPy float128, anchor | max rel **2.089e-16**, median **0** |
| C++ engine vs NumPy float128, σ | max rel 1.717e-08, median **5.782e-13** |
| C++ engine vs JS port (`tools/check_js_port.js`) | **17 of 18 outputs bit-identical** over all bars; composite score ≤ **4.40e-13** (Math.exp vs libm) |

An independent implementation cannot reproduce an error. Agreement at the
1e-16 level says the anchor is not "close to" a VWAP - it is the same number.

## 1. Is the anchor a real VWAP?

The primary correctness property is that the engine reproduces the textbook
volume-weighted average price. It is checked bar by bar against a brute-force
long-double reference:

| Test | Result |
|---|---|
| 3,000 random bars, worst relative deviation (test_engine) | **2.02e-16** |
| 16,200-bar fixture, worst relative deviation (test_data) | **2.92e-15** |
| Independent NumPy implementation, 16,200 bars (crosscheck.py) | **2.09e-16** max, **0** median |
| Dispersion vs long-double reference at price levels 1.1 / 150 / 1e9 | **1.2e-13 / 3.6e-13 / 4.4e-13** |
| Dispersion vs extended-precision NumPy reference | **5.8e-13** median, 1.7e-08 worst |

## 2. Does the numerical design matter?

The same measurement run against the accumulator that published VWAP
indicators use (`Σx`, `Σx²`, subtraction at the end):

| Data | naive `Σx² − (Σx)²/n` | VWAP Pro |
|---|---|---|
| EURUSD-like, 1.10000 ± 7e-5, 40k bars | 7.57e-07 | **4.68e-14** |
| Quiet market, 1.10000 ± 1e-6, 40k bars | 1.23e-02 (σ off by 0.6%) | **4.04e-11** |
| 1e9 price level, ±100, 100k bars | 1.04 (**104% wrong**) | **2.13e-10** |

Applied to the market fixture: computing the same reference σ in plain float64
(the way a normal indicator library would) gives a **median relative error of
1.2e-09 and a worst case of 1.5e-05**; the engine's shifted, compensated
accumulators land at 5.8e-13 median.

## 3. Are the bands calibrated?

`z = (close − VWAP)/σ` should behave like a standard score. The Gaussian
reference rates are `P(|z|>1)=31.7%`, `P(|z|>2)=4.55%`, `P(|z|>3)=0.27%`.
Market data is not Gaussian, so the *absolute* numbers will not match exactly —
but an estimator that is merely *correct* will be in the right neighbourhood,
and an unshrunk running σ will not be:

| estimator | mean \|z\| | P(\|z\|>1) | P(\|z\|>2) | P(\|z\|>3) |
|---|---|---|---|---|
| VWAP Pro | 1.252 | 0.597 | 0.176 | **0.0015** |
| naive running σ | 1.461 | 0.682 | 0.262 | **0.0240** |
| Gaussian reference | 0.798 | 0.317 | 0.0455 | 0.0027 |

A 3σ reading should be a once-in-370-bars event on Gaussian-like data. The
naive implementation fires one every 41 bars — a factor of **16** — because at
the start of every session its σ is still near zero. VWAP Pro's rate (0.15%) is
in the right neighbourhood; the naive rate (2.40%) is not a band, it is noise.

The aggregate calibration error `|P₂σ − 0.0455| + |P₃σ − 0.0027|`:

```
VWAP Pro 0.1320   naive 0.2382
```

Out-of-sample containment of the *next* close (crosscheck.py):

```
VWAP Pro   1σ 0.401   2σ 0.821   3σ 0.998      (calibrated: .683 / .954 / .997)
```

The 1σ figure being high is a property of the data, not of the estimator: this
fixture has strong intraday drift (an AR(1) order-flow process), so a
dispersion measured *about the anchor* under-states how far price wanders from
it. Both estimators face the same data; only one of them measures it correctly.

## 4. The shrinkage prior

| | σ at the first bar of an anchor |
|---|---|
| naive running σ | exactly **0** (zero-width band) |
| VWAP Pro | **5.26e-05**, against an ATR-implied prior of 5.33e-05 |

Dispersion profile by bar-of-session (σ normalised to the session median),
which is what the prior is shaping:

```
bars    0-2      0.060
bars    2-10     0.124
bars   10-60     0.256
bars   60-240    0.334
bars  240+       1.142
```

## 5. Does it survive hostile data?

`test_engine.cpp` fuzzes 60,000 bars drawn from twelve families of garbage:
flat bars with and without volume, microscopic ranges, zero prices, negative
prices, 1e12 ranges, 1e300 prices, 1e-300 prices, NaN volume, negative volume,
inverted ranges.

```
checked 60000 hostile bars: 0 non-finite, 0 inverted, 0 z out of bounds
```

It also checks the property that decides whether a trader can trust a signal:
the *incremental* path (closed bars committed, live bar evaluated on a clone)
and the *batch* path (a fresh engine fed the same closed bars) agree
bit-for-bit — 500 live bars × 3 ticks each, **0 mismatches**.

## 6. Does the tick rule carry information?

On a controlled stream — bars that close on their highs vs bars that close on
their lows, with identical volume:

```
typical-price anchor 1.103167
tick-rule anchor (buying bars)  1.103186
tick-rule anchor (selling bars) 1.103114
```

The anchor follows the inferred aggressive side, which the typical price cannot
express. On the volume-less feed test (the volume column stripped entirely) the
anchor still tracks the priced anchor to **0.015% of price** rather than
dividing by zero.

## 7. Does the score discriminate regimes?

```
persistent trend through a flat-volume stream  →  mean score +0.996
oscillation around a flat anchor               →  mean score −0.046
first bar of an anchor (below InpMinBars)      →  score exactly 0
```

On the fixture, median |t| of the anchor regression is 12.89 with median
R² = 0.568, and the score spans −0.935…+0.982 — i.e. the score uses its range
rather than sitting near zero.

## 8. Is it fast enough for a live chart?

`make bench` timings the compiled engine (CSV printing suppressed, process
startup subtracted) at three history lengths:

| bars | ns/bar | bars/s |
|---|---|---|
| 10,000 | 6,843 | 146,145 |
| 100,000 | 6,747 | 148,223 |
| 1,000,000 | 6,704 | 149,165 |

Flat across a 100× range: **O(1) per bar**, which is the property that matters
on a live M1 chart — a per-bar cost that grows with the session is the classic
VWAP bug that looks fine on a demo and freezes the terminal at 16:00. (The one
deliberately non-O(1) path is the optional rolling window:
`InpSigmaMode = window`, 512-bar window, 7,774 ns/bar at 1M bars.)

## 9. What is *not* claimed

* No profitability claim. The tests measure estimator accuracy, calibration and
  robustness — not edge.
* The fixture is synthetic. It is labelled as such in its own header, and the
  generator is deterministic and documented so that the properties the tests
  rely on are knowable. `tools/fetch_data.py` runs the identical battery on real
  exchange data in one command, and `test_data.cpp` picks up any CSV you drop
  into `tests/fixtures/`.
* The comparison in §3 is against a *correctly written naive VWAP* (running
  volume-weighted mean with a textbook σ), not a straw man: it is given the same
  bars, the same weights and the same anchor.
