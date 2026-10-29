# The FTMO Operating System

A complete, rules-based way to run FTMO evaluations and a funded account, built so that
every claim in it can be checked against a simulation rather than taken on faith.

**Files that make this real**

| File | What it is |
|---|---|
| `FTMO_SYSTEM.md` | this playbook — the decisions and the daily protocol |
| `ftmo_engine/REPORT.md` | the numbers: pass rates, failure attribution, payout-policy result |
| `ftmo_engine/` | the engine — rules, sizing, circuit breaker, Monte Carlo, CLI |
| `ftmo_engine/tests/` | 23 tests pinning the risk maths |
| `mql/FTMO_Ops.mq4` | **the trading EA** — places the orders, enforces the full risk engine |
| `mql/FTMO_Governor.mq4` | read-only supervisor — draws the four floor lines, halts visibly |
| `EA_Tesshinso_review.md` | review of the EA that prompted this; explains what disqualified it |

```bash
python3 -m unittest discover -s ftmo_engine/tests -t .   # verify the model
python3 -m ftmo_engine.run_report                         # regenerate REPORT.md
python3 -m ftmo_engine.cli size --balance 100000 --risk 0.5 --stop-pips 25
python3 -m ftmo_engine.cli gate --win-rate 0.45 --rr 1.8
```

---

## 0. Read this before anything else

You asked for a system that "functions as a reliable money-making machine" with "no
questions or doubts". The professional version of that request is: **a system where the
doubt is quantified, priced, and bounded** — not one where doubt has been asserted away.
So, plainly:

1. **No configuration of risk management creates an edge.** The simulation in
   `REPORT.md` shows a strategy with a *zero* edge passing Phase 1 about half the time
   and then dying inside the funded stage with 47% probability over two years. It also
   shows a 1.31 profit-factor system producing ~$1,400/month on a $100K account with
   near-certain survival. **The difference between those two outcomes is the edge, not
   the rules.** This playbook maximises the value of whatever edge you have and stops you
   from losing the account to arithmetic. It cannot manufacture one.
2. **The FTMO model is a leveraged option on your skill, sold for a fixed premium.** You
   pay ~$540 for the right to earn 80% of the profits on $100K. If your edge is real the
   option is mispriced in your favour; if it is not, you are the product. The engine's
   job is to tell you which case you are in *before* you pay.
3. **The binding constraint is almost never the one people fear.** It is not the 5% daily
   limit — at 0.5% risk with a daily stop, the daily breach rate rounds to zero. It is
   the **10% static floor**, which is only ten average losses away, plus **edge decay**,
   which is the only risk that cannot be managed once it starts.
4. **The single most profitable decision in the whole document is the payout policy.**
   Withdrawing everything every cycle loses the account with ~99.9% probability over two
   years while looking flawless on the equity curve. Keeping a 15% buffer and withdrawing
   only the excess more than doubles expected income and cuts failure by ~60x. Nothing
   else in this playbook has that leverage.

---

## 1. The FTMO structure, mechanically

### 1.1 The current rule set (verify before purchase — firms change terms)

| Rule | Challenge | Verification | Funded |
|---|---|---|---|
| Profit target | 10% | 5% | none |
| Max daily loss | 5% of day-start balance, resets midnight CET | same | same |
| Max total loss | 10% of **initial** balance, static | same | same |
| Min trading days | 4 | 4 | none |
| Time limit | none | none | none |
| Split | — | — | 80% → 90% via scaling |
| Fee | $155–$1,080 by size, refunded on first payout | — | — |

Non-numeric rules that void accounts even with a clean curve: no latency/tick-scalping,
no HFT (>2,000 server requests/day), no martingale-style escalation, no hedging the same
risk across accounts, no third-party signal copying, and on Normal accounts no holding
through high-impact news (±2 min) or over the weekend. Combined allocation per strategy
is capped (≈$400K).

### 1.2 Strengths — where the model is genuinely fair

| Strength | Why it matters to a systematic trader |
|---|---|
| **Static 10% drawdown** | The floor never trails your equity. Profits build a real buffer instead of tightening the noose. This is the best feature FTMO has and the reason the buffer payout policy works so well. |
| **No time limit** | You can trade the edge's natural frequency. The 0.5% plan needs ~2 months for Phase 1; a "make 10% in 30 days" firm forces you to triple risk, which is the failure mode, not the task. |
| **Fee refunded on first payout** | The evaluation is a deposit, not a sunk cost — *if* you reach a payout. (See §0.1: this is what makes near-zero edges look free.) |
| **Two phases, one objective** | Verification at 5% is a consistency check that punishes a lucky Phase 1. |
| **Long payout history, audited** | Counterparty risk is lower than with any 2021-2023 vintage firm. Money you can't withdraw isn't income. |

