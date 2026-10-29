# FTMO QuantEdge — Expert Advisor for MetaTrader 4

**Version 1.00** · statistical mean-reversion / momentum engine with an FTMO-compliant
risk governance layer.

| | |
|---|---|
| Platform | MetaTrader 4 (build 600 or newer) |
| File | `mt4/Experts/QuantEdge/FTMO_QuantEdge.mq4` |
| Instrument | Any FX, metal, index or CFD symbol the broker offers (tested design target: majors, gold, indices) |
| Timeframes | M15 / M30 / H1 (M5 and H4 also supported; see *Choosing a timeframe*) |
| Inputs | 104, all documented below |
| Presets | 6, in `mt4/Presets/` |
| Verification | `tools/mq4_check.py` (static) + `tools/validate_math.py` (52 numerical checks) |
| Account type | FTMO **Normal** or **Swing**; the news/weekend rules are configurable |

> **This is not financial advice and no performance claim is made.** The
> mathematics is verified; the edge is not. Any EA must be tested on demo and in
> the Strategy Tester on your broker's data before it is allowed near a funded
> account. See *Known limitations* before you consider it "done".

---

## 1. Design philosophy

The EA is a calculator with a compliance officer attached. Every decision is a
closed-form function of price history:

* no martingale, no grid, no averaging down, no recovery lot multiplier;
* no random numbers — the same bars produce the same trades, so a backtest is
  reproducible;
* no discretionary tweaks at run time — the entire behaviour is defined by the
  inputs and one file of code;
* position size is a function of the distance to the stop, never of a feeling.

The signal is a weighted average of five standardised statistics, and the trade
is only allowed if the risk layer permits it. If the risk layer and the signal
disagree, the risk layer wins — always.

```
price history
     │
     ├─ ATR + ATR percentile ──► volatility fitness filter ─┐
     ├─ robust z-score ────────► deviation from median ─────┤
     ├─ normalised momentum ───► direction / fade strength ─┼─► score s ∈ [-1,1]
     ├─ variance ratio ────────► regime tilt ───────────────┤        │
     ├─ OU half-life (DF test) ► is reversion provable? ────┤        │
     └─ Fibonacci confluence ──► structural location ───────┘        │
                                                                     ▼
   FTMO governors ─► daily / total / target / session / news ─► ENTRY
                                                                     │
                     sizing = equity × risk% / (stop × point value) ──┘
```

---

## 2. The mathematics

### 2.1 ATR and its percentile rank

Current volatility is the mean true range over `InpATRPeriod` closed bars. The EA
also computes, at every bar, the rolling ATR for each of the last
`InpATRPercentileWindow` bars and records the fraction of those that were *below*
the current value. That fraction is the volatility's percentile rank.

* percentile `< InpMinATRPercentile` → market is dead, spread eats the edge → no trade
* percentile `> InpMaxATRPercentile` → news-spike volatility, stops are unreliable → no trade

This is the filter that keeps the EA out of the two regimes where a fixed
ATR-multiple stop is wrong.

### 2.2 Robust z-score

```
z = (C₁ − medianₙ) / (1.4826 × MADₙ)          robust (default)
z = (C₁ − meanₙ)   / stdevₙ                    classic  (InpRobustZ = false)
```

`C₁` is the last closed bar; the benchmark uses the `n` bars **before** it, so the
bar being judged never enters its own window.

The 1.4826 factor makes the median absolute deviation a consistent estimator of
the standard deviation for normal data (verified: mean ratio 0.996 over 400
samples). Why robust: with 20% of the window contaminated by outliers, the robust
scale estimate stays at 1.18 against a true 1.00, while the classic standard
deviation explodes to 20.32. A single bad tick or a news spike therefore cannot
fake an "oversold" reading — the failure mode that kills naive z-score EAs.

### 2.3 Normalised momentum

```
m = (C₁ − C₁₊ₖ) / (ATR × √k)
```

Dividing by `√k` normalises the random-walk scale, so `m` is comparable across
lookbacks and instruments. It is clipped to `±InpMomCap` before scoring.

### 2.4 Variance ratio (regime)

```
VR(q) = Var(r_q) / (q × Var(r₁))        r_q = C_t − C_{t−q}
```

* `VR < 1 − InpVRThreshold` → mean reverting → the EA fades deviations
* `VR > 1 + InpVRThreshold` → trending/persistent → the EA follows the move
* otherwise → inconclusive → `InpNeutralRegime` decides (default: mean reversion)

**Honest calibration note.** At 240 bars the sampling error of VR is about 0.09–0.12,
so this is a *tilt*, not a hypothesis test. Measured on synthetic series: a
persistent AR(1) process (`φ = 0.35`) is classified as trending **100%** of the
time, but a fast mean-reverting process is only classified as mean reverting
**66%** of the time, and a pure random walk lands in the mean-reverting band 21%
of the time. In other words: the VR reliably tells you when the market is
*strongly trending* (and should not be faded); it does not reliably prove mild
mean reversion. That job is given to the half-life gate below, which is a proper
test.

