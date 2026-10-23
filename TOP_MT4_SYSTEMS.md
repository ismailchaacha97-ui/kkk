# Top MT4 systems in this repo — ranked

**Scope:** I went through every branch of `ismailchaacha97-ui/kkk` and found **34 branches carrying MQL source** — 55 distinct `.mq4/.mq5/.mqh` files, about **30 distinct systems**. Only `README.md` is on `main` — every system below lives on its own `arena/*` branch. Branch IDs are given so you can pull any of them.

**Ranking rubric** (weighted): evidence/backtest quality ×2, completeness (indicator + EA + presets) ×1.5, engineering/validation ×1.5, documentation ×1.

**The single most important caveat:** nothing in this repo has a broker statement, Myfxbook link, or live-money track record. The evidence is backtests, simulations, static checks and unit tests. Treat the ranking below as *"what is built and measured best"*, not *"what makes money"*.

---

## The ranking

| # | System | Type | Platform | Evidence | Branch |
|---|--------|------|----------|----------|--------|
| 1 | **EMA 60/132 study + EA** | Daily trend, long/flat | MT4 | 9.76M backtests, 82 markets, 1970–2026, walk-forward + DSR | `arena/01a085d5-kkk` |
| 2 | **VWAP Pro** | Anchored VWAP + reference EA | MT4 | 1,779 automated checks, 3 independent implementations | `arena/01a0b430-kkk` |
| 3 | **FVG Cascade** | ICT multi-TF cascade | MT4 | Exact Python port, 19 months Dukascopy M1, 1,002 trades | `arena/01a052c6-kkk` |
| 4 | **Premium / Discount** | ICT dealing range | MT4 **+ MT5** | 78 tests incl. no-repaint + real data | `arena/01a095ab-kkk` |
| 5 | **JobPick v1.20** | Votes + gates + trend/fade engines | MT4 | Trend engine 3 regimes; fade engine IS + OOS with 1.5 pip cost | `arena/01a06742-kkk` |
| 6 | **H.I.E.P.** | Pure price-action institutional entries | MT4 | Compiled through MQL4 shim, 3,000-bar behavioural sim, sanitizers | `arena/4771051a-kkk` |
| 7 | **WPR Swing Breakout** | %R stop-and-reverse + filters | MT4 | EA measures itself incl. **random-entry control group** | `arena/01a0488a-kkk` |
| 8 | **PropFirm Institutional Edge Pro** | SMC dashboard + execution EA + killswitch | MT4 | Static validator, web simulator — no backtest | `arena/01a0156e-kkk` |
| 9 | **TaylorCycle v3.00** | 3-day overnight cycle | MT4 | Research dossier + Python engine + verified macro calendars | `arena/01a09fa4-kkk` |
| 10 | **RuleOP Ladder + "No-Loss" teardown** | Martingale visualiser + EA | MT4 | 90 assertions, C++/Python cross-check, 600-account blow-up sim | `arena/01a06271-kkk` |

**Best read of the whole repo:** #10. It is the only thing here that *measures what martingale systems actually do to an account* instead of selling one.

---

## 1. EMA 60/132 — the strongest statistical work

**Branch:** `arena/01a085d5-kkk`
**Files:** `mt4/EMAStudy_Signals.mq4` (indicator, 532 lines), `mt4/EMAStudy_AutoTrade.mq4` (EA, 221 lines), `REPORT.md`, `results/`

This is not a vendor EA. It is a from-scratch research project that grid-searched **9,299 EMA pairs** across **82 markets** from 1970 to 2026 — 9.76 million backtests including cost, weekly-bar and SMA control runs — then shipped the winning rule to MT4.

