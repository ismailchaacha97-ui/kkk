# NOOB GUIDE: TaylorCycle from Zero
### What this indicator is, what every squiggle means, and exactly what to do each day — no experience assumed

**Read this first:** trading real money without practice loses money for ~most beginners.
Do everything below on a **demo account** for at least 30 trades before even thinking about real funds.
This is education, not financial advice.

All times below are shown as **New York (ET) / Morocco (GMT+1)**.

---

## 1. The 30-second version

Big traders push the market in a repeating **3-day rhythm**: down one day, up the next, fade the next.
This indicator figures out **which day today is**, paints the chart accordingly, and gives you **one clear
trade signal a day** (an arrow + 3 lines). You risk a tiny fixed amount, close everything before night,
and never hold overnight. That's the whole game.

## 2. The big idea (plain words)

- Markets don't move randomly every day. They breathe in a short rhythm: **dip → bounce → fade**.
- **Day 1 (BUY day):** price dips in the morning, then climbs into the evening. → *We buy the morning dip.*
- **Day 2 (SELL day):** choppy, pushes up then fails. → *We mostly sit out or make tiny range trades.*
- **Day 3 (SHORT day):** pops up in the morning, then slides down. → *We sell the morning pop.*
- Then the cycle repeats. The indicator labels each day automatically from yesterday's price action.

## 3. Your daily routine (Morocco time)

| When (Morocco) | What you do |
|---|---|
| **Before 14:30** | Open the M30 chart. Read the dashboard: `DAY:` label + `CAL:` + `SCORE:`. Write them down. That's your plan for the day. |
| **14:30–16:00** | US market opens. DO NOTHING. Let the first 90 minutes print. (Beginners lose the most money here by clicking early.) |
| **16:00** | The trigger bar closes. **Arrow + ENTRY/STOP/TP lines appear = you have a trade.** No arrow = no trade, close the laptop. |
| **16:00–16:30** | If arrow: place the trade exactly on the lines (entry, stop-loss, take-profit). Then set an alarm and walk away. |
| **16:30–19:00** | Dead zone. No new trades, ever. Check your trade at most once. |
| **~20:30–21:00** | Close ANY open trade, win or lose. Flat before bed. No exceptions. Log it in the journal. |

Total screen time: well under an hour once you're used to it.

## 4. Reading the chart (every element, simply)

**Colored day boxes (background rectangles):**
- 🟩 Green box = **BUY day** → only look for the blue ↑ arrow (buy). Never sell on green days.
- 🟥 Red box = **SHORT day** → only look for the orange ↓ arrow (sell). Never buy on red days.
- ⬜ Gray box = **SELL/choppy day** → beginners: take the day off.
- ⬛ Dark box = **Supertrend, market running hot** → take the day off, no exceptions.
- 🟨 Gold border = turn-of-month: historically friendlier for buyers. Same rules, slightly more confidence.

**Arrows (appear at 16:00 Morocco, never move once printed):**
- Blue ↑ below price = **buy here** (DT1 dip-long).
- Orange ↓ above price = **sell here** (DT2 fade-short).
- Aqua/magenta small arrows = gap-fade bonus signals (DT3). **Beginners: switch these off** — put `MQL4/Presets/TaylorCycle_DT1_DT2.set` in your Data Folder's `MQL4/Presets` folder, then in the indicator's Inputs tab click **Load** and select it (or just set `InpUseGapFade=false`). **DT1+DT2 only is the recommended beginner configuration.**

**The 3 lines (only on trade days):**
- **ENTRY** (blue/orange) = where you buy/sell.
- **STOP** (red) = where you admit you're wrong. The trade closes automatically here. This is your safety net — never trade without it, never move it further away.
- **TP** (green) = where you take profit (+0.5 ATR). If price gets there, half or all comes off with a win.

**Dashed steel-blue lines** = yesterday's high and low. The market treats these like invisible walls/floors. Just observe them for now.