### 1.3 Weaknesses — the design flaws to defend against

| Weakness | Consequence | The countermeasure in this plan |
|---|---|---|
| **10% floor vs 10% target is a thin, asymmetric bet** | You risk a 10% envelope to make 10%; ~10 average losses end it | 0.5% risk → 20 losses to fail, and a 2R daily breaker |
| **Daily limit is measured from day-start balance, resetting at CET midnight** | A late-night session in your timezone belongs to *tomorrow*; a "fresh start" can be minutes away | Trade a fixed session window per day; never open positions across the CET reset |
| **Drawdown counts open P&L intraday** | A floating loss on one position can fail you even if it later recovers | Never hold a floating loss > 1R; no average-down (also banned) |
| **Prohibited-practice clauses are behavioural, not numeric** | A wildly successful but martingale-shaped curve gets profits withheld | No size escalation after losses, ever; store the rule in code (§4) |
| **Normal accounts: no weekend/news holds** | Gap exposure around NFP/CPI is a rule violation, not just a risk | Swing variant if you need it, else a hard news/calendar filter |
| **Scaling needs ~4 consecutive months of ≥10%** | Slow path from 80% to 90% | Plan income on 80%; treat scaling as upside |
| **Fee is regressive to size** | A $10K evaluation costs 1.55% of the account vs 0.54% at $100K | Start at $10K only to validate execution; do the economics at $100K |
| **Funded stage has no finish line** | The failure mode is month 3, not week 1 | Buffer payout policy + edge-decay monitor (§6) |

