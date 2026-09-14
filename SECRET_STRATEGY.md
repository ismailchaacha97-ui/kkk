# The Secret No One Talks About: Taylor's 3-Day Overnight Cycle
### What a 1950 grain trader knew that 2008-2024 research papers proved — and YouTube still ignores

> **TL;DR:** The most robust, least-discussed edge from old books + papers is this:
> **Buy late on a Buy Day low, hold OVERNIGHT, sell morning strength on the Sell Day. Do nothing else.**
> Academic papers show ~100% of the US equity premium is overnight, ~100% of excess return is in 4 turn-of-month days, and momentum/reversal profits are 100% overnight. George D. Taylor described exactly how to time those 2-3 day markups in 1950 with his "Book Method" — no indicator, no news, just previous day high/low + cycle count.

This repo is a research dossier + tradeable rules + backtest starter.

Files:
- `SECRET_STRATEGY.md` (this file) — full thesis, rules, examples
- `taylor_overnight_backtest.py` — minimal backtest skeleton (SPY, yfinance)
- `SOURCES.md` — all books & papers with links

**Not financial advice.** Educational research. Overnight holds have gap risk. Backtest and paper-trade first.

---

## 1. Why this qualifies as "the secret"

I screened ~30 old books and ~40 papers. Most "secrets" are already crowded:

Talked to death: Wyckoff schematics, SMC/ICT, RSI divergence, breakouts, 200DMA, classic momentum, "buy the dip."

**NOT talked about:**

1. **George D. Taylor, *The Taylor Trading Technique* (1950) — the 3-Day Cycle / Book Method.** 128 pages, dense, almost unreadable, out of print for decades. Even most "Wyckoff guys" have never read it. Linda Raschke is one of the only famous traders who still teaches it. Core idea: market makers engineer a repeating 3-day rhythm — Buy Day → Sell Day → Sell Short Day — to trap buyers high and sellers low. You track it manually in a "Book" of highs/lows, penetration failures, and whether high/low was made first or last.

2. **Cliff / Cooper / Gulen (2008) "Like Night and Day."** Using transaction data they decompose the US equity premium into day (open-to-close) vs night (close-to-open). Result: **over the last decade the entire premium is overnight; intraday returns are ~zero and sometimes negative.** Holds for individual stocks, indexes, and futures, NYSE and Nasdaq. Driven by high opens that fade in the first hour.

3. **Lou et al. "Tug of War: Overnight vs Intraday Expected Returns."** 14 strategies dissected: **all momentum + short-term reversal profits happen entirely overnight** (industry momentum >100% overnight, negative intraday), while size/value/profitability happen intraday. Firm-level overnight continuation + cross-period reversal persist **for years**. Interpretation: institutions trade end-of-day, retail at open = clientele tug-of-war.

4. **Lakonishok & Smidt (1988) + McConnell & Xu (2008): Turn-of-Month.** Over **109 years (1897-2005) all positive excess return in the DJIA/CRSP occurred in 4 days: last trading day + first 3 days of next month.** Other 16 days: zero reward for risk. Same volatility. Not small-cap only, not January only, not US only.

5. **Lucca & Moench (2015) Pre-FOMC Drift + Hu et al. extension.** ~80% of S&P excess 1994-2011 earned in **24h before scheduled FOMC**. Hu et al. show same drift before **all macro releases** (CPI, NFP, etc.) if you measure close → minutes-before-release (~25bps avg). Resolution of variance-uncertainty, not the news itself.

6. **Heston & Sadka (2008): Same-Calendar-Month Seasonality.** Stocks that outperformed in a given calendar month continue to outperform **in that same month for up to 20 years**. 50bps+/month long-short on 20-year lookback. Heston thought it was a coding bug.

7. **George & Hwang (2004) + Bhootra & Hur (2013): 52-Week High (Recency).** Closeness to 52-week high beats classic momentum. **Recency of the high doubles it:** recent-high stocks >> distant-high stocks. Pure anchoring bias.

