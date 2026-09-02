# The "No Loss" / Rule OP trading system — what it actually is

A worked lesson on the family of retail-forex systems sold as **"Rule OP No Loss"**,
built as a simulator and an MT4 indicator you can run and break yourself.

```
python3 noloss/noloss_sim.py      # regenerates report.md + charts
cd mt4 && make test               # unit tests on the indicator's math core
cd mt4 && make cross              # cross-checks the C++ core vs the Python sim
```

The Python side is pure standard library — no pip install, no numpy. The C++ side
needs only `g++` and `make`.

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
both host it; both expose only its front matter, a sales page for "Indo Forex
Mentor", Rp 1.500.000, money-back guarantee), confirm from that what genre of
system it is, and then measure that genre properly.

**Re-attach the PDF, or paste its rule list, and I will re-run this with its exact
parameters.** They are plain numbers in two places:
`Params(...)` in `noloss/noloss_sim.py`, and the indicator inputs at the top of
`mt4/RuleOP_Ladder.mq4`.

---

## Lesson 1 — the ladder is arithmetic, not opinion

`$100 account, 0.01 lot, 30-pip step, 2x multiplier, 20-pip TP, 1:500, 50% stop out`:

| rung | cum lot | adverse | loss on newest rung | **stack floating loss** | basket TP payout | margin |
|---|---|---|---|---|---|---|
| 1 | 0.01 | 0 pips | $0 | **−$0** | $2 | $2 |
| 3 | 0.07 | 60 pips | $24 | **−$12** | $14 | $15 |
| 5 | 0.31 | 120 pips | $192 | **−$78** | $62 | $68 |
| 6 | 0.63 | 150 pips | $480 | **−$171** | $126 | $139 |
| 10 | 10.23 | 270 pips | $13,824 | **−$3,039** | $2,046 | $2,251 |

**Look hard at the two loss columns.** "Loss on newest rung" is what Rule-OP
write-ups show you: the damage done by the position you just added, on its own.
"Stack floating loss" is what your equity actually reads. By rung 6 the number you
were shown is $480 and the real number is $171 — different, and only the second one
can stop you out. Conflating them is exactly what makes these systems feel
survivable.

With those settings the deepest rung you can open is **rung 4** — just 90 pips of
adverse move. Rung 5 is the killer.

## Lesson 2 — the "no loss" claim is literally true, and that is the trap

The basket take profit sits at the **average** entry of the whole stack. So the
instant price reaches it, the entire stack is in profit by
`total lot × TP × pip value`. Measured over **6,861 closed cycles**:

| ladder depth | share of cycles | payout | smallest P&L seen |
|---|---|---|---|
| 1 rung | 60.9% | $2 | **$2.00** |
| 3 rungs | 10.3% | $14 | **$14.00** |
| 5 rungs | 1.3% | $62 | **$62.02** |

**Not one closed cycle lost money.** Judged per closed trade, it really is a no-loss
system. Judged per account, roughly **80% never got to finish one**.

The system does not remove losses. It moves them out of the per-trade column and
into a single balance-sheet event.

## Lesson 3 — there are two ways it fails, and only one is dramatic

Once the simulator checks **free margin** the way a real broker does — refusing the
order instead of letting you fund a rung you cannot afford — the failure splits:

| outcome | grid | hedge |
|---|---|---|
| broker refused the next rung (margin-blocked) | **60.2%** | 62.0% |
| equity hit the stop-out level (blown up) | 20.0% | 21.0% |

Most of the time the account is not vaporised by one violent candle. It simply runs
out of room: the ladder cannot fund its next rung, the stack sits there, and the
stop-out level eventually collects it. Either way the run is over.

## Lesson 4 — why the big wins are not skill

Payout per closed cycle is `base_lot × (2ⁿ − 1) × TP` — geometric in ladder depth.
The probability of *reaching* a deep rung falls at roughly the same rate. Those two
curves cancel. That is the martingale identity, and no combination of TP, step,
multiplier or indicator escapes it.

The simulation confirms it: with the spread switched off the grid returns **−5.7%**
of capital over 1,500 accounts — close enough to zero that the fat tail explains the
gap. Turn the spread back on and it is **−10.3%**. **Costs are what convert a
zero-expectation game into a losing one.**

## Lesson 5 — the "hedge lock" makes it worse, and not because of spread

I first assumed the hedge variant lost more because it pays the spread twice.
**That was wrong.** At zero spread: grid −5.7%, hedge −14.7%.

The real mechanism: when the winning hedge leg banks its profit, the surviving
losing leg was entered at the *hedge* price, but the position only closes at
`average entry + TP`. The survivor is one TP distance behind before it even starts,
so it needs a deeper ladder:

| ladder depth | grid | hedge |
|---|---|---|
| 1 rung | 60.9% | 17.2% |
| 3+ rungs | 16.9% | **35.1%** |

Deeper ladders *are* the tail risk. The "safety lock" you were sold buys you twice
as much of it.

## Lesson 6 — "just use a smaller lot" does not do what you think

This is the finding that surprised me, and it survived a re-run at n=4000 (±1.4%):

| base lot | stopped out | margin-blocked | **failed either way** | capital |
|---|---|---|---|---|
| 0.01 | 19.4% | 60.7% | **80.0%** | −8.9% |
| 0.005 | 26.5% | 39.0% | **65.5%** | −6.7% |
| 0.002 | 9.1% | 39.6% | **48.7%** | −5.9% |
| 0.001 | 2.2% | 31.8% | **34.1%** | −3.5% |

