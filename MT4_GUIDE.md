# MT4 GUIDE: TaylorCycle.mq4
### Install, inputs, and how to trade it — companion to `DAYTRADING.md`

**Not financial advice.** Educational research. Forward-test on demo before any live use.

---

## 1. Install (2 minutes)

1. MT4 → **File → Open Data Folder → MQL4 → Indicators** → copy `TaylorCycle.mq4` there.
2. Open MetaEditor (F4) → open the file → **Compile** (F7). You should get `0 errors`.
   If warnings about unused parameters appear, ignore them.
3. Attach to an **M30** chart: `US30`, `SPX500`, `NAS100` (names vary by broker).
   Works on FX majors too, but the edge was researched on equity index CFDs.
4. Load history: press **Home** / scroll left so M30 shows ≥ 30 days and D1 shows ≥ 260 bars
   (Tools → Options → Charts → Max bars in history: 500000+, then restart).

## 2. First-run setup (3 inputs that matter)

| Input | Set to | Why |
|---|---|---|
| `InpETOffset` | `-4` Mar–Nov (EDT), `-5` Nov–Mar (EST) | All session windows (9:30/11:00/16:00) are ET. Wrong offset = wrong boxes |
| `InpMacroDates` | output of `python mt4_cal_input.py` | Pre-macro / macro-day flags. Refresh monthly: `python fetch_calendars.py` then re-paste |
| `InpHistoryDays` | `30` | Days of boxes + arrows. Raise for research, lower if MT4 lags |

Verify: dashboard clock `ET HH:MM` matches US Eastern time, and day-boxes start at the
9:30 ET bar. If boxes start at the wrong bar, your `InpETOffset` is wrong.

## 3. Reading the chart

- **Day boxes** (9:30–16:00 ET): green = pre-open BUY day, red = SHORT day, gray = SELL/range day,
  dark = supertrend (no fades). **Gold border** = turn-of-month. Tag text shows `ToM` / `MACRO` / `PRE`.
- **Dashed steel-blue lines**: yesterday's High / Low — Taylor's only objective levels.
- **Arrows**: blue ↑ = DT1 dip-long trigger (11:00 ET bar close), red-orange ↓ = DT2 fade-short,
  aqua/magenta = DT3 gap fades (first-30m close).
- **Solid lines after a trigger**: ENTRY (blue/orange), STOP (red dashed, 0.5 ATR), TP (green, +0.5 ATR).
  Exit rule unchanged: EOD / time-stop, flat 15:58 ET — the indicator does not trade for you.
- **Dashboard** (top-left): ET clock + session state (`OPEN DRIVE / AM CONFIRM / DEAD ZONE–NO ENTRY /
  TAYLOR MOVE / CLOSE ONLY`), day label, calendar + 0–3 score, gap in ATR, ATR + stop in points,
  yesterday close-position + violation flag, 52W/seasonal leadership, live setup state, risk reminder.

## 4. Trading workflow (maps 1:1 to `DAYTRADING.md`)

1. **Before 9:30 ET**: read `DAY:` label + `CAL:` + `SCORE:`. No computation needed — the label
   uses completed daily bars only (same as the engine's pre-open labels).
2. **9:30–11:00**: let the first 90 minutes print. Do nothing.
3. **11:00 ET bar close**: if arrow + ENTRY/STOP/TP lines appear → place the trade per DT1/DT2 rules
   (0.25–0.5% risk, hard stop, EOD exit). No arrow → no trade; SELL days → DT5 manual range fades only.
4. **11:30–14:00**: dead zone — no new entries even if lines look tempting.
5. **15:30–15:58**: exits only. Flat into the close. (Overnight holds belong to the separate
   overnight system in `SECRET_STRATEGY.md`, not to this chart.)
6. **Macro days** (`MACRO-TODAY`): no entries 5 min before → 15 min after 8:30/14:00 releases.

## 5. Alerts

- Popup `InpAlerts=true`: fires once per setup per day (`SYMBOL TF DT1 @ price (stop …, score …)`).
- Push: set your MetaQuotes ID in MT4 → Tools → Options → Notifications, then `InpPush=true`.
- Email: configure SMTP in Options → Email, then `InpMail=true`.

## 6. Inputs reference (beyond §2)

| Input | Default | Notes |
|---|---|---|
| `InpAtrPeriod` | 14 | Daily ATR for stops/gaps/penetration |
| `InpSwingN` | 5 | Swing-high lookback for BUY-due logic |
| `InpMinClosePos` | 0.60 | SELL-day detection + quality math |
| `InpViolationPen/CP` | 0.25 / 0.35 | Low-violation definition (dashboard flag) |
| `InpStopAtr` | 0.5 | STOP/TP distance in ATR |
| `InpReclaimAtr` | 0.10 | Reclaim/reject buffer at trigger |
| `InpGapFadeAtr` / `InpUseGapFade` | 0.5 / true | DT3 threshold + toggle |
| `InpUse52W`, `InpWeeks52`, `InpMinH52`, `InpMinRec` | true, 52, 0.90, 0.75 | Leadership point (needs 260+ D1 bars) |
| `InpUseSeasonal`, `InpSeasonYears` | true, 5 | Same-month z-score (needs MN1 history) |
| `InpShow*` | — | Toggle dashboard / boxes / prev-HL / 52W line |
| Colors, corner, font | — | Cosmetic |

## 7. Known approximations vs `taylor_engine.py` (honest list)

1. **Broker-day vs ET-day**: daily streaks/prev-HL/52W use your broker's D1 bars, which start
   00:00 server (≈17:00–18:00 ET), not 9:30 ET. On index CFDs this rarely flips a label, but if your
   broker has Saturday/Sunday bars, labels can shift — prefer a broker with 5 daily bars/week.
2. **No portfolio simulation**: the indicator shows signals + score; position sizing across tickers
   lives in the Python engine, not here.
3. **Leadership needs history**: `n/a` until D1 ≥ ~260 bars / MN1 ≥ ~14 bars. Scroll/load history once.
4. **Backtest arrows repaint-free by construction**: arrows plot at closed bars (`f1 > 0`) and never
   move — but always confirm on demo forward first.
5. **Weekend/holiday ToM**: last-trading-day logic skips weekends, not exchange holidays (rare miss).

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| Boxes/arrows at wrong times | `InpETOffset` wrong (−4 summer / −5 winter); check dashboard ET clock |
| No boxes, empty dashboard labels | Not enough history — scroll left / raise Max bars, restart MT4 |
| `leadership: n/a` | Need 260 D1 + 14 MN1 bars (common on new charts — load history) |
| No push alerts | MetaQuotes ID missing or Notifications unchecked in Options |
| Indicator slows terminal | Lower `InpHistoryDays` to 15–20 |
| Compile errors | Must be MT4 build 600+ with `#property strict` support (any modern MT4) |
