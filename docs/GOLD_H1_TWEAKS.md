# GOLD H1 Tweaks — From Your Pasted Set → FTMO Safe

**You pasted:** ForexCracked GOLD H1 `Lot 0.02 / AutoLot / Martingale` with 4 optimization columns (`,F,1,2,3`).

**Problems for FTMO 10K+ (5% daily / 10% max):**
1. `StopLoss=1200 + Secondary 1500` = ~120-150 pips on GOLD = ~$14-$18 loss/trade at 0.02 lot. 4 losses = ~$64 = 0.64% DD — okay, but with `ReverseMartingale=1` (columns 2,3) and `LotIncrement=0.03` it martingales to 0.05→0.11→0.20 → 4th loss = $60+ alone → daily 5% breach.
2. `TakeProfit=4242 / ReverseTakeProfit2=423423` = 400+ pips — never hits on H1, you sit in DD until Friday.
3. `DisableTradingOnFriday=0` for main — but `=1` for 2,3 — means you hold GOLD over weekend gap risk (FTMO max loss killer).
4. `OnlyOneTradeAllowed` mixed 1/0 — hedging GOLD both ways doubles spread/loss.

### What was changed (why)

- **AutoLot 1 → 0:** Your 0.02→0.03→0.05 ladder is safer than `AutoLotStep=200` (which adds 0.01 per $200 profit = 50% lot jump after $200 → FTMO gambling flag).
- **LotIncrement 0.03 → 0.00:** Kills martingale. FTMO bans gambling patterns.
- **StopLoss 1200→600 / Secondary 1500→750 / TP 4242→900:** 600/900 = 1:1.5 RR, 60 pips SL = testable, 900 TP hits intraday on GOLD H1 (avg H1 range ~180-250 pips).
- **Trailing 1200→400, BreakEven 50→120:** 120 pips = GOLD's 1H noise floor — locks before reversal, old 50 pips was triggered by spread.
- **EnableReverseMartingale 0:** Column 2,3 had =1 with `ReverseMultiplier 1.3` → exponential loss.
- **DisableFriday 0→1:** All presets now close Friday — no weekend gap into FTMO max loss.
- **RSI 70/30 → 68/32:** GOLD false breaks 70 constantly — 68 filters.
- **ProfitThreshold 70%→55%:** Old 70% needed huge floating profit to close basket — never hit, DD grew.

### How to use

1. **10K FTMO:** Load `GOLD_H1_FTMO_TWEAKED.set` on **GOLD H1 only**. Keep `LotSize=0.02` → `0.03` after 3 good days → `0.05` max (same ladder you wanted for EURUSD). Test 2 weeks: you want Max Daily DD <2.5% in tester.
2. **If you want auto-scale after funded (50K+):** Change `AutoLot=1` + `AutoLotStep=10000` (0.01 per $10K profit = 0.1% risk).
3. **News:** Keep your 45m before / 30m after manual pause — GOLD is *worse* than EURUSD on USD CPI/NFP.

> **SECURITY:** You pasted an `sk-proj-...` API key. I removed it. **Revoke it immediately** at platform.openai.com → API Keys → Revoke. Anyone with it can bill you. Never paste keys in sets.

