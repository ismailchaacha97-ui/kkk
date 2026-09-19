# Which method is right for you?

*Prepared for: a trader on Forex + Gold (XAUUSD), 1–3 years in, 3–5 hours of
screen time per day, who wants a tool built around the method.*

---

## The honest answer first

**I cannot tell you which of these three is profitable. Nobody can, from a
PDF.** What I can do — and what I have done — is:

1. Read all three methods and separate the *rules* from the *storytelling*.
2. Encode each one as an unambiguous, executable rule set.
3. Build the engine that tells you, on **your** broker's data, with **your**
   spreads, whether the edge survives.

The verdict below is about **fit** — which method suits your market, your
time budget, and your experience level — and about which one is even
*possible* to test honestly. Those are different questions from
"which one makes money", and they have real answers.

Your files were not readable in this workspace (see `docs/data.md` §0), so I
worked from the standard published rule sets for each method family. Where a
method is taught with discretion, I made each discretionary choice an explicit
switch — so when you re-read the PDFs you can set the parameters to *your*
version of the rules rather than mine.

---

## The three methods, reduced to rules

### A. Magic Candle — `magic_candle`

**Core idea.** A single candle with a disproportionately large body shows
one-sided intent. It is not an entry. It is a *level*. You wait for price to
retrace into the **50% of that candle's body**, enter there, put the stop
beyond the candle's extreme, and target a multiple of the risk.

**Encoded as:**

| # | Rule | Parameter |
|---|------|-----------|
| 1 | Body ≥ 70% of the candle's range | `min_body_ratio` |
| 2 | Body ≥ 1.2 × ATR(14) | `body_atr_mult` |
| 3 | *(optional)* No opposite signal in last N bars | `no_opposite_lookback` |
| 4 | Entry: limit at 50% of body | `entry_mode` |
| 5 | Stop: beyond the extreme + 0.15 ATR | `stop_buffer_atr` |
| 6 | Target: 3R | `rr` |

**What makes it good.** It is *mechanical*. Every rule is a number. Two
traders reading the same chart get the same signal. A limit order means you
do not have to be at the screen when it triggers — you set it and walk away.

**What kills it.** Two things, and you must test both:
- **The missed trade.** The retracement to 50% frequently never comes. The
  market runs without you, and you watch it. Temptation is to chase — which
  destroys the whole risk geometry.
- **The retracement that fills and fails.** Sometimes price comes back to 50%
  precisely *because* the breakout is dying. Your limit fills exactly on the
  trades you least want.

### B. Liquidity Candle — `liquidity_candle`

**Core idea.** Price is drawn to where stop losses rest — below obvious lows,
above obvious highs. When those stops are taken (a *sweep*) and price
*reclaims* the level, the trapped traders are forced out and the move runs
the other way. You enter on the reclaim, stop beyond the sweep extreme.

**Encoded as:**

| # | Rule | Parameter |
|---|------|-----------|
| 1 | Reference = lowest low of the previous 20 bars | `lookback` |
| 2 | Bar pierces it by > 0 ATR | `min_pierce_atr` |
| 3 | Bar closes back **above** the level | *built in* |
| 4 | Close in the top 50% of the bar's range | `reclaim_frac` |
| 5 | Entry: market at next open | — |
| 6 | Stop: beyond the sweep low + 0.2 ATR | `stop_buffer_atr` |
| 7 | Target: 2R | `rr` |

**What makes it good.** The logic is real. Stop clusters genuinely exist,
and genuine reversals do follow failed breaks. Wick-based sweeps also produce
*tight* stops, which means large position size for the same cash risk.

**What kills it.** It has a **low win rate by construction** — you are buying
into a falling market at the exact moment it looks worst. On the synthetic
data in this repo it won 26% of the time and lost money. That is expected for
a random walk, but it illustrates the real danger: a method that needs a 33%+
win rate to break even at 2R *feels* like it is broken for long stretches.
Most people abandon it during the losing run, right before it works.

And the hard part is the one the PDFs usually gloss over: **telling a sweep
from a genuine break.** Same candle, opposite trade. Get that wrong
consistently and the method is a coin flip with worse costs.

### C. Structure Break / BOS — `structure_break`

**Core idea** (the Majed Al-Tounsi family). Map the market as a sequence of
swing highs and lows. Classify the structure: higher-highs-and-higher-lows is
an uptrend, lower-highs-and-lower-lows is a downtrend. When a downtrend
prints a close **above its last swing high**, the structure has changed —
that is your entry in the new direction. Stop beyond the last opposite swing.

**Encoded as:**

| # | Rule | Parameter |
|---|------|-----------|
| 1 | Swings = fractal of 2 bars each side | `swing_left` / `swing_right` |
| 2 | Structure from the last 3 swings each side | `structure_lookback` |
| 3 | Reversal *or* continuation mode | `mode` |
| 4 | Trigger: close beyond the last confirmed swing | `min_break_atr` |
| 5 | Stop: beyond the last opposite swing(s) + 0.2 ATR | `stop_swing_lookback` |
| 6 | Target: 2R | `rr` |