### 2.5 Ornstein–Uhlenbeck half-life, with a Dickey–Fuller gate

Regress the one-bar price change on the lagged price:

```
Δp_t = a + b · p_{t−1} + ε

Kendall bias correction:   b* = b + (1 + 3b)/n
half-life:                 HL = ln 2 / −ln(1 + b*)
Dickey–Fuller statistic:   t = b / se(b)
```

A mean-reversion trade is only permitted if `HL ≤ InpMaxHalfLifeBars` **and**
`t ≤ −InpHLTStatMin` (default −2.86, the 5% Dickey–Fuller critical value with a
constant).

Why the second condition is not optional: for a pure random walk, `t` does not
follow a normal distribution — it follows the Dickey–Fuller distribution, whose
5% critical value is about −2.86 rather than −1.65. Requiring only "a negative
slope" produces a plausible-looking half-life on **30–50%** of random walks. With
the DF gate, measured false-positive rates drop to **4.3%** on random walks and
**4.0%** on persistent trends, while a genuinely fast-reverting series is
detected **100%** of the time. This single test is the difference between a
mean-reversion EA and a machine for trading noise.

Two consequences to accept, both verified numerically:

1. the half-life *point estimate* carries roughly 20–40% error at `n = 240`, so it
   is a filter, not a forecast. The time stop multiplies it by 3
   (`InpHalfLifeStopMult`) to absorb that;
2. slow reversion (`HL ≈ 35` bars at `n = 240`) is only provable about 12% of the
   time. The EA will therefore skip most slow setups rather than assume them.

### 2.6 Fibonacci confluence

The EA finds the dominant swing inside `InpFibLookback` bars (highest high and
lowest low), determines which extreme is more recent (that defines the leg
direction), and measures the distance from price to each configured retracement
level **in ATR units**:

```
level = high − λ × range      (up leg)
level =  low + λ × range      (down leg)
score = ±(1 − distance_ATR / InpFibTolATR)   clipped to [-1, +1]
```

Score is maximal exactly on the level and decays linearly to zero at the
tolerance. A swing smaller than 2 ATR is ignored. Levels are configurable
(`0.382`, `0.500`, `0.618` by default) and the factor enters the composite with a
smaller weight than the statistical factors, because structure is context, not
proof.

### 2.7 Composite score and the decision

```
fz = clip(z / InpZCap,   −1, +1)
fm = clip(m / InpMomCap, −1, +1)
ff = fib score

in mean-reversion mode:  fz = −fz,  fm = −fm      (fade the deviation)
in momentum mode:        unchanged                 (follow the deviation)

s = (wz·fz + wm·fm + wf·ff) / (|wz| + |wm| + |wf|)     ∈ [−1, +1] by construction
```

A trade is opened when `|s| ≥ InpEntryThreshold` and every hard gate agrees
(volatility percentile, `|z| ≥ InpMinAbsZ`, half-life gate in MR mode, trend
agreement in momentum mode). Boundedness of `s` is what makes the threshold
portable across instruments and timeframes — verified by fuzzing 20 000 random
input triples, max |s| = 0.999987.

### 2.8 Exits

| Exit | Rule |
|---|---|
| Stop-loss | `InpSL_ATR_Mult × ATR` (default 2.0), never inside the broker's stop level |
| Take-profit | `InpExitMode = 1`: the statistical mean (the z-score benchmark), floored at `InpMinTP_R × stop`; `InpExitMode = 0`: fixed `InpRR` multiple |
| Statistical exit | MR trades close when `|z|` returns to `≤ InpZExitLevel` (default 0.25) |
| Break-even | at `InpBreakEvenR` (default 1R) lock `InpBreakEvenLockPts` beyond entry |
| Trailing | optional ATR trailing (`InpUseTrailingStop`), only ever tightens |
| Time stops | `InpMaxBarsInTrade` bars, and `InpHalfLifeStopMult × half-life` bars |

The statistical exit is applied **only to mean-reversion trades** (`mode = -1` in
the ticket tracker). A momentum or Fibonacci trade has no "z back to the mean"
thesis, so it is left to its stop, target and clock.

---

## 3. FTMO compliance layer

### 3.1 The rules this EA is built around

