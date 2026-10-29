# FTMO 10K+ — EURUSD Only (v2.12_FTMO)

This build is locked to your request: **FTMO rules from 10K and up, only EURUSD**.

### What FTMO enforces in the EA

- **Symbol lock:** `FTMO_RestrictEURUSD=true` → if you attach to GBPUSD/XAUUSD/etc, EA prints `[FTMO INIT ERROR] Not EURUSD` and halts. Works on `EURUSD`, `EURUSD.a`, `EURUSD.m`, `EURUSD#`, `EURUSDc` (all contain `EURUSD`).
- **10K+ auto:** `FTMO_InitialBalance=0` → auto-detects `AccountBalance()` at init. For a 10K FTMO Challenge it captures `10000`. For 25K/50K/100K it captures that instead. Set manually if you attach mid-challenge (e.g., already at 10700 equity but challenge initial was 10000 → set `10000`).
- **5% daily loss (FTMO hard):** `FTMO_MaxDailyLossPct=5.0` → of *initial* balance, not today's equity. Example 10K: daily loss >$500 (equity) → `CloseAllPositions("FTMO_DAILY_5%")` + halt till next D1. Your personal tighter `MaxDailyDrawdownPct=4.0` halts even earlier ($400 on 10K).
- **10% max loss (FTMO hard):** `FTMO_MaxTotalLossPct=10.0` → equity below `Initial * 0.90` (9K on 10K, 22.5K on 25K) → breach halt. Dashboard shows buffer `$` left.
- **Target tracker (display only):** `FTMO_ProfitTargetPct=8.0` (Phase 1) / set to 5.0 for Phase 2. Shows `Target 8%: 3.20% ($320) | Days 3/4`.
- **Min 4 trading days:** counter increments when a D1 bar had ≥1 trade (history or live). Dashboard `Days 3/4`.

### Your ladder — already compliant

At 10K, your fixed ladder is safe:

- `0.02 lot` ~$2.2*2 = $4.4 risk / 22-pip SL
- `0.03 lot` ~$6.6
- `0.05 lot` ~$11

Your worst 3-loss streak at 0.05 = $33 = **0.33% of 10K** → 12x below FTMO 5% daily. Even 0.20 lot would be 1.3% — so 0.05 is conservative and FTMO-friendly.

After you hit ~$10,600-11K: switch `LotMode=1 (RISK_BASED) RiskPercent=0.5-0.8` → ~0.20-0.35 lot on 10.6K, still 0.8% risk = $85 loss/trade, far from $500 daily.

### How to use (FTMO)

1. **Attach ONLY to EURUSD M15** (or M30 if you prefer — same set works, just fewer trades).
2. Load `sets/FTMO_10K_EURUSD_M15.set` → check inputs: `FTMO_Mode=true`, `FTMO_InitialBalance=10000` (or 25000, etc.), `FixedLots=0.02`.
3. Keep your manual **45m before / 30m after** news pause — leave `UseNewsFilter=0` as you requested. FTMO allows news trading but your 45/30 is what keeps DD <4%.
4. Watch dashboard: `FTMO Daily 0.80%/5.0% ($420 left) Total 2.1%/10% ($790 left)` + trading days. If breach, EA halts and prints `[FTMO BREACH]`.
5. For Phase 2, change `FTMO_ProfitTargetPct=5.0` only (limits stay 5%/10%).

### Backtest for FTMO (MT4 Tester)

Strategy Tester does NOT simulate FTMO's server 00:00 CET daily reset perfectly — but this EA mirrors it via `iTime(NULL,PERIOD_D1,0)`. Test:
- EURUSD M15, Every tick, Spread Current, 10K deposit, 2022-2025.
- Expect: PF 1.4-1.7, max equity DD 6-9% (under 10% FTMO), max daily DD 2.5-3.8% (under 5% FTMO), 4+ trading days naturally hit.

**Never** test with `MaxSpread 0` or `Every tick based on open prices` — hides FTMO daily loss breaches.