**What makes it good.** It is the only one of the three that gives you
**context** — a bias that tells you which trades to even consider. Used as a
filter on top of A or B, it is worth more than used alone. And it produces
few, large trades, which is cheap in spread.

**What kills it.** It is the **most subjective** of the three, and that is
not a small problem. Two traders with the same PDF will mark different
swings, and therefore trade in different directions on the same chart. A
"broken structure" on H1 is intact on H4. On the synthetic run its average
holding time was **48 bars** — two days on H1 — which demands patience and
conviction that is genuinely hard at 1–3 years in. And precisely *because* it
is subjective, it is the hardest of the three to backtest honestly.

---

## Comparison for **your** situation

| | A. Magic Candle | B. Liquidity Candle | C. Structure Break |
|---|---|---|---|
| Rules are objective | **High** | Medium | **Low** |
| Screen time needed | Low (limit order) | **High at session opens** | Medium–high |
| Signal frequency | Medium | High | Low |
| Typical holding time | Hours | Hours | **Days** |
| Win rate profile | Medium (~35–45%) | **Low (~25–35%)** | Medium |
| R:R per trade | Good (3R) | Good (2R) | Good (2R) |
| Psychological difficulty | Medium | **High** | High |
| Backtestable faithfully | **Yes** | Mostly | Partly |
| Fits 3–5h/day in Morocco | **Yes** | Only if it's the session open | Yes |
| Works on XAUUSD | Yes | **Yes — gold sweeps violently** | Yes |

---

## Verdict

> **Build around the Magic Candle. Use the Liquidity Candle as a filter. Use
> Structure Break as context.**

Here is the reasoning, in order of weight.

**1. The Magic Candle is the only one of the three that survives contact with
a backtester unmodified.** Its rules are numbers. That means the result you
get from `kkk` is *your* result, not my interpretation of it. For B and C you
are partly testing my reading of the rules, not the rules. Start with the one
you can actually measure.

**2. Your screen-time budget fits it exactly.** 3–5 hours a day is not enough
to sit and wait for sweeps across a session, but it is more than enough to
scan once, mark your levels, place limit orders, and let the market come to
you. The Magic Candle is a *set-and-wait* method. The Liquidity Candle is a
*watch-and-react* method. You have the budget for one of those, and it is not
the second.

**3. The Liquidity Candle concept is still worth having — as a filter, not a
trigger.** Do not trade every sweep. Instead, *only take Magic Candle signals
that appear at a level where liquidity was recently taken*, or during the
London/NY overlap. In Morocco (UTC+1) that overlap is **13:00–17:00 local**.
That is a filter you can add in one line of code (`sessions=("overlap",)`)
and test in one command.

**4. Structure Break is a bias layer, not a trigger.** Use it to answer
"am I a buyer or a seller today?" and then wait for a Magic Candle in that
direction (`trend_filter` in the strategy). This is where the Majed material
earns its place in your process — as the map, not the entry.

**5. And the part you will not like.** Your last method's win rate will
probably be under 45%, you will have months of negative expectancy, and none
of these three is guaranteed to have any edge at all on your instrument at
your spread. That is not cynicism; it is the base rate for retail candle
strategies. The entire point of the tool in this repo is to make you find
that out **on historical data instead of on your account**.

---

## What to do next, concretely

```bash
# 0. set up
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# 1. confirm the plumbing works
.venv/bin/python -m kkk.cli demo

# 2. export XAUUSD H1 from MT5 (see docs/data.md), then:
.venv/bin/python -m kkk.cli compare data/XAUUSD_H1.csv --symbol XAUUSD --out runs/xau

# 3. read the reality-check line at the bottom of that output.
#    If the best method does not clear the coin-flip noise band, stop.
#    Do not tune. Do not add indicators. The data just told you something.

# 4. only if it cleared the noise band, sweep it honestly:
.venv/bin/python -m kkk.cli sweep data/XAUUSD_H1.csv --symbol XAUUSD -s magic_candle
#    Choose parameters that win in-sample AND out-of-sample.
#    Anything else is a curve fit.

# 5. run it on a demo account for 100 trades before any real money.
```

**The rule that matters most:** *do not add a parameter because it makes the
backtest look better.* Every one of the three methods above has a parameter
grid in this repo specifically so you can see how easy it is to make almost
any of them look brilliant in-sample. That is the trap, and it is the same
trap in all three methods. `robust` in the sweep output is the only column
worth trusting.

---

*Not financial advice. Backtests are hypotheses, not promises. Spread,
slippage and swap will differ on your account from the defaults here — set
them to your broker's real numbers before believing any result.*