| FTMO rule | Measurement | EA control | Default |
|---|---|---|---|
| Max daily loss 5% | loss from start-of-day equity/balance, resets at 00:00 CE(S)T | `InpDailyRiskBudgetPct` halt, then hard circuit breaker at `InpMaxDailyLossPct` | halt 3.5%, hard 5.0% |
| Max total loss 10% | static, from the phase starting balance | `InpTotalRiskBudgetPct` halt, hard breaker at `InpMaxTotalLossPct` | halt 8.0%, hard 10.0% |
| Profit target 10% / 5% per phase | equity vs phase starting balance | `InpProfitTargetPct` + `InpLockAtProfitTarget` | lock at 10% |
| Min 4 trading days | at least one position opened per day | not enforceable by an EA — see §3.5 | — |
| No weekend holding (Normal accounts) | closed before Friday close | `InpCloseBeforeWeekend`, `InpFridayCloseHour` | on, 20:00 server |
| No news trading (Normal accounts) | ±2 min around high-impact events | `InpNewsFilter` with a CSV calendar | off — enable it (§7) |
| No HFT / tick scalping / latency arbitrage | trade profile | execution-efficiency guards (§4) | on |

Both governors are *buffered* deliberately: stopping at 3.5% instead of 5.0%
means that a gap, a slippage event or an in-flight position cannot push the
account over the hard limit between two ticks.

### 3.2 How the daily loss is measured

```
daily loss % = 100 × (anchor − equity) / anchor
anchor       = max(balance, equity) captured at the day rollover   (InpDailyAnchorMode)
```

Anchoring on equity (the default `QE_ANCHOR_MAX` takes the larger of balance and
equity) covers floating losses on open positions, which is how FTMO measures it.
The anchor is captured at the configured rollover, `InpDayRollHour` /
`InpDayRollMinute`.

> **Set the rollover to CET midnight in server time.** FTMO resets at 00:00
> CE(S)T. FTMO's MetaTrader servers run GMT+2 (winter) / GMT+3 (summer), exactly
> **one hour ahead of CET all year** — so the reset lands on **01:00 server
> time**. Set `InpDayRollHour = 1`, `InpDayRollMinute = 0` (the FTMO presets ship
> this way).
>
> Leaving it at 0 starts the EA's day one hour early: between 00:00 and 01:00
> server the EA would believe a fresh budget exists while FTMO is still counting
> those losses against the previous day. The 1.5-point buffer absorbs one trade,
> but it is the wrong boundary.
>
> To read the offset yourself: note the server clock in the Market Watch window,
> compare it with CET, and set the rollover to the server hour at which CET reads
> midnight. For a GMT+0 broker that is 23:00, for a GMT+1/+2 (CET) broker 00:00,
> for FTMO's GMT+2/+3 servers 01:00.
>
> `InpSkipRolloverMin` is a *separate* setting and stays around 00:00 server,
> because that is when the daily bar closes and spreads widen — not at the CET
> boundary.

The initial balance is detected from the account on first run and persisted in a
terminal global variable keyed by account number and magic number, so a terminal
restart does not silently reset the total-loss floor. Set `InpInitialBalance`
explicitly if you want it pinned, and `InpResetStoredAnchors = true` once when you
begin a new phase on the same account (it clears the stored value at
initialisation, then set it back to false).

### 3.3 Hard circuit breakers

Independently of the soft budgets, if the daily loss ever reaches
`InpMaxDailyLossPct` (5.0%) or the total loss reaches `InpMaxTotalLossPct`
(10.0%), the EA flattens every position with its magic number immediately,
prints an `!!! FTMO ... LIMIT REACHED !!!` line to the journal, and stops
trading. This is not configurable off — those two numbers end the account.

### 3.4 Position sizing

```
risk money      = equity × min(InpRiskPercent, InpMaxRiskPercent) / 100
lots            = risk money / (stop distance / point × value per point per lot)
lots            = floor(lots / lot step) × lot step          ← always rounds DOWN
```

then clamped by four independent ceilings:

1. `InpMaxOpenRiskPct` — aggregate open risk across all EA positions;
2. the remaining daily budget (`InpDailyRiskBudgetPct − consumed`);
3. the remaining total budget (`InpTotalRiskBudgetPct − consumed`);
4. `InpMaxLots`, the broker's `MODE_MAXLOT`, and the account's free margin.

If the result is below the broker minimum, the trade is **skipped** — it is never
rounded up into a larger position. Verified: 0.5% of a 100 000 account with a
30-pip stop gives 1.66 lots and a 498.00 loss at the stop, i.e. rounding is always
on the safe side.

Value per point is derived from `MODE_TICKVALUE` and `MODE_TICKSIZE`, not from
pip folklore, so indices and metals size correctly.

### 3.5 What an EA cannot do for you

* **The 4-trading-day minimum.** If you reach the profit target on day two, the
  EA stops opening trades (`InpLockAtProfitTarget`). You still owe FTMO the
  remaining days: either leave the lock off during the evaluation, or open a
  minimum-size position manually on the missing days. This is a rule about *your
  conduct*, not about the code.
* **Phase accounting.** The EA does not know whether you are in Challenge,
  Verification or funded. Set `InpProfitTargetPct` per phase (10% then 5%), and
  reset the anchors when a new phase begins.
