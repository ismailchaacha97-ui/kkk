# FVG Cascade — MT4 Indicator (H1 → M30 → M5 → M1)

An MT4 indicator that fully automates the multi-timeframe **ICT-style FVG cascade** strategy:

```
STEP 1  H1   BIAS          orderflow = who is winning?
STEP 2  M30  PD ARRAY      find the inversion FVG (IFVG) to base the trade on
STEP 3  M5   SWING         wait for price to print a low (buy) / high (sell)
STEP 4  M1   TRIGGER       wait for the FVG invalidation  ->  SIGNAL + ALERT -> you execute
```

Built for **EURUSD on the M1 chart** (works on any symbol — all logic reads the
timeframes internally, so attach it once and it does the whole cascade for you).

---

## 1. The exact rules implemented

### Step 1 — H1 bias (orderflow)
The indicator scans H1 for 3-candle FVGs (fair value gaps) and tracks **invalidations**
(a candle *closing* beyond the far side of a gap):

| What happens on H1 | Orderflow | Bias |
|---|---|---|
| Bearish FVGs get **invalidated** (price closes above them) | bullish orderflow is winning | **BULLISH** |
| Bullish FVGs get **invalidated** (price closes below them) | bearish orderflow is winning | **BEARISH** |

* The **latest** invalidation event decides the bias (must be recent: `InpBiasMaxAgeBars`).
* `InpBiasMinEvents` lets you require e.g. 2 invalidation events of the same type before
  the bias is accepted (smoother, default 1 = pure rule above).
* If there is no fresh event, bias is **UNDEFINED** and the indicator waits (no trades).

### Step 2 — M30 inversion FVG (the PD array / trade zone)
* A **bearish M30 FVG that price closed above** becomes a **bullish IFVG** (support) → used for **buys**.
* A **bullish M30 FVG that price closed below** becomes a **bearish IFVG** (resistance) → used for **sells**.
* The zone matching the bias is drawn on the chart. The indicator then waits for price to
  **trade back into the zone** ("tap") — detected on M1 granularity.
* The setup dies if a **M5 candle closes beyond the far side of the zone**, or when it gets
  too old (`InpZoneMaxAgeBars`, `InpSetupTimeoutMin`), or when the bias flips.

### Step 3 — M5 swing (the low / high)
After the tap, the indicator waits for price to print:

* **BUY**: an M5 **low** — confirmed as a fractal pivot (`InpSwingStrength` bars each side).
* **SELL**: an M5 **high** — same logic mirrored.

The lowest low / highest high since the tap is also tracked (used for the default stop loss).

### Step 4 — M1 trigger (FVG invalidation → execution)
On M1 the indicator waits for the **opposite-side FVG to be invalidated by a closing candle**:

* **BUY**: a **bearish M1 FVG** (formed during the move into / after the zone) gets
  **closed above** → bullish confirmation → **BUY SIGNAL**.
* **SELL**: a **bullish M1 FVG** gets **closed below** → **SELL SIGNAL**.

The signal fires on the **close** of the invalidating M1 candle (no repaint). Alert includes
entry, SL, TP, risk in pips and the whole setup context.

### SL / TP
* SL (choose `InpSLMode`): below the M5 swing extreme **(default)**, beyond the far side of
  the M30 IFVG zone, or beyond the far side of the M1 trigger FVG. Buffer: `InpSLBufferPoints`.
* TP (choose `InpTPMode`): RR multiple of the risk (default 2R) or fixed points.
* The last signal's SL/TP lines are drawn on the chart and the panel tracks the outcome
  (open / TP hit / SL hit).

---

## 2. Installation

