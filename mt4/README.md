# Apex Confluence Pro — MT4 indicator

**A price-action confluence engine for MetaTrader 4 that marks high-probability
entries at support/resistance, confirms them with volume and market structure,
and tells you in plain English when to stay out.**

No moving averages. No MACD. No Stochastics. No lagging crossovers.
Everything is derived from information that is *final* when a candle closes:
where the swing points are, where price is relative to them, what the candle
did, and how much volume backed it.

```
mt4/
├── indicators/
│   └── ApexConfluencePro.mq4     ← the indicator (single file, no dependencies)
├── presets/
│   ├── scalping.set
│   ├── daytrading.set
│   └── swing.set
├── README.md                     ← this manual
├── QUICKSTART.md                 ← 5-minute setup
└── CHANGELOG.md
```

---

## Table of contents

1. [Why there is no lag](#1-why-there-is-no-lag)
2. [What the indicator draws](#2-what-the-indicator-draws)
3. [Installation](#3-installation)
4. [60-second setup](#4-60-second-setup)
5. [How a signal is built](#5-how-a-signal-is-built)
6. [The dashboard, row by row](#6-the-dashboard-row-by-row)
7. [Profiles](#7-profiles)
8. [Input reference](#8-input-reference)
9. [Trading workflow](#9-trading-workflow)
10. [Non-repainting: what is guaranteed](#10-non-repainting-what-is-guaranteed)
11. [Tuning signal frequency](#11-tuning-signal-frequency)
12. [Presets](#12-presets)
13. [Alerts](#13-alerts)
14. [Using the buffers from an EA](#14-using-the-buffers-from-an-ea)
15. [Calibration notes](#15-calibration-notes)
16. [Limitations & disclaimer](#16-limitations--disclaimer)

---

## 1. Why there is no lag

A moving average is a lag machine: it is the average of the past, so it can only
tell you what *already happened*. When price finally crosses it, the move has
often started hours earlier.

This indicator replaces every lagging component with a structural one:

| Lagging tool | Replaced by | Why it is timely |
|---|---|---|
| Moving averages / MA cross | **Confirmed swing pivots + BOS/CHoCH** | A pivot is a fact about price, not an average of it. A break of a confirmed swing is the earliest objective evidence that control changed hands. |
| MACD / Momentum | **Candle anatomy + efficiency ratio** | A close beyond the previous 5-bar extreme with an 80 % body *is* momentum — measured directly, no smoothing. |
| Stochastics / RSI overbought | **Support/resistance zones + sweep rejection** | "Overbought" is not a level. A wick through a level that closes back inside is a level, and it is observable in real time. |
| Volume oscillator | **Median-relative tick volume + delta proxy** | Compares this bar to the *typical* bar, not to a smoothed average of itself. |
| ADX | **Kaufman efficiency ratio** | Net move ÷ total movement over N bars: 0 = pure chop, 1 = pure trend. |

Everything is computed on closed bars, so the output is stable the moment a bar
finishes.

> *One clarification:* ATR is used throughout — but only as a **volatility
> ruler** (how far a zone is, how wide a stop should be). It never votes on
> direction, and it is not smoothed into a trend line, so it introduces no
> directional lag.

---

## 2. What the indicator draws

| Object | Meaning |
|---|---|
| **Teal rectangles** | Support zones (confirmed swing lows, merged by distance). |
| **Red rectangles** | Resistance zones (confirmed swing highs). |
| **Purple "FLIP" zones** | Zones that have been tested from both sides — the strongest reaction areas. A broken resistance becomes a support zone and changes colour automatically. |
| **Green up-arrow** | Long signal, printed below the bar that closed with the setup. |
| **Red down-arrow** | Short signal, printed above the bar. |
| **Gold line** | Entry of the most recent setup. |
| **Red dotted line** | Stop loss (invalidation). |
| **Green dotted lines** | Target 1 and target 2. |
| **Faint dotted lines** | Previous day high/low (PDH/PDL), optional previous week (PWH/PWL). |

The dashboard panel in a corner summarises all of it in text.

---

## 3. Installation

1. Open MetaTrader 4 → **File → Open Data Folder**.
2. Go to `MQL4/Indicators/`.
3. Copy `ApexConfluencePro.mq4` into that folder.
4. Back in MT4, right-click **Navigator → Indicators → Refresh**
   (or restart MT4).
5. Drag **ApexConfluencePro** onto a chart.

To change the inputs later: right-click the chart → **Indicators List** →
select the indicator → **Edit** (or drag it onto the chart again and press
*Inputs*).

No DLLs, no external files, no includes. It compiles as a single file.

---

## 4. 60-second setup

| Style | Timeframe | Profile | Min score | Session filter |
|---|---|---|---|---|
| Scalping | M1 / M5 | `Scalping (M1-M5)` | 10 | London + New York |
| Day trading | M5 / M15 / M30 | `Day trading (M5-M30)` | 10 | off (or London + NY) |
| Swing | H1 / H4 | `Swing (H1-H4)` | 10 | off |

1. Pick the profile that matches your timeframe.
2. Leave everything else at default.
3. Watch the dashboard: **SIGNAL** tells you *what*, **STATUS** tells you if it
   is still valid, and the orange advice line tells you what to do next.
4. Do not trade while the panel says **AVOID** — the reason is printed.

The indicator works on any symbol: FX majors, metals, indices, crypto CFDs.
Volume features use tick volume, which every MT4 broker provides.

---

## 5. How a signal is built

### 5.1 The engine, step by step

Every new bar the indicator re-runs one forward pass over the last
`InpHistoryBars` bars (700 by default). For each bar, in order:

1. **Confirm pivots.** A swing high/low is only accepted `strength` bars after
   it forms — never before.
2. **Update zones.** A new pivot is merged into an existing zone if it is within
   `0.45 × ATR`, otherwise a new zone is created. Touches accumulate into a
   strength score.
3. **Flip or retire zones.** A resistance zone that price closes above becomes a
   support zone (and vice-versa). That is the "broken level becomes support"
   rule, applied mechanically.
4. **Update structure.** The most recent confirmed, unbroken swing high/low is
   tracked. A close beyond it is a **BOS** (continuation) or **CHoCH** (change
   of character, i.e. a reversal).
5. **Score the bar** from 0 to 15 (see below).
6. **Apply hard gates.** If any gate blocks, no signal — the dashboard prints the
   reason.
7. **Build the trade.** Entry, stop, two targets.

### 5.2 The 15-point confluence score

| # | Component | Points | Condition |
|---|---|---|---|
| 1 | Rejection at a zone | **2–4** | close in the far half of the range, wick ≥ 35 % of range, at an active zone; 3 points if the wick ≥ 50 %, +1 if the zone has ≥ 2 touches |
| 2 | Engulfing at a zone | 2 | previous candle of opposite colour fully engulfed, near a zone |
| 3 | Liquidity sweep | 2 | wick beyond the prior `N`-bar extreme, close back inside (stop-hunt reclaim) |
| 4 | BOS | 2 | close beyond the last confirmed opposite swing |
| 4b | CHoCH | 3 | same break, but against the previous structure — control has changed |
| 5 | Structure alignment | 1 | sequence of confirmed swings agrees with the trade direction |
| 6 | Momentum close | 1 | body ≥ 55 % of range and close beyond the 5-bar extreme |
| 7 | Volume expansion | 2 (1) | tick volume ≥ 1.5 × median (2 pts) or ≥ 1.15 × (1 pt) |
| 8 | Delta pressure | 1 | 5-bar up/down volume skew ≥ 15 % in the trade direction |
| 9 | Fair value gap | 1 | 3-bar imbalance ≥ 0.25 ATR |
| 10 | HTF bias | **+2 / −2** | higher-timeframe structure agrees (+2) or opposes (−2) |
| 11 | Trend efficiency | 1 | efficiency ratio ≥ 0.22 |
| 12 | Room to the next level | 1 | at least 1.2 ATR of clear space to the opposing zone |

Score is capped at 15. **The dashboard shows the live score and which factors
fired**, so you are never looking at a black box.

### 5.3 Hard gates — the "do not trade" logic

| Gate | Default | Dashboard message |
|---|---|---|
| A structural trigger must exist | always | `WAIT - no structural trigger` |
| Minimum score | 10 / 15 | `WAIT - score 8/10` |
| Chop filter (efficiency ratio) | ER ≥ 0.10 | `AVOID - choppy (ER 0.07)` |
| Volatility floor | ATR ≥ 0.55 × 20-bar ATR | `AVOID - volatility too low` |
| Session filter | optional | `AVOID - ASIA session` |
| News blackout | optional | `AVOID - news blackout` |
| Spread cap | optional | `AVOID - spread 38 pts` |
| Reward:risk to TP1 | 1.2–2.2 by profile | `AVOID - target too close (1.1R)` |

A score alone is never enough: the bar must also contain a *trigger* (rejection,
engulfing, sweep, FVG, BOS/CHoCH, or a momentum break inside a trend).

### 5.4 Entry, stop and targets

* **Entry** — close of the signal bar (the arrow bar).
* **Stop** — signal bar low/high ∓ `0.35 × ATR`, but never closer than
  `InpSLMinATR × ATR`.
* **Target 1** — the near edge of the next opposing zone (where price is likely
  to hesitate). If no zone exists, a measured 2.5 R.
* **Target 2** — the following zone, otherwise 1.5 × the TP1 distance.

Levels are re-validated against `InpMinRR`; a setup with a target too close is
discarded and reported.

---

## 6. The dashboard, row by row

```
┌──────────────────────────────────────────────┐
│ APEX CONFLUENCE PRO                          │
│ structure | levels | volume | timing         │
│ PROFILE    DAYTRADE   EURUSD M5              │  ← active profile / symbol / TF
│ STRUCTURE  BULLISH (HH/HL)                   │  ← confirmed swing sequence
│ HTF M15    BULLISH (HH/HL)                   │  ← higher-timeframe bias
│ SIGNAL     BUY   11/15                       │  ← live setup + score
│ SCORE      [##########.....] 10              │  ← meter (10 of 15)
│ ENTRY      1.08452   BUY                     │
│ STOP       1.08310   14.2 pips               │
│ TARGET 1   1.08680   1.6R                    │
│ + Rejection at support                       │
│ + Volume expansion 1.8x                      │
│ + HTF M15 bullish                            │
│ + Structure: higher highs                    │
│ MARKET     TRENDING  ER 0.31                 │  ← trend vs chop
│ VOLATILITY NORMAL    RVOL 1.8 (EXPANSION)    │  ← ATR vs average, relative volume
│ SESSION    LONDON+NY    delta +22            │  ← session + volume pressure
│ STATUS     ACTIVE  (bar 1/5)                 │  ← lifecycle of the setup
│ > ACTION: BUY valid at zone                  │  ← what to do now
│ > Risk 14.2 pips | invalidation 1.08310      │
└──────────────────────────────────────────────┘
```

**Status values**

| Status | Meaning | What to do |
|---|---|---|
| `ACTIVE (bar 1/5)` | setup is live, `InpSetupTTL` bars to act | enter on your own trigger / retest |
| `TARGET 1 REACHED` | price already hit TP1 | take partials, trail the rest |
| `INVALIDATED - STOP HIT` | price traded through the stop | stand aside, wait for a new flush |
| `STRUCTURE FLIP - EXIT` | a CHoCH has formed against the trade | take profit / tighten the stop |
| `EXPIRED` | older than the TTL | no longer a valid plan |
| `NO SETUP` | nothing qualifies | wait |

**Colour of the left accent bar**: green = bullish live setup, red = bearish
live setup, orange = an `AVOID` gate is active, grey = neutral.

`SIGNAL ... (forming)` only appears when *Evaluate forming bar* is enabled or
when a bar is still open. It is a preview of the current, unfinished candle and
is **not** a trade signal. It disappears or becomes final at the close.

---

## 7. Profiles

A profile is a bundle of geometry presets tuned for one holding period. Pick one
and the indicator sets the pivot strength, proximity tolerance, stop distance,
minimum R:R, cooldown and setup lifetime accordingly.

| Parameter | Scalping (M1–M5) | Day trading (M5–M30) | Swing (H1–H4) |
|---|---|---|---|
| Pivot strength (bars each side) | 2 | 3 | 5 |
| History scanned | 400 | 700 | 1000 |
| Zone proximity | 0.60 ATR | 0.55 ATR | 0.65 ATR |
| Zone merge distance | 0.50 ATR | 0.45 ATR | 0.55 ATR |
| Sweep lookback | 8 | 12 | 20 |
| Median volume window | 14 | 20 | 30 |
| Minimum stop | 0.8 ATR | 1.0 ATR | 1.4 ATR |
| Minimum R:R | 1.2 | 1.5 | 2.2 |
| Bars between signals | 3 | 4 | 5 |
| Setup lifetime (bars) | 3 | 5 | 8 |
| ER "trending" threshold | 0.20 | 0.22 | 0.25 |

**Always active regardless of profile** (so you keep control):
`InpMinScore`, `InpAtrPeriod`, `InpERPeriod`, `InpERMinTrend`, `InpERChop`,
`InpVolSpikeMult`, and every session / drawing / alert input.

**Profile-controlled only** (ignored unless `Custom`): pivot strength, history,
proximity, merge, sweep lookback, volume window, HTF steps, minimum stop,
minimum R:R, cooldown, setup lifetime. Choose **Custom** if you want to set these
by hand.

---

## 8. Input reference

### Display

| Input | Default | Notes |
|---|---|---|
| `InpProfile` | Day trading | Scalping / Day trading / Swing / Custom |
| `InpShowPanel` | true | dashboard on/off |
| `InpCorner` | Top-left | panel corner |
| `InpPanelX`, `InpPanelY` | 12, 24 | pixel offsets |
| `InpFont`, `InpFontSize` | Courier New 9 | monospace keeps columns aligned |
| `InpColorBull`, `InpColorBear` | Lime / Tomato | arrow colours |

### Engine — quality gates (always active)

| Input | Default | Notes |
|---|---|---|
| `InpAtrPeriod` | 14 | volatility unit for every distance |
| `InpMinScore` | 10 | **main frequency control** (5–15) |
| `InpERMinTrend` | 0.22 | efficiency ratio that counts as "trending" |
| `InpERChop` | 0.10 | below this the bar is rejected as chop |
| `InpERPeriod` | 14 | efficiency-ratio lookback |
| `InpVolSpikeMult` | 1.5 | multiple of median volume that counts as expansion |

### Engine — geometry (Custom profile)

| Input | Default | Notes |
|---|---|---|
| `InpSwingStrength` | 3 | fractal width; higher = fewer, cleaner pivots |
| `InpHistoryBars` | 700 | bars rebuilt on each new bar |
| `InpLevelProxATR` | 0.55 | how close a bar must be to a zone |
| `InpMergeATR` | 0.45 | pivots closer than this share one zone |
| `InpSweepLookback` | 12 | bars used to define the "prior extreme" |
| `InpVolPeriod` | 20 | median volume window |
| `InpHTFSteps` | 2 | higher-TF ladder steps (M5→H1, H1→D1, …) |
| `InpSLMinATR` | 1.0 | minimum stop in ATR |
| `InpMinRR` | 1.5 | minimum reward:risk to TP1 |
| `InpCooldownBars` | 3 | minimum bars between arrows |
| `InpSetupTTL` | 5 | bars a live setup stays actionable |

### Session / news

| Input | Default | Notes |
|---|---|---|
| `InpSessionMode` | Off | Off / London+NY / London / New York |
| `InpAsiaStart/End` | 0 / 8 | **server** time hours |
| `InpLondonStart/End` | 7 / 16 | server time |
| `InpNYStart/End` | 12 / 21 | server time |
| `InpBlackout1/2` | empty | `"12:30-13:30"`, `"14:00-14:30"` — server time |
| `InpMaxSpreadPoints` | 0 | 0 = off; reject signals when spread is wider |

> Hours are **broker server time**, not your local time. Check the Market Watch
> clock in MT4 before setting them.

### Drawing

| Input | Default | Notes |
|---|---|---|
| `InpShowZones` | true | draw support/resistance |
| `InpMaxZonesShown` | 6 | per side of price |
| `InpShowZoneLabels` | true | `SUP 1.0845 (3)` |
| `InpShowTradeLevels` | true | entry/stop/target lines |
| `InpShowDailyLevels` | true | previous day high/low |
| `InpShowWeeklyLevels` | false | previous week high/low |
| `InpZoneExtendBars` | 40 | how far zones project to the right |
| `InpArrowOffsetATR` | 0.45 | distance of arrows from the bar |

### Alerts

| Input | Default | Notes |
|---|---|---|
| `InpAlertPopup` | true | MT4 alert box |
| `InpAlertSound` | false | plays `InpSoundFile` |
| `InpAlertPush` | false | push to phone (needs MetaQuotes ID) |
| `InpAlertEmail` | false | email (needs SMTP in Tools → Options) |
| `InpAlertIntrabar` | false | also alert on the *forming* bar — may flicker by design |

---

## 9. Trading workflow

**Before the session**

1. Profile matches the timeframe.
2. Session filter set to your trading hours (server time!).
3. Optional: news blackout windows for red-folder events.

**When an arrow appears**

1. Read the dashboard: score, status and reasons.
2. Confirm price is reacting at the zone the arrow points to.
3. Entry options:
   * market at the close of the arrow bar, or
   * limit order at the 50 % retracement of the signal bar (better price, may
     not fill).
4. Stop and targets are printed on the chart — you do not have to calculate
   anything.
5. If the status changes to `INVALIDATED`, the idea is dead. Do not re-enter the
   same direction without a new signal.

**Trade management**

* At TP1: bank 50–70 %, move the stop to break-even.
* Trail the remainder behind the last confirmed swing (the indicator's structure
  tracker uses the same pivots).
* If the dashboard shows `AVOID - choppy` while you are in a trade, tighten up:
  the engine believes the market has lost directional efficiency.

**When *not* to trade — the indicator says it explicitly**

* `SIGNAL NO TRADE` / orange accent bar → a gate is blocking; the reason is on
  the panel.
* `STATUS EXPIRED` → the moment has passed.
* `MARKET CHOPPY` with a low ER → wait.
* Price in the middle of two zones with no room to the next one → the R:R gate
  will usually block these for you.

---

## 10. Non-repainting: what is guaranteed

**Guaranteed**

* Signals are computed only from closed bars and confirmed pivots. No future
  data is used: at bar *s* the engine knows pivots that confirmed at
  *s + strength*, closes of bars ≥ *s*, and the last **closed** higher-timeframe
  candle.
* An arrow is printed on the bar that has just closed. It is never printed on
  the forming bar.
* The cooldown between signals is applied **forward in time**, so adding a new
  arrow can never remove an older one. Once printed, an arrow does not move or
  disappear while it remains inside the analysis window (`InpHistoryBars`).
* The trade plan (entry/stop/targets) is fixed at the signal bar's close and is
  not recalculated as price moves (the *status* changes, the levels do not).

**Not guaranteed (and clearly labelled)**

* With `InpAlertIntrabar = true`, the dashboard shows a **forming** preview.
  It can appear, disappear or flip while the candle is open. That is the honest
  nature of an unfinished bar; it never prints an arrow.
* History is rebuilt from the last `InpHistoryBars` bars on every new bar. An
  arrow far back at the very left edge of that window can be re-evaluated when
  the window slides. In practice the visible, recent signals are stable.
* The engine is deterministic: the same data produces the same arrows.

---

## 11. Tuning signal frequency

`InpMinScore` is the single most useful dial. Approximate behaviour on the
development data set (signals per 100 bars):

| Min score | Signals / 100 bars | Character |
|---|---|---|
| 12 | ~0.6 | only textbook confluence |
| 11 | ~1.1–1.5 | very selective |
| **10 (default)** | **~1.5–2.8** | selective, A/B grade setups |
| 9 | ~3.5–5 | more active |
| 8 | ~5–7 | scalping mode, expect noise |

To make it quieter: raise `InpMinScore`, enable the session filter, increase
`InpCooldownBars`, or raise `InpMinRR`. To see more: lower `InpMinScore` or the
ER chop threshold.

Approximate calendar frequency at the default of 10:

| Timeframe | Per 100 bars | Roughly |
|---|---|---|
| M1 | ~2 per 100 minutes | 8–12 per London/NY session |
| M5 | ~2 per 7 hours | 2–3 per day |
| M15 | ~2 per 25 hours | 2 per day |
| H1 | ~2 per 4 days | 2–3 per week |
| H4 | ~2 per 17 days | 3–4 per month |

---

## 12. Presets

Load them from the indicator's **Inputs → Load** button
(after copying them to `MQL4/Presets/`):

| File | Profile | Extra |
|---|---|---|
| `scalping.set` | Scalping | London+NY session, 20-point spread cap |
| `daytrading.set` | Day trading | session filter off, daily levels on |
| `swing.set` | Swing | weekly + daily levels on |

---

## 13. Alerts

One alert per signal bar (never repeated for the same bar). The message contains
symbol, timeframe, direction, score, entry, stop and target so you can act from
the notification alone:

```
Apex Confluence Pro | EURUSD M5 | BUY | score 11/15 (min 10) | entry 1.08452
SL 1.08310 TP 1.08680 | Rejection at support
```

Enable `InpAlertIntrabar` if you want an early warning while the bar is still
open — clearly marked `(forming)`.

---

## 14. Using the buffers from an EA

The indicator exposes four buffers, readable with `iCustom`. Buffer indices:

| Buffer | Content |
|---|---|
| 0 | Long arrow price (`EMPTY_VALUE` elsewhere) |
| 1 | Short arrow price (`EMPTY_VALUE` elsewhere) |
| 2 | Confluence score of the bar (0 if none) |
| 3 | Structure bias (+1 / −1 / 0) |

```mql4
double longSignal = iCustom(NULL, 0, "ApexConfluencePro",
                            /* inputs in declaration order */, 0, 1);
```

Pass the inputs in the exact order they are declared in the `.mq4` file, or use
the defaults by supplying the profile enum only where supported by your build.

Signals appear on bar 1 when bar 1 closes, so an EA should evaluate
`shift = 1` on a new bar.

---

## 15. Calibration notes

The defaults were validated with a Python port of the engine
(`../tools/engine_sim.py`, requires Python 3 + numpy) over ~100 000 synthetic
bars containing alternating trend, range and squeeze regimes:

* ~55 % of evaluated bars are rejected by the score gate, ~30 % by the trigger
  requirement, ~7 % by the R:R gate — the filters are doing the work.
* With the default profile, ~1.5 signals per 100 bars are produced.
* On the synthetic set, TP1 was reached within 120 bars before the stop in
  roughly 55–75 % of signals; that number is a property of the data generator
  and **is not a performance claim** for live markets.

The simulator is included so the logic can be re-tuned and re-checked without
touching MT4.

---

## 16. Limitations & disclaimer

* **Tick volume is broker-dependent.** MT4 has no centralised volume. The
  volume features compare a bar to *its own broker's* median, which is robust,
  but two brokers can show different absolute values.
* **Zones are approximate**, by construction (`InpMergeATR`). They are areas,
  not exact prices.
* **News blackout is manual.** There is no economic-calendar feed in a
  single-file MT4 indicator; enter the windows yourself.
* **The forming preview is not a signal.** Do not enter on it.
* **No strategy is profitable by itself.** This tool formalises a
  price-action/volume process and removes lag — it does not remove risk.
  Test on a demo account and size positions according to your own risk rules.

*Trading foreign exchange and CFDs carries a high level of risk. Past
performance, including any behaviour observed in simulation, is not indicative
of future results.*