* **Broker-side rule changes.** FTMO's published rules and account-type matrix do
  change. Re-read them before each evaluation; the inputs are there to be
  updated.

---

## 4. Prohibited trading practices — how they are avoided

FTMO prohibits latency arbitrage, tick scalping/HFT and gambling-style recovery
methods, and its monitors look at the *execution profile*, not at your strategy
description. The EA is built so that the prohibited profile is structurally
impossible:

| Prohibited pattern | Structural guard | Default |
|---|---|---|
| Tick scalping / HFT | decisions only on closed bars; `InpMinSecBetweenTrades` = 30 s between entries | 30 s |
| Millisecond round-trips | every EA-initiated exit waits `InpMinTradeDurationSec` | 120 s |
| Bursts of orders | `InpMaxTradesPerDay`, `InpOneTradePerBar` | 6/day, 1/bar |
| Latency arbitrage | no tick-timestamp comparison, no second feed, no round-trip in milliseconds; entries require a statistical deviation, not a stale quote | — |
| Gap trading | entries blocked for `InpReopenBlackoutMin` after any market re-open (gap > 1 h detected automatically) | 10 min |
| Rollover spread spike | no entries ±`InpSkipRolloverMin` around 00:00 server | 15 min |
| Martingale / averaging down | position size is a function of stop distance only; no add-on logic exists in the code | — |
| Hedging across positions | `InpAllowHedge = false` blocks an opposite position while one is open | off |

Effective maximum frequency: 6 entries per day, at least 30 s apart, each held at
least 120 s — roughly 0.5 entries per hour in a 12-hour session. That is three
orders of magnitude away from anything a tick-scalping detector would flag.

---

## 5. Installation

1. Copy `mt4/Experts/QuantEdge/FTMO_QuantEdge.mq4` into
   `<terminal data folder>/MQL4/Experts/QuantEdge/`.
2. In MetaEditor press **F7** to compile. Expected: `0 errors, 0 warnings`.
3. Restart the terminal (or right-click Navigator → Refresh) so the EA appears.
4. Enable **Tools → Options → Expert Advisors → Allow automated trading** (and
   *Allow DLL imports* is **not** required — the EA imports nothing).
5. Attach the EA to one chart of the instrument you want to trade, tick
   *Allow live trading*, and load a preset from `mt4/Presets/`.
6. Check the on-chart panel: it shows the live score, regime, half-life, both
   governor percentages and the current block reason (if any).

If you need the news filter, put the CSV in
`<terminal data folder>/MQL4/Files/` before attaching (format in §7.10).

To run several instances on different symbols: give each chart a different
`InpInstanceId` (1, 2, 3 …). The magic number is derived from the base plus the
instance id, so instances never manage each other's trades.

---

## 6. Recommended setup

| | |
|---|---|
| Symbol | EURUSD, GBPUSD, USDJPY, AUDUSD, XAUUSD (one instance each, distinct `InpInstanceId`) |
| Timeframe | **M15** (default), M30 alternative, H1 only with `InpMaxBarsInTrade ≈ 24`. Never M1/M5. |
| Preset | `FTMO_Challenge_Conservative` for a first *live* evaluation; `FTMO_Challenge_Balanced` for tester/demo; `FTMO_Challenge_Active` only after an evaluation has been passed on demo |

**Pairing, in one line each:**

* *First tester run* → `Backtest_M15_Diagnostics` on **M15**, verbose + CSV, read §8.3.
* *First demo week* → `FTMO_Challenge_Balanced` on **M15**.
* *First paid evaluation* → `FTMO_Challenge_Conservative` on **M15**.
* *Research only* → `Mean_Reversion_Pure` / `Momentum_Pure`; do not run them on a paid account before a full walk-forward.
| History | at least 2 000 bars of clean M15 data; the engine needs ~480 bars to warm up (`QE_MAX_WINDOW`) and reports the exact requirement on init |
| VPS | recommended; the EA is event-driven but must be online to enforce the governors |

**Choosing a timeframe.** Three windows are fixed in *bars*, so the timeframe
decides how much wall-clock data each one sees:

| Timeframe | 240 bars (half-life / VR window) | 200 bars (ATR percentile) | 48 bars (max trade life) | Verdict |
|---|---|---|---|---|
| M5 | 20 hours | 17 hours | 4 hours | too short for a stable DF test — avoid |
| **M15** | **60 hours ≈ 2.5 trading days** | 50 hours | **12 hours** | **default**: a real sample, and the time stop stays inside a session |
| M30 | 120 hours ≈ 5 days | 100 hours | 24 hours | fewer, longer trades; also fine |
| H1 | 240 hours ≈ 10 days | 8 days | 48 hours | detects slower reversion, but 48 bars spans two days — lower `InpMaxBarsInTrade` to ~24 |

