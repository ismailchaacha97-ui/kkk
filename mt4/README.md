# RuleOP_Ladder — MT4 indicator

Draws a Rule OP / "no loss" grid + martingale ladder on your chart, including the
price at which your account gets stopped out. It does not trade.

Install: copy `RuleOP_Ladder.mq4` into `MQL4/Indicators/`, compile in MetaEditor,
drop it on a chart.

Full write-up, including how the math is tested without MetaEditor and what the
system actually does to an account: [`../noloss/README.md`](../noloss/README.md).

## Tests

```
make test    # 37 checks on the whole file via an MQL4 API stub,
             # + 53 checks on the ladder arithmetic with hand-derived values
make cross   # cross-check the C++ core against the Python simulator
make clean
```

`core_under_test.inc`, `ind_under_test.inc`, `test_ladder` and `test_api` are
generated — do not edit them, and they are gitignored.

**MetaEditor is not available in this sandbox, so these tests do not prove
MetaEditor will compile the file.** They do prove the logic is correct and that
the whole file is syntactically valid C++.
