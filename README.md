# RealLiquidity — MT4 liquidity mapper

`RealLiquidity.mq4` is a MetaTrader 4 chart indicator that maps **where resting liquidity most likely sits** on the price chart:

* **Buy-side liquidity (BSL)** — stops and breakout orders parked *above* swing highs.
* **Sell-side liquidity (SSL)** — stops parked *below* swing lows.
* **Liquidity pools** — two or more equal / near-equal highs or lows. Everyone's stop sits in the same place, so these act as magnets and as obvious targets for stop hunts.
* **Volume-spike areas** — bars where volume expanded far above its average *and* price actually travelled. This is the closest thing to “institutional activity” a retail MT4 chart can show.
* **Liquidity voids / imbalances** — 3-bar gaps left by an aggressive move; price often returns to rebalance them.
* **Liquidity sweeps** — a wick through a level that closes back inside: a stop-run / liquidity grab, followed by a reversal.

The indicator is **object based** (no indicator buffers), so it works on any symbol and timeframe without touching the chart's indicator list, and it **does not repaint confirmed structure**: a pivot is only used after its right-hand confirmation bars have closed.

```
               ╔══════════════════════════════════════════╗  ← BSL x3  (equal highs + stops)
               ║                                          ║
   highs  ─────╫───┬─────────────┬────────────────┬───────╫──── pool box, extends right
               ╚═══╪═════════════╪════════════════╪═══════╝
                   │             │                │
                   │        ▄▄▄▄▄│▄▄▄▄▄      ▲    │  ← sweep arrow (wick above, close back)
              ▄▄▄▄▄│▄▄▄▄▄  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄   ╷
     ┌─────────────┴──────────────────────────┐   ╷  ← volume-spike zone
     │  ███ 6.3x vol                          │   ╷
     └────────────────────────────────────────┘   ╷
                     ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄╵
               ╔══════════════════════════════════════════╗  ← SSL x2 (equal lows)
               ║                                          ║
   lows   ─────╚══════════════════════════════════════════╝
```

---

## 1. Installation

1. Copy `RealLiquidity.mq4` to `<MetaTrader 4 data folder>/MQL4/Indicators/`
   (in MT4: **File → Open Data Folder → MQL4 → Indicators**).
2. Open **MetaEditor** (F4), open the file from the Navigator, press **F7** (Compile) — it must report `0 error(s)`.
3. Back in MT4, refresh the Navigator (**right-click → Refresh**), then drag **RealLiquidity** onto a chart.
4. The inputs dialog opens. Defaults are tuned for FX majors on M5–H1; see §3 for other markets.

> **MT4 only.** The file uses the MQL4 object API and the MQL4 `OnCalculate(rates_total, prev_calculated, ...)` signature. It will not compile as-is in MetaTrader 5 (MT5 uses `ENUM_TIMEFRAMES`-based object calls and a different `OnCalculate`).

Removal: detach the indicator; every chart object it created is prefixed `RLQO_` / `RLQP_` and is deleted automatically.

---

## 2. What gets drawn

| On the chart | Meaning |
|---|---|
| **Orange shaded box** | Buy-side liquidity pool (≥ `InpMinTouches` equal highs). Stops sit just above the top edge. |
| **Blue shaded box** | Sell-side liquidity pool (≥ `InpMinTouches` equal lows). Stops sit just below the bottom edge. |
| **Orange / blue dotted line** | A single confirmed swing high/low — one resting level, not a pool. |
| **Gray dashed box + dotted line** | A pool that has already been **swept** (liquidity taken). |
| **Label `BSL x3` / `SSL x2`** | Side and number of touches in the pool. |
| **Green box, `6.3x vol`** | Bullish volume-spike area (heavy buying participation). |
| **Red box, `2.1x vol`** | Bearish volume-spike area (heavy selling participation). |
| **Gold dash-dot box, `void up/dn`** | Unfilled liquidity void / 3-bar imbalance. |
| **Up / down arrow + `sweep`** | Stop-run: price wicked through a pool and closed back inside. |
| **Dotted horizontal line + `BSL 1.09485 (+5.9p)`** | The **nearest** liquidity level above and below the current price, with distance in pips. |
| **Panel (top-left)** | Live statistics: swing count, active vs swept pools, volume zones, flow bias, market structure, current volume expansion, nearest levels, last event. |
| **Legend (bottom-left)** | Colour key. |

