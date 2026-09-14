# DEEP DIVE (Part 2): The Quantified Taylor–Livermore–Overnight System
### Every formula, threshold, and fill assumption behind `taylor_engine.py` — no vibes, just specs

Companion to `SECRET_STRATEGY.md` (thesis) — this is the **implementation manual**.
Engine defaults below match `taylor_engine.py --help` flags exactly.

**Not financial advice.** Educational research. Every parameter here must be re-verified
on your own data before risking capital.

---

## 0. File map (v2)

| File | Purpose |
|---|---|
| `SECRET_STRATEGY.md` | Thesis: why the edge exists (books + papers) |
| `DEEP_DIVE.md` | This file: quantified rules |
| `taylor_engine.py` | Full backtest + screener (`--demo` runs offline) |
| `taylor_overnight_backtest.py` | v1 skeleton (kept for reference; v2 supersedes it) |
| `data/fomc_dates.csv` | FOMC announcement dates 2023–2026, verified vs federalreserve.gov |
| `data/macro_dates.csv` | CPI + NFP release dates, verified vs bls.gov |
| `fetch_calendars.py` | Extends both CSVs by scraping Fed + BLS (marks rows VERIFY) |
| `TAYLOR_BOOK.csv` | Daily journal template (Taylor's Book, modernized) |
| `SOURCES.md` | All sources with links |

---

## 1. Quantified Taylor Book: the state machine

Run this every evening after the close (5 minutes by hand, or `--screen`).

### 1.1 Inputs per ticker/day
- `prev_high`, `prev_low` (yesterday's extremes — Taylor's only objective levels)
- `close_pos = (Close − Low) / (High − Low)` → 1.0 = closed on the high
- `pen_high = (High − prev_high) / ATR14`, `pen_low = (prev_low − Low) / ATR14`
  (+`pen_low` = broke under yesterday's low; units of ATR so it works on any ticker)
- `dn_streak` / `up_streak` (consecutive closes), `supertrend` = streak ≥ 6 either way
- `days_since_swing_hi` (swing high = 5-day highest high, confirmed with 2-day lag)

### 1.2 Day labels (engine: `label_cycle`)
| Label | Condition (evaluated at today's close) |
|---|---|
| **BUY candidate** | `dn_streak ≥ 2` **OR** 2–3 days after confirmed 5-day swing high |
| **SELL day** | tomorrow, if today was a confirmed Buy Day (you hold into it) |
| **SHORT candidate** | `up_streak ≥ 2` |
| **Supertrend** | streak ≥ 6 → **no counter-cycle trades at all** |

### 1.3 Buy-Day Low Violation (the void filter)
Taylor: if the market smashes under yesterday's low and closes weak, smart money
is *not* done marking down — do not hold.
```
violation = (pen_low > 0.25) AND (close_pos < 0.35)
```
Engine default hold gate (`--min-close-pos 0.6`):
```
hold_ok = (close_pos ≥ 0.60) AND (NOT violation)
```
Interpretation: you only hold the **top-40% closes**. Backtest both sides of this
gate (`--min-close-pos 0.0` vs `0.6`) — the "by q_closepos" breakdown will show you
exactly what weak closes cost. Expectation from the literature: weak-close holds
earn ~zero or negative overnight; the edge concentrates in strong closes.

### 1.4 Intraday confirmation (optional but recommended)
With `--intraday 30m` (or `--intraday-csv`), the engine adds:
| Feature | Taylor meaning | Formula |
|---|---|---|
| `low_first` | ideal Buy Day makes its low in the morning | time(day low) ≤ time(day high) |
| `first_low_vs_prev` | morning dip depth | (first-bar low − prev_low) / ATR |
| `reclaim` | dip under prev low, close back above it | first low < prev_low AND close > prev_low |
| `eod_push` | tape firm into the close | (last close − prior close) / ATR |

### 1.5 Buy-Day Quality Score (0–100, for ranking, not gating)
```
quality = 55 × close_pos
        + 20 × (NOT violation)
        + 10 × (broke prev low AND closed ≥ mid)   # failed breakdown = fuel
        + 10 × low_first          (5 neutral if no intraday data)
        +  5 × reclaim
```
Use it to choose between simultaneous setups (take the highest score) and to
size within the score band. It is deliberately dominated by `close_pos` — the one
input Taylor, Raschke, and the overnight papers all agree on.

---

## 2. Entries, exits, and fill assumptions (read before trusting any backtest)

### 2.1 LONG: Buy Day close → Sell Day morning
- **Entry:** today's close (proxy for 15:30–15:50 accumulation; use MOC or last-30-min VWAP live).
- **Exits** (`--exit`):
  - `open` (default, most honest): exit at next open. Captures pure overnight drift.
  - `limit`: limit at Buy-Day high. Fill logic — gap through → open; tagged intraday → limit − 1bp slip; never tagged → **close** (conservative: absorbs the full intraday bleed as penalty for missing).
  - `firsthour`: exit at first-hour (≤10:30 ET) high − 1bp. **Requires intraday data**, else falls back to open.
- **FOMC extended** (`--fomc-extended`): on FOMC announcement mornings, hold to the last print before 13:55 instead of the open (Lucca–Moench's window runs into the 14:00 announcement). Requires intraday; falls back to open without it.

### 2.2 SHORT: Sell-Short Day fade (off by default; `--shorts`)
Quantified Taylor mirror, deliberately neutered vs the long side because it fights
the overnight drift:
- Setup: `up_streak ≥ 2`, `close_pos ≤ 0.45` (today faded), NOT ToM, NOT pre-macro.
- Entry: today's open − 1bp (proxy for shorting morning-high area).
- Exit: **same-day close** (no overnight short hold — borrow + drift headwind).
- Cost: `cost_bps` + 3bp borrow proxy.
- Skip entirely in the first 3 trading days of the month and before FOMC/CPI.

### 2.3 What the backtest assumes (costs)
- `cost_bps = 2` round-trip proxy for SPY/QQQ (spread + commission). Raise to 5–10 for single stocks.
- No market impact (valid ≤ ~$1M/trade in index ETFs; single-stock slippage is on you to model).
- Dividends/splits: use adjusted data (yfinance `auto_adjust` caveat — engine uses unadjusted OHLC for realistic open/close fills; for multi-year single-stock tests, prefer adjusted closes).

---

## 3. The 0–3 Academic Score → position size (sizing, not entries)

Computed at the close, before entry:

| Point | Condition | Flag |
|---|---|---|
| +1 ToM | last trading day of month, or day 1–3 of new month | `--` (always on) |
| +1 Pre-macro | tomorrow is a FOMC/CPI/NFP date in `data/*.csv` | `--` (always on) |
| +1 Leadership | `h52_ratio ≥ 0.90` AND `h52_rec_cal ≥ 0.75` AND `seas_z > 0` | `--min-h52`, `--min-rec` |

Where:
- `h52_ratio = Close / max(High, 252d)` (George–Hwang nearness)
- `h52_rec_cal = 1 − (calendar days since 252d high) / 365` (Bhootra–Hur recency; ≥0.75 ≈ high within ~90 days)
- `seas_z` = trailing same-calendar-month mean return / its std, prior 5 years only, strictly before the current month (Heston–Sadka, point-in-time)

Risk per trade = `equity × risk_pct × mult[score]`, notional capped at `max_pos × equity`:

| Score | Default mult | Meaning |
|---|---|---|
| 0 | 0.5× | mid-month chop: half size or skip |
| 1 | 1.0× | one tailwind |
| 2 | 1.5× | two tailwinds: full edge |
| 3 | 2.0× | rare: ToM + macro + leader |

Defaults: `--risk-pct 0.005 --max-pos 0.5`. Stop distance = `max(ATR14/price, 0.2%)`
(overnight gap proxy — your real stop is the *time stop*: out on Sell-Day morning
if no follow-through within 1–2h; a hard stop below the Buy-Day low is the backstop).

---

## 4. Livermore Market Key, quantified (the 3-pt / 6-pt rule in ATR)

Livermore's Key (1940): **continuation needs 3 points of confirmation, reversal needs 6** —
i.e., twice the evidence to flip bias. Translated to ATR so it adapts to volatility:

```
continuation confirmed: close through pivot + 0.5 × ATR
reversal confirmed:     close through pivot + 1.0 × ATR  (opposite side)
```

Pivot detection (daily, mechanical): prior 20-day high/low, round numbers
($50/$100…), or the Buy-Day/Sell-Day extremes themselves. Practical use inside
this system:
- **Pyramid rule:** adds only within the first 1/3 of the move off the pivot,
  sizes 1.0 / 0.5 / 0.25 (Livermore's decreasing adds), each add only after
  +0.5 ATR of profit. Never add to a loser. Never add after the "last 48 hours"
  extension starts (that's distribution — sell into it, per §6 of the thesis).
- **Danger signal:** a continuation that needed 1.0 ATR to confirm (i.e., reversal
  energy to keep going) = exhausted trend. Tighten to breakeven immediately.

---

## 5. Execution microstructure (where the bps leak or compound)

| Effect (paper) | Practical handling |
|---|---|
| High opens fade in the first hour (Cooper et al.) | Default exit = open or first-30-min scale; never chase the open |
| Mispricing worst into the close, esp. Friday (Hendershott et al.) | Enter 15:30–15:50; Friday holds only if score ≥ 2 (`--no-friday`) |
| Drift resolves *before* the release (Hu et al.) | Exit at the open / minutes before 8:30 releases; never hold *through* CPI/NFP |
| FOMC window runs to 14:00 (Lucca–Moench) | Optional `--fomc-extended` hold to 13:55 on announcement days |

Live order mapping (ET): entry = MOC or 15:45 limit at mid; open exit = MOO or
9:31–10:00 limit ladder at Buy-Day high / prior high; futures (ES) = same logic,
1/10th size to start (24h session changes the open/close definitions — use RTH
9:30–16:00 bars only for labeling).

---

## 6. Single-stock screen spec (`--screen`)

For each ticker, engine prints: cycle state, `close_pos`, quality, `h52_ratio`,
`h52_rec_cal`, `seas_z`, ToM, pre-macro, score, verdict. Gates before *any* single
stock qualifies for an overnight hold:
1. Liquidity: price > $20, ADV $ > $50M (check yourself — engine doesn't fetch volume $).
2. No earnings within 1 trading day (`--earnings-csv date[,ticker]` blackout).
3. Spread sanity: edge is 10–50bps — if spread + borrow > 10bps, skip.
4. Leadership for score +1: §3 thresholds.
5. Max 3 concurrent overnight holds, uncorrelated (SPY + QQQ + AAPL = one bet).

Rebalance note: the seasonal and 52W features are slow — re-screen weekly, trade
the cycle daily.

---

## 7. Backtest interpretation guide (what "good" looks like)

Run order:
```
python taylor_engine.py --demo                                   # offline sanity
python taylor_engine.py --ticker SPY --start 2015-01-01 --source stooq
python taylor_engine.py --ticker SPY --start 2015-01-01 --source stooq --exit limit
python taylor_engine.py --ticker SPY --start 2015-01-01 --source stooq --exit limit --shorts --no-friday
```

Healthy signatures (index ETFs, net of 2bps):
- avg_net **+3 to +12bps**, hit **52–58%**, t-stat rising with √n (demand t > 2 before sizing up)
- ToM avg ≈ **1.5–2.5×** non-ToM; pre-macro avg > baseline; quality/close_pos monotone rising left→right
- worst gap −2% to −4% on SPY (2020-type nights) — this is why score sizing + `max_pos` exist
- `--exit limit` ≥ `--exit open` by a few bps (you're paid for the morning extension), but with fatter left tail on no-fill days

Overfitting checklist (the edge is small — respect it):
- [ ] Tested 2015+ AND 2008–2012 (regime change)? `--start 2000-01-01`
- [ ] Costs doubled — still positive? `--cost-bps 5`
- [ ] Works on QQQ + DIA, not just SPY?
- [ ] Score-0 trades ≈ break-even (if score-0 prints big money, a gate is leaking)
- [ ] No parameter scanned more than 2–3 values (close_pos gate, costs, exits — that's it)

---

## 8. Failure modes & kill switches

| Failure | Signal | Action |
|---|---|---|
| Volatility explosion (2008/2020-type) | ATR% > 90th pctile | `--max-atr-pctile 0.9`, halve risk, or flat |
| Supertrend | 6+ straight closes | system auto-skips; don't override |
| Pre-FOMC decay (post-2015 effect) | FOMC-night avg → 0 in recent years | rely on CPI/NFP + ToM, keep FOMC at 1× not 2× |
| Earnings / binary events | blackout list | flat, no exceptions |
| 3 consecutive max-loss gaps | review log | 2-week pause, re-check calendar alignment |

## 9. 30-trade paper protocol
1. Trade the system on paper for 30 Buy-Day holds (or 3 months), logging every night in `TAYLOR_BOOK.csv`.
2. Weekly: compute your avg overnight bps vs the engine's on the same dates. If you trail by >5bps/trade, it's execution (entry timing, exit chasing) — fix that before sizing.
3. Graduate to 0.25% risk only after: hit ≥ 50%, avg_net > 0 after your real commissions, zero rule violations in the last 10 trades.
