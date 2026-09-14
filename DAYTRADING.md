# DAY TRADING ADAPTATION: Taylor Intraday Playbook
### Same cycle, no overnight holds — flat every close. What survives, what dies, and the 5 setups.

**Not financial advice.** Educational research. Day trading has a high failure rate;
commission drag kills most intraday systems — read §7 before trading anything here.

---

## 0. The honest framing (read this first)

The core system earns the **overnight premium** (Part 1, §3). If you day-trade it, you
deliberately give up the biggest edge. What remains is smaller and demands precision:

| Edge | Holds overnight? | Expected size | Day-trade verdict |
|---|---|---|---|
| Overnight drift (Cooper et al.) | yes | ~5–15bps | **given up** |
| Turn-of-month (McConnell–Xu) | yes | ~2× baseline | given up as held edge; keep as *bias* |
| Pre-macro drift (Hu et al.) | yes | ~25bps close→release | given up; keep as bias/context |
| Buy-Day afternoon ramp (Taylor) | no | ~5–15bps intraday | **tradeable: DT1, DT4** |
| First-hour fade of strong opens (Cooper et al.) | no | ~5–10bps | **tradeable: DT3** |
| Intraday momentum: first 30m → last 30m (Gao et al. 2018) | no | statistically + economically significant | **tradeable: DT4** |
| Sell-Day / Short-Day morning failure (Taylor) | no | ~5–15bps intraday | **tradeable: DT2, DT5** |

Rule of thumb: expect **0–6bps avg per day-trade vs 3–12bps overnight**, with
~2× the trades. Costs decide everything — see §7.

---

## 1. Pre-open routine: label the day (5 minutes, before 9:30 ET)

You need the label **before the open**, so it uses data through *yesterday's* close only
(engine: `build_daytrades` shifts everything by one day — no lookahead):

| Pre-open label | Condition (through yesterday) | Intraday bias | Setups allowed | Forbidden |
|---|---|---|---|---|
| **BUY day** | 2 down closes before today, OR down 1 + 2 days after swing high | dip-buy; afternoon long | DT1, DT4-long | morning shorts |
| **SHORT day** | 2 up closes before today | fade strength; morning short | DT2, DT4-short | morning dip-buys |
| **SELL day** (day after your Buy Day) | yesterday was a Buy-Day ramp | range-fade both sides | DT5, DT3 | fresh trend bets |
| **Supertrend** | 6+ straight closes | stand aside from fades | none (DT4 with-trend only, half size) | all fades |