**What I would change if I ran the prop model** (useful even if you don't): price the fee
as a share of funded income rather than per attempt, make the drawdown trail *upward* only
after a full payout cycle, and allow a "consistency credit" that grants the next evaluation
free after two profitable cycles. Each of those reduces the incentive to gamble — the
structural reason traders fail is that the fee is sunk and the payoff is a lottery ticket.

---

## 2. The go/no-go gate — do not buy an evaluation before this

The engine answers one question: **is this venture positive-EV for you?** It will
happily tell you "no".

```bash
python3 -m ftmo_engine.cli gate --win-rate 0.45 --rr 1.8
python3 -m ftmo_engine.cli check --win-rate 0.45 --rr 1.8 --risk 0.5
```

Requirements before spending money, in order:

| # | Gate | Threshold | How to verify |
|---|---|---|---|
| 1 | **Live or demo sample** | ≥ 100 trades executed by hand, on the same broker/feed | trading journal, not backtest |
| 2 | **Expectancy** | ≥ **+0.10R** per trade net of spread/commission/swap | rolling 100-trade mean |
| 3 | **Profit factor** | ≥ 1.25 net | same sample |
| 4 | **No single trade > 1.0R loss** (excluding forced gaps) | zero violations | journal audit |
| 5 | **Max drawdown of the sample** | ≤ 8R | if a 10R streak would fail you, so will the challenge |
| 6 | **Execution error rate** | < 2% (missed entries, wrong size, late exits) | count them; this is the most common real cause of failure |
| 7 | **Monte Carlo of your own edge** | `check` returns GO | `python3 -m ftmo_engine.cli check` |

From `REPORT.md`: at 1.8R average win, **38.2%** win rate is the zero-expectancy floor and
**41.7%** is the minimum worth trading. Below 38.2%, discipline has nothing to compound.
If gates 1–6 are not met, the answer is not "buy a bigger account" — it is "trade the
demo for another six weeks".

---

## 3. The trading system

A spec, not a philosophy. Every line is a binary pass/fail condition, so two people
following it take the same trade.

### 3.1 Universe and sessions

| Element | Rule |
|---|---|
| Symbols | EURUSD, GBPUSD, USDJPY (max 2 open at once; they are one USD bet — see §4.4) |
| Sessions | London open → London/NY overlap (07:00–16:00 **CET**), no positions carried into the weekend |
| News filter | flat ±30 min around high-impact events (regardless of account type; the 2-min rule is the firm's minimum, not yours) |
| Account type | Normal is fine for this system because it holds intraday only. Choose Swing only if you require overnight/weekend holds |

### 3.2 Setup — trend-pullback continuation (H1 bias, M15 trigger)

This is the shape of system that produces the ~1.3 profit factor used in the report. It is
a template: keep the structure, replace the parameters with whatever your own testing
validates.

**Bias (H1, closed bars only — no repainting):**
- `EMA50 > EMA200` and price above both → long only. Inverse → short only. Mixed → no trade.

**Zone (H1):**
- Identify the most recent H1 demand zone for longs: the body low of the last up-impulse leg
  that broke a swing high. Longs only from that zone (±3 pips).
- Zone must not have been touched more than twice.

**Trigger (M15, on bar close):**
- Price tapped the zone, then printed a bullish engulfing or pin with the body closing back
  **inside** the zone, and `ATR(14)` on M15 ≤ 1.2 × its 20-bar mean (no news candle).

**Entry / stop / target:**

| Field | Rule |
|---|---|
| Entry | market on the M15 close of the trigger bar |
| Stop | below the zone low − 0.3 × ATR(M15), minimum 8 pips, must exceed spread × 2 |
| Target | 2.0R fixed for 60% of the position; the remaining 40% at 3.5R with stop to breakeven at +1R |
| Time stop | if not +0.5R within 8 M15 bars, close at market |
| Max holds | none over the weekend; all flat by 21:00 CET Friday |

**Why this shape:** it trades *with* the higher-timeframe flow, enters at a predetermined
price (so risk is known before clicking), and has a mechanical exit ladder that produces a
win rate in the 42–50% band with an average win near 1.8R — exactly the parameter space the
report was simulated on. A system that needs a 60% win rate to survive will not survive
FTMO's drawdown envelope.

### 3.3 What is explicitly forbidden (the anti-martingale clause)

- No position sizing based on conviction, fear, or "making it back".
- No adding to a losing position. Ever. (Also a prohibited practice.)
- No widening a stop. If the stop is wrong, take the stop.
- No more than **2 trades per day** and **3 per week** per symbol unless the journal shows
  the setup is genuinely that frequent.
- No trading after a daily halt, a weekly halt, or a rule violation — those are hard stops,
  not suggestions.

---

## 4. The risk algorithm

This is the "advanced risk assessment" layer: four deterministic calculations that run
before every order. Nothing here is discretionary.

### 4.1 Position size (fixed-fractional off the stop, never off a lot table)

```
risk_$   = reference_balance × risk_pct / 100
lots     = risk_$ / (stop_pips × pip_value_per_lot)
lots     = floor(lots / lot_step) × lot_step        # never round up
if lots < min_lot: skip the trade                   # not "round up to 0.01"
```

| Account | Phase | Risk/trade | $ on 100K | Lots @ 25-pip stop |
|---|---|---|---|---|
| $100K | Challenge | 0.50% | $500 | 2.00 |
| $100K | Verification | 0.50% | $500 | 2.00 |
| $100K | **Funded** | **0.40%** | $400 | 1.60 |

`reference_balance` is **fixed at the phase's starting balance** — it does not grow with
profit. Risking a percentage of a growing balance compounds size and is the quiet road to
the 10% floor. (The engine supports both; the fixed version is what the numbers assume.)

**Why 0.5% and not 1%:** at 1% you halve the pass probabilities while the run to target
shrinks from ~7 weeks to ~4. You are buying impatience with the funded account, which is
the actual asset. The optimum is a plateau; take its left edge.

### 4.2 The daily budget (three limits, none negotiable)

| Limit | Value on $100K | Source |
|---|---|---|
| Firm daily loss | $5,000 (5% of day-start balance) | FTMO |
| **Self-imposed daily stop** | **$2,000 (2%)** | this plan |
| **Trade-level breaker** | **2 losses or −2R, whichever first** | this plan |
| Firm total floor | $90,000 | FTMO |
| **Self-imposed total stop** | **$93,000 (7%) — stop, review, reset** | this plan |

The 3-point gap between the self-imposed total stop and the firm's floor is deliberate: it
is the only way to observe a losing streak without the account ending. If you hit $93K, you
stop for a week regardless of how the next setup looks.

### 4.3 Halt conditions (checked in code, not by feel)

Open no new position if **any** is true:

1. Daily realized loss ≥ 2% of day-start balance.
2. Two consecutive losing trades today.
3. Two trades already taken today.
4. Floating loss on the open basket ≥ 1.5R.
5. `equity − risk_$ < firm daily floor` (a single loss could breach).
6. News window open (±30 min high-impact).
7. Weekly loss ≥ 2 days' budget, or two daily halts in the same week (weekly halt).
8. Phase-1 profit ≥ 8% and fewer than 4 trading days → trade only 0.1% to satisfy the rule.

### 4.4 Correlation cap (the unmodelled risk)

EURUSD-long + GBPUSD-long + USDCHF-short is **one** short-USD bet at 3× the size. The
engine sums signed USD exposure across open positions and refuses a candidate that pushes
the net beyond `max(net, 1.5 × reference lots)`. The simulation's worst single event is
2.5R on one trade; it does **not** model a correlated 5% gap across three positions — which
is exactly why the funded risk is 0.4% and the buffer is 15%, not 5%.

### 4.5 The math you must be able to do in your head

At 0.5% risk and a 2R daily stop:

- A full daily stop costs **1%** of the account, not 5%. You could have three bad days in a
  row and still be inside a single firm daily limit.
- Ten consecutive losses = **5%**. Twenty = **10%**, i.e. the account. There is no
  configuration where 20 sequential losses are survivable, so the job is to never have a
  reason to take them: no averaging down, no correlated stacking, no trading after a halt.

---

## 5. Execution protocol

### 5.1 In the terminal — the executor

`mql/FTMO_Ops.mq4` **places the trades**. It is the full mechanical implementation of
§3 + §4: H1 bias, H1 zone detection, M15 trigger entry, fixed-fractional sizing off the
stop, the complete exit ladder (breakeven at +1R, 60% split at +2R, runner to 3.5R,
time stop at 8 M15 bars), every halt condition from §4.3, the weekly halt, the
correlation cap (§4.4), the news window, and the 8%-profit lock from §6.

> **Compile and test before trusting it.** The logic is a port of `risk.py`/`mc.py`,
> which are unit-tested; the MQL4 file itself has **not** been compiled or run in the
> environment where it was written. Order of operations: MetaEditor compile →
> Strategy Tester on "every tick based on real ticks" for 6+ months (check: no trade
> after a halt day, no weekend holds, every order has SL+TP, lots match the risk table,
> nothing trades inside the news window) → live demo 2–4 weeks → a real evaluation.

Usage notes:

- One chart per symbol (EURUSD, GBPUSD, USDJPY), **same `InpMagic`** on all of them.
  The daily caps and breakers are counted from account history by magic number, so one
  chart cannot spend another chart's budget.
- `InpMode` sets the risk regime: 0 = challenge/verification (0.5%), 2 = funded (0.4%).
  The reference balance is fixed on first attach — delete the `FTMOOPS_*`
  global variables from the terminal when the account changes.
- Set the NFP time to your broker's **server time** (typical 08:30 UTC = 12:30 on a
  +4h server) and list any other high-impact dates in `InpNewsTimesServer`.
- `InpDryRun = true` logs every signal it *would* take without sending orders — run
  this first to verify the zone/trigger logic on your feed before real orders.

`mql/FTMO_Governor.mq4` remains available as a read-only supervisor (draws the four
floor lines, halts visibly) — useful on a second screen, or if you ever trade manually.
If you trade manually with no EA: keep a spreadsheet with `day_start_balance`,
`realized_today`, `trades_today`, and check it before every entry. The failure mode is
not the arithmetic — it is not doing it on the day you least want to.

### 5.2 Pre-session checklist (5 minutes, before the London open)

- [ ] Day-start balance recorded; daily stop price calculated and written down.
- [ ] News calendar checked; blackout windows marked.
- [ ] HTF bias marked for each allowed symbol (long / short / no-trade).
- [ ] Zones drawn on H1; alerts set at zone edges.
- [ ] Max 2 trades and 3 per week stated out loud.
- [ ] Emotional self-check: sleep, stress, outside distraction → if 2 of 3 are bad, demo day.

### 5.3 Per-trade checklist (before the click)

- [ ] Setup confirms on **closed** bars only.
- [ ] Stop is at structure, not at a round number of pips.
- [ ] Lot size from the formula (§4.1), floored, ≥ min_lot.
- [ ] SL/TP attached **in the same order**, not added afterwards.
- [ ] Risk ≤ 0.5% and no halt condition active.
- [ ] Screenshot + journal row written *before* entry (setup, zone, R, reason).

### 5.4 Post-trade (60 seconds)

- [ ] Grade execution (A–F) separately from outcome: a losing A-grade trade is a good trade.
- [ ] Log `R` outcome, MAE/MFE, and whether the plan was followed.
- [ ] Update `realized_today` / `trades_today`.
- [ ] If a rule was broken: stop for the day, regardless of the P&L sign.

---

## 6. The funded stage — where the money actually is

### 6.1 The payout policy (the highest-leverage rule in this document)

**Keep the account at least 15% above its starting balance. Withdraw only what exceeds that
line.**

Why, from `REPORT.md` §6 (52 payout cycles ≈ 2 years, 0.5% risk, healthy edge):

| Policy | P(account lost) | Mean earnings | 10th percentile |
|---|---|---|---|
| Withdraw 100% each cycle | **99.9%** | $33,739 | $10,297 |
| Withdraw 70%, keep 30% | 20.9% | $62,530 | $15,597 |
| **Buffer 15%, withdraw excess** | **1.7%** | **$71,161** | **$45,702** |

Profit leaves; losses stay. Take everything and your buffer shrinks against a fixed floor
every cycle, so ruin is not a risk — it is a schedule. The buffer converts the static
drawdown into an asset you can actually rent out.

Mechanics: on a $100K funded account, the withdrawal line is **$115,000**. After each
14-day cycle, request a payout of `balance − 115,000` (nothing if below). Raise the line only
when the firm's scaling plan increases your balance; never raise it because you want money.

### 6.2 Edge-decay monitor (the only early-warning system that matters)

Every payout cycle, compute rolling expectancy over the last 50 trades:

| Rolling 50-trade expectancy | Action |
|---|---|
| ≥ 0.10R | continue at 0.4% |
| 0.00R to 0.10R | cut to 0.2%, review the last 20 trades for execution error |
| < 0.00R for 50 trades | **stop trading**, cut to 0.1% or demo, re-validate the setup |
| < 0.00R for 100 trades | retire the setup; the regime changed |

From `REPORT.md` §7, a 50% edge decay reduces income by ~62% and triples failure; a 0%
edge leaves only a quarter of accounts ever reaching a payout. Decay is not detectable in
the moment — only by measuring on a schedule. Do the arithmetic on a fixed day, not when it
feels bad.

### 6.3 What NOT to do with a funded account

- Do not raise risk to "build the buffer faster" — that is the exact trade that fails the account.
- Do not treat the first payout as proof of anything; it is one 14-day sample.
- Do not scale by opening several accounts running the same signals (prohibited, and capped
  at ~$400K combined).
- Do not skip a cycle's payout because the month was good; the buffer policy is mechanical.

---

## 7. Psychological resilience, operationalised

Discipline is not a personality trait; it is what remains when the decision is already made.
Everything below exists to remove in-the-moment choice.

| Failure mode | What it looks like | Protocol |
|---|---|---|
| **Target panic** (Phase 1) | 8% up on day 20, doubling size to finish | Hard rule: after 8%, risk drops to 0.1% and only the 4-day minimum is completed. Profit targets are not races. |
| **Revenge trading** | Two losses, immediately hunting a third | The 2-loss breaker is enforced in code and by the journal, not by willpower. |
| **Drawdown denial** | Widening stops, holding losers overnight | No-hold rule + broker-side SL in the entry order. An order without a stop is not placed. |
| **Outcome attribution** | "I'm good this week" / "the market hates me" | Journal grades execution separately from P&L. Only execution grades drive behaviour. |
| **Boredom trading** | Taking B-setups in a quiet session | Max 2 trades/day; B-setups are logged as *skipped*, and skipping is scored. |
| **Post-payout euphoria** | Risk creep after a good cycle | Withdrawal line is mechanical; risk changes only in the quarterly review. |
| **Recovery tilt after a halt** | Re-entering the same day "just to check" | Halt = terminal for the day; the governor blocks it, and the next session starts fresh at CET midnight. |

**The 24-hour rule.** Any rule violation → no trading for 24 hours and a written
post-mortem answering three questions: which rule, what state (sleep/stress/screen time),
and what structural change prevents a repeat. The post-mortem is not optional and not a
confession; it is the only mechanism that turns a violation into an improved system.

**Process score.** Score each week on 5 binary items: all trades journaled, zero rule
violations, all stops attached pre-entry, max-trade cap respected, review completed. Five of
five for four consecutive weeks is the precondition for the next account size — not a
profitable week.

---

## 8. Scaling

Scaling has three independent levers. Use them in this order; do not skip.

| Stage | Trigger (operational, not emotional) | Action |
|---|---|---|
| 1. Validation | 100 demo trades, gates §2 met | buy the smallest evaluation ($10K) — pay for execution proof, not income |
| 2. Income | one funded account, 3 consecutive cycles above the withdrawal line | hold risk at 0.4%; raise nothing |
| 3. Size | 6 months funded, ≥ 4 payouts, process score 5/5 for 4 weeks | move to $100K (fee efficiency 0.54% vs 1.55%) |
| 4. Diversify | $100K funded and stable for 2 cycles | one **uncorrelated** second strategy on a second account — never the same signals (prohibited + capped) |
| 5. Split | 4 months ≥ 10% profit → scaling plan | 90% split + 25% balance increase; raise the withdrawal line with the balance |

**Realistic income expectation.** From `REPORT.md` §5, at 0.5% risk with a healthy edge and
the buffer policy, a $100K account averages ~**$1,400/month** over its first six funded
months, with a 10th-percentile outcome near zero and a very wide upper tail. If a plan
quotes more than ~2%/month on the account as a *base case*, the edge assumption is the first
thing to audit. Scale the account, not the risk.

---

## 9. Operating cadence

| Frequency | Task | Output |
|---|---|---|
| Daily, pre-open | §5.2 checklist | bias, zones, budget |
| Daily, post-close | journal rows, execution grades | data |
| Weekly (Friday) | process score, halt audit, skip-log review | 5-item score / 5 |
| Per payout cycle | rolling 50-trade expectancy (§6.2), payout request | decision: continue / cut / stop |
| Monthly | Monte Carlo re-run on the *live* expectancy | P(pass), EV, go/no-go |
| Quarterly | strategy review: retire/keep/tune; risk re-set | written decision |

The monthly Monte Carlo is the discipline that prevents the classic ending: a trader who
never re-measures keeps trading an dead edge at a size calibrated for a live one.

---

## 10. Kill criteria — when to stop, written in advance

A system without pre-committed exit conditions is a system that will be renegotiated in
the worst state of mind. Any one of these ends the current attempt:

1. Two consecutive failed phases with the same setup → return to demo, no third purchase.
2. A rule violation during a funded account → voluntary halt for a full cycle.
3. Rolling 100-trade expectancy < 0 → retire the setup.
4. Six months without a payout → stop funding attempts; the economics are not working.
5. Cumulative fees > 50% of cumulative payouts over 12 months → the model is not paying for
   itself; stop.
6. Any trade taken without a stop, or any size above the plan → immediate stop, full audit.

---

## 11. Journal schema (one row per trade)

```
date | symbol | session | htf_bias | setup | zone_id | entry | stop | target | lots
risk_$ | planned_R | exit | R_result | MAE_R | MFE_R | rule_broken(y/n) | exec_grade A-F
screenshot | note
```

Weekly aggregate: trades, win rate, avg win R, avg loss R, expectancy, PF, max DD,
violations, skips. Anything else is entertainment.

---

## 12. Summary — the ten decisions that constitute this system

1. Do not buy until the gate in §2 says GO. Most people fail this step.
2. Risk **0.5%** in evaluation, **0.4%** funded, off a **fixed** reference balance.
3. Stop at **2 losses or −2R** per day; stop the phase at **−7%**.
4. One trade = one known stop, attached with the entry. No stop, no trade.
5. Three correlated pairs = one bet. Cap the net.
6. Trade H1 bias + M15 trigger, in-session, news-flat, weekend-flat.
7. After 8% in Phase 1, cut to 0.1% and finish the 4-day minimum.
8. Funded: keep a **15% buffer**, withdraw only the excess, on schedule.
9. Re-measure expectancy every cycle; halve risk at the first sign of decay.
10. Grade execution, not P&L. Process first, size second, income third.

Everything above is arithmetic you can audit, run, and re-verify:

```bash
python3 -m unittest discover -s ftmo_engine/tests -t .   # 23 tests, all pass
python3 -m ftmo_engine.run_report                         # all tables in REPORT.md
```