Nothing is drawn inside the future beyond `InpExtendBars` bars to the right of the current bar.

---

## 3. Inputs

### Detection

| Input | Default | Description |
|---|---|---|
| `InpSensitivity` | `5` | Master dial, 1 = strict … 10 = aggressive. It simultaneously (a) lowers the pivot strength, (b) widens the equal-level tolerance, and (c) lowers the volume-spike threshold. |
| `InpLookbackBars` | `600` | How many bars back to scan. Ignored for pivots older than this. |
| `InpPivotLeft` | `0` | Confirmation bars to the **left** of a swing. `0` = derive from sensitivity. |
| `InpPivotRight` | `0` | Confirmation bars to the **right** (this is the non-repainting delay). `0` = derive from sensitivity. |
| `InpEqualTolPips` | `2.0` | How close two highs/lows must be to count as “equal”. Effective value is scaled by sensitivity (×0.7 … ×1.3). |
| `InpMaxPoolWidthPips` | `5.0` | Hard cap on how tall one pool may grow through clustering. Prevents tolerance chaining from merging unrelated swings into one huge band. `0` = no limit. |
| `InpMinTouches` | `2` | Pivots required before a cluster is treated as a pool (instead of a single swing line). |
| `InpMaxPools` | `12` | Maximum pool boxes drawn (strongest/freshest first). |
| `InpMaxSingleLevels` | `10` | Maximum single swing lines drawn. |
| `InpExtendBars` | `60` | How far the zones are projected to the right. |
| `InpOnlyActivePools` | `false` | Hide pools that were already swept. |
| `InpShowSweeps` | `true` | Draw sweep arrows. |
| `InpSweepCloseBack` | `true` | Require a close back inside the level for a sweep. `false` = any wick through counts. |

### Volume / order flow

| Input | Default | Description |
|---|---|---|
| `InpVolumeSource` | `Tick volume` | `Tick volume` (default, always available on FX) or `Real volume` (exchange volume; falls back to tick volume automatically if the symbol has none). |
| `InpVolAvgPeriod` | `20` | Average period for the volume baseline. The baseline **excludes the current bar**, so a spike cannot hide itself. |
| `InpVolSpikeMult` | `1.8` | Volume must exceed `baseline × multiplier` to qualify (scaled by sensitivity: ×0.8 … ×1.2). |
| `InpVolMinTicks` | `20` | Bars below this raw volume are ignored (filters thin sessions and rollover). |
| `InpVolZoneATRMult` | `0.60` | The bar's range must be at least this × ATR(14); a volume spike with no price travel is just noise. |
| `InpVolZoneUseBody` | `false` | Zone = candle body instead of the full high–low range. |
| `InpMaxVolZones` | `10` | Maximum volume zones drawn (newest first). |
| `InpVolZoneExtend` | `30` | Right extension of a volume zone, in bars. |
| `InpFlowBars` | `50` | Bars used for the flow-bias estimate (see §5). |

### Liquidity voids

| Input | Default | Description |
|---|---|---|
| `InpShowVoids` | `true` | Draw 3-bar voids/imbalances. |
| `InpVoidMinATR` | `0.35` | Minimum gap size as a fraction of ATR(14). |
| `InpMaxVoids` | `8` | Maximum voids drawn. |
| `InpHideFilledVoids` | `true` | Hide voids that price has already traded back through. |

### Visuals

| Input | Default | Description |
|---|---|---|
| `InpShowPanel` | `true` | Top-left information panel. |
| `InpShowLegend` | `true` | Bottom-left legend. |
| `InpShowNearest` | `true` | Dotted lines + labels for the nearest liquidity above/below. |
| `InpFontSize` | `8` | Base font size. |
| `InpColorBSL` | `OrangeRed` | Buy-side liquidity. |
| `InpColorSSL` | `DodgerBlue` | Sell-side liquidity. |
| `InpColorBull` | `LimeGreen` | Bullish volume spike. |
| `InpColorBear` | `Red` | Bearish volume spike. |
| `InpColorVoid` | `Gold` | Void / imbalance. |
| `InpColorSwept` | `SlateGray` | Already-swept liquidity. |
| `InpColorText` | `Silver` | Chart labels. |
| `InpColorPanelBg` | `Black` | Panel background. |
| `InpColorPanelTx` | `White` | Panel text. |

