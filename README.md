# kkk — TradingView Indicators

## Dynamic Anchored VWAP `[DAVWAP]`

📄 **Script:** [`indicators/dynamic-anchored-vwap.pine`](indicators/dynamic-anchored-vwap.pine) (Pine Script v6, overlay)

A classic Anchored VWAP is pinned to **one manually chosen bar**. **DAVWAP** makes the
anchor *dynamic* — it automatically re-anchors the VWAP to fresh, market-defined events
as they happen.

### Anchor modes

| Mode | Behaviour |
|---|---|
| **Swing High & Low (Auto)** ⭐ | Two VWAPs: one re-anchored to the latest confirmed **swing high** (supply/resistance: line "A", red) and one to the latest confirmed **swing low** (demand/support: line "B", green). Each new confirmed swing moves the anchor. |
| Swing High / Swing Low | Single VWAP from the latest confirmed swing of the chosen type. |
| Highest High / Lowest Low (Window) | VWAP anchored to the extreme price bar inside the rolling lookback window. |
| Highest Volume (Window) | VWAP anchored to the highest-volume bar inside the window — tracks institutional activity zones. |
| New Day / New Week / New Month | Anchor resets at each calendar period start. |
| Manual Time | Classic fixed AVWAP anchored at a date/time you pick. |

### Features

- **Volume-weighted VWAP + standard-deviation bands** (2 configurable levels, σ-weighted, not a plain SMA of price).
- **Supply/demand cloud** shaded between the two auto-anchored lines.
- **Trend tinting** — optionally color lines by whether price is above/below.
- **Anchor markers** — tiny triangles mark each new anchor as it confirms (hover for tooltip).
- **Info table** (top-right) — current mode, anchor dates, and price distance (%) from each VWAP.
- **🎯 Entry signals** — see below.
- **Alerts** — price crossings *and* long/short entries (`alertcondition`).
- **No-volume feeds** (some FX/indices) automatically fall back to equal bar weighting.

### 🎯 Entry signals

Pick the logic in **Settings → 🎯 Entry Signals → Entry Logic**:

| Logic | LONG when… | SHORT when… |
|---|---|---|
| **Pullback Reclaim (Trend)** ⭐ | price wicks into the support-side VWAP (line B in Auto mode) and **closes back above** it — classic trend-continuation | price tags the resistance-side VWAP (line A) and closes back below |
| **Band Reversal (Mean Reversion)** | same logic against **Band 1** lower — fades stretched moves back to the VWAP *(requires Band 1 enabled)* | mirror at Band 1 upper |
| **VWAP Cross** | close crosses above the support-side line | close crosses below the resistance-side line |

Details:

- **One signal per touch** — an internal "arming" state prevents repeated signals while price sits at the line.
- **Slope filter** (optional, ON by default): longs only when the support VWAP is rising, shorts only when the resistance VWAP is falling.
- **Stop/target guides** (optional): on each signal the script draws an ATR-based stop (`ATR(14) × 1.5`) and a target at `Risk × 2.0`, projected 15 bars forward with price labels.
- **Alerts**: `DAVWAP: Long Entry` / `DAVWAP: Short Entry` in the alert dialog.
- Markers: ▲ `LONG` below the bar, ▼ `SHORT` above the bar.

### How to install on TradingView

1. Open [TradingView](https://www.tradingview.com/) → your chart → **Pine Editor** (bottom panel).
2. Delete the default template, paste the full contents of `indicators/dynamic-anchored-vwap.pine`.
3. Click **"Add to chart"** (optionally **"Save"** first to keep it in your account).
4. Configure via the indicator's ⚙️ settings; create alerts from the ⏰ alert dialog → condition **DAVWAP: …**.

### How it works (internals)

- The script keeps rolling prefix sums of `Σ(price·volume)`, `Σ(volume)`, and `Σ(price²·volume)`
  over the last `lookback + rightBars + 10` bars. The VWAP from *any* anchor bar to "now" is
  rebuilt in O(1) as a range difference of those prefix sums; the bands use the
  volume-weighted variance `E[p²] − E[p]²`.
- Swing anchors use `ta.pivothigh`/`ta.pivotlow`: a swing only **confirms after "Pivot Right
  Bars" bars have printed**. On confirmation the anchor jumps to the actual swing bar and the
  line is rebuilt from that bar forward. Past plotted values are not retroactively changed —
  this is standard, non-repainting pivot behaviour.
- `Window Lookback` also caps how far back an anchor may sit (anchor memory).

### Suggested starting settings

| Style | Timeframe | Left/Right | Lookback |
|---|---|---|---|
| Scalping | 1–5m | 3 / 3 | 300 |
| Day trading | 15m–1h | 5 / 5 | 300 |
| Swing | 4h–1D | 10 / 10 | 500 |

---

*For educational purposes only — not financial advice.*
