# kkk

- [`mt4/`](mt4/) — **Market Structure Sync Scanner**, an MT4 indicator that
  scans all your pairs on Weekly, Daily and H4 and reports which ones have
  market structure in sync on all three (all HH+HL, or all LH+LL). It also
  grades and draws the Weekly/Daily **Area Of Interest** zones, and flags
  **entries on M15 / M30 / H1** while price sits inside one.
  See [`mt4/README.md`](mt4/README.md).
- `shorts/` — render kit for the short-form videos.

## Checks

```
python3 tools/test_core.py        # compiles + runs the structure engine (gcc)
python3 tools/mutate_check.py     # breaks FindAOI/EntrySignal 16 ways and requires the suite to catch each
python3 tools/lint_mq4.py         # static lint of the .mq4
python3 tools/check_mql4_api.py   # cross-checks MQL4 API names against real .mq4 sources
```