- Optimum is a **plateau**, not a peak: fast 40–80, slow 115–165; best single pair **60/132** (round to 60/130).
- Median cross-market Sharpe **0.431**, positive in **94%** of 82 markets, ~**1.46 round trips/year**, survives **3× costs**.
- Two out-of-sample referees: 6-fold walk-forward re-optimisation and a cross-market split-sample test.
- Popular pairs are the bad ones: **12/26 (MACD) ranks 9,177th of 9,299**, 50/200 ranks 2,219th.
- Honest limitation: on Sharpe it does **not** beat buy & hold; on drawdown it does — at 10% vol target the book's worst episode goes **−63% → −21%** (Calmar 0.11 → 0.43).
- Includes `check_mt4_parity.py`: verifies MT4's SMA-seeded EMA reproduces the study's signals.

**Use it if:** you want a slow, boring, diversified daily trend filter, not an intraday robot. The EA is long/flat and designed for a basket, not one symbol.

---

## 2. VWAP Pro — the best-engineered MT4 code here

**Branch:** `arena/01a0b430-kkk`
**Files:** `MQL4/Indicators/VWAPPro.mq4` (592), `MQL4/Include/VWAPPro/*.mqh` (~2,000 lines), `MQL4/Experts/VWAPProSignalEA.mq4` (182), `docs/`, `web/index.html`, `tests/`

An anchored VWAP written the way a textbook VWAP should be, on MT4's quantised tick volume. The evidence is about **correctness**, and it is unusually rigorous:

- **1,779 assertions** in `make test`, all passing.
- Engine implemented **three times** — MQL4/C++, NumPy `float128`, and JavaScript. C++ vs NumPy agree to **2.1e-16**; JS vs C++ is **bit-identical on 17 of 18 outputs** across 16,200 bars.
- Naive `Σx² − (Σx)²/n` bands carry **104% error** at a 1e9 price level; VWAP Pro's compensated accumulators are at **4.4e-13**.
- Never repaints: closed bars are committed once, live bar evaluated on a clone. 0 mismatches over 1,500 bars.
- 60,000 hostile bars (NaNs, 1e300 spikes, zero/negative prices, missing volume) → **0 non-finite values, 0 crossed bands**.
- Degenerate feeds (no volume) fall back to a volatility clock instead of dividing by zero.
- Docs: `ALGORITHM.md`, `EVIDENCE.md`, `TESTING.md`, `USER_GUIDE.md`.
- Browser demo: `python3 -m http.server` then open `/web/index.html`.

**Caveat:** the EA is explicitly a *reference implementation* — "not a strategy to run live on its own". This is a superb indicator and a template for how to write MT4 code, not a proven strategy.

---

## 3. FVG Cascade — the only real tick-level backtest

**Branch:** `arena/01a052c6-kkk`
**Files:** `FVG_Cascade.mq4` (1,199 lines), `backtest/backtest.py`, `backtest/report.md`, `backtest/trades.csv`, Dukascopy data

An ICT 4-step cascade: H1 bias → M30 inversion FVG → M5 swing → M1 trigger FVG invalidation. It ships an **exact Python port** of the MQL4 logic and a backtest on **19 months of Dukascopy EURUSD M1** (554,071 bars, per-bar measured spread), **no parameter tuning**.

| Segment | Trades | Win rate | PF | Net pips |
|---|---|---|---|---|
| Gross | 1,002 | 42.4% | 1.17 | +985 |
| Net, 0.5 pip cost | 1,002 | 42.4% | 1.08 | +484 |
| Net, 1.0 pip cost | 1,002 | 42.4% | **1.00** | **−17** |
| Net, measured spread | 1,002 | 42.4% | 1.11 | +637 |

- Edge is entirely **sell-side** (PF 1.51 vs 0.86 for buys) and entirely **2021** (PF 1.39 vs 0.94 in 2022).
- At a realistic 1 pip all-in cost it is **break-even**.
- Indicator only — no EA, no position management, no news filter.

**Verdict:** the most honest backtest in the repo, and a genuinely useful discretionary tool, but not a deployable edge as-is.

---

## 4. Premium / Discount — the best ICT context tool