### Alerts

| Input | Default | Description |
|---|---|---|
| `InpAlertSweep` | `true` | Alert when a pool is swept on the last closed bar. |
| `InpAlertApproach` | `false` | Alert when price comes within `InpAlertDistPips` of the nearest liquidity. |
| `InpAlertDistPips` | `5.0` | Approach distance. |
| `InpAlertPush` | `false` | Also send a push notification (MetaQuotes ID required). |
| `InpAlertSound` | `false` | Play `alert2.wav`. |

Alerts are evaluated **once per new bar**, never on the first calculation after attaching, and never on every tick.

---

## 4. Suggested settings per market

| Market / TF | Sensitivity | Lookback | Equal tolerance | Volume mult | Notes |
|---|---|---|---|---|---|
| FX majors, M5–M15 | 5–6 | 600–900 | 2.0 | 1.8 | Defaults. Tick volume is meaningful. |
| FX majors, H1–H4 | 4–5 | 400–600 | 2.5–3.0 | 1.6 | Wider tolerance because swings are wider. |
| Gold (XAUUSD) | 5 | 500 | 3.0–5.0 (0.30–0.50 in price) | 2.0 | Pip size auto-detects 0.10 on 2-digit quotes. |
| Indices / CFDs | 4 | 500 | 4.0–6.0 | 1.5 | Prefer `Real volume` if your broker provides it. |
| Crypto CFDs | 6 | 800 | 3.0 | 2.0 | Tick volume is noisy; raise the multiplier. |
| Futures (if broker offers) | 5 | 600 | 2.0 | 1.5 | Switch `InpVolumeSource` to `Real volume`. |

If the chart is too busy: raise `InpSensitivity`? **No** — lower it (strict), reduce `InpMaxPools` / `InpMaxSingleLevels`, or enable `InpOnlyActivePools`.
If the chart is too empty: raise sensitivity, widen `InpEqualTolPips`, or increase `InpLookbackBars`.

---

## 5. How the calculation works

1. **Pivot detection**
   Fractal pivots with `L` bars to the left and `R` bars to the right (strict inequality on both sides). A pivot at bar *i* is only created once bars *i−1 … i−R* have closed, which is why the structure does not repaint.

2. **Clustering into pools**
   Pivots of the same type are merged when they are within the equal-level tolerance of the pool's current extreme, and when the resulting band stays inside `InpMaxPoolWidthPips`. A cluster with ≥ `InpMinTouches` members becomes a **pool**; the rest are drawn as single levels.
   `level` = the highest high (BSL) or lowest low (SSL) in the cluster — the exact price where stops would sit.
   `top`/`bottom` describe the band of highs/lows that formed the cluster.

3. **Sweep detection**
   Starting from the bar where the pool's newest pivot was confirmed, each newer bar is tested:
   * BSL swept when `high > level` **and** `close < level` (when `InpSweepCloseBack = true`);
   * SSL swept when `low < level` **and** `close > level`.
   The first such bar is stored (`tSwept`, `sweepPrice`), and the pool is rendered gray with an arrow.

4. **Volume spikes**
   Baseline = mean tick (or real) volume of the `N` bars **before** the bar being tested. A bar qualifies when
   `volume ≥ baseline × multiplier` **and** `volume ≥ InpVolMinTicks` **and** `range ≥ ATR(14) × InpVolZoneATRMult`.
   Direction comes from the close-location value (below).

5. **Flow-bias proxy (order-flow estimate)**
   MQL4 has no access to the order book, so a directional delta is estimated per bar:

   ```
   CLV   = (close - low) / (high - low)        // 0 … 1, where the bar closed in its range
   delta = (2 × CLV - 1) × volume              // signed volume proxy
   bias% = sum(delta, last InpFlowBars) / sum(volume, last InpFlowBars) × 100
   ```

   `+100%` = every bar closed on its high, `-100%` = every bar closed on its low. The panel shows `Flow bias: +23% buyers` and colours it green/red. Treat it as a **sentiment proxy**, not as exchange order flow.

