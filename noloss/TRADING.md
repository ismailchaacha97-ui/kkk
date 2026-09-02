# Trading the Rule OP ladder

## Start here

I measured this system. Over 600 simulated $100 accounts it returned **−9.7%** of
capital, and **80% of those accounts never completed the run**. Those numbers are
in [`report.md`](report.md) and you can regenerate them yourself with
`python3 noloss_sim.py`.

There is no entry rule that fixes this, because there is no entry rule in the
system. It is pure position sizing, and after spread the expectation is negative.
Everything below is about **limiting what it costs you to find that out**, not
about making it work.

**Do not put money into this before you have run the check at the bottom of this
file on a demo account and read the answer yourself.**

---

## Install

1. Copy `RuleOP_Ladder.mq4` and `RuleOP_LadderEA.mq4` into
   `MQL4/Indicators/` and `MQL4/Experts/`.
2. Compile both in MetaEditor. **The EA has not been compiled by MetaEditor** —
   see "What is not verified" below.
3. Open a **demo** account. Attach the indicator first and just watch the ladder
   and the red kill-price line for a day before the EA trades anything.
4. Attach the EA. Enable algo trading.

## The settings that actually matter

Everything else is cosmetic. These four decide what you lose.

| input | default | what it does |
|---|---|---|
| `InpMaxDrawdownPct` | 15.0 | Equity this far below your **peak** → close everything and stop permanently. **This is the important one.** |
| `InpRiskCapital` | 100.0 | Absolute dollars you are willing to lose. The EA refuses to start if it is ≥ your balance. |
| `InpMaxDailyLossPct` | 10.0 | Same idea, measured from the start of the day. Stops for the day, not for good. |
| `InpMaxRungs` | 4 | Hard cap on ladder depth. |

Set `InpMaxDrawdownPct` to **10**, not 15. And set `InpRiskCapital` to the amount
you would genuinely shrug at losing — for most people that is far below the
account balance.

**The stop is worth more than the entire strategy.** I added the same equity stop
to the simulator and re-ran 1,500 accounts:

| config | capital returned | accounts blown up |
|---|---|---|
| no stop (as sold) | **−10.3%** | 19.4% |
| equity stop 25% | −3.4% | 0.0% |
| equity stop 15% | −2.3% | 0.0% |
| equity stop 10% | **−1.4%** | **0.0%** |

The tighter the stop, the less you lose, and no account gets liquidated. Note
what that means: the stop is doing more work than every entry, ladder and
multiplier decision combined. It is also still negative — a stop controls the
size of the loss, it cannot create an edge.

**Why `InpMaxRungs = 4`:** on a $100 account at 1:500 with a 30-pip step and a 2×
multiplier, rung 4 is the deepest one a broker will fund. Rung 5 needs $68.20 of
margin against $22 of equity. Letting the EA try for rung 5 means the order gets
rejected and you are left holding the first four rungs with no plan. Set the cap
at the depth you can actually afford, or lower.

**Why the drawdown is measured from the peak:** if it were measured from your
deposit, an account that grew to $200 could give all of it back before the stop
ever fired. There is a test for exactly this case.

## First run

```
InpOneCycleOnly = true
InpVerbose      = true
```

That trades a single ladder, closes it at the basket take profit, and stops.
Check the log in the Experts tab. If the log looks wrong, nothing is at risk.

## The check you should actually run

Not "did I make money this week." This:

1. Leave it on demo for **at least 100 completed cycles**. That is a few days,
   not an afternoon — fewer than that and you are reading noise.
2. Count the wins. It will be high, probably 90%+. That is real and it is not
   evidence of anything.
3. **Sum the P&L of every closed cycle.** Then add the drawdown you were sitting
   in at the worst point.

If the total is negative, the system does not work for you, and no combination of
take profit, step, multiplier or lot size will change the sign. That is the
martingale identity, and it is the same reason it failed in the simulation.

You can also run the numbers for *your* broker instead of mine: edit
`spread_pips` and `tick_sd_pips` in `noloss_sim.py` and re-run. A wider spread
makes it worse; a choppier market makes the tail fatter.

---

## What is not verified

`RuleOP_LadderEA.mq4` has **never been compiled by MetaEditor**. The indicator
took three rounds of compile errors to get through, all from MQL4 rules I could
not check from here, so assume the EA has some too.

What *is* verified is the decision logic. The `EA CORE` section is extracted and
compiled as C++17 by the same Makefile:

```
$ cd mt4 && make test
37 checks, 0 failures — ALL PASS     indicator, whole file against an MQL4 stub
45 checks, 0 failures — ALL PASS     EA core: breakers, ladder, lot sizing
53 checks, 0 failures — ALL PASS     ladder arithmetic, hand-derived values
$ make cross
all 12 rungs agree                   vs the Python simulator
```

That covers the circuit breakers, the basket close, the rung trigger, lot
normalisation and the spread filter. It does not cover `OrderSend`,
`OrderClose`, or anything else that talks to the terminal. **Test on demo.**

Writing the tests caught a real bug: `BasketShouldClose` compared the bid to the
basket take profit with `==`-style exactness, so floating-point residue in the
weighted average could leave a stack sitting on its own take profit, refusing to
close. It now allows a tolerance.