M15 is the default because it is the fastest timeframe on which 240 bars still
represent more than two trading days of behaviour. On M5 the same window covers
under one day, the Dickey–Fuller test loses power, and the anti-scalping guards
(6 entries/day, 2 min minimum life) start to dominate the strategy rather than
just shape it.

### 6.1 Presets

| Preset | Risk/trade | Daily / total budget | Positions | Character |
|---|---|---|---|---|
| `FTMO_Challenge_Balanced` | 0.50% | 3.5% / 8.0% | 2 | shipped defaults, adaptive regime |
| `FTMO_Challenge_Conservative` | 0.25% | 2.0% / 6.0% | 1 | first live evaluation; strict threshold 0.65, trailing on, 3 entries/day |
| `FTMO_Challenge_Active` | 0.75% | 4.0% / 8.0% | 2 | lower threshold 0.50, up to 8 entries/day — still inside the governors |
| `Mean_Reversion_Pure` | 0.50% | 3.5% / 8.0% | 2 | z/momentum weighted hard to the fade, half-life cap 60 bars |
| `Momentum_Pure` | 0.50% | 3.5% / 8.0% | 2 | follows the move, 2R target, trailing stop, no MR gate |
| `Backtest_M15_Diagnostics` | 0.50% | 3.5% / 8.0% | 2 | verbose journal + CSV log for a tester run |

Regenerate after editing inputs: `python3 tools/gen_presets.py` (it fails loudly if
a preset references an input that no longer exists).

**Funded accounts.** There is no profit target on a funded FTMO account, and
`InpLockAtProfitTarget` locks entries permanently once reached. On a funded
account set `InpLockAtProfitTarget = false` (or raise `InpProfitTargetPct` well
above any plausible day) so the EA keeps trading after a good run.

---

## 7. Input reference

`Inp*` names are exactly as they appear in the EA properties dialog. Defaults are
the shipped values; presets in `mt4/Presets/` override a subset.

### 7.1 Identity

| Input | Default | Meaning |
|---|---|---|
| `InpMagicBase` | 771100 | Base magic number; `0` derives it from symbol + timeframe + instance |
| `InpInstanceId` | 1 | Distinct id per chart instance |
| `InpTradeComment` | `QEdge` | Order comment (`QEdge-MR`, `QEdge-MO`, `QEdge-FB` suffixes are added) |

### 7.2 Strategy

| Input | Default | Meaning |
|---|---|---|
| `InpStrategy` | `QE_ADAPTIVE` | `ADAPTIVE` (VR switch), `MEANREV`, `MOMENTUM`, `FIBONLY` |
| `InpEntryThreshold` | 0.55 | Minimum `|s|` to trade (0.10–0.95) |
| `InpWeightZ` | 1.00 | Weight of the z factor |
| `InpWeightMom` | 0.60 | Weight of the momentum factor |
| `InpWeightFib` | 0.40 | Weight of the Fibonacci factor |
| `InpMinAbsZ` | 1.00 | Hard gate: minimum `|z|` (0 disables) |

### 7.3 Statistics

| Input | Default | Meaning |
|---|---|---|
| `InpZPeriod` | 20 | z-score window (bars) |
| `InpRobustZ` | true | median/MAD (true) vs mean/stdev (false) |
| `InpZCap` | 3.00 | z is clipped to ±this before scoring |
| `InpMomLookback` | 8 | momentum lookback |
| `InpMomCap` | 2.00 | momentum clip |
| `InpATRPeriod` | 14 | ATR period |
| `InpVRWindow` | 240 | variance-ratio window (bars) |
| `InpVRHorizon` | 4 | variance-ratio `q` |
| `InpVRThreshold` | 0.08 | `|VR−1|` needed to declare a regime; `0` disables the switch |
| `InpNeutralRegime` | `QE_NEUTRAL_MR` | mode when VR is inconclusive: `NONE` (no trade), `MR`, `MO` |
| `InpHalfLifeWindow` | 240 | AR(1)/DF regression window |
| `InpMaxHalfLifeBars` | 80.0 | reject reversion slower than this |
| `InpHLTStatMin` | 2.86 | Dickey–Fuller `|t|` the slope must beat (0 disables the test) |
| `InpRequireHalfLifeGate` | true | MR entries require a proven half-life |
| `InpATRPercentileWindow` | 200 | volatility percentile window |
| `InpMinATRPercentile` | 0.10 | skip dead markets |
| `InpMaxATRPercentile` | 0.95 | skip extreme volatility |
| `InpTrendMAPeriod` | 200 | trend MA period |
| `InpTrendSlopeBars` | 20 | slope measurement distance |
| `InpUseTrendFilter` | true | momentum entries require MA slope agreement |

### 7.4 Fibonacci