6. **Market structure**
   The last two swing highs and the last two swing lows produce `HH/HL (up)`, `LH/LL (down)`, `HH/LL (expansion)` or `LH/HL (contraction)`.

7. **Voids**
   A bullish void exists when `low[i] > high[i+2]` and the gap is at least `ATR × InpVoidMinATR`; a bearish void when `high[i] < low[i+2]`. A void is *filled* once any later bar trades back into it.

---

## 6. Reading the chart — practical use

**Liquidity as a magnet.** Price is usually drawn to the nearest pool: stops above equal highs are fuel for a move up, stops below equal lows for a move down. The nearest-level lines show how many pips away that fuel is.

**Sweep → reversal.** The classic setup this indicator highlights:
1. A BSL/SSL pool is marked (two or more equal highs/lows).
2. Price wicks through it and **closes back inside** → the pool turns gray, a `sweep` arrow appears, and the panel's last event reads `Swept BSL @ …`.
3. Look for a reversal entry against the sweep, ideally confirmed by a volume-spike zone in the reversal direction, and target the opposite pool.

**Pool → continuation.** If price pushes through a pool and *closes* beyond it (`InpSweepCloseBack` blocks the sweep flag when the close is outside), treat it as acceptance, not rejection.

**Voids as rebalance targets.** Unfilled gold boxes are areas price left too fast; they often get revisited. They work well as take-profit zones.

**Structure + flow alignment.** `HH/HL (up)` plus a positive flow bias plus an untouched BSL pool above is a coherent long-side picture; conflicting readings are a reason to stand aside.

**Confluence is the point.** A zone where a volume spike, a pool and a void overlap is far more meaningful than any single marker.

---

## 7. Notes, limitations, troubleshooting

* **“Real” liquidity is inferred, not observed.** MT4 is a retail charting terminal: it exposes OHLC and tick volume only, with no DOM, no depth-of-market and no per-order data. True order-flow analysis needs a futures/exchange feed (e.g. CME datamine, Bookmap, Sierra Chart) or broker-side depth. This indicator reconstructs the *most probable* resting-liquidity locations from price structure and volume proxies, which is what the concept is based on in practice. If your broker supplies exchange volume (some do for futures), switch `InpVolumeSource` to `Real volume`.
* **Tick volume ≠ traded contracts.** On FX it is the number of price updates in a bar and correlates well with activity, but it is not contract volume.
* **No repainting of confirmed pivots** — but the right-most bars are by definition not yet confirmed, so zones can appear/disappear near the live edge. This is normal and matches how structure forms.
* **Objects, not buffers** — you cannot `iCustom()` the values from an EA as indicator buffers. If you need EA access, read the chart objects by their `RLQO_` prefix (e.g. `ObjectGetDouble` on the `RLQO_LVL_*` trend lines).
* **Performance:** analysis runs on new-bar events (and on history refresh), not on every tick; only the panel is refreshed per tick. A typical chart holds ~50–150 objects.
* **Not enough bars:** below 100 bars loaded the indicator stays silent.
* **Nothing appears:** check that the chart is not in a weekend/flat period, lower `InpSensitivity` (more strict → fewer, but also check the opposite direction), raise `InpLookbackBars`, and confirm the timeframe has visible swings.
* **Too many boxes:** set `InpOnlyActivePools = true`, lower `InpMaxPools`/`InpMaxSingleLevels`, or raise `InpMinTouches` to 3.
* **Alerts fire once per bar**, on the bar that completes, using the last closed bar's sweep.
* **Testing:** the MQL4 source was verified with a C++/ASan harness (240 randomized parameter/bar-count cases, geometry and object-lifecycle assertions). Always compile in MetaEditor for your own build.

---

## 8. File layout

```
RealLiquidity.mq4   the indicator (single file, no dependencies)
README.md           this document
```

## 9. Disclaimer

Trading involves substantial risk. This tool is an analysis aid, not a signal service, and it is provided **as is**, without warranty of any kind. Past behaviour of liquidity zones does not guarantee future results. Test on a demo account before using it with real money.
