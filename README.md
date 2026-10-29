# kkk

Two pieces of work on trading systems:

## 1. FTMO operating system

A runnable, auditable model of the FTMO 2-step evaluation and funded account — rules,
position sizing, circuit breakers, payout policy, and Monte Carlo of pass/fail/EV — plus
the playbook a trader actually follows.

| File | What it is |
|---|---|
| [`FTMO_SYSTEM.md`](FTMO_SYSTEM.md) | the playbook: rule analysis, strategy spec, risk algorithm, psychology protocol, scaling, checklists |
| [`ftmo_engine/REPORT.md`](ftmo_engine/REPORT.md) | simulation results — pass rates, where failures come from, the payout-policy finding |
| [`ftmo_engine/`](ftmo_engine) | rules, sizing, daily guard, Monte Carlo, CLI (pure standard library) |
| [`mql/FTMO_Governor.mq4`](mql/FTMO_Governor.mq4) | in-terminal daily-budget supervisor |

```bash
python3 -m unittest discover -s ftmo_engine/tests -t .   # 22 tests
python3 -m ftmo_engine.run_report                         # regenerate REPORT.md (~1 min)
python3 -m ftmo_engine.cli size --balance 100000 --risk 0.5 --stop-pips 25
python3 -m ftmo_engine.cli gate --win-rate 0.45 --rr 1.8
python3 -m ftmo_engine.cli check --win-rate 0.45 --rr 1.8 --risk 0.5
```

No third-party dependencies. Requires Python 3.10+.

## 2. EA review

[`EA_Tesshinso_review.md`](EA_Tesshinso_review.md) — line-by-line review of the
"EA Tesshinso" MQL4 expert advisor, including the two defects that make it untestable
and non-functional as written.

## Other

`shorts/` holds an unrelated video-rendering script.