| Input | Default | Meaning |
|---|---|---|
| `InpFibLookback` | 120 | swing search window |
| `InpFibLevel1` | 0.382 | retracement level 1 (0 disables it) |
| `InpFibLevel2` | 0.500 | retracement level 2 |
| `InpFibLevel3` | 0.618 | retracement level 3 |
| `InpFibTolATR` | 0.35 | tolerance around a level, in ATR units |

### 7.5 Exits

| Input | Default | Meaning |
|---|---|---|
| `InpExitMode` | `QE_EXIT_MEANREV` | statistical mean target vs fixed `InpRR` |
| `InpSL_ATR_Mult` | 2.00 | stop distance in ATR |
| `InpRR` | 1.50 | R multiple for `QE_EXIT_RMULT` |
| `InpMinTP_R` | 0.80 | target floor in R when the mean is too close |
| `InpExitOnZNeutral` | true | MR trades close when z normalises |
| `InpZExitLevel` | 0.25 | `|z|` considered normalised |
| `InpMaxBarsInTrade` | 48 | hard time stop (bars) |
| `InpUseHalfLifeStop` | true | also time-stop at `k × half-life` |
| `InpHalfLifeStopMult` | 3.00 | `k` |
| `InpUseBreakEven` | true | move stop to break-even |
| `InpBreakEvenR` | 1.00 | at this R multiple |
| `InpBreakEvenLockPts` | 10 | points locked in |
| `InpUseTrailingStop` | false | ATR trailing stop |
| `InpTrailATRMult` | 1.20 | trailing distance in ATR |

### 7.6 Risk

| Input | Default | Meaning |
|---|---|---|
| `InpRiskPercent` | 0.50 | risk per trade, % of equity |
| `InpMaxRiskPercent` | 1.00 | hard cap per trade (validation rejects > 2.0) |
| `InpMaxOpenRiskPct` | 1.50 | cap on aggregate open risk |
| `InpMaxOpenPositions` | 2 | maximum simultaneous positions |
| `InpAllowHedge` | false | allow opposite positions |
| `InpMaxLots` | 10.00 | absolute lot cap |
| `InpMinStopDistancePts` | 0 | extra minimum stop distance (points) |

### 7.7 FTMO governors

| Input | Default | Meaning |
|---|---|---|
| `InpProfitTargetPct` | 10.0 | phase target (set 5.0 for Verification) |
| `InpLockAtProfitTarget` | true | stop opening trades at target (set **false** on funded accounts) |
| `InpMaxDailyLossPct` | 5.0 | FTMO hard daily limit — circuit breaker |
| `InpDailyRiskBudgetPct` | 3.5 | EA halt threshold (must be below the hard limit) |
| `InpMaxTotalLossPct` | 10.0 | FTMO hard total limit — circuit breaker |
| `InpTotalRiskBudgetPct` | 8.0 | EA halt threshold |
| `InpInitialBalance` | 0.0 | phase starting balance; 0 = auto-detect + persist |
| `InpDailyAnchorMode` | `QE_ANCHOR_MAX` | balance / equity / max at rollover |
| `InpDayRollHour` / `InpDayRollMinute` | 0 / 0 | server time of the FTMO day rollover. **Set 1 / 0 on FTMO** (their GMT+2/+3 servers are one hour ahead of CET). The FTMO presets ship with 1 / 0 |
| `InpResetStoredAnchors` | false | clear the stored phase balance on init |
| `InpCloseAllOnBreach` | true | flatten when a soft governor trips |
| `InpFlattenOnProfitLock` | false | also flatten at the profit target |

### 7.8 Session and market structure

| Input | Default | Meaning |
|---|---|---|
| `InpUseSession` | true | restrict entries to a window |
| `InpSessionStartHour` | 8 | window start, hour (server time) |
| `InpSessionStartMin` | 0 | window start, minute |
| `InpSessionEndHour` | 20 | window end, hour |
| `InpSessionEndMin` | 0 | window end, minute |
| `InpSkipRolloverMin` | 15 | no entries ±this many minutes around 00:00 |
| `InpReopenBlackoutMin` | 10 | no entries after a market re-open |
| `InpCloseBeforeWeekend` | true | flatten before the weekend (Normal accounts) |
| `InpFridayCloseHour` | 20 | Friday flatten hour |
| `InpNoNewTradesFriday` | true | no new entries late Friday |
| `InpFridayNoTradeHour` | 17 | cut-off hour |
| `InpMaxSpreadPoints` | 0 | hard spread cap; 0 = `InpAutoSpreadMult ×` the median of the last 64 per-bar spread samples (a median so the rollover spike cannot inflate the cap) |
| `InpAutoSpreadMult` | 3.0 | auto-cap multiplier |

### 7.9 Execution