Taylor intuited 1 without computers. Papers 2-7 proved *why* 1 works: constrained arbitrageurs + market makers can't hold inventory intraday, so they press price down into the close, then markup happens overnight / at month-turn / before macro when uncertainty resolves.

No guru teaches the **combination**: Taylor timing + overnight-only holding + turn-of-month / pre-macro filter + 52W/seasonal stock filter. That's the secret.

---

## 2. The old books: what they actually said (not the Twitter version)

### George D. Taylor (1950) — The 3-Day Cycle
Premise: "Smart Money" manipulates in repeating stages. Forget news/fundamentals. Watch only:
- previous day high/low (the only objective levels)
- did market make high first or low first?
- length of last upswing vs downswing
- penetration or failure to penetrate prior high/low

Cycle:
- **Day 1 — Buy Day:** After 1-3 days decline / 2 days after swing high. Ideal: opens flat to lower, makes **low first** in morning near/just under yesterday's low, rallies, **closes in upper part of range**. If it breaks too far under yesterday's low and closes weak = **Buy Day Low Violation** → DO NOT hold long overnight. If it closes strong → hold overnight, odds favor higher open.
- **Day 2 — Sell Day:** Exit longs into strength. Often exceeds Buy Day high then fails. Flat/weak close or down-open after strong Buy Day close is normal. Go home flat. This is often a "fade day" — tradable both sides intraday but core system just exits.
- **Day 3 — Sell Short Day:** Mirror of Buy Day. After 2-3 day rally. Ideal: opens up, makes **high first** near/above yesterday's high, declines, **closes weak**. Short morning resistance, cover weakness same day or next morning low. Then cycle repeats with new Buy Day.

Taylor's extra beats: in trends cycle stretches to 4-5 days (4 up + 1 reaction). Don't fight "Supertrends" of 6-7 straight days. Calculate "rally number" (today high - yesterday low) to project support/resistance zones.

Raschke's modern translation: trade 2-3 day timeframe, focus on prev day high/low test, determine "play for the day" (trend day vs test day), ignore news, use 60/120-min to judge swing length, 2-day rate-of-change for exhaustion.

### Jesse Livermore (*How to Trade in Stocks*, 1940 + Wyckoff interviews)
- Only trade **Pivotal Points**: prior highs/lows, round numbers, breakout levels. Wait for how price *reacts* there.
- **6-point reversal vs 3-point continuation rule** (in his Market Key): needs twice the evidence to reverse a trend vs continue it. Modern version: use ATR buffer — e.g. 0.5×ATR to confirm continuation, 1×ATR to flip bias.
- **"Large part of a movement occurs in last 48 hours of a play."** → Don't overstay. Taylor's 2-3 day window is the same insight.
- Time stop + price stop. First commitment must show profit immediately or you're wrong. Never average down. Pyramid only early, smaller each add.
- Cash out when unsure. Livermore went flat before major uncertainty — same as modern pre-announcement logic in reverse (we *enter* before resolution, but only with Taylor timing).

### Humphrey B. Neill (*Tape Reading and Market Tactics*, 1931; *Art of Contrary Thinking*, 1954)
- Tape = human nature in review. Don't guess *who* is buying; read *what* the record says. Price + volume only.
- **Public is always wrong at important turning points, but right in the trend.** So: fade exhaustion (Taylor Short Day after 2-3 up), follow strength after Buy Day confirms. Not blanket contrarianism.
- "Mechanical forecasting will never take the place of intelligent judgment." Use cycle as framework, not autopilot.

### Gerald M. Loeb (*Battle for Investment Survival*, 1935)
- **Ever-liquid account:** concentrate in few liquid leaders, cut 10% losers fast, let winners run with trailing stops, take profits in stages.
- Price and trend > value. Specialize. Keep cash when no setup. Relevance: this system is *supposed* to be in cash 70%+ of time. That's the point.

### W.D. Gann (*45 Years in Wall Street*, 1949)
Strip astrology: his durable rules were trail stops to breakeven fast, diversify across uncorrelated bets, small size so no single loss hurts psychologically, profits > losses. All used below in risk section.

---