1. Open MT4 → `File → Open Data Folder` → `MQL4\Indicators\`
2. Copy `FVG_Cascade.mq4` there.
3. In MetaEditor (F4) open the file and press **Compile** (F7) — it should compile with 0 errors.
4. In MT4, open the **EURUSD M1** chart and drag the indicator on it
   (Navigator → Indicators → FVG Cascade).
5. The first load needs multi-timeframe history: if you see
   *"loading multi-timeframe data…"*, just wait a few seconds/minutes (or open H1/M30/M5
   charts of EURUSD once so MT4 downloads them). Enable **Tools → Options → Charts →
   Max bars in history/chart** reasonably high for good history signals.

### Alerts
`InpAlertPopup` (Alert window), `InpAlertPush` (push notification — configure your MetaQuotes ID in
Tools → Options → Notifications), `InpAlertEmail`, `InpAlertSound`. Stage alerts
(bias flip / new zone / tap / swing formed) can be disabled with `InpStageAlerts = false`
so you only get the final entry signals.

---

## 3. What you see on the chart

| Object | Meaning |
|---|---|
| Yellow box | the H1 FVG whose invalidation currently sets the bias |
| Blue / red boxes (big) | H1 FVGs (invalidated ones go gray) |
| Blue / red zone (extended right) | the **active M30 IFVG trade zone** |
| Gray zone | next IFVG waiting for a tap |
| Up/down arrow | the confirmed M5 swing low/high of the active setup |
| Small red/blue box near price | the M1 FVG being watched for the trigger |
| Lime / red arrows in the chart | past BUY / SELL signals |
| SL / TP lines + labels | last signal |
| Dashboard (top-left) | live status of all 4 steps + last signal & result |

Dashboard example:

```
FVG CASCADE  EURUSD  [H1 > M30 > M5 > M1]
1) H1 bias: BULLISH  (last: bear FVG invalidated 08.30 14:00 | 24 bars: 4 bear-inv / 1 bull-inv)
2) IFVG (active): 1.09281..1.09518  inv 13:30  tap 14:45  trades 0/1
3) M5 swing LOW @ 1.09372 (14:55)  extreme 1.09372
4) waiting M1 close > 1.09390  (bear FVG 1.09375..1.09390)
STATE: WAIT: M1 close > 1.09390 (bearish FVG)
Last signal: BUY 1.09399 SL 1.09362 TP 1.09472  (14:58)  WIN +37.0 pips
```

---

## 4. Inputs

### The cascade
| Input | Default | Description |
|---|---|---|
| `InpBiasTF` / `InpZoneTF` / `InpSwingTF` / `InpEntryTF` | H1 / M30 / M5 / M1 | the 4 steps of the cascade |

### Step 1 — bias
| Input | Default | Description |
|---|---|---|
| `InpH1Lookback` | 200 | H1 bars scanned for FVGs |
| `InpBiasWindowBars` | 24 | window (bias-TF bars) for counting invalidation events |
| `InpBiasMaxAgeBars` | 36 | latest invalidation must be newer than this |
| `InpBiasMinEvents` | 1 | min invalidation events supporting the bias |

### Step 2 — zone
| Input | Default | Description |
|---|---|---|
| `InpM30Lookback` | 150 | M30 bars scanned for FVGs |
| `InpZoneMaxAgeBars` | 96 | IFVG stays valid this many M30 bars after inversion (96 = 2 days) |
| `InpMinZonePoints` / `InpMaxZonePoints` | 0 / 0 | optional zone height filter (points, 0 = off) |

### Steps 3–4 — swing & trigger
| Input | Default | Description |
|---|---|---|
| `InpSwingStrength` | 2 | M5 fractal strength (bars each side) |
| `InpM5Lookback` | 600 | M5 bars scanned for pivots (auto-extended if needed) |
| `InpSetupTimeoutMin` | 240 | setup expires this many minutes after the tap |
| `InpM1ScanMinutes` | 720 | M1 history scanned for trigger FVGs |
| `InpMaxTradesPerZone` | 1 | max signals per IFVG zone |
| `InpSignalCooldownMin` | 10 | min minutes between two signals (anti-duplicate for overlapping zones) |

### Risk
| Input | Default | Description |
|---|---|---|
| `InpSLMode` | SL_SWING | `SL_SWING` (swing extreme) / `SL_ZONE` / `SL_FVG` |
| `InpSLBufferPoints` | 10 | SL buffer in points (10 = 1 pip on EURUSD) |
| `InpTPMode` | TP_RR | `TP_RR` / `TP_FIXED` |
| `InpRiskReward` | 2.0 | TP = RR × risk |
| `InpTPPoints` | 200 | fixed TP in points (fixed mode) |

### Alerts / visuals
Popup, push, email, sound toggles, `InpStageAlerts`, drawing toggles, colors, panel position,
`InpHistorySignals` + `InpHistoryBars` (draw past signals when loading — useful to eyeball how
the strategy would have behaved on recent data).

---

## 5. Important behaviour notes

* **No repainting**: every decision (bias, inversion, tap, swing, trigger) uses **closed**
  candles only. A signal is confirmed on the close of the invalidating M1 candle, so the
  alert arrives when the next M1 candle opens — enter at market then (≈ trigger close).
* Because the M5 swing needs `InpSwingStrength` bars to confirm, a trigger that fires during
  those few minutes is still caught (reported on its own bar) — nothing is missed.
* One signal per zone by default (`InpMaxTradesPerZone`); overlapping zones produce one
  signal thanks to the cooldown.
* The state machine resets by itself: bias flip, zone break, zone expiry or a completed
  trade all move the hunt back to step 2.
* The signal is **selective by design** (4 conditions must line up) — expect quality over
  quantity. Loosen `InpSwingStrength=1`, `InpBiasMinEvents=1`, `InpMaxTradesPerZone=2`,
  `InpSetupTimeoutMin` to get more signals.
* This is an **indicator** (alerts + drawings) — it does not place orders. It can be turned
  into an EA on request.
* MT4 cannot back-test indicators in the strategy tester; use `InpHistorySignals` on live
  charts (or visual-mode tester) to review past signals. Always forward-test on demo first.

---

## 6. الاستعمال بالدارجة (Darija quick guide)

1. Hadi fichier `FVG_Cascade.mq4` → copieha f `MQL4/Indicators` → compile f MetaEditor.
2. Hell chart dyal **EURUSD M1** f MT4 w zid l indicateur.
3. Huwa ghadi ydir kolchi automatiquement:
   - **H1**: kaychof wach l bias bullish wla bearish (achmen FVGs kaytinvalidaw).
   - **M30**: kay9elleb 3la l **inversion FVG** li ghadi nticto 3lih (kayrssemha f chart).
   - **M5**: kaytsenna price ydir **low** (buy) wla **high** (sell) mn b3d ma ytouchi l zone.
   - **M1**: kaytsenna l **invalidation dyal FVG** → kay3tik signal m3a entry/SL/TP w alert.
4. F panel (foq 3la lisser) katshof fin wsalna f cascade: bias, zone, swing, trigger, w akhir signal.
5. Ila bghit alerts f telephone: khelli `InpAlertPush = true` w configurer MetaQuotes ID f MT4.

⚠️ Indicator kay3tik signals — nta li kateksekuti l trade. Testi 3la demo 9bel l live.

---

## 7. Backtest (2021 – Jul 2022, real Dukascopy data)

The exact same cascade logic was ported to Python and replayed on **554,071 M1 bars** of real
EURUSD tick data (Dukascopy, GMT, bid + measured spread) — see the `backtest/` folder.

**Headline (RR 2.0, SL = swing, indicator defaults, no tuning):**

| | Trades | Win rate | PF | Net pips* |
|---|---|---|---|---|
| All signals | 1002 | 42.4% | 1.17 | **+637** |
| SELL only | 510 | 46.9% | 1.51 | +1402 |
| BUY only | 492 | 37.8% | 0.86 | −417 |
| 2021 | 647 | 43.9% | 1.39 | +1144 |
| 2022 (Jan–Jul) | 355 | 39.7% | 0.94 | −159 |

\* net of the spread measured on each entry bar (avg 0.35 pip — Dukascopy is tighter than retail brokers;
with a 1.0-pip cost the system is roughly break-even).

**Read it honestly:** the edge is real but thin, it comes mostly from with-trend SELLs during the
2021–22 downtrend, and it degrades in the 2022 high-volatility regime. RR 1.5–2.0 is the sweet spot.
Full statistics, monthly table, RR sensitivity, drawdown and caveats: **`backtest/report.md`**,
trades list in `backtest/trades.csv`, equity curve in `backtest/equity_curve.png`.

Reproduce: `cd backtest && python3 backtest.py && python3 make_report.py` (~8 s).

---

## Files

* `FVG_Cascade.mq4` — the indicator (MQL4, compiles with `#property strict`).
* `backtest/` — engine + data + report: `backtest.py` (exact port of the indicator logic),
  `build_m1.py` (Dukascopy ticks → M1), `make_report.py`, `report.md`, `trades.csv`,
  `equity_curve.png`, `data/EURUSD_M1_2021.csv.gz` + `data/EURUSD_M1_2022.csv.gz`.

*Disclaimer: educational tool, not financial advice. Trading involves substantial risk. Past
backtest performance does not guarantee future results.*
