# H.I.E.P. — Entry Protocol

A one-page operating procedure. Print it, or keep it next to the chart.

**The single most important rule:** an entry exists only at the **close of a signal bar**. Intrabar
movement is noise; this tool deliberately does not signal on it. If you find yourself entering
because "it looks like it's about to sweep", you are not trading this system — you are trading your
impatience.

---

## 1. The two states of the chart

| State | What you see | What you do |
|---|---|---|
| **Armed** | `WATCH  LIQUIDITY TAKEN BELOW - WATCH RECLAIM` (or ABOVE) | Nothing yet. Pay attention. |
| **Triggered** | Arrow + `BUY 82` / `SELL 71` label on a **closed** bar, plus an alert | Run the 6 checks below |
| **Neither** | `WATCH  no live sweep` | Nothing. Close the chart. |

`WATCH` means a stop hunt is in progress. It is a **heads-up, not an entry** — many sweeps produce
no signal, because a signal also requires a reclaim, a zone, structure and score. Expect roughly
one signal for every six or seven sweeps.

---

## 2. The six checks (30 seconds, in this order)

Run these against the panel. Any single failure = no trade, no exceptions, no "but this one looks
strong".

| # | Check | Pass condition | Where it is |
|---|---|---|---|
| 1 | **Prop guard** | `PROP GUARD  GREEN` — not `AMBER - FILTERED`, not `LOCKED - DAILY CAP` | panel, last lines |
| 2 | **Session** | `SESSION  LONDON` or `NEW YORK`, suffix `OPEN` | panel |
| 3 | **Spread** | `SPREAD ... OK` | panel |
| 4 | **Score** | `82` / `71` — at least your `InpMinScore` (default 68) | label next to the arrow, and `LAST BUY/SELL` line |
| 5 | **Confluence** | `HTF BIAS` not opposed to the signal, and `STRUCTURE` agrees or is flat | panel |
| 6 | **Payoff** | distance to TP >= 1.5 x distance to SL; SL not further than ~3 x ATR | panel `E` / `SL` / `TP` lines |

Check 6 is arithmetic you can do in five seconds:

```
risk   = |entry - SL|
reward = |TP - entry|
trade only if reward / risk >= 1.5
```

If the panel shows a TP so close that the reward is under 1.5R, the engine already rejected those
cases — but always confirm, because your fill will differ from the reference close.

---

## 3. Executing the entry

Three legitimate ways, in order of what I recommend for a prop challenge.

**A. Market at the bar close (recommended).** The alert fires when the signal bar closes; enter at
market on the next tick with the panel's SL/TP and the suggested lot. You are trading exactly what
was tested. Cost: your fill is a few points worse than the reference close.

**B. Limit at the zone mean (better price, can miss).** Place a limit order at the dotted
mean-threshold line of the order block (the 50% level). Better R, but price does not always return —
roughly a third of signals never fill, and the ones that do are often the weaker ones because they
needed a deeper pullback. Do not use this until you have 30+ logged trades on method A.

**C. Next-bar confirmation (safest, worst price).** Wait for the bar after the signal to close in
the same direction, then enter. Filters out signals that immediately reverse, but you give up part
of the move and your R:R drops. Useful only if your journal shows signal bars that frequently fail
on the very next bar.

**What not to do:** do not enter before the bar closes, do not enter after price has already run
more than ~1 ATR from the signal close (your stop becomes the cap and R:R collapses), and do not
"add" to a losing position.

---

## 4. Hard "no trade" list

Skip the signal — regardless of score — when:

- A **red-folder news event** for that currency is within 15 minutes (add the hour to
  `InpBlackoutHours` if it recurs).
- The signal is the **4th of the day**, or you already took two losses today.
- **Spread spiked** (rollover, illiquid Asian session on a minor pair).
- Price is already **past the TP level** by the time you look — the move happened, you missed it.
- You are **not at the screen** to place SL/TP immediately. A naked entry is not a trade.
- You feel the need to **lower `InpMinScore`** to justify this specific trade. That is the system
  telling you there is no setup.

---

## 5. Worked example

Panel and chart show:

```
STRUCTURE   BULLISH (HH/HL)
HTF BIAS    H4 BULL
SESSION     LONDON  OPEN
SPREAD      12 pts  OK
ATR(14)     0.00184
VOLUME      1.41x avg
SIGNALS     1 / 4 today
LAST BUY   14:00  82
 E 1.08420  SL 1.08260
 TP 1.08790
 LOT 0.42  (risk 1.0%)
PROP GUARD  GREEN
LAST SWEEP  LOW 1.08275 (1 bars ago)
```

1. Guard green, London open, spread 12 — checks 1–3 pass.
2. Score 82 (>= 68), arrow on a closed H1 bar — check 4 passes.
3. Structure bullish, H4 bullish, volume 1.41x — check 5 passes.
4. Risk = 1.08420 − 1.08260 = **16.0 pips**. Reward = 1.08790 − 1.08420 = **37.0 pips**.
   R:R = 2.31 — check 6 passes.
5. Enter at market, 0.42 lot, stop 1.08260, target 1.08790. Do not move the stop.

If instead the TP had been 1.08500, reward = 8 pips against 16 risk = 0.5R: **no trade**, even though
the arrow is there.

---

## 6. After you are in

- **The stop does not move against you.** Ever.
- **Move to breakeven only after price closes beyond 1R** — earlier and normal pullbacks stop you
  out of the exact trades this system is designed to catch.
- **Partial at the next opposing liquidity line** is acceptable; the engine's TP already targets it.
- **One trade per signal.** A stop-out is information, not an invitation to re-enter.
- If a new opposite signal appears, **do not flip immediately** — close the first trade and wait for
  the next closed bar.

The indicator does not manage positions. That is your job, and it is the part that decides whether
the challenge is passed.

---

## 7. The journal is the actual edge

Log every signal, taken or skipped:

```
date | symbol | dir | score | entry | SL | TP | took? | why skipped | result (R) | session | news?
```

After 30 trades, compute:

- **Win rate** and **average R** — expectancy = (win% x avgWin) − (loss% x avgLoss).
- **Score vs. outcome** — if your sub-75 signals lose and your 80+ signals win, raise `InpMinScore`.
- **Session vs. outcome** — if New York loses and London wins, shrink the New York window.
- **Skipped signals** — if the ones you skipped outperformed the ones you took, you are filtering
  for the wrong reason (usually fear, not logic).

Two to five trades a month per instrument is normal on H1. Judge the system after 30 trades, not
after 3. A 2R system that wins 45% of the time is profitable; do not abandon it during the losing
streak that any such system must produce.