| Input | Default | Meaning |
|---|---|---|
| `InpSlippagePoints` | 10 | maximum deviation |
| `InpMaxRetries` | 3 | retries per order |
| `InpRetryDelayMs` | 250 | delay between retries |
| `InpMinSecBetweenTrades` | 30 | minimum seconds between entries |
| `InpMinTradeDurationSec` | 120 | minimum lifetime of an EA-closed position |
| `InpMaxTradesPerDay` | 6 | daily entry cap (0 = unlimited) |
| `InpOneTradePerBar` | true | at most one entry per bar |

Retries are only attempted for transient errors (requote, price changed, off
quotes, trade context busy, invalid stops). `134` (not enough money) and `131`
(invalid volume) abort immediately — retrying those just wastes the tick.

### 7.10 News filter

| Input | Default | Meaning |
|---|---|---|
| `InpNewsFilter` | false | enable the blackout |
| `InpNewsFileName` | `QuantEdge_news.csv` | file in `MQL4/Files` |
| `InpNewsBeforeMin` | 2 | blackout starts this many minutes before the event |
| `InpNewsAfterMin` | 2 | and ends this many minutes after |
| `InpNewsHighOnly` | true | only rows whose impact contains `High` |

CSV format (`;` separated, **server time**, matching `TimeCurrent()`):

```
date;time;currency;impact;title
2026.11.06;15:30;USD;High;Non-Farm Employment Change
2026.11.06;15:30;USD;High;Unemployment Rate
2026.11.12;10:00;EUR;High;German ZEW
```

A `date` field containing `YYYY` is treated as a header and skipped. Rows whose
currency is not the base or quote currency of the chart symbol are ignored
(`ALL` matches everything). Reload happens hourly and on init.

### 7.11 Diagnostics

| Input | Default | Meaning |
|---|---|---|
| `InpVerbose` | false | log every blocked entry and every signal |
| `InpCsvLog` | false | append decisions to a CSV |
| `InpCsvFileName` | `QuantEdge_log.csv` | log file in `MQL4/Files` |
| `InpShowDashboard` | true | on-chart panel |
| `InpDashCorner` / `InpDashX` / `InpDashY` | left-upper / 12 / 18 | panel position |
| `InpDashFontSize` | 9 | panel font size |
| `InpDashColor` | DodgerBlue | panel colour |
| `InpDashRefreshSec` | 1 | panel refresh |
| `InpSelfTest` | true | run the invariant check on init |

---

## 8. Testing protocol

### 8.1 Compile check

MetaEditor must report **0 errors**. If it reports warnings, the two usual causes
are an old build (upgrade MT4) or a modified input name that the presets still
reference — regenerate presets with `python3 tools/gen_presets.py`.

### 8.2 Strategy Tester setup

1. **Every tick** model (`Every tick` or `Every tick based on real ticks`) — the
   EA manages positions intra-bar, and only real ticks respect the stop/target
   ordering correctly.
2. Period: at least 12 months for M15, 3 years for H1. The engine needs 480 bars
   to warm up, so start reading results after the first ~500 bars.
3. Deposit and leverage matching the FTMO account type you will trade.
4. Enable `InpVerbose` and `InpCsvLog` in a separate diagnostics run so every
   blocked entry is recorded with its reason.

### 8.3 What to look at

| Metric | Healthy range | What it tells you |
|---|---|---|
| Max daily loss %, max total DD % | always < 3.5% and < 8.0% | the governors are doing their job; if you see 4.9% the daily anchor is misconfigured |
| trades per month | 5–40 on M15 across a major | far fewer means the DF/vol gates are rejecting everything (check `InpHLTStatMin`, `InpMinATRPercentile`) |
| average holding time | tens of minutes to hours | seconds means something is wrong with the exits |
| block reasons in the log | all gates appear over time | one gate permanently blocking points at a mis-set window |
| profit factor | > 1.15 with > 100 trades | below that, the configuration has no demonstrated edge |

### 8.4 Walk-forward

Do not tune on the data you report. Split the history in three: optimise on the
first 40%, validate on the next 30%, and only then look at the last 30%. Which
parameters are worth testing (and only these):

* `InpEntryThreshold` (0.45 … 0.70)
* `InpSL_ATR_Mult` (1.5 … 3.5)
* `InpMaxHalfLifeBars` (40 … 120)
* `InpZPeriod` (10 … 40)
* `InpHLTStatMin` (1.65 … 3.43)

Never optimise `InpRiskPercent`, the governor thresholds or the anti-scalping
guards — those are constraints, not degrees of freedom.

### 8.5 Forward test

Two weeks on demo, then a full evaluation period on FTMO. Read the journal for
`QE: !!!` lines (circuit breakers) and confirm the panel's daily loss figure
matches FTMO's client area for the same day before trusting the governor.

---

## 9. Known limitations

1. **No compiler on the build machine.** The MQL4 source is verified by static
   analysis (`tools/mq4_check.py`) and by a numerical mirror of every formula
   (`tools/validate_math.py`), not by MetaEditor. Compile it yourself and read
   the warnings — that step is not optional.