**Dashboard (top-left panel), line by line:**
- `DAY:` = today's plan (BUY/SHORT/SELL/SUPER). If it says SUPER or SELL → day off.
- `CAL:` = calendar flags (`ToM` = month-turn, friendly; `PRE-MACRO`/`MACRO-TODAY` = news day, be careful — stay flat around 13:30 news and 19:00 Fed announcements).
- `SCORE: x/3` = how many tailwinds today has. 0–1 = small trade or skip. 2–3 = your best days.
- `Gap: +0.30 ATR` = how far price jumped overnight. Big gaps (>0.5) often fade back — that's the DT3 idea; ignore for now.
- `SETUP:` = live status: `WAITING` (before 14:30) → `ARMED` (14:30–16:00, don't touch) → `TRIGGERED` (trade!) → `NO TRIGGER` (after 16:30 with no arrow = day over).
- `DBG` = technical health line. You only need it if asking for help.

## 5. Your first trade, step by step (example)

Say the dashboard reads: `DAY: BUY DAY`, `SCORE: 1/3`, box is green.

1. 14:30–16:00: price dips, then starts climbing back. You watch. Hands off keyboard.
2. 16:00: blue ↑ arrow prints. ENTRY line = 44,800. STOP = 44,700. TP = 44,900. (Example numbers.)
3. You open a **buy** at 44,800 with stop-loss 44,700 and take-profit 44,900, risking 0.5% of demo funds.
4. You close MT4 (or set a phone alarm for 20:30). You do NOT stare at it.
5. Either: price hits 44,900 → win, done. Or hits 44,700 → small controlled loss, done. Or neither → at ~20:30 you close manually wherever it is. Done.
6. You write one line in your journal: date, setup, entry, exit, profit/loss, and whether you followed the rules.

Six steps. No improvising. The system makes the decisions; you execute like a robot.

## 6. Money rules (this section keeps you alive)

1. **Demo only** until 30+ logged trades with rules followed. No debate.
2. **Risk 0.5% per trade, max.** $1,000 account → max $5 lost per trade. $500 → $2.50. Tiny on purpose.
3. **Daily stop: lose 1.5%, you're done for the day.** Close the terminal. No "one more trade."
4. **Max 3 trades a day.** Usually you'll take 0 or 1. That's correct.
5. **2 losses in a row = done for the day.** The market is telling you the read is wrong.
6. **Start at 0.01 lots** (the smallest). To know what that risks in real money: Market Watch → right-click your symbol → *Specification* → look at *Tick value* and *Contract size*. Your risk ≈ stop-distance × value-per-point × lots. When in doubt, go smaller.
7. **Never move your stop further away.** Never add money to a losing trade. Never hold past ~21:00.

Why so strict? Because beginners don't lose from bad strategy — they lose from **one emotional day**
wiping out ten good ones. These rules make that mathematically impossible.

## 7. Noob mistakes (everyone makes them — now you won't)

| Mistake | Why it kills | Do this instead |
|---|---|---|
| Entering before 16:00 | The signal isn't confirmed; morning noise fakes you out | Wait for the arrow. No arrow, no trade. |
| Trading gray/dark-box days | Chop and runaway trends shred beginners | Green/red days only for your first 2 months |
| No stop-loss ("it'll come back") | One bad day deletes the account | Stop on every trade, placed immediately |
| Revenge trading after a loss | Emotional trading has ~zero edge | 2 losses = laptop closed |
| Trading news (13:30 CPI/NFP, 19:00 Fed) | Price jumps insanely in seconds | Flat 5 min before → 15 min after |
| Changing the system after 3 losses | 3 losses in a row is normal noise | Judge after 30+ trades, not 3 |

## 8. Mini-glossary

- **M30** = each candle = 30 minutes. Our chart timeframe.
- **Buy/Long** = profit if price goes up. **Sell/Short** = profit if price goes down.
- **Stop-loss** = automatic exit that caps your loss. **Take-profit** = automatic exit that banks your win.
- **ATR** = average wiggle-size of price. The indicator uses it to set stops that fit current volatility.
- **Arrow/trigger** = the confirmed signal. Only trade when you see it.
- **Flat** = no open trades. How you end every day.
- **Demo account** = fake money, real prices. Ask your broker for one; it's free.
- **Lot** = trade size. 0.01 = smallest. Bigger lots = bigger wins AND bigger losses.
- **ToM (turn-of-month)** = last trading day + first 3 days of a month; historically strong days.
- **FOMC/CPI/NFP** = big US news releases that shake markets. Calendar flags warn you.

## 9. Your first 30 days

- **Days 1–3:** get the indicator showing (see MT4_GUIDE.md troubleshooting). Don't trade. Just watch one full day and read this guide twice.
- **Days 4–10:** paper trade (write down what you *would* do, no clicks). Compare with what happened.
- **Days 11–30:** demo trade 0.01 lots, max 1/day, journal every trade (use TAYLOR_BOOK.csv).
- **After 30 trades:** review. Rules followed ≥ 90%? Losses small and controlled? Only then consider the *idea* of tiny real money — and re-read section 6 first.

Welcome in. Slow is fast in trading. 🌱