Write down before the bell: label, prev high/low (today's reference levels),
gap size in ATR (`(Open − prevClose)/ATR`), ToM? (bias +, not a hold), macro today?
(FOMC 14:00 / CPI 8:30 days: no new trades 5 min before → 15 min after the release).

---

## 2. Time-of-day map (ET) — when each setup lives

| Window | Character | What to do |
|---|---|---|
| 9:30–10:00 | Opening drive + noise; gaps fade (Cooper: high opens fade first hour) | DT3 gap-fade window; otherwise observe |
| 10:00–11:30 | Taylor confirmation: Buy Day should bottom; Short Day should top | DT1/DT2 triggers arm (low/high in first 90 min?) |
| 11:30–14:00 | Dead zone: lunch lull, algo chop | **No new entries.** Manage or walk away |
| 14:00–15:30 | Taylor move: Buy-Day ramp / Short-Day slide; Gao intraday momentum: last-30m follows first-30m | DT4 entries; add nothing into chop |
| 15:30–16:00 | MOC imbalances, close | Exits only. Flat by 15:58. No exceptions |

---

## 3. The 5 setups (exact triggers)

Conventions: `ATR` = 14-day ATR known at yesterday's close. All exits EOD.
Defaults match engine flags: `--dt-stop-atr 0.5 --dt-cost-bps 3`.

### DT1 — Buy-Day Dip (long) ⭐ core
- **Day:** pre-open BUY label. **Window:** 9:30–11:00 trigger, exit 15:30–15:58.
- **Trigger:** day's low printed in first 90 min AND 10:30–11:00 bar closes back above
  (first-90m low + 0.1 ATR) — the Taylor low-first + reclaim, intraday version.
- **Entry:** that bar's close. **Stop:** entry − 0.5 ATR (hard, OCO). **Target:** EOD
  (time exit); scale half at +0.5 ATR if offered.
- **Void:** low keeps sliding past 11:30 (that's a Violation day — walk away, don't catch).
- **Best when:** ToM window or day before macro (upward bias days); gap down < 0.5 ATR.

### DT2 — Short-Day Fade (short) ⭐ core
- Mirror of DT1. **Day:** pre-open SHORT label. **Trigger:** day's high in first 90 min
  AND late-morning bar closes below (first-90m high − 0.1 ATR).
- **Entry:** that bar's close. **Stop:** entry + 0.5 ATR. **Target:** EOD; scale half at −0.5 ATR.
- **Void:** pushes to new highs after 11:30 (short squeeze / trend day — cover, done).
- **Skip:** first 3 trading days of the month, mornings before CPI/NFP/FOMC (up-drift headwind).

### DT3 — First-Hour Gap Fade (both directions)
- **Any day.** **Trigger:** opening gap > 0.5 ATR vs prev close. Fade the first 30-min
  close toward the prior close / VWAP. **Exit:** midday (≈12:00) or VWAP tag, whichever first.
- This is Cooper et al.'s "high opens fade in the first hour," tradeable form.
- **Cap:** one gap-fade per day; if it extends > 0.5 ATR against you by 10:30, it's a trend
  day — scratch and flip bias to DT4 with-trend.

### DT4 — Last-Half-Hour Momentum (Gao et al.)
- **Trigger (14:30 check):** sign of first-30-min return (9:30–10:00, measured from prev close)
  predicts last-30-min direction. If first-30m was up AND day-label agrees (BUY day for longs,
  SHORT day for shorts): enter 15:00–15:30 in that direction. **Exit:** 15:55 MOC.
- **Filter (Raschke Holy Grail intraday):** on a 5-min chart, 14-ADX > 30 and entry bar
  above its 20-EMA for longs (below for shorts) — only take DT4 when the trend is confirmed,
  not when it's already vertical into resistance (prior high = fade zone, see DT5).
- Strongest on high-vol / high-volume / macro-news days (per Gao et al.) — size normal,
  never double; volatility already sizes you via ATR stops.

### DT5 — Sell-Day Range Fade (both sides, advanced)
- **Day:** SELL label (day after a Buy-Day ramp). Character: push beyond yesterday's
  extreme, then fail — Taylor's "fade day."
- **Trigger:** tag of prev-day high/low (or today's developing range extreme) + 5-min
  reversal bar (wick rejection, close back inside). Fade toward VWAP/mid.
- **Stop:** 0.3 ATR beyond the extreme (failures fail fast — if it doesn't reverse in
  2 bars, scratch). **Target:** VWAP, then opposite extreme only if tape is dead.
- Max 2 round-trips/day on DT5. If range breaks > 0.5 ATR past the extreme with volume,
  the cycle stretched (4–5 day trend beat) — stop fading, stand aside.

---

## 4. Daily risk rules (the actual system)

1. **Per-trade risk 0.25–0.5%** (half the overnight size — you trade more often).
2. **Daily loss limit 1–1.5%**: hit it → flat, platform closed, no "one more."
3. **Max 3 entries/day** (gap-fade + one cycle trade + one DT4 is a full day).
4. **Time stops beat price stops:** DT1/DT2 not working by 13:00 → scratch at market,
   even at breakeven. Livermore: the first commitment must profit fast.
5. **No holds past 15:58.** No "it'll gap my way." The overnight system exists for that —
   run it separately or not at all; never blur the two books.
6. **News blackout:** flat 5 min before → 15 min after FOMC (14:00), CPI/NFP/PPI (8:30).
7. **Revenge rule:** 2 consecutive stop-outs → done for the day. The label was wrong.

---

## 5. Sizing example ($50k account, SPY ≈ $650, ATR ≈ $8 ≈ 1.2%)

| Setup | Risk 0.5% = $250 | Stop 0.5 ATR ≈ $4 | Shares | Commission drag* |
|---|---|---|---|---|
| DT1/DT2 | $250 | $4 | ~60 sh (~$39k notional) | ~$2–4 round trip |
| DT4 | $250 | time stop ≈ $3–4 | ~60–80 sh | same |

\*At $0.0035/share (IBKR Pro tiered-ish): 120 shares round trip ≈ $0.42 + fees ≈ **~1bp on
$39k notional** — fine. On a $500-position Robinhood-style account the same trade is
prohibitive: **intraday Taylor needs ≥ ~$25k or futures (MES: $5/pt, ~$2–3 round trip all-in).**
Engine default `--dt-cost-bps 3` models a retail-futures-ish reality; verify yours.

---

## 6. Backtesting it (engine `--daytrade` mode)

```bash
python taylor_engine.py --demo --daytrade
python taylor_engine.py --demo --daytrade --dt-gap-fade
python taylor_engine.py --ticker SPY --start 2020-01-01 --source yf --intraday 30m --daytrade
python taylor_engine.py --ticker SPY --start 2020-01-01 --source yf --intraday 30m --daytrade --dt-gap-fade --dt-stop-atr 0.75
```

Mechanics (see `build_daytrades`): labels use t−1 data only; DT1/DT2 enter at the
10:30–11:00 bar close after a first-90m dip-under-open (probe-over-open) + reclaim,
0.5-ATR stop, EOD exit; DT3 enters first-30m close, exits midday. Costs pre-applied
per trade. No full-day extremes are used in triggers (that would be lookahead).

What "healthy" looks like (vs overnight §7 of DEEP_DIVE):
- avg_net **0 to +6bps**, hit **50–55%** — thinner than overnight; demand t-stat > 2
  over ≥ 300 trades before sizing.
- DT1+DT4-long should beat DT2+DT4-short over time (upward drift asymmetry) — if shorts
  dominate your sample, you're curve-fitting a down year.
- `--dt-cost-bps 6` must stay ≥ breakeven or the system is commission-fragile: reduce
  frequency (BUY/SHORT days only, skip DT5) until it passes.

---

## 7. Cost math that kills most day traders (do this on paper first)

Per-trade cost in bps ≈ `(commission + spread×shares) / notional × 10⁴`.
A 60-share SPY trade at $650 with $0.01 effective spread/share: spread cost = $0.60 on
$39k ≈ 0.15bps — negligible. The killer is **frequency × losers**: 3 trades/day × 20 days
at −2bps expectancy = −120bps/month drag before one winner. That's why this playbook
caps you at 3/day and forbids the 11:30–14:00 chop: **every skipped B-trade is +2bps
of expectancy you didn't spend.**

## 8. Journal additions (extend `TAYLOR_BOOK.csv`)
Add columns: `setup` (DT1–DT5), `entry_time`, `exit_time`, `mae_atr`, `mfe_atr`,
`followed_time_stop` (Y/N), `dead_zone_trade` (must stay N). Weekly review: expectancy
by setup × day-label; any setup with t < 0 after 50 trades gets benched for a month.

## 9. Sources specific to this file
- Gao, Han, Li, Zhou (2018), *Market Intraday Momentum* (first-30m → last-30m, SPY 1993–2013):
  https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2440866
- Cooper–Cliff–Gulen (2008) first-hour fade of high opens: see `SOURCES.md`.
- Raschke Holy Grail intraday (ADX14 > 30, first pullback to 20-EMA, buy trigger-bar high):
  https://tradersmastermind.com/linda-raschke-trading-strategy/
- Taylor 3-day structure + Raschke 60/120-min adaptation: see `SOURCES.md`.
