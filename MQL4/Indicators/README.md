# JobPick.mq4 — MT4 indicator

One overlay for the five jobs: **Bias · Trend · Momentum · Participation · Risk**.

| Job | Default tool |
|---|---|
| Bias / fair value | VWAP (intraday) or 200 EMA (swing) |
| Trend structure | 20 / 50 EMA |
| Momentum / trigger | RSI(14) or MACD histogram |
| Participation | Volume / RVOL |
| Risk | ATR (stop, target, trailing stop) |

## Install

Copy `JobPick.mq4` into your MT4 data folder:

```
<MT4 data folder>/MQL4/Indicators/JobPick.mq4
```

Then: **File → Open Data Folder** in MT4, or restart / right-click Navigator → Refresh.
Compile with MetaEditor (F7) or just drag it onto a chart.

## What's drawn

* **Orange (thick)** — session VWAP, resets daily / weekly / custom hour
* **Deep sky blue (thick)** — 200 EMA bias line
* **Lime / Gold** — fast / slow EMA
* **Dashed-dot green or red** — ATR trailing stop (active side only)
* **Arrows** — confluence signals on **closed bars only** (no repaint)
* **Horizontal lines** — entry / SL / TP of the most recent signal
* **Dashboard (top-left)** — live readout of all five jobs + score

## Signal logic

Each job votes, out of 4:

1. **Bias** — close above/below fair value (VWAP, EMA200, or both)
2. **Trend** — EMA fast above/below EMA slow
3. **Momentum** — RSI above 50 & rising (or bouncing off oversold), or MACD hist > 0 & rising / zero-line cross
4. **Participation** — RVOL ≥ threshold

An arrow fires when the required score (`InpMinScore`, default **4/4**) is reached
*and* the direction flips. Alerts fire once, on the bar that just closed.

Stops/targets use ATR: `SL = close ± ATR × 1.5`, `TP = SL distance × 2.0` (both inputs).

## Suggested presets

| Style | Bias | Trend | Momentum | RVOL | ATR | Min score |
|---|---|---|---|---|---|---|
| Scalp M1–M5 | VWAP | 9 / 21 | RSI 14 | 1.5 | 14 × 1.0, R:R 1.5 | 4 |
| Intraday M15 | VWAP | 20 / 50 | RSI 14 | 1.2 | 14 × 1.5, R:R 2 | 4 |
| Swing H4–D1 | EMA200 | 20 / 50 | MACD 12/26/9 | 1.0 | 14 × 2.0, R:R 3 | 3 |

## Notes / limits

* MQL4 can only draw in **one window per indicator**, so the oscillator is reported
  numerically in the dashboard rather than as a sub-window panel.
* VWAP uses **tick volume** by default (real volume is only available on exchange
  instruments). If your broker reports no volume at all, RVOL shows `n/a` and the
  participation vote is treated as neutral.
* VWAP resets on **broker server time**. Use `InpVWAPAnchor = VWAP_HOURS` with
  `InpSessionStartHour` if you want sessions to start at e.g. 17:00 NY.
* Not financial advice. Backtest / forward-test before risking money.
