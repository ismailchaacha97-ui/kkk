# How to trade with the Premium/Discount indicator

**One rule:** buy in the DISCOUNT half of the range (cheap), sell in the PREMIUM
half (expensive), take profit at EQ (equilibrium), and enter at the deep levels
(70.5% / 29.5%) — ideally inside a kill zone.

The indicator is a **map**. It tells you *where value is*. It does not tell you
*when* the turn happens — that's what the confirmation step below is for.

---

## 1. Read the map first

Look at the info panel, top-left:

```
Position: DISCOUNT 42%   >>   DISCOUNT - BUY AREA
```

* `DISCOUNT xx%` → price is cheap relative to the range → **only look for BUYS**
* `PREMIUM xx%` → price is expensive → **only look for SELLS**
* `DEEP DISCOUNT / DEEP PREMIUM` → price is in the optimal entry zone (29.5% / 70.5%)
* `EXTREME DISCOUNT / PREMIUM` → price is beyond the range edge (outside low/high)
* `AT EQ` → no edge. Stand aside.

And the kill-zone lines below it:

```
London KZ: in 01:23:45
New York KZ: OPEN NOW
```

The best trades happen when price sweeps a deep level **while a kill zone is open**.

---

## 2. The setup checklist (all four, in order)

1. **Zone**: price is at/into a deep level (29.5% or 70.5%) or beyond the range edge.
2. **Time**: a kill zone is open (London 07:00–10:00 or New York 13:00–16:00 server
   time by default) — or at minimum Asia/London session liquidity.
3. **Confirmation**: price has *reacted* — see step 3.
4. **Risk**: you know your stop loss and it costs ≤1% of the account.

If any one is missing → no trade. The market will be there tomorrow.

---

## 3. The two setups

### BUY — sweep into deep discount (29.5% or below)

**Worked example (gold, from the demo chart):**

Previous-day range = 4365.8 – 4389.5, so:

| Level | Price |
|---|---|
| Range low (0%) | 4365.8 |
| **Deep discount (29.5%)** | **4372.8** |
| EQ (50%) | 4377.6 |
| Deep premium (70.5%) | 4382.5 |
| Range high (100%) | 4389.5 |

Price drops in Asia, sweeps below the range low to **4333.0** (extreme discount —
a liquidity grab), then closes back up.

1. **Entry**: on the confirmation (a strong bullish close back above the sweep /
   above 4333 + a small buffer), e.g. 4340.
2. **Stop**: below the sweep low — 4325 (15 pts risk).
3. **Target 1**: EQ 4377.6 (+37.6 → ~2.5R). Take half.
4. **Target 2**: range high 4389.5 / +50% extension 4401.4. Move SL to break-even
   after Target 1.

> In the example price ran from 4333 all the way to 4444.9 — target 1 (EQ) was hit
> first, then premium, then beyond. That's the ideal discount-buy: cheap → back to value.

### SELL — rally into deep premium (70.5% or above)

Same day, continuation: price rallies to **4444.9**, far above the range high 4389.5
(extreme premium — buyers exhausted above value).

1. **Entry**: on confirmation (bearish close / rejection of the highs), e.g. 4440.
2. **Stop**: above the rally high — 4452 (12 pts risk).
3. **Target 1**: EQ 4377.6 (+62 → ~5R). Take half.
4. **Target 2**: range low 4365.8 / −50% extension 4353.9.

---

## 4. What counts as "confirmation"

The deep-level alert firing is NOT the entry. Wait for one of:

* a **close back through** the deep level (e.g. close below 70.5% then close back
  above it for a sell → actually: for a sell, close above the level, then a close
  back below it),
* a **displacement candle** (large body closing through the level in your direction),
* a **rejection wick** (long wick piercing the level, small body),
* your own confluence (order block, FVG, EMA…).

No confirmation → no entry. The level alone only tells you *where*; confirmation
tells you *when*.

---

## 5. Risk management (non-negotiable)

* **Risk ≤1% per trade.** Position size = (account × 1%) ÷ stop distance.
* **Stop beyond structure**, not a fixed pip value: beyond the sweep low/high.
* **Minimum 2R** to Target 1; if the map gives less room (deep level too close to
  EQ), skip the trade.
* **Take partials**: half at EQ, move stop to break-even, let the rest run.
* **Max 2–3 losses a day**, then stop. Max 1–2 concurrent trades.

---

## 6. When NOT to trade

* Price near **EQ** (no edge either way)
* Between EQ and a deep level (the "middle" — poor RR)
* **News minutes** (NFP, CPI, FOMC, red-folder events) — spreads blow out
* **Tiny ranges** (weekends, holidays — the indicator will show a small range or
  fall back to an older one)
* **No kill zone** and no confirmation — the deep level alone is not a reason

---

## 7. Settings cheat sheet

| Style | Anchor | Timeframe | Alerts |
|---|---|---|---|
| Intraday swings (recommended) | PREV DAY (default) | M15/H1 chart | Kill-zone only: ON |
| Scalping | CUR DAY | M1/M5 chart | Kill-zone only: ON |
| Asian-range method | ASIA (00:00–06:00) | M5/M15 | London KZ only |
| Swing / position | PREV DAY | H4/D1 | Kill-zone only: OFF |

Set `EQ = session open` if you trade the "open as the magnet" style; leave 50% for
the classic ICT style.

Check your **broker's server time** and set Asia + kill zones to match it (panel
shows server time at the bottom).

---

## 8. How to use the alerts

* **"DEEP DISCOUNT reached" / "DEEP PREMIUM reached"** → get ready, don't enter.
* **"Returned to EQ"** → take-profit / exit reminder, or reversal watch.
* **"Price entered DISCOUNT/PREMIUM"** → bias reminder (only look for buys in
  discount, only sells in premium).

Sound + push enabled with kill-zone filtering means you only get woken up at the
hours that matter.

---

## 9. Realistic expectations

* This is an **edge map, not a crystal ball**. Wins will come from the structure
  of buying cheap and selling expensive *with confirmation and risk control* —
  not from every deep-level touch.
* Expect losing trades. The edge lives in the **RR asymmetry**: stop behind the
  sweep, target EQ and beyond.
* **Demo/backtest for at least 2 weeks** before real money. Keep a journal:
  date, setup, level, entry, stop, targets, result, screenshot. After 20 trades,
  review what actually works for you and delete what doesn't.

Trading involves substantial risk of loss. Nothing here is financial advice.