**Branch:** `arena/01a095ab-kkk`
**Files:** `PremiumDiscount.mq4` (841), `.mq5` (868), `TRADING_GUIDE.md`, `validation/`, `examples/`

Draws the daily or Asia dealing range with ICT OTE levels (29.5% / 70.5%), EQ, extensions and killzones; premium/discount zones filled behind candles. Both **MT4 and MT5** versions maintained in parallel.

- **78 validation tests**: unit tests, no-repaint/determinism, alert-once semantics, kill-zone gating, weekend/holiday fallbacks, real-data smoke tests, performance.
- Real data used in the harness: COMEX gold daily, EURUSD daily (ECB), PAX Gold hourly.
- Static MQL sanity checker (`mql_check.py`) validates both sources.
- No profitability claim — it is a map, not a signal generator.

---

## 5. JobPick v1.20 — one indicator, two engines

**Branch:** `arena/01a06742-kkk`
**File:** `MQL4/Indicators/JobPick.mq4` (1,030 lines)

Clean separation of **3 directional votes** (bias/trend/momentum) and **8 hard gates** (ADX regime, RVOL, adaptive extension, spread, session, HTF, ATR floor, cooldown), plus ATR stop, 2R target, chandelier trail and breakeven.

- v1.20 adds a **mean-reversion engine** for ADX < 25 that fades stretch back to the mean, mutually exclusive with the trend engine.
- Evidence (synthetic, 1.5 pip round trip): MR in-sample **+0.517R** over 65 trades, out-of-sample on 12 unseen seeds **+0.662R** over 76 trades. Trend engine +0.965R trending, but **−0.768R in chop** — it wins by *not trading* (1,837 → 271 trades).
- Every gate is displayed as `ok` / `NO` on the dashboard, so you can see what blocked a signal.

**Caveat:** synthetic data, one parameter set, no walk-forward on the full system. The author says it himself: "sanity check, not proof."

---

## 6. H.I.E.P. — Hidden Institutional Entry Protocol

**Branch:** `arena/4771051a-kkk`
**Files:** `MQL4/Indicators/Hidden_Institutional_Entries.mq4` (1,887 lines), two presets, `TRADING_PLAYBOOK.md`

Raw OHLC + tick volume only — no moving averages, no oscillators. Detects liquidity sweeps, displacement, order blocks, FVGs, BOS/CHoCH, killzones, and scores confluence 0–100. Includes a **PROP GUARD** panel (daily signal cap, risk per trade, session/spread filters).

Validation is better than most:
- Full source compiled through a faithful **MQL4 API shim** with `g++ -Wall -Wextra` — no errors/warnings.
- Driven through a **simulated MT4 terminal** for 3,000 H1 bars: full-rebuild vs bar-by-bar feed produced **identical signals, score, SL and TP**.
- Tested under **AddressSanitizer + UBSan**; degenerate data (flat market, zero prices, 1e-7 ranges, weekend gaps) produces no crash and no signals.
- Two real bugs found and fixed this way: an ATR cache keyed to bar shift, and a state horizon anchored to "now".
- Explicitly **not tested: profitability**.

Expect ~2–5 signals per instrument per month on H1.

---

## 7. WPR Swing Breakout — the EA that grades itself

**Branch:** `arena/01a0488a-kkk`
**Files:** `indicators/WPR_SwingBreakout.mq4` (515), `experts/WPR_SwingBreakout_EA.mq4` (549)

Williams %R leg tracking + stop-and-reverse breakout, with a confluence filter stack (spread, volatility, session, HTF). The interesting part is the EA: it **measures its own signals** and runs a **random-entry control group**, so you can see whether the setup beats a coin flip.

The README also contains the best explanation in the repo of why an "80% win rate" is an exit artefact, not an edge:

| TP : SL | Break-even win rate |
|---|---|
| 0.3 : 1 | 76.9% |
| 1 : 1 | 50.0% |
| 2 : 1 | 33.3% |
| 3 : 1 | 25.0% |