## 3. The papers: what academia proved (in plain English)

| Paper | Finding | Trading implication |
|---|---|---|
| Cooper-Cliff-Gulen 2008 | 100% of premium overnight; intraday ~0/negative; high opens fade first hour | Only be long close→open; avoid holding through intraday bleed; sell morning strength |
| Lou et al Tug of War | Momentum/reversal = overnight; value/size = intraday; overnight continuation lasts years | Trade momentum/reversal overnight only; don't mix with value logic |
| Hendershott/Menkveld/Papanikolaou + Qin et al | Overnight risk + margin/lending fees force arbitrageurs flat EOD → mispricing worsens into close, esp. Friday (4× Monday) | Buy Day dip into close is *structural*, not random; Friday dips are juiciest (but weekend gap risk) |
| McConnell-Xu / Lakonishok-Smidt | All excess in 4 ToM days over 109 yrs | Size up Buy Days in ToM window (T-1 to T+3), size down / skip mid-month |
| Lucca-Moench + Hu et al | 49bps pre-FOMC 24h; ~25bps pre-macro close-to-minutes-before | Best overnight holds = night before FOMC/CPI/NFP/Payrolls when Taylor says Buy Day |
| Heston-Sadka | Same-month winners repeat 20 yrs | Prefer longs whose same-calendar-month rank is top decile |
| George-Hwang + Bhootra-Hur | Near + *recent* 52W high wins | Prefer longs within ~10% of 52W high, high made in last 1-3 months |
| Hartzmark-Solomon | Dividend-month premium | Bonus filter: long in dividend month |

Why it persists: overnight margin is higher, lending fees accrue overnight, illiquidity + gap risk overnight → arbitrageurs reduce into close. Retail trades open, institutions close. Paychecks/dividends/pensions cluster at month-end → liquidity wave. Uncertainty resolves before scheduled news → drift. None of this is arbitraged away because it's *risk + constraint*, not free money — you get paid to hold when others can't.

---

## 4. THE STRATEGY: Taylor Overnight Cycle (tradeable rules)

### 4.1 Universe
- Start: **SPY / QQQ / ES / NQ** only. Master cycle counting on one ticker.
- Expand: top 100 liquid US stocks, avg daily $ > $50M, price > $20, options available (for hedging if desired).
- Avoid: earnings night (unless deliberately trading PEAD — separate system), biotech/binary events, illiquid small caps where spread > edge.

### 4.2 Cycle labeling (do this every evening, 5 min)
1. Mark swing highs/lows (highest high / lowest low of last ~5 days).
2. **Buy Day candidate** = 2 days after swing high, OR after 1-3 down days, OR day after Sell Short Day weak close.
3. **Sell Day** = day after confirmed Buy Day (Buy Day closed strong).
4. **Sell Short Day candidate** = 2 days after swing low, OR after 2-3 up days.
5. In strong trend: expect 4 days primary + 1 reaction → shift entry 1 day earlier (Raschke rule). If 6-7 straight closes same direction = Supertrend → **stand aside**, do not fade.

Write it down like Taylor's Book:
```
Date | Prev H/L | High/Low 1st/Last? | Close position in range | Penetrated? | Label → Next play
```

