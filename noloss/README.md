# The "No Loss" / Rule OP trading system — what it actually is

A worked lesson on the family of retail-forex systems sold as **"Rule OP No Loss"**,
built as a simulator you can run and break yourself.

```
python3 noloss/noloss_sim.py
```

Pure Python standard library. No pip install, no numpy, no internet. It writes
`report.md` plus four SVG charts next to itself.

---

## Important: your PDF did not arrive

The file `RULE OP NO LOSS TRADING SYSTEM.pdf` was attached to the message but never
landed in this workspace. I verified this rather than assuming it:

```
$ ls /home/user/uploads/
ls: cannot access '/home/user/uploads/': No such file or directory
$ find / -name "*.pdf" 2>/dev/null
(no output)
```

So **the specific numbers in your PDF are not reproduced here** — I have not seen
its take profit, its step size, its multiplier, or its entry filter. What I did
instead was find the same document circulating publicly (adoc.pub and pdfcoffee
both host it; both expose only its front matter, which is a sales page for
"Indo Forex Mentor", Rp 1.500.000, money-back guarantee), confirm from that what
genre of system it is, and then measure that genre properly.

**Re-attach the PDF, or paste its rule list, and I will re-run this with its exact
parameters.** The simulator takes them as plain numbers:

```python
Params(balance=..., base_lot=..., tp_pips=..., step_pips=..., multiplier=..., spread_pips=...)
```

---

## Lesson 1 — the ladder is arithmetic, not opinion

Before any simulation, just multiply it out. `$100 account, 0.01 lot, 30-pip step,
2x multiplier, EURUSD pip value $10 per lot`:

| rung | lot | adverse move | floating loss |
|---|---|---|---|
| 1 | 0.01 | 0 pips | $0 |
| 3 | 0.04 | 60 pips | $24 |
| 5 | 0.16 | 120 pips | $192 |
| 7 | 0.64 | 180 pips | $1,152 |
| 10 | 5.12 | 270 pips | $13,824 |

Rung 10 demands $13,824 of margin on a $100 account. No setting of that account
ever reaches rung 10 — it dies around rung 5 or 6. That single row is the entire
strategy, and it needed no simulation to find.

## Lesson 2 — the "no loss" claim is literally true, and that is the trap

This is the part nobody selling it explains, and it is why the marketing works.

The basket take profit sits at the **average** entry of the whole stack. So the
instant price reaches it, the entire stack is in profit by
`total lot × TP × pip value`. Measured over **7,262 closed cycles** in the sim:

| ladder depth | share of cycles | payout | smallest P&L seen |
|---|---|---|---|
| 1 rung | 60.5% | $2 | **$2.00** |
| 3 rungs | 10.2% | $14 | **$14.00** |
| 5 rungs | 1.7% | $62 | **$62.02** |

**Not one closed cycle lost money.** If you judge the system per closed trade, it
really is a no-loss system. If you judge it per account, **77% of the $100
accounts in that run were stopped out** and never got to close one.

The system does not remove losses. It moves them out of the per-trade column and
into a single balance-sheet event.

## Lesson 3 — why the big wins are not skill

Payout per closed cycle is `base_lot × (2ⁿ − 1) × TP` — geometric in ladder depth.
The probability of *reaching* a deep rung falls at roughly the same rate. Those
two curves cancel. That is the martingale identity, and no combination of TP,
step, multiplier or indicator escapes it.

The simulation confirms it: with the spread switched off the grid returns
**−3.4%** of capital over 1,500 accounts — statistically indistinguishable from
zero given how fat the tail is. Turn the spread back on and it is **−11.1%**.
**Costs are what convert a zero-expectation game into a losing one.**

## Lesson 4 — the "hedge lock" makes it worse, and not because of spread

I first assumed the hedge variant lost more because it pays the spread twice.
**That was wrong.** At zero spread the grid returns −3.4% and the hedge −14.6%.

The real mechanism: when the winning hedge leg banks its profit, the surviving
losing leg was entered at the *hedge* price, but the position only closes at
`average entry + TP`. The survivor is one TP distance behind before it even
starts, so it needs a deeper ladder:

| ladder depth | grid | hedge |
|---|---|---|
| 1 rung | 60.5% | 16.9% |
| 3+ rungs | 17.3% | **35.6%** |

Deeper ladders *are* the tail risk. The "safety lock" you were sold buys you
twice as much of it.

## Lesson 5 — "just use a smaller lot"

| base lot | accounts blown up | capital returned | deepest rung |
|---|---|---|---|
| 0.01 | 77.9% | −11.3% | 6 |
| 0.005 | 63.2% | −7.0% | 7 |
| 0.002 | 45.5% | −6.0% | 8 |
| 0.001 | 33.7% | −6.7% | 9 |

Shrinking the lot genuinely reduces the blow-up rate — it is the only honest
lever in the whole system. But capital returned stays negative in **every** row
(it isn't even monotonic; at this sample size the tail noise is that big), and
the deepest rung reached climbs from 6 to 9 as the lot shrinks. You are buying
survival, not profit.

---

## Files

| file | what it is |
|---|---|
| `noloss_sim.py` | the simulator. Start here. |
| `report.md` | every number above, regenerated from source on each run |
| `equity_grid.svg`, `equity_hedge.svg` | five account equity curves each |
| `rungs_grid.svg`, `rungs_hedge.svg` | histogram of deepest ladder rung reached |

## Things worth trying

Change these in `Params` at the top of `noloss_sim.py` and re-run:

- `multiplier = 1.5` — the ladder grows slower, so you survive longer, so each
  blow-up is *bigger*. Watch the total stay negative.
- `tp_pips = 5` with `step_pips = 60` — a very high win rate. Watch what it does
  to the tail.
- `swap_per_lot_per_tick = 0.5` — turns on overnight financing, the real cost of
  holding a losing stack for days.
- `tick_sd_pips = 8` — a news day. This is what kills these accounts in one move.

Then ask yourself the only question that matters: **which of those settings
changed the sign of the total, and which only changed how fast you got there?**
