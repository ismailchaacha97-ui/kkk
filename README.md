# kkk

## MT4 — Supply & Demand: BOS + Fresh Retest + LTF Confirmation

مؤشر MetaTrader 4 يطبّق منطق "لا تدخل مباشرة عند وصول السعر إلى منطقة العرض/الطلب".

| File | Description |
|---|---|
| [`mt4/SupplyDemand_BOS_Retest.mq4`](mt4/SupplyDemand_BOS_Retest.mq4) | MT4 indicator source (MQL4, build 600+) |
| [`mt4/README_AR.md`](mt4/README_AR.md) | دليل عربي كامل: التثبيت، شرح كل إعداد، طريقة الاستخدام |

**What it does**

1. Detects a strong move (displacement ≥ `InpMinImpulseATR × ATR`) that **broke market structure** (a candle closes beyond the last confirmed swing).
2. Marks the **last opposite candle** before that move (extended to the origin wick) as the supply/demand zone.
3. Waits for price to come back — the first touch is **never** a signal.
4. Requires a **lower-timeframe confirmation** (mini structure break and/or engulfing/pin bar).
5. Discards zones that were **already tested or broken** (freshness state machine).
6. Places the stop **outside** the zone and takes the target from the nearest **liquidity/structure** level, enforcing a minimum R:R.

A checklist panel on the chart shows the status of all six rules plus the trade plan, and it never
says "SIGNAL" before the lower-timeframe confirmation exists.

---

## Shorts

`shorts/` contains an unrelated video pipeline (see `shorts/UPLOAD_KIT.md`).