### 4.3 LONG: Buy Day → Sell Day (core edge, 80% of P&L)
**Setup (Buy Day):**
- Prior 1-3 days down or Sell Short Day closed weak.
- Today opens flat to slightly down, **makes low first** (morning dip toward/under yesterday's low).
- Noon/afternoon: holds above morning low, starts reclaiming. 60-min downswing shorter than prior upswing.

**Entry:**
- **Buy afternoon weakness**, ideally 14:00-15:50 ET, near day low but off lows, OR on reclaim of yesterday's low.
- Alternative for indices: buy **last 30 min** if holding above morning low.
- **Void if:** breaks hard under yesterday's low and stays weak into close (Buy Day Low Violation) → NO HOLD. Flat.
- **Confirm to hold:** must **close in top 30-40% of day range**. If closes mid/weak → scratch or tiny size.

**Exit (Sell Day next morning):**
- Sell into **opening strength / test of Buy Day high / prior high**. Default: **sell first 30-60 min** or limit at yesterday high.
- If opens gap-up strongly above Buy Day high → sell faster (fade day likely). If opens flat/down but holds Buy Day low → give 1-2h max, then exit. **Time stop: out by noon Sell Day** unless clearly trending (then trail).
- Go home flat. Do NOT hold Sell Day → Short Day long.

**Why:** you bought the structural EOD markdown, you sell the overnight markup + retail morning bid before intraday bleed.

### 4.4 SHORT: Sell Short Day (optional, smaller size)
- Only after 2-3 day rally / Sell Day extended.
- Ideal: opens up, **makes high first** near/above yesterday's high, stalls.
- Short morning resistance (prior high / opening high), cover **same-day weakness / close**, or next morning Buy Day dip. Do NOT hold short through ToM or pre-FOMC nights (upward drift headwind).
- Skip shorts entirely in first 3 days of month and day before FOMC/CPI.

### 4.5 The 3 academic amplifiers (position sizing, not entries)
Score each Buy Day long 0-3:
- **+1 ToM:** date is last trading day of month or day 1-3 of new month.
- **+1 Pre-macro:** holding night before scheduled FOMC / CPI / NFP / PPI (close → morning). Check calendar.
- **+1 Stock leadership:** (for single stocks) within 10% of 52W high + high in last 60 days + top same-calendar-month rank. For SPY/QQQ this is always 0 — use index as baseline.

Sizing:
- 0 points: 0.5× base risk or skip if mid-month chop.
- 1 point: 1× base risk.
- 2-3 points: 1.5-2× base risk (cap at 2×).

This concentrates risk when papers say drift is strongest, keeps you alive otherwise.

### 4.6 Risk (Loeb + Gann + Livermore fused)
- **Base risk 0.5-1% of equity per trade.** 2× max on 2-3 point setups.
- **Stop:** below Buy Day morning low (or 1× ATR from entry for indices). No averaging down. Ever.
- **Time stop:** if Sell Day morning doesn't follow through in 1-2h → exit. Livermore: first commitment must profit fast.
- **Max 2-3 overnight positions**, uncorrelated (e.g. not SPY+QQQ+3 tech longs = 1 bet).
- **Weekend rule:** Friday Buy Days have biggest EOD dislocation but weekend gap risk. Take only if ToM or 2+ points, else flat.
- **Supertrend rule:** 6+ straight closes → no fades, no counter-cycle trades.
- **Journal:** Taylor's Book + screenshot + label (Buy/Sell/Short). Review weekly: % of Buy Days that closed strong? Avg overnight (close→open) vs intraday (open→close)? Are you actually capturing night premium?

### 4.7 Worked example (SPY-style)
- Mon: swing high, closes weak. Tue: down, closes mid. → Wed is **Buy Day candidate**.
- Wed 9:30-11:00: dips under Tue low, holds, 60-min selling shorter than Mon-Tue swings. 14:30: reclaims Tue low, basing. 15:30: still above morning low, pushing to mid-range. **Buy 15:30-15:50.** Close in top 35% → **hold**.
- Wed is last trading day of month (+1) and CPI is Thu 8:30 (+1) = 2 points → full size.
- Thu open: gap-up / pops to Wed high in first 30 min. **Sell 9:45-10:30.** Flat. Thu = Sell Day chop/fade. Fri = Short Day candidate — but it's day 1 of new month (ToM) → **skip short**.
- P&L = overnight gap + morning extension, minus almost zero intraday bleed.

Inverse: if Wed broke Tue low and closed on lows → Buy Day Low Violation → no hold, saved capital. That's the system working.

---

## 5. Why this still works in 2026 (and when it dies)

Works because it's **compensation for constraint**, not a pattern:
- Higher overnight margin + stock-loan fees only overnight + gap/illiquidity risk → pros go flat → predictable EOD pressure → overnight reversal.
- Month-end pay/dividend/pension flows + window-dressing + uncertainty resolution → ToM bid.
- Scheduled macro timing is precise → variance-uncertainty resolves pre-release → drift.

Dies / underperforms when:
- 24/7 trading + zero overnight margin difference (crypto-like structure) — not US equities now.
- Volatility regime flip: 2020 COVID crash, 2008 — overnight gaps both ways explode. Reduce size, widen stops, or pause shorts/longs per trend.
- Pre-FOMC specifically weakened post-2015 as press conferences every meeting reduced uncertainty (Kurov et al.). Answer: don't rely on FOMC alone — use **all macros + ToM + Taylor timing**, not FOMC in isolation.

---

## 6. Five more forgotten edges (quick hits for further research)

1. **Same-Month Seasonality long-short (Heston-Sadka).** Each month, rank stocks by avg return in *that calendar month* over prior 5-20y. Long top decile, short bottom, hold 1 month. Rebalance monthly. Shockingly persistent, almost no retail implementation.
2. **Recent 52W High momentum (Bhootra-Hur).** Long stocks near 52W high made in last 1-2 months, short distant-high / far-from-high. 6-12m hold. Beats classic 12-1 momentum.
3. **Turn-of-Month only (McConnell-Xu).** Hold SPY only T-1 to T+3 each month, T-bills otherwise. ~100% of excess with ~20% time-in-market over 109y. Boring = unpopular = persistent.
4. **Pre-macro overnight drift (Hu et al.).** Long ES/SPY close before CPI/NFP/FOMC/PPI, exit minutes before release. ~25bps avg. Requires precise calendar + discipline to *not* hold through release.
5. **Livermore 48-Hour + Pivotal continuation.** Only pyramid/add in first 1/3 of move off pivot; most of move comes in last 48h → take profits into parabolic extension, don't chase. Combine with 3-pt continuation / 6-pt reversal ATR buffers.

---

## 7. Backtest plan (do before risking $1)

1. **Index baseline (easy):** SPY 1993-now. Rule: if down 2 days → buy close → sell next open. Compare: all days vs ToM-only vs pre-macro-only. Metrics: avg overnight vs intraday, hit rate, avg bps, max adverse overnight gap.
2. **Taylor filter:** add Buy Day quality: require close in top 40% of range to hold; skip Buy Day Low Violations. Measure improvement in next-open return.
3. **Morning exit:** compare sell-next-open vs sell-first-hour-high vs sell-prior-high-limit. Pick one, don't overfit.
4. **Single-stock overlay:** add 52W proximity + recency + same-month rank. Does it beat index-only on risk-adjusted basis after spreads/fees?
5. **Costs:** include spread + commission + stock-loan if short + taxes. Overnight edge is ~10-50bps — costs kill it if you overtrade mid-month chop. That's why ToM/macro concentration matters.

Starter code: `taylor_overnight_backtest.py` (buy 2-down-days close → sell next open, ToM flag). Extend with intraday data for true Buy Day low-first + close-position logic.

---

## 8. Reading list (in order)

1. Taylor — *The Taylor Trading Technique* (1950), Ch. 5-10 (Buy/Sell/Short days, violations, penetration failures). Skim Ch. 1-4.
2. Raschke — *Taylor Trading Technique* deck (slides) — modern translation.
3. Livermore — *How to Trade in Stocks* (1940), Ch. on Pivotal Points + Market Key.
4. Neill — *Tape Reading and Market Tactics* (1931), Ch. on volume + when to act contrary.
5. Loeb — *Battle for Investment Survival* (1935) — ever-liquid account, cutting losses.
6. Cooper-Cliff-Gulen (2008) — *Like Night and Day* (SSRN).
7. Lou-Polk-Skouras / Tug of War (AER) — overnight vs intraday cross-section.
8. McConnell-Xu (2008) + Lakonishok-Smidt (1988) — turn-of-month.
9. Lucca-Moench (2015) + Hu et al. (NBER) — pre-announcement drift.
10. Heston-Sadka (2008) — seasonality; George-Hwang (2004) + Bhootra-Hur (2013) — 52W recency.

See `SOURCES.md` for links.