2. **The VR layer is a tilt, not a test** (§2.4). It reliably detects strong
   trending behaviour; it does not prove mild mean reversion.
3. **The half-life point estimate has 20–40% error** at `n = 240`. Slow reversion
   is often unprovable and is therefore skipped. Expect few trades in quiet,
   trendless markets — that is the gate working, not a bug.
4. **The Fibonacci factor is context, not an edge.** It shifts the score; it does
   not create signals on its own (except in `QE_FIBONLY` mode, which should be
   treated as an experiment).
5. **Single-symbol risk only.** Correlation between EURUSD, GBPUSD and EURGBP is
   not modelled. Running several instances multiplies your real exposure; the
   per-instance `InpMaxOpenRiskPct` does not know about the other charts.
6. **The governors act on ticks.** If the terminal is offline, nothing is
   enforced. Use a VPS.
7. **No guarantee of FTMO compliance.** The EA implements the numeric limits and
   the anti-HFT profile it can control; execution quality, broker behaviour, rule
   changes and your own manual actions are outside its control.

---

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `QE INPUT ERROR: ...` then no init | an input is outside its validated range | the journal names the exact input; fix it |
| `QE: entry blocked - insufficient remaining daily budget` | day already used its budget | intended behaviour; wait for the rollover |
| `QE: blocked - reversion not proven` (verbose) | DF gate rejecting noise | correct behaviour; do not disable it to "get more trades" |
| `QE: OrderSend failed (invalid stops)` | stop inside the broker's minimum distance | raise `InpSL_ATR_Mult` or `InpMinStopDistancePts`; the EA already retries with the widened distance |
| `QE: OrderSend failed (invalid volume)` | lots below the broker minimum | raise `InpRiskPercent` or accept fewer trades |
| Panel shows `NO DATA: warming up` | fewer bars than the engine needs | scroll the chart left to load history |
| Daily loss in the panel does not match FTMO | wrong rollover hour / anchor mode | on FTMO's GMT+2/+3 servers set `InpDayRollHour = 1` (CET midnight = 01:00 server); keep `InpDailyAnchorMode = QE_ANCHOR_MAX` |
| EA does not trade at all | session window, spread cap, news blackout, or governor | run with `InpVerbose = true`; the journal prints the exact block reason each bar |

---

## 11. Verification summary

Three tools, all runnable in a few seconds:

| Tool | Checks | Result |
|---|---|---|
| `tools/mq4_check.py` | statics: scope-correct identifier resolution, undefined/duplicate functions, MQL5-only calls, unbalanced blocks, input syntax | `0 error(s), 0 warning(s)` |
| `tools/validate_math.py` | 52 numerical checks against synthetic series with known ground truth: z-score breakdown, VR on random walk / OU / persistent processes, half-life recovery and Dickey–Fuller false-positive rates, ATR percentile bounds, Fibonacci geometry, score boundedness, lot sizing and rounding direction, governor arithmetic, execution guards, and a bar-by-bar replay with a random-walk null control | `All 52 checks passed` |
| `tools/test_checker.py` | 9 regression tests that inject the defect classes MetaEditor rejects into a copy of the EA and assert the analyser reports them (5 error classes, 2 warning classes, clean source) | `All 9 checker tests passed` |

The static analyser is itself tested because it is the only compile-like gate in
this environment. It was upgraded twice from MetaEditor's own output: after the
first build reported two errors it had missed (`iSpread`, and a variable used
outside the scope it was declared in), and after the second build reported
warning classes it did not model (an uninitialised scratch array, and an implicit
`double`→`int` narrowing). It now reproduces both builds' findings.

Full output and the compile feedback: [`docs/VALIDATION.md`](VALIDATION.md).

## 12. Version history

**1.00** — first release. Two rounds of MetaEditor feedback applied: build 1
reported 2 errors (`iSpread`, `dow` used outside its scope) and build 2 reported
0 errors / 4 warnings (uninitialised scratch array, implicit `double`→`int`
narrowing). All fixed and re-verified (§11, `docs/VALIDATION.md`). Contents: Robust z-score, ATR-percentile fitness, variance-ratio
regime tilt with neutral fallback, Dickey–Fuller-gated OU half-life, Fibonacci
confluence, statistical exits, FTMO daily/total/target governors with hard
breakers, execution-efficiency guards, news blackout, CSV diagnostic log,
presets generated from the source.

---

### Disclaimer

Trading leveraged instruments carries a high risk of loss. FTMO evaluations can
be lost, and this software may lose money or fail to trade for reasons including
broker execution, connectivity, terminal updates and rule changes. Nothing in
this repository is investment advice, a promise of profitability, or a guarantee
of compliance. Test on demo; use money you can afford to lose. You are
responsible for your account.