No published performance numbers — it is a measurement harness, not a claimed winner.

---

## 8. PropFirm Institutional Edge Pro

**Branch:** `arena/01a0156e-kkk`
**Files:** indicator (1,720 lines), execution EA (666), `PropFirm_Constants.mqh`, strategy guide, `validate_mql4.py`, `web_demo/index.html`

Full SMC suite: fractal swings, BOS/CHoCH, order blocks with volume validation, FVGs with consequent encroachment, liquidity sweeps, EQH/EQL, killzones, plus a drawdown HUD and a **hard daily-loss killswitch EA**. Has a browser simulator and structural validator.

**Weakness:** no backtest, no statistical evidence, marketing-heavy language ("hedge funds", "institutional-grade"). Good feature coverage and prop-firm plumbing; treat performance claims as unproven.

---

## 9. TaylorCycle v3.00

**Branch:** `arena/01a09fa4-kkk`
**Files:** `MQL4/Indicators/TaylorCycle.mq4` (1,063), presets, `SECRET_STRATEGY.md`, `DEEP_DIVE.md`, `DAYTRADING.md`, `MT4_GUIDE.md`, `NOOB_GUIDE.md`, `SOURCES.md`, Python engine + backtests, FOMC/CPI/NFP calendars

A research dossier on Taylor's 3-day overnight cycle — buy late on Buy-Day dips, hold overnight, sell morning strength, size up around turn-of-month and macro events. The documentation depth is the best here: every formula, threshold and fill assumption is written down, sources are cited, and the macro calendars were verified against the Fed and BLS.

It is an **indicator + research engine**, not an EA, and the edge is equity-index overnight seasonality — not forex intraday.

---

## 10. RuleOP Ladder + the "No-Loss" teardown

**Branch:** `arena/01a06271-kkk`
**Files:** `mt4/RuleOP_Ladder.mq4` (533), `mt4/RuleOP_LadderEA.mq4` (430), `mt4/` C++ test harness, `noloss/noloss_sim.py`, `noloss/report.md`

Two things: an MT4 ladder visualiser (shows the exact price where your account is stopped out) and a full simulation of the "Rule OP / No Loss" martingale system on **600 accounts per variant**, zero-drift random-walk prices, 1:500 leverage, 50% stop-out.

- 37 checks on the whole MQL file through an API stub + 53 checks on ladder arithmetic with hand-derived values.
- C++ core cross-checked against the Python simulator.
- The report does the arithmetic vendors avoid: by rung 10 the floating loss is **−$3,039** on a $100 account against a **$2,046** basket payout; the ladder needs **20.47 lots** to survive 300 pips.

**Read this before buying any "no loss" EA.**

---

## Runners-up worth knowing