Shrinking the lot **does** cut the overall failure rate — 80% down to 34%. I
expected it not to, so I checked at higher sample size, and it holds.

But read *which* failure it removes. Almost all of the improvement is in the
margin-blocked column (60.7% → 31.8%), because a small lot can actually fund a
full ladder. The **stopped-out** column — the catastrophic one — does not fall
cleanly. It *rises* first, 19.4% → 26.5%, before collapsing at the very smallest
size.

So a smaller lot buys you a longer life with more green days, and shifts the way it
ends from a quiet margin refusal toward a violent stop-out. Capital returned stays
negative in every row. You are not buying an edge. You are buying time.

---

## The MT4 indicator

`mt4/RuleOP_Ladder.mq4` draws the ladder on your chart. It **does not trade** —
an MQL4 indicator cannot place orders, and you should want it that way. It shows
you:

- every rung, with its lot size, blue if you can afford it, red if you cannot
- the **average entry**, which walks toward the market each time a rung is added
- the **basket take profit**, with the exact dollar payout it would book
- the **kill price** in red — where the broker stops this account out
- the deepest rung your balance can actually open
- alerts when price reaches the next rung, or enters the kill zone

Copy it into `MQL4/Indicators/`, compile in MetaEditor, drop it on a chart. In
preview mode it draws the ladder from the current Bid. Set `InpMagic` to your EA's
magic number and it will adopt your **real** open positions instead.

### How the math is tested without MetaEditor

There is no MetaEditor in this sandbox, so I could not compile the indicator. What
I did instead is compile it two different ways with g++:

```
$ cd mt4 && make test
extracted 180 lines of core from RuleOP_Ladder.mq4
generated ind_under_test.inc (#property stripped, OnCalculate signature aliased)
37 checks, 0 failures — ALL PASS      <- the whole file, against an MQL4 API stub
53 checks, 0 failures — ALL PASS      <- the core, against hand-derived values
```

- **`test_ladder`** — the ladder arithmetic between `CORE BEGIN` / `CORE END`,
  written to be valid both as MQL4 and as C++17. 53 assertions with expected
  values derived by hand, not read back off the code.
- **`test_api`** — the *entire* file, core and drawing half, compiled against a
  stub MQL4 API (`mql4_api_stub.h`). It drives `OnInit`, `OnCalculate`,
  `OnDeinit` and `LiveAnchor` and asserts on the objects actually drawn: rung
  prices, average entry, basket TP, kill price, and which rungs are coloured
  unaffordable.

`make cross` then checks the C++ core against the Python simulator: all 12 rungs
agree on cumulative lot and basket take profit.

**This caught five real bugs**, which is the reason to bother:

1. `TickValue` / `TickSize` are not predefined variables in MQL4 — they have to
   come from `MarketInfo()`. Two hard compile errors.
2. **Structs cannot be passed by value in MQL4 at all.** My first fix removed
   `const` and left them by value, which produced the *same* error with different
   wording. The real fix is `const LadderSpec &s`, chosen by an object-like macro
   so one source serves both languages. `MakeSpec` and `MakeAccount` also had to
   stop returning structs by value.
3. `LiveAnchor` picked rung 1 as the **lowest** buy entry. In an averaging-down
   ladder rung 1 is the *first* position — the **highest** buy. The indicator was
   drawing the entire ladder from the wrong end.
4. A `"literal" + "literal"` concatenation, which is pointer arithmetic rather
   than string building.
5. Nothing above would have been caught by the original test setup, because g++
   happily accepts a by-value struct. In reference mode the structs now inherit a
   deleted copy constructor, so a by-value parameter is a compile error *here*
   too. Verified by reintroducing bug 2 on purpose: the build fails with 8
   errors; revert it and both suites pass again.

I also dropped the function-like macros (`NOLOSS_SPEC(T, name)`) in favour of
object-like ones. MQL4's preprocessor is documented for object-like macros only,
and I am not going to bet your compile on an undocumented feature.

**What is still not verified:** that MetaEditor itself accepts the file. The stub
is not the real compiler, and MQL4 has rules g++ does not model — bug 2 proves
that twice over. If it errors again, paste the messages and I will fix them.

## Files

| file | what it is |
|---|---|
| `noloss/noloss_sim.py` | the Monte Carlo simulator |
| `noloss/report.md` | every number above, regenerated from source on each run |
| `noloss/equity_*.svg`, `noloss/rungs_*.svg` | equity curves and ladder-depth histograms |
| `mt4/RuleOP_Ladder.mq4` | the indicator |
| `mt4/test_ladder.cpp` | 53 assertions on the core, hand-derived expected values |
| `mt4/crosscheck.py` | C++ core vs Python simulator |
| `mt4/Makefile` | `test`, `cross`, `clean` |

## Things worth trying

Change these in `Params` and re-run:

- `multiplier = 1.5` — the ladder grows slower, so you survive longer, so each
  blow-up is bigger. Watch the total stay negative.
- `tp_pips = 5` with `step_pips = 60` — a very high win rate. Watch the tail.
- `swap_per_lot_per_tick = 0.5` — overnight financing, the real cost of holding a
  losing stack for days.
- `tick_sd_pips = 8` — a news day. Blow-up rate goes from ~79% to ~98%.

Then ask the only question that matters: **which of those settings changed the sign
of the total, and which only changed how fast you got there?**
