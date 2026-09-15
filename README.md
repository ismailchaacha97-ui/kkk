# kkk — Supply & Demand "Three Entries" Indicator (MT4)

An MT4 indicator implementing the supply/demand method from the
"DIFFERENT TYPES OF ENTRIES" chart: it detects supply & demand zones and
marks the three entry styles on the chart.

- **Source:** [`MQL4/Indicators/SDZ_ThreeEntries.mq4`](MQL4/Indicators/SDZ_ThreeEntries.mq4)

## What it does

**Zone detection** (objective, rule-based):
- An *impulse* candle (body ≥ `InpImpulseMult × ATR`) that optionally breaks
  prior structure (`InpRequireBOS`) defines a zone.
- The zone rectangle is the *base*: the last opposite-colour candle before the
  impulse, including the candles between base and impulse.
- Zone lifecycle: **fresh → tapped (mitigated) → broken** (a close beyond the
  far edge). Fresh zones have solid borders, tapped zones dotted, broken zones
  grey dashed (hidden by default).

**Three entry styles** (as in the reference image):
1. `LMT` — pending limit order tagged at the zone's proximal line when the
   zone forms.
2. `CNF` — candle confirmation: an engulfing candle printed while tapping the
   zone.
3. `STR` — pullback structure: zone tap → fractal swing → counter-swing →
   close beyond the counter-swing (structure break) entry.

Green up-arrow = buy setup (demand), red down-arrow = sell setup (supply).
All logic runs on **closed candles only** — the indicator does not repaint.

**v1.1 — "trade it like it's my money" upgrades:**
- **HTF trend filter** (EMA fast/slow on a higher TF): signals only with the trend.
- **Zone quality score `Q0..Q4`** tagged on every zone: +1 impulse ≥ 1.5×ATR,
  +1 structure break, +1 liquidity sweep before the impulse, +1 tight base.
  Signals only fire at/above `InpMinScore`.
- **Session filter** (two windows, server time) — off by default.
- **RR trade planner**: every approved signal gets Entry / SL / TP lines at
  `InpRR` (default **1.50**); SL = far zone edge + buffer.
- **Room check**: if the TP would land inside the next opposite zone, the plan
  is suppressed and the tag reads `NR` (no room).
- **Alerts** now carry exact `@ entry / SL / TP` prices.

## Install

1. Copy `SDZ_ThreeEntries.mq4` into `<terminal data folder>/MQL4/Indicators/`.
2. Open MetaEditor (F4), press **F7** to compile.
3. In MT4, attach **SDZ_ThreeEntries** from the Navigator to any chart.

## Key inputs

| Input | Default | Meaning |
|---|---|---|
| `InpATRPeriod` / `InpImpulseMult` | 14 / 1.0 | impulse = candle body ≥ mult × ATR |
| `InpRequireBOS` / `InpBOSLookback` | true / 10 | impulse must close beyond prior swing |
| `InpMaxBaseCandles` | 3 | how far back the base candle is searched |
| `InpSkipOverlap` | true | drop zones stacked on an active same-side zone |
| `InpHistoryBars` / `InpMaxZones` | 1500 / 30 | scan depth / memory cap |
| `InpEntryLimit/Confirm/Struct` | true | toggle each of the three entry styles |
| `InpFractalN` | 2 | fractal side bars for the structure entry |
| `InpMinScore` | 2 | minimum zone quality (Q0..Q4) for signals |
| `InpUseHTF` / `InpHTF` | true / H1 | HTF EMA bias filter (fast 50 vs slow 200) |
| `InpUseSessions` + hours | false | trade only inside two session windows |
| `InpDrawPlan` / `InpRR` | true / 1.50 | draw Entry/SL/TP lines at this RR |
| `InpSLBufferPips` | 3 | stop buffer beyond the far zone edge |
| `InpRoomCheck` | true | suppress plans whose TP hits the next opposite zone |
| `InpFutureBars` | 20 | how far zone boxes extend to the right |
| `InpShowBroken` | false | keep broken zones visible (grey) |
| `InpAlertPopup/Push` | true / false | alerts for brand-new signals |

## Suggested workflow (matches the reference image)

- Use **LMT** in ranging markets / with higher-TF tailwind: best R:R, no
  confirmation.
- Use **CNF** when you want one candle of evidence at the zone.
- Use **STR** when the zone is your only evidence: best win rate, more missed
  V-shaped taps.

## Status / verification

Written and manually reviewed in this repo. MetaEditor is a Windows binary and
this Linux sandbox has no outbound network (Wine/MT4 could not be fetched), so
the file has **not been compiler-verified here** — that is the one unchecked
step. It targets plain MQL4 (`#property strict`, predefined series arrays,
no exotic API) and should build clean on any build 600+ terminal; compile with
F7 in MetaEditor. If your terminal reports anything, paste the error and it
will be fixed.

## Roadmap

- EA that places the three order types from these signals.
- Quantitative backtester comparing win rate / R:R / missed-trade rate per
  entry style.

*Educational tool, not financial advice.*