| System | Branch | What it is | Why it's not top 10 |
|---|---|---|---|
| **PriceActionSentinel** | `arena/01a03456-kkk` | Full PA chart: S/R zones, BOS/CHoCH, trendlines, 14 candle patterns, confluence score, dashboard | Very complete but no backtest, indicator only |
| **RealLiquidity** | `arena/c30be5f1-kkk` | BSL/SSL pools, volume-spike zones, voids, sweeps, entry+SL+TP arrows | Recent cleanup, object-based, no stats |
| **Liquidity EMA 9 / SMA 20** | `arena/01a0908c-kkk` | Instruction-following indicator + optional EA, MTF zones, fibs, virtual pyramids, risk sizing | Trading off by default, no edge test |
| **VeteranTrader Pro** | `arena/01a0430c-kkk` | Dow/Weinstein/pivots/momentum confluence + Bloomberg-style template + manual in Darija/EN/FR | No validation or backtest |
| **ExhaustionStrength** | `arena/c947de6c-kkk` | Clean MT4 **and MT5** rewrite of the decompiled "Modified LexLampard" counter-trend indicator | Counter-trend knife-catcher by design |
| **SDZ Three Entries** | `arena/01a0a4ef-kkk` | Supply/demand zones with LMT/CNF/STR entry styles, HTF filter, quality score, RR planner | No performance evidence |
| **HolyGrail VWAP SSL v7** | `arena/01a0aad8-kkk` | Weekly/monthly VWAP + SSL flip, ENTER/SKIP scoring, big-move RR to 2SD/3SD | Feature-heavy, no out-of-sample test |
| **VWAP Anchored M15 + EA** | `arena/01a00116-kkk` | M15-anchored VWAP displayed on M5 with pullback signals and an EA | Narrow (indices), no backtest |
| **BuyLowSellHigh + EA** | `arena/01a0495f-kkk` | Mean-reversion extremes, indicator + EA | Author warns it loses in trends; no stats |
| **3-Tier London Breakout V3.3** | `arena/01a02f22-kkk` | Session breakout with broker-time/DST correction | Time-window tool, no EA |
| **HiddenInstitutionalEntry v2.3** | `arena/bde91237-kkk` | Single-file institutional entry with auto SL/TP at 1:1.5 / 1:2 | Superseded by HIEP |
| **NF Volume Profile MTF** | `arena/01a0aa34-kkk` | Multi-timeframe volume profile + identifier audit | Profile tool, no signals |
| **Adaptive SMC Dashboard** | `arena/019fec01-kkk` | SMC dashboard with conservative and gold H4 presets | No EA, no stats |
| **BPT GEX OrderFlow** | `arena/01a08b49-kkk` | Gamma-exposure / order-flow terminal | Niche, undocumented README |
| **Xard Confirmation** | `arena/01a02948-kkk` | Conservative confirmation filter | Small utility |
| **SessionsOnly** | `arena/01a01a9b-kkk` | Session shading utility | Utility |
| **TA + FA Confluence** | `arena/01a042f4-kkk` | Technical + fundamental confluence indicator | No validation |

---

## Which one should you actually install?

| Your goal | Pick |
|---|---|
| One EA to run on a diversified daily basket | **EMA 60/132** (`01a085d5`) |
| Intraday EURUSD ICT signals with a real backtest | **FVG Cascade** (`01a052c6`) |
| Gold / indices mean-reversion with a strict gate stack | **JobPick** (`01a06742`) |
| Prop-firm challenge, selective H1 entries | **H.I.E.P.** (`4771051a`) + its FTMO preset |
| Chart context for discretionary trading | **Premium/Discount** (`01a095ab`) or **PriceActionSentinel** (`01a03456`) |
| Understand the risk before risking money | **No-Loss teardown** (`01a06271`) |
| Best code to learn MT4 engineering from | **VWAP Pro** (`01a0b430`) |

---

## How to pull a system

Branches are remote-only. To inspect one without leaving your current branch:

```bash
git fetch origin
git show origin/arena/01a085d5-kkk:mt4/EMAStudy_AutoTrade.mq4 > EMAStudy_AutoTrade.mq4
git ls-tree -r --name-only origin/arena/01a085d5-kkk   # list everything on that branch
```

Or check the whole branch out in a separate worktree:

```bash
git worktree add ../ema-study origin/arena/01a085d5-kkk
```

Install paths (MT4): `File → Open Data Folder`

- indicators → `MQL4/Indicators/`
- experts → `MQL4/Experts/`
- includes → `MQL4/Include/`
- presets → `MQL4/Presets/`
- templates → `templates/` → copy into `MQL4/templates/`

Then compile each `.mq4` in MetaEditor (F7). Several systems were written in a sandbox with **no MetaEditor**; their authors validated them through shims and static checks, not a real MetaEditor build. Expect to fix an occasional warning on first compile — and never run an EA on a live account before a demo forward test.

---

*Compiled 2026-10-23 from the branch contents of `ismailchaacha97-ui/kkk`. No live track records exist in this repo; every performance figure above is a backtest or simulation quoted from the system's own documentation.*
